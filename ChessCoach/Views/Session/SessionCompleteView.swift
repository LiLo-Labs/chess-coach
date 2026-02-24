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

    @State private var showPromotion = false
    @State private var showPersonalBest = false
    @State private var progressAnimationValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            // Improvement 18: Confetti on line completion
            if result?.phasePromotion != nil || result?.linePhasePromotion != nil || (result?.accuracy ?? 0) >= 0.8 {
                ConfettiView()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: AppSpacing.xxxl + AppSpacing.sm)

                    // Phase Promotion Banner
                    if let promo = result?.phasePromotion ?? result?.linePhasePromotion {
                        promotionBanner(promo: promo)
                    }

                    // Accuracy + Personal Best
                    accuracySection

                    // Extra stats: time and moves per minute
                    if result?.timeSpent != nil || result?.movesPerMinute != nil {
                        extraStatsSection
                    }

                    // Progress Toward Next Phase
                    if let result, result.nextPhaseThreshold != nil {
                        progressSection(result: result)
                    }

                    // Newly Unlocked Lines
                    if let result, !result.newlyUnlockedLines.isEmpty {
                        unlockedLinesSection(lines: result.newlyUnlockedLines)
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
            if let result, let threshold = result.nextPhaseThreshold {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.6)) {
                    progressAnimationValue = min(result.compositeScore / threshold, 1.0)
                }
            }
        }
    }

    // MARK: - Promotion Banner

    private func promotionBanner(promo: SessionResult.PhasePromotion) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppColor.phase(promo.to))
                .scaleEffect(showPromotion ? 1.0 : 0.5)
                .opacity(showPromotion ? 1.0 : 0)

            Text("Phase Up!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text(promo.to.displayName)
                .font(.headline)
                .foregroundStyle(AppColor.phase(promo.to))

            Text(promo.to.phaseDescription)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, AppSpacing.md)
        .sensoryFeedback(.success, trigger: showPromotion)
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

                    if result.isPersonalBest {
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
                    } else {
                        Text("accuracy")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                    }
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
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Progress Section

    private func progressSection(result: SessionResult) -> some View {
        VStack(spacing: AppSpacing.sm) {
            if let threshold = result.nextPhaseThreshold {
                ProgressView(value: progressAnimationValue)
                    .tint(AppColor.phase(result.phasePromotion?.to ?? currentPhaseFromScore(result)))
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progressAnimationValue)

                // Smart hint text
                if let gamesLeft = result.gamesUntilMinimum, gamesLeft > 0 {
                    Text("Play \(gamesLeft) more game\(gamesLeft == 1 ? "" : "s") to qualify")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                } else if result.compositeScore >= threshold - 5 {
                    Text("Almost there!")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.success)
                } else if let nextPhase = currentPhaseFromScore(result).nextPhase {
                    Text("\(Int(result.compositeScore))/\(Int(threshold)) to \(nextPhase.displayName)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
    }

    // MARK: - Unlocked Lines

    private func unlockedLinesSection(lines: [String]) -> some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(lines, id: \.self) { name in
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "lock.open.fill")
                        .font(.caption)
                        .foregroundStyle(AppColor.success)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.primaryText)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lines.count)
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
                    .background(AppColor.info.opacity(0.1), in: Capsule())
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
            // Next stage CTA (pipeline progression)
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
                    .background(AppColor.guided, in: Capsule())
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
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onDone) {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .padding(.horizontal, AppSpacing.xxl + AppSpacing.xxs)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.success, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            FeedbackButton(screen: "Session Complete")
        }
    }

    // MARK: - Helpers

    /// Format a time interval as "Xm Ys" or just "Ys" for durations under a minute.
    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Infer current phase from the session result for display purposes.
    private func currentPhaseFromScore(_ result: SessionResult) -> LearningPhase {
        if let promo = result.phasePromotion {
            return promo.to
        }
        // Infer from threshold
        if result.nextPhaseThreshold == nil { return .freePlay }
        if result.nextPhaseThreshold == 60 { return .learningMainLine }
        if result.nextPhaseThreshold == 70 { return .naturalDeviations }
        if result.nextPhaseThreshold == 75 { return .widerVariations }
        return .learningMainLine
    }
}
