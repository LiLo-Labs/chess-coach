import Foundation
import ChessKitEngine

actor StockfishService {
    private var engine: Engine?
    private var isStarted = false

    func start() async {
        guard !isStarted else { return }
        engine = Engine(type: .stockfish)
        await engine?.start()
        // Wait for engine to be ready (with timeout)
        do {
            try await withThrowingTimeout(seconds: 5) {
                if let stream = await self.engine?.responseStream {
                    for await response in stream {
                        if response == .readyok {
                            break
                        }
                    }
                }
            }
            isStarted = true
        } catch {
            print("[ChessCoach] Stockfish failed to start within timeout")
            await engine?.stop()
            engine = nil
        }
    }

    func stop() async {
        await engine?.stop()
        engine = nil
        isStarted = false
    }

    func bestMove(fen: String, depth: Int = 15) async -> String? {
        guard let engine else { return nil }
        await engine.send(command: .stop)
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .go(depth: depth))

        do {
            return try await withThrowingTimeout(seconds: 10) {
                if let stream = await engine.responseStream {
                    for await response in stream {
                        if case let .bestmove(move, _) = response {
                            return move
                        }
                    }
                }
                return nil
            }
        } catch {
            print("[ChessCoach] Stockfish bestMove timed out")
            await engine.send(command: .stop)
            return nil
        }
    }

    func evaluate(fen: String, depth: Int = 15) async -> (bestMove: String, score: Int)? {
        guard let engine else { return nil }
        await engine.send(command: .stop)
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .go(depth: depth))

        do {
            return try await withThrowingTimeout(seconds: 10) {
                var lastScore: Int = 0
                if let stream = await engine.responseStream {
                    for await response in stream {
                        switch response {
                        case let .info(info):
                            if let cp = info.score?.cp {
                                lastScore = Int(cp)
                            }
                            if let mate = info.score?.mate {
                                lastScore = mate > 0 ? 10000 : -10000
                            }
                        case let .bestmove(move, _):
                            return (bestMove: move, score: lastScore)
                        default:
                            break
                        }
                    }
                }
                return nil
            }
        } catch {
            print("[ChessCoach] Stockfish evaluate timed out")
            await engine.send(command: .stop)
            return nil
        }
    }

    func topMoves(fen: String, count: Int = 3, depth: Int = 15) async -> [(move: String, score: Int)] {
        guard let engine else { return [] }
        await engine.send(command: .stop)
        await engine.send(command: .setoption(id: "MultiPV", value: "\(count)"))
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .go(depth: depth))

        do {
            let results: [Int: (move: String, score: Int)] = try await withThrowingTimeout(seconds: 10) {
                var results: [Int: (move: String, score: Int)] = [:]
                if let stream = await engine.responseStream {
                    for await response in stream {
                        switch response {
                        case let .info(info):
                            if let multipv = info.multipv,
                               let pv = info.pv, !pv.isEmpty,
                               let cp = info.score?.cp {
                                results[multipv] = (move: pv[0], score: Int(cp))
                            }
                        case .bestmove:
                            return results
                        default:
                            break
                        }
                    }
                }
                return results
            }

            await engine.send(command: .setoption(id: "MultiPV", value: "1"))
            return results.sorted(by: { $0.key < $1.key }).map(\.value)
        } catch {
            print("[ChessCoach] Stockfish topMoves timed out")
            await engine.send(command: .stop)
            await engine.send(command: .setoption(id: "MultiPV", value: "1"))
            return []
        }
    }
}

// MARK: - Timeout Helper

private func withThrowingTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        guard let result = try await group.next() else {
            throw CancellationError()
        }
        group.cancelAll()
        return result
    }
}
