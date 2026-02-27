import Foundation

/// Abstraction over any text-generating LLM backend (Claude, Ollama, on-device).
protocol TextGenerating: Sendable {
    func generate(prompt: String, maxTokens: Int) async throws -> String
    func generateWithThinking(prompt: String, maxTokens: Int) async throws -> String
}

/// Abstraction over any position-evaluating engine (Stockfish, etc.).
protocol PositionEvaluating: Sendable {
    func bestMove(fen: String, depth: Int) async -> String?
    func evaluate(fen: String, depth: Int) async -> (bestMove: String, score: Int)?
    func topMoves(fen: String, count: Int, depth: Int) async -> [(move: String, score: Int)]
}

/// Abstraction over any human-move-predicting model (Maia, etc.).
protocol MovePredicting: Sendable {
    func predictMove(
        fen: String,
        legalMoves: [String],
        eloSelf: Int,
        eloOppo: Int
    ) async throws -> [(move: String, probability: Float)]

    func sampleMove(
        fen: String,
        legalMoves: [String],
        eloSelf: Int,
        eloOppo: Int,
        temperature: Float
    ) async throws -> String
}
