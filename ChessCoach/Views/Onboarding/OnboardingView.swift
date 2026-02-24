import SwiftUI

/// First-run tutorial with 4 screens (improvement 6).
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0

    private let totalPages = 4

    var body: some View {
        @Bindable var s = settings

        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                howItWorksPage.tag(1)
                phasesPage.tag(2)
                eloPage(bindable: $s).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Page counter and Skip button anchored to bottom-left for thumb reach
            VStack {
                Spacer()
                HStack(alignment: .center) {
                    // Skip button — bottom-left for easier thumb reach
                    if page < totalPages - 1 {
                        Button("Skip") {
                            settings.hasSeenOnboarding = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.leading, AppSpacing.xxxl)
                        .accessibilityLabel("Skip introduction")
                    }

                    Spacer()

                    // Page counter — bottom-right
                    Text("\(page + 1) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.trailing, AppSpacing.xxxl)
                }
                .padding(.bottom, AppSpacing.lg)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.gold)
            Text("Welcome to ChessCoach")
                .font(.title.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
            Text("Learn chess openings with AI-powered coaching, spaced repetition, and a human-like opponent.")
                .font(.body)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)
            Spacer()
            nextButton
        }
    }

    private var howItWorksPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "book.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.success)
            Text("How It Works")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                featureRow(icon: "1.circle.fill", text: "Pick an opening to learn")
                featureRow(icon: "2.circle.fill", text: "Play moves on the board")
                featureRow(icon: "3.circle.fill", text: "Get coaching on every move")
                featureRow(icon: "4.circle.fill", text: "Review weak spots with spaced rep")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
        }
    }

    private var phasesPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.guided)
            Text("4 Learning Phases")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Improvement 26: Color-blind shape icons alongside phase colors
                phaseRow(
                    color: AppColor.study,
                    name: "Learn",
                    desc: "Read through the line with explanations",
                    shape: "book.fill"
                )
                phaseRow(
                    color: AppColor.guided,
                    name: "Guided Practice",
                    desc: "Play with hints and coaching",
                    shape: "hand.point.right.fill"
                )
                phaseRow(
                    color: AppColor.unguided,
                    name: "Unguided Practice",
                    desc: "Play from memory",
                    shape: "brain.head.profile"
                )
                phaseRow(
                    color: AppColor.practice,
                    name: "Mixed Practice",
                    desc: "All lines, no hints",
                    shape: "shuffle"
                )
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
        }
    }

    // Takes a Bindable projection so the Stepper can write back through AppSettings
    private func eloPage(bindable s: Bindable<AppSettings>) -> some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.unguided)
            Text("What's your level?")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text("This helps us adjust coaching and opponent difficulty.")
                .font(.body)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            VStack(spacing: AppSpacing.sm) {
                Text("\(settings.userELO)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)

                Stepper("ELO", value: s.userELO, in: 400...2000, step: 100)
                    .labelsHidden()
                    .padding(.horizontal, 60)
                    .accessibilityLabel("Your ELO rating: \(settings.userELO)")

                Text(eloDescription)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer()

            Button {
                settings.hasSeenOnboarding = true
            } label: {
                Text("Let's Go!")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Shared Components

    private var nextButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
        } label: {
            Text("Next")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColor.guided, in: RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to next page")
        .padding(.horizontal, AppSpacing.xxxl)
        .padding(.bottom, 40)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppColor.success)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private func phaseRow(color: Color, name: String, desc: String, shape: String = "circle.fill") -> some View {
        HStack(spacing: AppSpacing.md) {
            if settings.colorblindMode {
                Image(systemName: shape)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 18)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .padding(.leading, 4)
            }
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    // MARK: - Helpers

    private var eloDescription: String {
        switch settings.userELO {
        case ..<600: return "Complete beginner"
        case 600..<800: return "Beginner — learning the basics"
        case 800..<1000: return "Novice — knows how pieces move"
        case 1000..<1200: return "Intermediate — some tactical awareness"
        case 1200..<1500: return "Club player — understands strategy"
        case 1500..<1800: return "Advanced — strong positional play"
        default: return "Expert — competitive tournament player"
        }
    }
}
