import SwiftUI

/// First-run onboarding flow — visual, airy, minimal text.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0

    var onComplete: () -> Void = {}

    private let totalPages = 5

    // Per-element stagger states
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showItems: [Bool] = Array(repeating: false, count: 6)
    @State private var showButton = false

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                whatYouLearnPage.tag(1)
                howItWorksPage.tag(2)
                privacyPage.tag(3)
                skillPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                Spacer()
                HStack(alignment: .center) {
                    if page < totalPages - 1 {
                        Button("Skip") { onComplete() }
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
        .onChange(of: page) { _, _ in triggerEntryAnimations() }
        .onAppear { triggerEntryAnimations() }
    }

    // MARK: - Animations

    private func triggerEntryAnimations() {
        showIcon = false
        showTitle = false
        showItems = Array(repeating: false, count: 6)
        showButton = false

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
            showIcon = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
            showTitle = true
        }
        // Stagger each content item individually
        for i in 0..<6 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.45 + Double(i) * 0.1)) {
                showItems[i] = true
            }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.9)) {
            showButton = true
        }
    }

    private func itemVisible(_ index: Int) -> Bool {
        index < showItems.count && showItems[index]
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppColor.gold)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            VStack(spacing: 12) {
                Text("ChessCoach")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("Master chess openings.\nNo experience needed.")
                    .font(.title3)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            Spacer()
            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 2: What You'll Learn

    private var whatYouLearnPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("What Are Openings?")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(alignment: .leading, spacing: 16) {
                animatedBullet(0, icon: "chess.board.fill", color: .cyan, text: "Every game starts with a **plan**")
                animatedBullet(1, icon: "brain", color: .blue, text: "We teach you **why**, not what to memorize")
                animatedBullet(2, icon: "star.fill", color: .orange, text: "The right move becomes **obvious**")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 3: How It Works

    private var howItWorksPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("How It Works")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(alignment: .leading, spacing: 20) {
                animatedStep(0, number: 1, color: .cyan, text: "Learn the plan")
                animatedStep(1, number: 2, color: .blue, text: "Practice with guidance")
                animatedStep(2, number: 3, color: .indigo, text: "Face real opponents")
                animatedStep(3, number: 4, color: .orange, text: "Master it")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 4: Privacy

    private var privacyPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("Your Privacy")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(alignment: .leading, spacing: 14) {
                animatedPrivacyRow(0, icon: "xmark.shield.fill", text: "No data selling. Ever.")
                animatedPrivacyRow(1, icon: "eye.slash.fill", text: "No tracking.")
                animatedPrivacyRow(2, icon: "iphone", text: "AI runs on your device.")
                animatedPrivacyRow(3, icon: "heart.fill", text: "Your progress is yours.")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 5: Skill Level

    private var skillPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.layer(.handleVariety))
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            HStack(spacing: 6) {
                Text("Your Level")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                HelpButton(topic: .skillLevel)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            Text("You can change this anytime.")
                .font(.subheadline)
                .foregroundStyle(AppColor.tertiaryText)
                .opacity(itemVisible(0) ? 1 : 0)

            VStack(spacing: AppSpacing.md) {
                Text("\(settings.userELO)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())

                HStack(spacing: AppSpacing.xxl) {
                    Button {
                        withAnimation { settings.userELO = max(400, settings.userELO - 100) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(settings.userELO <= 400 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO <= 400)

                    Button {
                        withAnimation { settings.userELO = min(2000, settings.userELO + 100) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(settings.userELO >= 2000 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO >= 2000)
                }
                .accessibilityLabel("Your skill level: \(settings.userELO)")

                Text(eloDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .offset(y: itemVisible(1) ? 0 : 20)
            .opacity(itemVisible(1) ? 1 : 0)

            Spacer()

            Button {
                withAnimation { onComplete() }
            } label: {
                Text("Let's Go!")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Animated Components

    private func animatedBullet(_ index: Int, icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
        .offset(x: itemVisible(index) ? 0 : -30)
        .opacity(itemVisible(index) ? 1 : 0)
    }

    private func animatedStep(_ index: Int, number: Int, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text("\(number)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
            }
            .scaleEffect(itemVisible(index) ? 1 : 0.5)

            Text(text)
                .font(.title3)
                .foregroundStyle(AppColor.primaryText)
        }
        .opacity(itemVisible(index) ? 1 : 0)
        .offset(x: itemVisible(index) ? 0 : -20)
    }

    private func animatedPrivacyRow(_ index: Int, icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
                .scaleEffect(itemVisible(index) ? 1 : 0)
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
        }
        .opacity(itemVisible(index) ? 1 : 0)
        .offset(x: itemVisible(index) ? 0 : -20)
    }

    // MARK: - Shared

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

    private var eloDescription: String {
        switch settings.userELO {
        case ..<600: return "Complete beginner"
        case 600..<800: return "Beginner"
        case 800..<1000: return "Novice"
        case 1000..<1200: return "Intermediate"
        case 1200..<1500: return "Club player"
        case 1500..<1800: return "Advanced"
        default: return "Expert"
        }
    }
}
