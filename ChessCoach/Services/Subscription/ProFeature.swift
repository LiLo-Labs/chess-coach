import Foundation

/// Subscription tiers from free to full pro.
enum SubscriptionTier: String, CaseIterable, Codable, Sendable {
    case free       // No AI, template coaching, limited openings
    case onDeviceAI // Bundled Qwen3-4B on-device LLM
    case cloudAI    // User's own Anthropic key or Ollama server
    case pro        // Everything + all future updates

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .onDeviceAI: return "On-Device AI"
        case .cloudAI: return "Cloud AI"
        case .pro: return "Pro"
        }
    }

    var description: String {
        switch self {
        case .free: return "Learn with guided coaching — no AI needed"
        case .onDeviceAI: return "AI coaching runs privately on your device"
        case .cloudAI: return "Connect your own AI service for coaching"
        case .pro: return "Everything unlocked, all future updates included"
        }
    }

    /// Whether this tier includes any AI coaching capability.
    var hasAI: Bool {
        self != .free
    }

    /// Whether this tier grants access to all openings.
    var hasAllOpenings: Bool {
        self == .pro
    }

    /// Minimum tier required for a feature.
    static func minimumTier(for feature: ProFeature) -> SubscriptionTier {
        switch feature {
        // On-Device AI tier
        case .onDeviceModelDownload:
            return .onDeviceAI

        // Any AI tier (on-device or cloud)
        case .llmCoaching, .deepExplanation, .offBookExplanation,
             .liveLLMCoaching, .fullPES, .lineStudyChat:
            return .onDeviceAI

        // Cloud AI tier (needs external provider config)
        case .llmProviderSettings:
            return .cloudAI

        // Pro-only features
        case .handleVarietyLayer, .realConditionsLayer,
             .allOpenings, .advancedPuzzles, .unlimitedPuzzles,
             .drills, .gameImport, .openingRecommendations, .spacedRepetition:
            return .pro
        }
    }
}

/// All features gated behind subscription tiers.
enum ProFeature: String, CaseIterable {
    // AI coaching features (require on-device AI or higher)
    case llmCoaching          // LLM-generated coaching (getCoaching, getBatchedCoaching)
    case deepExplanation      // "Explain why" deep explanations
    case offBookExplanation   // Deviation analysis via LLM
    case llmProviderSettings  // LLM provider picker, API key, Ollama config
    case onDeviceModelDownload // Download on-device model
    case lineStudyChat         // AI chat during line study (Stage 1)

    // Plan-first learning features (v2)
    case fullPES              // Full composite Plan Execution Score (soundness + alignment + popularity)
    case liveLLMCoaching      // Live LLM coaching in Layer 1 (vs pre-baked text)
    case handleVarietyLayer   // Layer 4: Handle Variety
    case realConditionsLayer  // Layer 5: Real Conditions
    case allOpenings          // Access to all openings (free = 3 starter openings)
    case advancedPuzzles      // Paid puzzle types (whatWentWrong, opponentDeviated, speedRecognition)
    case unlimitedPuzzles     // Unlimited puzzles (free = 5/day)
    case drills               // Drill exercises
    case gameImport           // Import games for analysis
    case openingRecommendations // AI-powered opening recommendations
    case spacedRepetition     // Spaced repetition review system
}
