import Foundation
import UIKit

/// Posts feedback as GitHub Issues to MALathon/chess-coach.
/// Uses a fine-grained PAT with issues:write scope only.
final class FeedbackService: Sendable {
    static let shared = FeedbackService()

    // MARK: - Configuration
    // Replace with your fine-grained PAT (issues:write only on MALathon/chess-coach)
    private let token = "PASTE_YOUR_GITHUB_PAT_HERE"
    private let repo = "MALathon/chess-coach"

    struct FeedbackPayload: Sendable {
        let screen: String
        let category: String  // bug, feature, general
        let message: String
    }

    enum FeedbackError: Error, LocalizedError {
        case notConfigured
        case networkError(String)
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Feedback token not configured"
            case .networkError(let msg): return msg
            case .apiError(let code, let msg): return "GitHub API error \(code): \(msg)"
            }
        }
    }

    func submit(_ payload: FeedbackPayload) async throws {
        guard token != "PASTE_YOUR_GITHUB_PAT_HERE" else {
            throw FeedbackError.notConfigured
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = await UIDevice.current.systemVersion
        let deviceModel = await UIDevice.current.model

        let title = "[\(payload.category.capitalized)] \(payload.screen): \(String(payload.message.prefix(60)))"
        let body = """
        **Screen:** \(payload.screen)
        **Category:** \(payload.category)
        **App Version:** \(appVersion)
        **iOS Version:** \(osVersion)
        **Device:** \(deviceModel)

        ---

        \(payload.message)
        """

        let url = URL(string: "https://api.github.com/repos/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let json: [String: Any] = [
            "title": title,
            "body": body,
            "labels": ["user-feedback", payload.category]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackError.networkError("Invalid response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FeedbackError.apiError(httpResponse.statusCode, message)
        }
    }
}
