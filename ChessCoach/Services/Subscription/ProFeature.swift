import Foundation

/// All features gated behind Pro tier.
enum ProFeature: String, CaseIterable {
    case llmCoaching          // LLM-generated coaching (getCoaching, getBatchedCoaching)
    case deepExplanation      // "Explain why" deep explanations
    case offBookExplanation   // Deviation analysis via LLM
    case llmProviderSettings  // LLM provider picker, API key, Ollama config
    case onDeviceModelDownload // Download on-device model
    case lineStudyChat         // AI chat during line study (Stage 1)
}
