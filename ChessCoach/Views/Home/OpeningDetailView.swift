import SwiftUI

/// Navigation target for the 5-layer training pipeline.
enum TrainingNavigation: Identifiable, Equatable {
    case planUnderstanding
    case executePlan(lineID: String)
    case discoverTheory
    case handleVariety(lineID: String)
    case realConditions(lineID: String)
    // Legacy
    case study(lineID: String)
    case guided(lineID: String)
    case unguided(lineID: String)
    case practice

    var id: String {
        switch self {
        case .planUnderstanding: return "planUnderstanding"
        case .executePlan(let id): return "execute-\(id)"
        case .discoverTheory: return "discoverTheory"
        case .handleVariety(let id): return "variety-\(id)"
        case .realConditions(let id): return "real-\(id)"
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
    @State private var mastery: OpeningMastery
    @State private var progress: OpeningProgress
    @State private var showLockedHint = false
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppServices.self) private var appServices

    init(opening: Opening) {
        self.opening = opening
        let openingID = opening.id
        self._mastery = State(initialValue:
            PersistenceService.shared.loadMastery(forOpening: openingID)
            ?? OpeningMastery(openingID: openingID)
        )
        self._progress = State(initialValue: PersistenceService.shared.loadProgress(forOpening: opening.id))
    }

    private var allLines: [OpeningLine] {
        opening.lines ?? [
            OpeningLine(
                id: "\(opening.id)/main",
                name: OpeningNode.generateLineName(moves: opening.mainLine),
                moves: opening.mainLine,
                branchPoint: 0,
                parentLineID: nil
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                headerSection

                // Animated board preview
                OpeningPreviewBoard(opening: opening)

                // Plan summary (if available)
                if let plan = opening.plan {
                    planSummaryCard(plan: plan)
                }

                // 5-layer pipeline progress
                layerPipelineSection

                // Lines section (for advanced users)
                if mastery.currentLayer >= .executePlan {
                    linesPanel
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColor.background)
        .navigationTitle(opening.name)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    FeedbackToolbarButton(screen: "Opening Detail")
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { refreshData() }) {
            OpeningSettingsView(opening: opening)
        }
        .onAppear { refreshData() }
        .conceptIntro(.whatAreOpenings)
        .fullScreenCover(item: $activeNavigation) { nav in
            navigationDestination(for: nav)
        }
        .onChange(of: activeNavigation) { old, new in
            if old != nil && new == nil {
                refreshData()
            }
        }
        .alert("Locked", isPresented: $showLockedHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Upgrade to Pro to access Layers 4-5 with opponent variety and real conditions.")
        }
    }

    private func refreshData() {
        mastery = PersistenceService.shared.loadMastery(forOpening: opening.id)
            ?? OpeningMastery(openingID: opening.id)
        progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func navigationDestination(for nav: TrainingNavigation) -> some View {
        switch nav {
        case .planUnderstanding:
            PlanUnderstandingView(opening: opening) { quizScore in
                var m = mastery
                m.completePlanUnderstanding(quizScore: quizScore)
                PersistenceService.shared.saveMastery(m)
                mastery = m
                activeNavigation = nil
            }
        case .executePlan(let lineID):
            SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .guided, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .discoverTheory:
            TheoryDiscoveryView(opening: opening) { quizScore in
                var m = mastery
                m.completeTheoryDiscovery(quizScore: quizScore)
                PersistenceService.shared.saveMastery(m)
                mastery = m
                activeNavigation = nil
            }
        case .handleVariety(let lineID):
            SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .unguided, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .realConditions(let lineID):
            SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .practice, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .study(let lineID):
            if let line = allLines.first(where: { $0.id == lineID }) {
                LineStudyView(
                    opening: opening,
                    line: line,
                    isPro: subscriptionService.isPro,
                    onStartPracticing: {
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
            SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .guided, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .unguided(let lineID):
            SessionView(opening: opening, lineID: lineID, isPro: subscriptionService.isPro, sessionMode: .unguided, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .practice:
            PracticeOpeningView(opening: opening, stockfish: appServices.stockfish)
        }
    }

    // MARK: - Hero Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Color + name row
            HStack(alignment: .center, spacing: AppSpacing.md) {
                // Refined color indicator
                ZStack {
                    Circle()
                        .fill(opening.color == .white
                              ? LinearGradient(colors: [.white, Color(white: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color(white: 0.28), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 42, height: 42)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(opening.color == .white ? "White Opening" : "Black Opening")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    // Difficulty dots
                    HStack(spacing: 4) {
                        Text("Difficulty")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppColor.tertiaryText)
                        HelpButton(topic: .difficulty)
                        ForEach(0..<opening.difficulty, id: \.self) { _ in
                            Circle()
                                .fill(AppColor.gold)
                                .frame(width: 6, height: 6)
                        }
                        ForEach(0..<(5 - opening.difficulty), id: \.self) { _ in
                            Circle()
                                .fill(AppColor.disabledText.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }

                Spacer()

                // Current stage + last played
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    PillBadge(
                        text: mastery.currentLayer.shortName,
                        color: AppColor.layer(mastery.currentLayer)
                    )
                    if let lastPlayed = mastery.lastPlayed {
                        Text(TimeAgo.string(from: lastPlayed))
                            .font(.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }
            }

            // Description
            Text(opening.description)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }

    // MARK: - Plan Summary Card

    private func planSummaryCard(plan: OpeningPlan) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header row
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cyan.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.cyan)
                }

                Text("The Game Plan")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)

                Spacer()
            }

            Text(plan.summary)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .lineSpacing(3)

            // Key squares
            if !plan.keySquares.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Important Squares")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    HStack(spacing: AppSpacing.xs) {
                        ForEach(plan.keySquares, id: \.self) { square in
                            Text(square)
                                .font(.caption.weight(.bold).monospaced())
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }

            // Strategic goals
            let topGoals = plan.strategicGoals.prefix(3)
            if !topGoals.isEmpty {
                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("What You're Aiming For")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    ForEach(Array(topGoals.enumerated()), id: \.offset) { _, goal in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.green.opacity(0.8))
                                .padding(.top, 1)
                            Text(goal.description)
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.cardBackground)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.cyan.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: - 5-Layer Pipeline Section

    private var layerPipelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Learning Journey")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)
                        HelpButton(topic: .learningJourney)
                    }
                    Text(mastery.currentLayer.displayName)
                        .font(.caption)
                        .foregroundStyle(AppColor.layer(mastery.currentLayer))
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.top, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.md)

            Divider()
                .opacity(0.3)
                .padding(.horizontal, AppSpacing.cardPadding)

            // Layer rows
            VStack(spacing: 0) {
                ForEach(Array(LearningLayer.allCases.enumerated()), id: \.element.rawValue) { index, layer in
                    layerRow(layer: layer, index: index)

                    if index < LearningLayer.allCases.count - 1 {
                        // Inset connector line between rows
                        HStack {
                            Spacer().frame(width: AppSpacing.cardPadding + 15)
                            Rectangle()
                                .fill(connectorColor(forIndex: index))
                                .frame(width: 1, height: 8)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.bottom, AppSpacing.sm)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.cardBackground)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        }
    }

    private func connectorColor(forIndex index: Int) -> Color {
        let layer = LearningLayer.allCases[index]
        let isComplete = mastery.currentLayer.rawValue > layer.rawValue
        return isComplete ? AppColor.layer(layer).opacity(0.4) : Color.white.opacity(0.08)
    }

    private func layerRow(layer: LearningLayer, index: Int) -> some View {
        let isCurrent = mastery.currentLayer == layer
        let isCompleted = mastery.currentLayer.rawValue > layer.rawValue
        let isLocked = !isCompleted && !isCurrent
        let isFree = layer.isFreeLayer
        let canAccess = isFree || subscriptionService.isPro

        return Button {
            if isLocked && !canAccess {
                showLockedHint = true
            } else if isCurrent || isCompleted {
                navigateToLayer(layer)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Step indicator
                ZStack {
                    Circle()
                        .fill(isCompleted
                              ? AppColor.layer(layer)
                              : (isCurrent ? AppColor.layer(layer).opacity(0.2) : Color.white.opacity(0.05)))
                        .frame(width: 30, height: 30)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: AppColor.layerIcon(layer))
                            .font(.system(size: 12))
                            .foregroundStyle(isCurrent ? AppColor.layer(layer) : AppColor.disabledText)
                    }
                }

                // Text content
                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(layer.displayName)
                            .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                            .foregroundStyle(isLocked ? AppColor.tertiaryText : AppColor.primaryText)

                        if isCurrent {
                            Text("CURRENT")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(AppColor.layer(layer))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(AppColor.layer(layer).opacity(0.15), in: Capsule())
                        }

                        if !isFree && !subscriptionService.isPro && isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                    }

                    Text(layerDetail(layer))
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                // CTA chevron
                if isCurrent {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.layer(layer))
                } else if isCompleted {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.md)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColor.layer(layer).opacity(0.07))
                        .padding(.horizontal, AppSpacing.xs)
                }
            }
            .opacity(isLocked ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func layerDetail(_ layer: LearningLayer) -> String {
        switch layer {
        case .understandPlan:
            return mastery.planUnderstanding ? "Completed" : "Learn what you're aiming for"
        case .executePlan:
            if mastery.executionScores.isEmpty {
                return "Play it your way"
            }
            return mastery.isExecutionComplete ? "Complete" : "Keep practicing"
        case .discoverTheory:
            return mastery.theoryCompleted ? "Completed" : "Discover the history"
        case .handleVariety:
            let count = mastery.varietyResponseCount
            return count > 0 ? "\(count)/3 responses handled" : "Face different opponents"
        case .realConditions:
            if mastery.realConditionScores.isEmpty {
                return "No hints — just you and the board"
            }
            return "\(mastery.realConditionScores.count) sessions completed"
        }
    }

    private func navigateToLayer(_ layer: LearningLayer) {
        let mainLineID = allLines.first?.id ?? "\(opening.id)/main"
        switch layer {
        case .understandPlan:
            activeNavigation = .planUnderstanding
        case .executePlan:
            activeNavigation = .executePlan(lineID: mainLineID)
        case .discoverTheory:
            activeNavigation = .discoverTheory
        case .handleVariety:
            activeNavigation = .handleVariety(lineID: mainLineID)
        case .realConditions:
            activeNavigation = .realConditions(lineID: mainLineID)
        }
    }

    // MARK: - Lines Panel

    private var linesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Paths")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)
                        HelpButton(topic: .paths)
                    }
                    Text("Tap to practice")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                Spacer()
                Text("\(allLines.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColor.tertiaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppColor.tertiaryText.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.top, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.md)

            Divider()
                .opacity(0.3)

            VStack(spacing: 0) {
                ForEach(Array(allLines.enumerated()), id: \.element.id) { index, line in
                    let lp = progress.progress(forLine: line.id)
                    let unlocked = progress.isLineUnlocked(line.id, parentLineID: line.parentLineID)

                    lineRow(line: line, lp: lp, unlocked: unlocked)

                    if index < allLines.count - 1 {
                        Divider()
                            .padding(.leading, AppSpacing.cardPadding + 32 + AppSpacing.md)
                            .opacity(0.25)
                    }
                }
            }
            .padding(.bottom, AppSpacing.xs)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.cardBackground)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        }
    }

