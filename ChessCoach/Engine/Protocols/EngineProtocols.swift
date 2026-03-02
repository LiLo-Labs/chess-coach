import Foundation

/// Abstraction over any text-generating LLM backend (Claude, Ollama, on-device).
protocol TextGenerating: Sendable {
    func generate(prompt: String, maxTokens: Int) async throws -> String
    func generateWithThinking(prompt: String, maxTokens: Int) async throws -> String
}
