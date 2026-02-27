import SwiftUI

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppServices.self) private var appServices

    @State private var isReady = false
    @State private var loadingStep = "Starting up..."
    @State private var loadingProgress: Double = 0
    @State private var refreshID = UUID()
    @State private var errorMessage: String?
    @State private var showOpeningPicker = false

    var body: some View {
        ZStack {
            if isReady {
                if settings.hasSeenOnboarding {
                    HomeView()
                        .id(refreshID)
                        .transition(.opacity)
                } else if showOpeningPicker {
                    FreeOpeningPickerView(onComplete: {
                        withAnimation {
                            showOpeningPicker = false
                            settings.hasSeenOnboarding = true
                        }
                    })
                    .transition(.opacity)
                } else {
                    OnboardingView(onComplete: {
                        // Free users go to the opening picker; paid users skip it
                        if subscriptionService.currentTier == .free && !settings.hasPickedFreeOpening {
                            withAnimation { showOpeningPicker = true }
                        } else {
                            withAnimation { settings.hasSeenOnboarding = true }
                        }
                    })
                    .transition(.opacity)
                }
            } else {
                launchScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isReady)
        .animation(.easeInOut(duration: 0.4), value: settings.hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.4), value: showOpeningPicker)
        .task {
            await performStartup()
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugStateDidChange)) { _ in
            withAnimation {
                refreshID = UUID()
            }
        }
        #endif
    }

    // MARK: - Launch Screen

    private var launchScreen: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColor.gold)
                    .symbolEffect(.pulse, options: .repeating)

                Text("ChessCoach")
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Spacer()

                VStack(spacing: AppSpacing.md) {
                    ProgressView(value: loadingProgress)
                        .tint(AppColor.layer(.executePlan))
                        .frame(maxWidth: 200)

                    Text(loadingStep)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .contentTransition(.numericText())
                }
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Startup Sequence

    private func performStartup() async {
        // Step 1: Data migration
        updateStep("Checking data...", progress: 0.05)
        _ = PersistenceService.shared // triggers migrateIfNeeded()
        await Task.yield()

        // Step 2: Load opening database
        updateStep("Loading openings...", progress: 0.1)
        _ = OpeningDatabase.shared
        await Task.yield()

        // Step 3: Check subscription
        updateStep("Checking subscription...", progress: 0.15)
        do {
            try await subscriptionService.loadProduct()
        } catch {
            errorMessage = error.localizedDescription
        }
        await Task.yield()

        // Step 4: Load user progress
        updateStep("Loading your progress...", progress: 0.2)
        _ = PersistenceService.shared.loadAllMastery()
        await Task.yield()

        // Step 5: Start chess engine
        updateStep("Starting chess engine...", progress: 0.3)
        await appServices.startStockfish()

        // Step 6: Load coaching model (skip for free tier users)
        if subscriptionService.hasAI {
            updateStep("Loading coaching model...", progress: 0.5)
            await appServices.startLLM()
        }

        // Step 7: Ready
        updateStep("Ready!", progress: 1.0)

        try? await Task.sleep(for: .milliseconds(300))

        withAnimation {
            isReady = true
        }
    }

    private func updateStep(_ step: String, progress: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            loadingStep = step
            loadingProgress = progress
        }
    }
}

#if DEBUG
extension Notification.Name {
    static let debugStateDidChange = Notification.Name("debugStateDidChange")
}
#endif
