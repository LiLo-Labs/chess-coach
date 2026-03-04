import SwiftUI

@main
struct ChessCoachApp: App {
    @State private var subscriptionService = SubscriptionService()
    @State private var appSettings = AppSettings()
    @State private var appServices = AppServices()
    @State private var tokenService = TokenService()
    @State private var modelDownloadService = ModelDownloadService()

    static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")

    init() {
        if Self.isScreenshotMode {
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(subscriptionService)
                .environment(appSettings)
                .environment(appServices)
                .environment(tokenService)
                .environment(modelDownloadService)
        }
    }
}