    private func lineRow(line: OpeningLine, lp: LineProgress, unlocked: Bool) -> some View {
        Button {
            if unlocked {
                activeNavigation = .executePlan(lineID: line.id)
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(unlocked
                              ? AppColor.layer(.executePlan).opacity(0.12)
                              : Color.white.opacity(0.05))
                        .frame(width: 32, height: 32)
                    Image(systemName: unlocked ? "book.fill" : "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(unlocked ? AppColor.layer(.executePlan) : AppColor.disabledText)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(line.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(unlocked ? AppColor.primaryText : AppColor.tertiaryText)

                    if lp.guidedCompletions > 0 || lp.unguidedCompletions > 0 {
                        HStack(spacing: AppSpacing.sm) {
                            if lp.guidedCompletions > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "eye.fill")
                                        .font(.system(size: 8))
                                    Text("\(lp.guidedCompletions) with hints")
                                        .font(.caption2)
                                }
                                .foregroundStyle(AppColor.tertiaryText)
                            }
                            if lp.unguidedCompletions > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "brain.fill")
                                        .font(.system(size: 8))
                                    Text("\(lp.unguidedCompletions) without hints")
                                        .font(.caption2)
                                }
                                .foregroundStyle(AppColor.tertiaryText)
                            }
                        }
                    }
                }

                Spacer()

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.md)
            .opacity(unlocked ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
    }
}
