import SwiftUI

/// First-run onboarding flow — warm, inviting, and beginner-friendly.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var page = 0

    /// Called when the user finishes onboarding. The caller decides what comes next
    /// (e.g. opening picker for free users, or straight to HomeView for paid users).
    var onComplete: () -> Void = {}

    private let totalPages = 6

    // Staggered entry animation states
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showContent = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                whatYouGetPage.tag(1)
                philosophyPage.tag(2)
                howItWorksPage.tag(3)
                privacyPage.tag(4)
                skillPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                Spacer()
                HStack(alignment: .center) {
                    if page < totalPages - 1 {
                        Button("Skip") {
                            onComplete()
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
        .onChange(of: page) { _, _ in
            triggerEntryAnimations()
        }
        .onAppear {
            triggerEntryAnimations()
        }
    }

    // MARK: - Entry Animations

    private func triggerEntryAnimations() {
        // Reset
        showIcon = false
        showTitle = false
        showContent = false
        showButton = false

        // Stagger in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
            showIcon = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25)) {
            showTitle = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4)) {
            showContent = true
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.55)) {
            showButton = true
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppColor.gold)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("Welcome to ChessCoach")
                .font(.title.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(spacing: AppSpacing.sm) {
                Text("Your personal guide to mastering chess openings.")
                    .font(.title3)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)

                Text("No experience needed. We'll start from the beginning.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 2: What You Get

    private var whatYouGetPage: some View {
        VStack(spacing: AppSpacing.xxl) {
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

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                bulletPoint(
                    icon: "chess.board.fill",
                    color: .cyan,
                    text: "The first 10-15 moves of every chess game follow a **plan**"
                )
                bulletPoint(
                    icon: "brain",
                    color: .blue,
                    text: "Strong players have studied these plans for **centuries**"
                )
                bulletPoint(
                    icon: "map.fill",
                    color: .indigo,
                    text: "We'll teach you **proven strategies** so you always know what to do"
                )
                bulletPoint(
                    icon: "star.fill",
                    color: .orange,
                    text: "No memorization — just understanding **why** each move works"
                )
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 3: Philosophy

    private var philosophyPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("Our Belief")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(spacing: AppSpacing.lg) {
                Text("We believe you learn best when you understand **why** — not by memorizing moves.")
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)

                Text("Every move in chess has a reason. When you understand the reason, you don't need to memorize the move — it becomes the obvious choice.")
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)

                Text("That's what makes ChessCoach different. We teach the **plan**, not the moves.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 4: How It Works

    private var howItWorksPage: some View {
        VStack(spacing: AppSpacing.xxl) {
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

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                stepRow(number: 1, color: .cyan, text: "Learn the plan behind the moves")
                stepRow(number: 2, color: .blue, text: "Practice playing it with guidance")
                stepRow(number: 3, color: .indigo, text: "Discover the history and famous games")
                stepRow(number: 4, color: .orange, text: "Face opponents who surprise you")
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Text("We'll guide you every step of the way.")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)
                .opacity(showContent ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 5: Privacy

    private var privacyPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("Your Privacy Matters")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(spacing: AppSpacing.lg) {
                Text("We want to be upfront with you:")
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    privacyRow(icon: "xmark.shield.fill", color: .green, text: "We will **never** sell your data")
                    privacyRow(icon: "eye.slash.fill", color: .green, text: "We don't track your behavior")
                    privacyRow(icon: "iphone", color: .green, text: "AI coaching runs **on your device**")
                    privacyRow(icon: "heart.fill", color: .pink, text: "Your progress is **yours** — always")
                }
                .padding(.horizontal, AppSpacing.md)

                Text("We built this app because we love chess and teaching. That's it.")
                    .font(.subheadline.italic())
                    .foregroundStyle(AppColor.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 6: Skill Level

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
                Text("What's your level?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                HelpButton(topic: .skillLevel)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            Text("This helps us adjust coaching difficulty. You can change it anytime.")
                .font(.body)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)
                .opacity(showContent ? 1 : 0)

            VStack(spacing: AppSpacing.md) {
                Text("\(settings.userELO)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())

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
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1 : 0)

            Spacer()

            Button {
                withAnimation {
                    onComplete()
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
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
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

    private func bulletPoint(icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private func stepRow(number: Int, color: Color, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "\(number).circle.fill")
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private func privacyRow(icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.primaryText)
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
