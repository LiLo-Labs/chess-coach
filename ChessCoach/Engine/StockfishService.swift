import Foundation
import ChessKitEngine

/// Wraps ChessKitEngine's Stockfish with a single persistent stream consumer
/// and continuation-based response collection.
actor StockfishService: PositionEvaluating {
    private var engine: Engine?
    private var isStarted = false
    private var streamTask: Task<Void, Never>?

    // Continuation-based response collection
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var collectedResponses: [EngineResponse] = []
    private var waitingForBestMove = false
    private var waitingForReady = false

    // Serialization: waiters queue up here while a search is in progress
    private var searchInProgress = false
    private var searchQueue: [CheckedContinuation<Void, Never>] = []

    /// Default timeout for search operations (seconds)
    private let searchTimeout: TimeInterval = AppConfig.engine.searchTimeout

    func start() async {
        guard !isStarted else { return }

        debugLog("Stockfish start() called")

        let eng = Engine(type: .stockfish)
        engine = eng
        debugLog("Calling eng.start()")
        await eng.start()
        debugLog("eng.start() returned")

        guard let stream = await eng.responseStream else {
            debugLog("No response stream")
            #if DEBUG
            print("[ChessCoach] Stockfish: no response stream")
            #endif
            return
        }

        debugLog("Got response stream, setting up consumer")
        waitingForReady = true

        // Single persistent stream consumer
        streamTask = Task { [weak self] in
            debugLog("Stream consumer task started")
            for await response in stream {
                await self?.handleResponse(response)
            }
            debugLog("Stream consumer task ended")
        }

        // Timeout safety
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConfig.engine.readyTimeout))
            await self?.handleReadyTimeout()
        }

        debugLog("Waiting for readyok...")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
        }

        timeoutTask.cancel()
        isStarted = true
        debugLog("Stockfish started, confirming setup complete...")

        // Send a second isready to confirm all setoption commands
        // (especially NNUE weight loading) have been fully processed
        // before we allow any searches.
        waitingForReady = true
        let confirmTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConfig.engine.readyTimeout))
            await self?.handleReadyTimeout()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
            Task { [engine = self.engine!] in
                await engine.send(command: .isready)
            }
        }
        confirmTimeout.cancel()

        debugLog("Stockfish fully ready")
        #if DEBUG
        print("[ChessCoach] Stockfish started")
        #endif
    }

    func stop() async {
        streamTask?.cancel()
        streamTask = nil
        await engine?.stop()
        engine = nil
        isStarted = false
    }

    func bestMove(fen: String, depth: Int = 15) async -> String? {
        let responses = await runSearch(commands: [
            .position(.fen(fen)),
            .go(depth: depth)
        ])

        for response in responses {
            if case let .bestmove(move, _) = response {
                return move
            }
        }
        return nil
    }

    func evaluate(fen: String, depth: Int = 15) async -> (bestMove: String, score: Int)? {
        guard isStarted else {
            #if DEBUG
            print("[ChessCoach] evaluate: engine not started")
            #endif
            return nil
        }

        let responses = await runSearch(commands: [
            .position(.fen(fen)),
            .go(depth: depth)
        ])

        var lastScore: Int = 0
        var bestMoveStr: String?

        for response in responses {
            switch response {
            case let .info(info):
                if let cp = info.score?.cp {
                    lastScore = Int(cp)
                }
                if let mate = info.score?.mate {
                    lastScore = mate > 0 ? 10000 : -10000
                }
            case let .bestmove(move, _):
                bestMoveStr = move
            default:
                break
            }
        }

        guard let move = bestMoveStr else { return nil }
        return (bestMove: move, score: lastScore)
    }

    func topMoves(fen: String, count: Int = 3, depth: Int = 15) async -> [(move: String, score: Int)] {
        guard let engine, isStarted else { return [] }

        await engine.send(command: .setoption(id: "MultiPV", value: "\(count)"))

        let responses = await runSearch(commands: [
            .position(.fen(fen)),
            .go(depth: depth)
        ])

        var results: [Int: (move: String, score: Int)] = [:]

        for response in responses {
            if case let .info(info) = response,
               let multipv = info.multipv,
               let pv = info.pv, !pv.isEmpty,
               let cp = info.score?.cp {
                results[multipv] = (move: pv[0], score: Int(cp))
            }
        }

        await engine.send(command: .setoption(id: "MultiPV", value: "1"))

        return results.sorted(by: { $0.key < $1.key }).map(\.value)
    }

    // MARK: - Private

    private func handleReadyTimeout() {
        guard waitingForReady else { return }
        waitingForReady = false
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume()
        #if DEBUG
        print("[ChessCoach] Stockfish: readyok timeout, proceeding anyway")
        #endif
    }

    private func handleResponse(_ response: EngineResponse) {
        debugLog("[SF] handleResponse: \(response), waitingForReady=\(waitingForReady), waitingForBestMove=\(waitingForBestMove)")
        if waitingForReady {
            if case .readyok = response {
                waitingForReady = false
                let cont = pendingContinuation
                pendingContinuation = nil
                debugLog("[SF] handleResponse: resuming readyok continuation (cont=\(cont != nil))")
                cont?.resume()
            }
            return
        }

        if waitingForBestMove {
            collectedResponses.append(response)
            if case .bestmove = response {
                waitingForBestMove = false
                let cont = pendingContinuation
                pendingContinuation = nil
                debugLog("[SF] handleResponse: resuming bestmove continuation (cont=\(cont != nil))")
                cont?.resume()
            }
        }
    }

    private func runSearch(commands: [EngineCommand]) async -> [EngineResponse] {
        guard let engine, isStarted else {
            debugLog("runSearch: engine not ready")
            return []
        }

        // C-1: Serialize concurrent searches — wait until no search is in progress
        if searchInProgress {
            debugLog("runSearch: another search in progress, queuing")
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                searchQueue.append(cont)
            }
        }
        searchInProgress = true

        // C-2: If a stale continuation exists (should not happen with serialization,
        // but defend against it), resume it before proceeding so it is never leaked.
        if let staleCont = pendingContinuation {
            debugLog("runSearch: resuming stale pending continuation")
            pendingContinuation = nil
            waitingForBestMove = false
            staleCont.resume()
        }

        // C-3: Ensure engine is idle before starting a new search.
        // After a timeout, the engine may still be processing the old search.
        // Sending stop + isready guarantees any stale state is flushed before
        // we send new position/go commands.
        await ensureEngineIdle()

        debugLog("runSearch starting with \(commands.count) commands")
        collectedResponses = []
        waitingForBestMove = true

        // C-4: Set continuation BEFORE sending commands. This closes the race
        // where bestmove arrives between engine.send() and withCheckedContinuation.
        // Commands are sent from a Task that executes after this method suspends.
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.searchTimeout ?? 5))
            await self?.handleSearchTimeout()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
            Task { [engine] in
                for cmd in commands {
                    await engine.send(command: cmd)
                }
            }
        }

        timeoutTask.cancel()
        let results = collectedResponses
        debugLog("runSearch done, \(results.count) responses")

        // Release the next queued search, if any
        searchInProgress = false
        if !searchQueue.isEmpty {
            let next = searchQueue.removeFirst()
            next.resume()
        }

        return results
    }

    /// Sends `stop` + `isready` and waits for `readyok`.
    /// This guarantees the engine has fully flushed any in-flight search
    /// (e.g. from a previous timeout) before we begin a new one.
    /// Cost: ~1ms roundtrip — negligible compared to search time.
    private func ensureEngineIdle() async {
        guard let engine else { return }
        await engine.send(command: .stop)

        // Wait for engine to confirm it's idle
        waitingForReady = true
        let idleTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.handleReadyTimeout()
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
            Task { [engine] in
                await engine.send(command: .isready)
            }
        }
        idleTimeout.cancel()
        debugLog("ensureEngineIdle: engine confirmed idle")
    }

    private func handleSearchTimeout() {
        debugLog("[SF] handleSearchTimeout: waitingForBestMove=\(waitingForBestMove), hasCont=\(pendingContinuation != nil)")
        guard waitingForBestMove else { return }
        waitingForBestMove = false

        // CRITICAL: Tell the engine to stop searching so it doesn't keep
        // running in the background and corrupt subsequent searches.
        Task { [engine] in
            await engine?.send(command: .stop)
        }

        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume()
        debugLog("[SF] handleSearchTimeout: resumed continuation after sending stop")
        #if DEBUG
        print("[ChessCoach] Stockfish: search timeout after \(Int(searchTimeout))s — engine stopped")
        #endif
    }
}
