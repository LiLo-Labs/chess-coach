import Foundation

/// Shared app-level services initialized once at launch.
/// Passed via SwiftUI Environment to avoid re-creating engines per session.
@Observable
@MainActor
final class AppServices {
    let stockfish = StockfishService()
    let llmService = LLMService()

    private(set) var stockfishReady = false
    private(set) var llmReady = false

    func startStockfish() async {
        await stockfish.start()
        stockfishReady = true
    }

    func startLLM() async {
        await llmService.detectProvider()
        let provider = await llmService.currentProvider
        if provider == .onDevice {
            await llmService.warmUp()
        }
        llmReady = true
    }
}
