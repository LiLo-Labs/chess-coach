import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.hasSeenOnboarding {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
}
