import SwiftUI

struct SessionCompleteView: View {
    let result: SessionResult?
    let moveCount: Int
    let openingName: String
    let lineName: String?
    let sessionMode: SessionMode?
    let onTryAgain: () -> Void
    let onDone: () -> Void
    let onReviewNow: (() -> Void)?
    let onNextStage: (() -> Void)?
    var coachPersonality: CoachPersonality?

    @State private var showPromotion = false
    @State private var showPersonalBest = false
    @State private var showPESScore = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            // Confetti on familiarity milestone or high PES/accuracy
            if result?.familiarityMilestone != nil || (sessionMode != .guided && (result?.averagePES ?? 0) >= 80) || (result?.accuracy ?? 0) >= 0.8 {
                ConfettiView()
                    .ignoresSafeArea()
            }

            // Close button at top-right
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.top, AppSpacing.topBarSafeArea)
                .padding(.trailing, AppSpacing.screenPadding)
                Spacer()
            }
            .zIndex(1)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: AppSpacing.xxxl + AppSpacing.sm)

                    // Familiarity Milestone Banner
                    if let milestone = result?.familiarityMilestone {
                        familiarityMilestoneBanner(milestone: milestone)
                    }

                    // PES Score for non-guided when familiarity >= 30%
                    if sessionMode != .guided, let pes = result?.averagePES, pes > 0 {
                        pesSection(averagePES: pes, category: result?.pesCategory)
                    } else {
                        accuracySection
                    }

                    // Move score breakdown
                    if sessionMode != .guided, let scores = result?.moveScores, !scores.isEmpty {
                        pesBreakdownSection(scores: scores)
                    }

                    // Extra stats
                    if result?.timeSpent != nil || result?.movesPerMinute != nil {
                        extraStatsSection
                    }

                    // Familiarity progress indicator
                    if let pct = result?.familiarityPercentage, pct > 0 {
                        familiarityProgressSection(percentage: pct)
                    }

                    // Coach Session Message
                    if let coach = coachPersonality, let message = result?.coachSessionMessage {
                        coachMessageCard(coach: coach, message: message)
                    }

                    // Review Nudge
                    if let result, result.dueReviewCount > 0 {
                        reviewNudge(count: result.dueReviewCount)
                    }

                    // Buttons
                    buttonRow

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.xxxl)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) {
                showPromotion = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(0.5)) {
                showPersonalBest = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4)) {
                showPESScore = true
            }
        }
    }

    // MARK: - Familiarity Milestone Banner

    private func familiarityMilestoneBanner(milestone: FamiliarityMilestone) -> some View {
        let tier = milestone.tierReached
        let color = AppColor.familiarity(tier)

        return VStack(spacing: AppSpacing.sm) {
            Image(systemName: AppColor.familiarityIcon(tier))
                .font(.system(size: 44))
                .foregroundStyle(color)
                .reveal(isVisible: showPromotion, delay: 0)

            Text("\(milestone.thresholdPercentage)% Familiar!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text(tier.displayName)
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(.vertical, AppSpacing.md)
        .sensoryFeedback(.success, trigger: showPromotion)
    }

    // MARK: - PES Score Section

    private func pesSection(averagePES: Double, category: ScoreCategory?) -> some View {
        VStack(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.xxs) {
                Text("\(moveCount / 2) moves")
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                Text(openingName)
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                if let line = lineName {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            let cat = category ?? ScoreCategory.from(score: Int(averagePES))
            let pesColor = AppColor.pesColor(cat)

            VStack(spacing: AppSpacing.xs) {
                ZStack {
                    Circle()
                        .stroke(pesColor.opacity(0.2), lineWidth: 6)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: showPESScore ? min(averagePES / 100, 1.0) : 0)
                        .stroke(pesColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(averagePES))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.primaryText)
                        .reveal(isVisible: showPESScore, delay: 0)
                }

                PillBadge(text: cat.rawValue.uppercased(), color: pesColor, fontSize: 12)

                HStack(spacing: 4) {
                    Text("Plan Score")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    HelpButton(topic: .planScore)
                }
            }

            if let result, result.isPersonalBest {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(AppColor.gold)
                    Text("New Best!")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.gold)
                }
                .scaleEffect(showPersonalBest ? 1.0 : 0.8)
                .opacity(showPersonalBest ? 1.0 : 0)
                .sensoryFeedback(.impact(weight: .medium), trigger: showPersonalBest)
            }
        }
    }

    // MARK: - PES Breakdown

    private func pesBreakdownSection(scores: [PlanExecutionScore]) -> some View {
        VStack(spacing: AppSpacing.sm) {
            let avgSoundness = scores.map(\.soundness).reduce(0, +) / scores.count
            let avgAlignment = scores.map(\.alignment).reduce(0, +) / scores.count

            HStack(spacing: AppSpacing.lg) {
                VStack(spacing: AppSpacing.xxxs) {
                    Text("\(avgSoundness)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.green)
                    HStack(spacing: 2) {
                        Text("Move Safety")
                            .font(.caption2)
                            .foregroundStyle(AppColor.secondaryText)
                        HelpButton(topic: .moveSafety)
                    }
                }

                VStack(spacing: AppSpacing.xxxs) {
                    Text("\(avgAlignment)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.cyan)
                    HStack(spacing: 2) {
                        Text("Following the Plan")
                            .font(.caption2)
                            .foregroundStyle(AppColor.secondaryText)
                        HelpButton(topic: .followingPlan)
                    }
                }

                VStack(spacing: AppSpacing.xxxs) {
                    let avgPopularity = scores.map(\.popularity).reduce(0, +) / scores.count
                    Text(avgPopularity >= 0 ? "+\(avgPopularity)" : "\(avgPopularity)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                    Text("Popularity")
                        .font(.caption2)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground()
    }

    // MARK: - Accuracy Section

    private var accuracySection: some View {
        VStack(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.xxs) {
                Text("\(moveCount / 2) moves")
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                Text(openingName)
                    .font(.body)
                    .foregroundStyle(AppColor.secondaryText)
                if let line = lineName {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            if let result {
                VStack(spacing: AppSpacing.xxs) {
                    Text("\(Int(result.accuracy * 100))%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.primaryText)

                    Text("accuracy")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
    }

    // MARK: - Extra Stats Section

    private var extraStatsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            if let timeSpent = result?.timeSpent {
                StatRow(
                    icon: "clock.fill",
                    label: "Time spent",
                    value: formattedDuration(timeSpent),
                    color: AppColor.info
                )
            }

            if let mpm = result?.movesPerMinute {
                StatRow(
                    icon: "bolt.fill",
                    label: "Moves per minute",
                    value: String(format: "%.1f", mpm),
                    color: AppColor.warning
                )
            }
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground()
    }

    // MARK: - Familiarity Progress Section

    private func familiarityProgressSection(percentage: Int) -> some View {
        let tier = FamiliarityTier.from(progress: Double(percentage) / 100.0)
        let color = AppColor.familiarity(tier)

        return HStack(spacing: AppSpacing.md) {
            ProgressRing(progress: Double(percentage) / 100.0, color: color, lineWidth: 4, size: 40)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text("\(percentage)% Familiar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(tier.displayName)
                    .font(.caption)
                    .foregroundStyle(color)
            }

            Spacer()
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground()
    }

    // MARK: - Review Nudge

    private func reviewNudge(count: Int) -> some View {
        Group {
            if let onReviewNow {
                Button(action: onReviewNow) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(AppColor.info)
                        Text("You have \(count) position\(count == 1 ? "" : "s") to review")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.info)
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.vertical, AppSpacing.sm + AppSpacing.xxs)
                    .buttonBackground(AppColor.info.opacity(0.1))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(AppColor.info.opacity(0.7))
                    Text("You have \(count) position\(count == 1 ? "" : "s") to review")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        VStack(spacing: AppSpacing.md) {
            // Next stage CTA
            if let onNextStage, let mode = sessionMode {
                Button(action: onNextStage) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: mode == .guided ? "eye.slash" : "target")
                            .font(.subheadline)
                        Text(mode == .guided ? "Try Without Hints" : "Ready for the Real Test?")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(AppColor.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .buttonBackground(AppColor.guided)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.screenPadding)
            }

            HStack(spacing: AppSpacing.md) {
                Button(action: onTryAgain) {
                    Text("Try Again")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, AppSpacing.xxl)
                        .padding(.vertical, AppSpacing.md)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)

                Button(action: onDone) {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, AppSpacing.xxl + AppSpacing.xxs)
                        .padding(.vertical, AppSpacing.md)
                        .buttonBackground(AppColor.success)
                }
                .buttonStyle(.plain)
            }

            FeedbackButton(screen: "Session Complete")
        }
    }

    // MARK: - Coach Message Card

    private func coachMessageCard(coach: CoachPersonality, message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: coach.humanIcon)
                .font(.system(size: 16))
                .foregroundStyle(AppColor.info)
                .frame(width: 32, height: 32)
                .background(AppColor.info.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(coach.humanName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.info)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground()
    }

    // MARK: - Helpers

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
