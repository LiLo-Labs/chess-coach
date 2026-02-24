import SwiftUI
import Charts

/// Navigation target for the training pipeline.
enum TrainingNavigation: Identifiable, Equatable {
    case study(lineID: String)
    case guided(lineID: String)
    case unguided(lineID: String)
    case practice

    var id: String {
        switch self {
        case .study(let id): return "study-\(id)"
        case .guided(let id): return "guided-\(id)"
        case .unguided(let id): return "unguided-\(id)"
        case .practice: return "practice"
        }
    }
}

struct OpeningDetailView: View {
    let opening: Opening
    @State private var activeNavigation: TrainingNavigation?
    @State private var progress: OpeningProgress
    @State private var showLockedHint = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService

    init(opening: Opening) {
        self.opening = opening
        self._progress = State(initialValue: PersistenceService.shared.loadProgress(forOpening: opening.id))
    }

    private var allLines: [OpeningLine] {
        opening.lines ?? [
            OpeningLine(
                id: "\(opening.id)/main",
                name: "Main Line",
                moves: opening.mainLine,
                branchPoint: 0,
                parentLineID: nil
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                headerSection

                // Pipeline progress card
                pipelineProgressSection

                // Practice Opening CTA
                if progress.isPracticeUnlocked {
                    practiceButton
                }

                // Progress chart
                if progress.accuracyHistory.count >= 2 {
                    accuracyChartSection
                }

                // Lines section
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Lines & Variations")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)
                    Text("Tap a line to continue your training")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    ForEach(allLines) { line in
                        let unlocked = progress.isLineUnlocked(line.id, parentLineID: line.parentLineID)
                        let lp = progress.progress(forLine: line.id)

                        linePipelineRow(line: line, lineProgress: lp, isUnlocked: unlocked)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if unlocked {
                                    activeNavigation = nextStage(for: line, lineProgress: lp)
                                } else {
                                    showLockedHint = true
                                }
                            }

                        if line.id != allLines.last?.id {
                            Divider()
                                .padding(.leading, CGFloat(AppSpacing.screenPadding + CGFloat(lineDepth(line)) * 20))
                        }
                    }
                }
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .padding(AppSpacing.screenPadding)
        }
        .background(AppColor.background)
        .navigationTitle(opening.name)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FeedbackToolbarButton(screen: "Opening Detail")
            }
        }
        .onAppear {
            progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        }
        .fullScreenCover(item: $activeNavigation) { nav in
            switch nav {
            case .study(let lineID):
                if let line = allLines.first(where: { $0.id == lineID }) {
                    LineStudyView(
                        opening: opening,
                        line: line,
                        isPro: subscriptionService.isPro,
                        onStartPracticing: {
                            // Mark as studied and transition to guided
                            var prog = PersistenceService.shared.loadProgress(forOpening: opening.id)
                            if prog.lineProgress[lineID] == nil {
                                prog.lineProgress[lineID] = LineProgress(lineID: lineID, openingID: opening.id)
                            }
                            prog.lineProgress[lineID]?.hasStudied = true
                            PersistenceService.shared.saveProgress(prog)
                            activeNavigation = .guided(lineID: lineID)
                        }
                    )
                    .environment(subscriptionService)
                }
            case .guided(let lineID):
                SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .guided)
                    .environment(subscriptionService)
            case .unguided(let lineID):
                SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .unguided)
                    .environment(subscriptionService)
            case .practice:
                PracticeOpeningView(opening: opening, isPro: subscriptionService.isPro)
            }
        }
        .onChange(of: activeNavigation) { old, new in
            // Refresh progress when returning from any training view
            if old != nil && new == nil {
                progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
            }
        }
        .alert("Line Locked", isPresented: $showLockedHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Complete the parent line with 70%+ accuracy and 50%+ win rate to unlock this variation.")
        }
    }

    // MARK: - Pipeline Progress Section

    private var pipelineProgressSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Your Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)

            VStack(spacing: AppSpacing.sm) {
                pipelineStageLine(
                    icon: progress.studiedLineCount >= allLines.count ? "checkmark.circle.fill" : "circle",
                    iconColor: progress.studiedLineCount >= allLines.count ? AppColor.success : AppColor.study,
                    label: "Learn",
                    detail: "\(progress.studiedLineCount)/\(allLines.count) lines studied",
                    completed: progress.studiedLineCount,
                    total: allLines.count
                )

                pipelineStageLine(
                    icon: progress.guidedLineCount >= allLines.count ? "checkmark.circle.fill" : "circle",
                    iconColor: progress.guidedLineCount >= allLines.count ? AppColor.success : AppColor.guided,
                    label: "Guided",
                    detail: "\(progress.guidedLineCount)/\(allLines.count) lines practiced",
                    completed: progress.guidedLineCount,
                    total: allLines.count
                )

                pipelineStageLine(
                    icon: progress.unguidedLineCount >= allLines.count ? "checkmark.circle.fill" : "circle",
                    iconColor: progress.unguidedLineCount >= allLines.count ? AppColor.success : AppColor.unguided,
                    label: "Unguided",
                    detail: "\(progress.unguidedLineCount)/\(allLines.count) lines mastered",
                    completed: progress.unguidedLineCount,
                    total: allLines.count
                )

                if progress.practiceSessionCount > 0 {
                    pipelineStageLine(
                        icon: "target",
                        iconColor: AppColor.practice,
                        label: "Practice",
                        detail: "\(progress.practiceSessionCount) session\(progress.practiceSessionCount == 1 ? "" : "s") completed",
                        completed: progress.practiceSessionCount,
                        total: max(progress.practiceSessionCount, 5) // Show progress toward 5 sessions
                    )
                }
            }
        }
        .padding(AppSpacing.cardPadding)
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func pipelineStageLine(icon: String, iconColor: Color, label: String, detail: String, completed: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                // Mini progress bar
                if total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.primaryText.opacity(0.08))
                                .frame(height: 3)

                            Capsule()
                                .fill(completed >= total ? AppColor.success : iconColor)
                                .frame(width: geo.size.width * CGFloat(completed) / CGFloat(max(1, total)), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()
        }
    }

    // MARK: - Practice Opening CTA

    private var practiceButton: some View {
        Button {
            activeNavigation = .practice
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "target")
                    .font(.subheadline.weight(.semibold))
                Text("Practice Opening")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColor.practice, in: RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Per-line Pipeline Row

    private func linePipelineRow(line: OpeningLine, lineProgress: LineProgress, isUnlocked: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Indentation
            if lineDepth(line) > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<lineDepth(line), id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .padding(.horizontal, 9)
                    }
                }

                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.disabledText)
            }

            // Lock / book icon
            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.unguided.opacity(0.6))
            } else {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.study)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(line.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isUnlocked ? AppColor.primaryText : AppColor.primaryText.opacity(0.45))

                if isUnlocked {
                    // Mini pipeline: Learn -> Guided -> Unguided -> checkmark
                    miniPipeline(lineProgress: lineProgress, lineID: line.id)
                } else {
                    Text("Complete parent line first")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            Spacer()

            // CTA for next stage — now uses PillBadge via nextStageBadge
            if isUnlocked {
                let stage = nextStage(for: line, lineProgress: lineProgress)
                nextStageBadge(stage: stage)
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.md)
        .opacity(isUnlocked ? 1.0 : 0.6)
    }

    private func miniPipeline(lineProgress: LineProgress, lineID: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            miniStageChip("Learn", done: lineProgress.hasStudied, color: AppColor.study)
            Image(systemName: "arrow.right")
                .font(.system(size: 6))
                .foregroundStyle(AppColor.disabledText)
            miniStageChip("Guided", done: lineProgress.guidedCompletions > 0, color: AppColor.guided)
            Image(systemName: "arrow.right")
                .font(.system(size: 6))
                .foregroundStyle(AppColor.disabledText)
            miniStageChip("Unguided", done: lineProgress.unguidedCompletions > 0, color: AppColor.unguided)

            if lineProgress.unguidedCompletions > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.success)
            }
        }
    }

    private func miniStageChip(_ label: String, done: Bool, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(done ? color : AppColor.tertiaryText)
    }

    @ViewBuilder
    private func nextStageBadge(stage: TrainingNavigation) -> some View {
        switch stage {
        case .study:
            PillBadge(text: "Study", color: AppColor.study)
        case .guided:
            PillBadge(text: "Practice", color: AppColor.guided)
        case .unguided:
            PillBadge(text: "Unguided", color: AppColor.unguided)
        case .practice:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColor.success)
        }
    }

    /// Determine the next training stage for a line.
    private func nextStage(for line: OpeningLine, lineProgress: LineProgress) -> TrainingNavigation {
        if !lineProgress.hasStudied {
            return .study(lineID: line.id)
        }
        if lineProgress.guidedCompletions == 0 {
            return .guided(lineID: line.id)
        }
        if lineProgress.unguidedCompletions == 0 {
            return .unguided(lineID: line.id)
        }
        // All stages done — tapping cycles back to unguided for more practice
        return .unguided(lineID: line.id)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 10) {
                Circle()
                    .fill(opening.color == .white ? Color.white : Color(white: 0.35))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(opening.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    HStack(spacing: AppSpacing.xxs) {
                        ForEach(0..<opening.difficulty, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.gold)
                        }
                        ForEach(0..<(5 - opening.difficulty), id: \.self) { _ in
                            Image(systemName: "star")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.disabledText)
                        }
                    }
                }

                Spacer()

                // Last-played timestamp
                if let lastPlayed = progress.lastPlayed {
                    Text(TimeAgo.string(from: lastPlayed))
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }

            Text(opening.description)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accuracy Chart

    private var accuracyChartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Accuracy Trend")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)

            let history = Array(progress.accuracyHistory.suffix(20))
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { index, accuracy in
                    LineMark(
                        x: .value("Session", index + 1),
                        y: .value("Accuracy", accuracy * 100)
                    )
                    .foregroundStyle(AppColor.phase(progress.currentPhase))

                    PointMark(
                        x: .value("Session", index + 1),
                        y: .value("Accuracy", accuracy * 100)
                    )
                    .foregroundStyle(AppColor.phase(progress.currentPhase))
                    .symbolSize(20)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) {
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
        .padding(AppSpacing.cardPadding)
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func lineDepth(_ line: OpeningLine) -> Int {
        if line.parentLineID == nil { return 0 }
        return 1
    }
}

// MARK: - String Identifiable for fullScreenCover

extension String: @retroactive Identifiable {
    public var id: String { self }
}
