import SwiftUI

@main
struct ChessCoachApp: App {
    @State private var subscriptionService = SubscriptionService()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(subscriptionService)
                .environment(appSettings)
        }
    }
}
