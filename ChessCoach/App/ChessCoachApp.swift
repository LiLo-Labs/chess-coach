import SwiftUI

@main
struct ChessCoachApp: App {
    @State private var subscriptionService = SubscriptionService()
    @State private var appSettings = AppSettings()
    @State private var appServices = AppServices()
    @State private var tokenService = TokenService()
    @State private var modelDownloadService = ModelDownloadService()

    init() {
        // One-time migration: clear review items saved with wrong FENs (pre-fix)
        let migrationKey = "reviewItemsFenFix_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            PersistenceService.shared.saveReviewItems([])
            UserDefaults.standard.set(true, forKey: migrationKey)
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
