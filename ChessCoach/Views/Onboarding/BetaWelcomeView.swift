import SwiftUI

/// Shown once for TestFlight beta testers after onboarding.
/// Explains how to test, use debug states, and leave feedback.
struct BetaWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                    header
                    howToTestSection
                    #if DEBUG
                    debugStatesSection
                    #endif
                    feedbackSection
                    knownLimitationsSection
                    thankYouSection
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, 40)
            }
            .background(AppColor.background)
            .preferredColorScheme(.dark)
            .navigationTitle("Beta Testing Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Got It") {
                        settings.hasSeenBetaWelcome = true
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)
                .padding(.top, AppSpacing.xl)

            Text("Welcome, Beta Tester!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text("Thank you for helping test ChessCoach. This guide will help you get the most out of testing.")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - How to Test

    private var howToTestSection: some View {
        sectionCard(title: "What to Test", icon: "checklist", color: .green) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                bulletPoint("Open an opening and play through the main line")
                bulletPoint("Try deviating from the book to see coaching feedback")
                bulletPoint("Run the Skill Assessment (Settings > Your Level)")
                bulletPoint("Try the Trainer mode against Maia (human-like opponent)")
                bulletPoint("Test the puzzle system from the home screen")
                bulletPoint("Check that sound effects and haptics feel right")
            }
        }
    }

    // MARK: - Debug States

    #if DEBUG
    private var debugStatesSection: some View {
        sectionCard(title: "Debug States", icon: "ladybug.fill", color: .orange) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("This is a **debug build** with extra testing tools:")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

                bulletPoint("Go to **Settings > Developer > Debug States**")
                bulletPoint("**Token presets** \u{2014} test free and paid tiers with different token balances")
                bulletPoint("**Free user state** \u{2014} see the app as a free user (3 openings, limited puzzles)")
                bulletPoint("**On-Device AI** \u{2014} test coaching text with the local model")
                bulletPoint("**Cloud AI** \u{2014} test Claude API coaching (needs your API key)")
                bulletPoint("**Pro state** \u{2014} unlock everything to test all features")
                bulletPoint("**Export/Import** \u{2014} save and restore app state snapshots")

                Text("Changes from Debug States take effect immediately. The app reloads when you switch states.")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
    }
    #endif

    // MARK: - Feedback

    private var feedbackSection: some View {
        sectionCard(title: "Leaving Feedback", icon: "bubble.left.fill", color: .cyan) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                bulletPoint("Tap the **bug icon** on any screen to report an issue for that screen")
                bulletPoint("Or go to **Settings > About > Send Feedback**")
                bulletPoint("Include what you were doing, what you expected, and what happened")
                bulletPoint("Screenshots from TestFlight are automatically attached")

                Text("Every piece of feedback helps. Don't hesitate to report even small things!")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
    }

    // MARK: - Known Limitations

    private var knownLimitationsSection: some View {
        sectionCard(title: "Known Limitations", icon: "exclamationmark.triangle.fill", color: .yellow) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                bulletPoint("AI coaching requires Pro tier \u{2014} use Debug States to unlock")
                bulletPoint("On-device AI model is ~2.5 GB and downloads in the background")
                bulletPoint("The model download happens via Settings > AI Coach > Download AI Model")
                bulletPoint("Some openings may have incomplete variation trees")
            }
        }
    }

    // MARK: - Thank You

    private var thankYouSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("Thank you for testing!")
                .font(.headline)
                .foregroundStyle(AppColor.primaryText)
            Text("Your feedback directly shapes what ships to the App Store.")
                .font(.caption)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Helpers

    private func sectionCard(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            content()
        }
        .padding(AppSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    private func bulletPoint(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text("\u{2022}")
                .foregroundStyle(AppColor.secondaryText)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.primaryText)
        }
    }
}
