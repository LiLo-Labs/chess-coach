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
    @State private var showPESScore = false
    @State private var progressAnimationValue: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            // Confetti on layer promotion, high PES (non-guided), or high accuracy (guided)
            if result?.layerPromotion != nil || result?.phasePromotion != nil || (sessionMode != .guided && (result?.averagePES ?? 0) >= 80) || (result?.accuracy ?? 0) >= 0.8 {
                ConfettiView()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: AppSpacing.xxxl + AppSpacing.sm)

                    // Layer Promotion Banner (new v2)
                    if let layerPromo = result?.layerPromotion {
                        layerPromotionBanner(promo: layerPromo)
                    }
                    // Legacy Phase Promotion Banner
                    else if let promo = result?.phasePromotion ?? result?.linePhasePromotion {
                        promotionBanner(promo: promo)
                    }

                    // PES Score for Layer 2+ non-guided, accuracy for guided/Layer 1
                    if sessionMode != .guided, let pes = result?.averagePES, pes > 0 {
                        pesSection(averagePES: pes, category: result?.pesCategory)
                    } else {
                        accuracySection
                    }

                    // Move score breakdown — only when PES is active
                    if sessionMode != .guided, let scores = result?.moveScores, !scores.isEmpty {
                        pesBreakdownSection(scores: scores)
                    }

                    // Extra stats: time and moves per minute
                    if result?.timeSpent != nil || result?.movesPerMinute != nil {
                        extraStatsSection
                    }

                    // Progress Toward Next Phase (legacy)
                    if let result, result.nextPhaseThreshold != nil, result.averagePES == nil {
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4)) {
                showPESScore = true
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

    // MARK: - Layer Promotion Banner

    private func layerPromotionBanner(promo: SessionResult.LayerPromotion) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: AppColor.layerIcon(promo.to))
                .font(.system(size: 44))
                .foregroundStyle(AppColor.layer(promo.to))
                .scaleEffect(showPromotion ? 1.0 : 0.5)
                .opacity(showPromotion ? 1.0 : 0)

            Text("Level Up!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text(promo.to.displayName)
                .font(.headline)
                .foregroundStyle(AppColor.layer(promo.to))

            Text(promo.to.layerDescription)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)
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
                        .scaleEffect(showPESScore ? 1.0 : 0.5)
                        .opacity(showPESScore ? 1.0 : 0)
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
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Accuracy Section (legacy)

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
