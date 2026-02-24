import Foundation
import ChessKitEngine

/// Wraps ChessKitEngine's Stockfish with a single persistent stream consumer
/// and continuation-based response collection.
actor StockfishService {
    private var engine: Engine?
    private var isStarted = false
    private var streamTask: Task<Void, Never>?

    // Continuation-based response collection
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private var collectedResponses: [EngineResponse] = []
    private var waitingForBestMove = false
    private var waitingForReady = false

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
            print("[ChessCoach] Stockfish: no response stream")
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
            try? await Task.sleep(for: .seconds(10))
            await self?.handleReadyTimeout()
        }

        debugLog("Waiting for readyok...")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
        }

        timeoutTask.cancel()
        isStarted = true
        debugLog("Stockfish started successfully")
        print("[ChessCoach] Stockfish started")
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
        guard isStarted else { print("[ChessCoach] evaluate: engine not started"); return nil }

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
        print("[ChessCoach] Stockfish: readyok timeout, proceeding anyway")
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
        debugLog("runSearch starting with \(commands.count) commands")
        collectedResponses = []
        waitingForBestMove = true

        for (i, cmd) in commands.enumerated() {
            debugLog("runSearch: sending cmd[\(i)]: \(cmd)")
            await engine.send(command: cmd)
            debugLog("runSearch: sent cmd[\(i)] done")
        }

        // Timeout so searches don't hang forever
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            await self?.handleSearchTimeout()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pendingContinuation = cont
        }

        timeoutTask.cancel()
        debugLog("runSearch done, \(self.collectedResponses.count) responses")
        return collectedResponses
    }

    private func handleSearchTimeout() {
        debugLog("[SF] handleSearchTimeout: waitingForBestMove=\(waitingForBestMove), hasCont=\(pendingContinuation != nil)")
        guard waitingForBestMove else { return }
        waitingForBestMove = false
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume()
        debugLog("[SF] handleSearchTimeout: resumed continuation")
        print("[ChessCoach] Stockfish: search timeout after 10s")
    }
}
