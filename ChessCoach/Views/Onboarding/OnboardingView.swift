import SwiftUI

/// First-run tutorial introducing the plan-first learning model.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0

    private let totalPages = 4

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                howItWorksPage.tag(1)
                layersPage.tag(2)
                eloPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                Spacer()
                HStack(alignment: .center) {
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
            Text("Every chess game starts with a plan. We'll teach you proven game plans used by the best players — and help you understand WHY each move matters.")
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
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)
            Text("How It Works")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                featureRow(icon: "1.circle.fill", color: .cyan, text: "Learn the plan behind the moves")
                featureRow(icon: "2.circle.fill", color: .blue, text: "Practice playing it your way")
                featureRow(icon: "3.circle.fill", color: .indigo, text: "Discover the history and famous names")
                featureRow(icon: "4.circle.fill", color: .orange, text: "Face real opponents who surprise you")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Text("We'll guide you every step of the way — no prior knowledge needed.")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
        }
    }

    private var layersPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.layer(.executePlan))
            Text("Your Learning Journey")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ForEach(LearningLayer.allCases, id: \.rawValue) { layer in
                    layerRow(layer: layer)
                }
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
            nextButton
        }
    }

    private var eloPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.layer(.handleVariety))
            Text("What's your level?")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text("This helps us adjust coaching and opponent difficulty.")
                .font(.body)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            VStack(spacing: AppSpacing.md) {
                Text("\(settings.userELO)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())

                // Use explicit +/- buttons instead of Stepper to avoid
                // gesture conflicts with TabView page swiping
                HStack(spacing: AppSpacing.xxl) {
                    Button {
                        withAnimation { settings.userELO = max(400, settings.userELO - 100) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(settings.userELO <= 400 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO <= 400)

                    Button {
                        withAnimation { settings.userELO = min(2000, settings.userELO + 100) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(settings.userELO >= 2000 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO >= 2000)
                }
                .accessibilityLabel("Your skill level: \(settings.userELO)")

                Text(eloDescription)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer()

            Button {
                withAnimation {
                    settings.hasSeenOnboarding = true
                }
            } label: {
                Text("Let's Go!")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
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
                .background(AppColor.layer(.executePlan), in: RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to next page")
        .padding(.horizontal, AppSpacing.xxxl)
        .padding(.bottom, 40)
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private func layerRow(layer: LearningLayer) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: AppColor.layerIcon(layer))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.layer(layer))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(layer.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.layer(layer))
                Text(layer.layerDescription)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            if !layer.isFreeLayer {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }
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
