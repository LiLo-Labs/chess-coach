import Foundation
import UIKit

/// Posts feedback to a Cloudflare Worker proxy that creates GitHub Issues.
/// No secrets are stored in the app — the Worker holds the GitHub PAT.
final class FeedbackService: Sendable {
    static let shared = FeedbackService()

    // MARK: - Configuration
    // After deploying the worker, replace with your actual URL:
    //   https://chess-coach-feedback.<your-subdomain>.workers.dev/feedback
    private let workerURL = "https://chess-coach-feedback.malathon.workers.dev/feedback"

    // Optional API key for the worker (set via wrangler secret put API_KEY)
    private let apiKey: String? = nil

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
            case .notConfigured: return "Feedback service not configured"
            case .networkError(let msg): return msg
            case .apiError(let code, let msg): return "Server error \(code): \(msg)"
            }
        }
    }

    func submit(_ payload: FeedbackPayload) async throws {
        guard let url = URL(string: workerURL),
              !workerURL.contains("REPLACE_ME") else {
            throw FeedbackError.notConfigured
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = await UIDevice.current.systemVersion
        let deviceModel = await UIDevice.current.model

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let json: [String: String] = [
            "screen": payload.screen,
            "category": payload.category,
            "message": payload.message,
            "appVersion": appVersion,
            "osVersion": osVersion,
            "device": deviceModel
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
