import SwiftUI

/// Navigation target for opening play modes.
enum TrainingNavigation: Identifiable, Equatable {
    case guided(lineID: String?)
    case unguided(lineID: String?)
    case practice

    var id: String {
        switch self {
        case .guided(let id): return "guided-\(id ?? "nil")"
        case .unguided(let id): return "unguided-\(id ?? "nil")"
        case .practice: return "practice"
        }
    }
}

struct OpeningDetailView: View {
    let opening: Opening
    @State private var activeNavigation: TrainingNavigation?
    @State private var positions: [PositionMastery] = []
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppServices.self) private var appServices

    init(opening: Opening) {
        self.opening = opening
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

                // Play modes
                playModesSection

                // Lines section
                linesPanel
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
    }

    private func refreshData() {
        positions = PersistenceService.shared.loadAllPositionMastery().filter { $0.openingID == opening.id }
    }

    // MARK: - Navigation Destination

    @ViewBuilder
    private func navigationDestination(for nav: TrainingNavigation) -> some View {
        switch nav {
        case .guided(let lineID):
            GamePlayView(mode: .guided(opening: opening, lineID: lineID), isPro: subscriptionService.isPro, tier: subscriptionService.currentTier, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .unguided(let lineID):
            GamePlayView(mode: .unguided(opening: opening, lineID: lineID), isPro: subscriptionService.isPro, tier: subscriptionService.currentTier, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
        case .practice:
            GamePlayView(mode: .practice(opening: opening, lineID: nil), isPro: subscriptionService.isPro, tier: subscriptionService.currentTier, stockfish: appServices.stockfish, llmService: appServices.llmService)
                .environment(subscriptionService)
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

    // MARK: - Play Modes Section

    private var playModesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text("Play")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("Choose how to practice")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.top, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.md)

            Divider()
                .opacity(0.3)
                .padding(.horizontal, AppSpacing.cardPadding)

            VStack(spacing: 0) {
                playModeRow(
                    icon: "hand.raised.fill",
                    color: AppColor.guided,
                    title: "Guided",
                    subtitle: "Hints + coaching as you play",
                    action: { activeNavigation = .guided(lineID: allLines.first?.id) }
                )

                Divider()
                    .padding(.leading, AppSpacing.cardPadding + 32 + AppSpacing.md)
                    .opacity(0.25)

                playModeRow(
                    icon: "brain.fill",
                    color: .cyan,
                    title: "Unguided",
                    subtitle: "No hints, scored on plan execution",
                    action: { activeNavigation = .unguided(lineID: allLines.first?.id) }
                )

                Divider()
                    .padding(.leading, AppSpacing.cardPadding + 32 + AppSpacing.md)
                    .opacity(0.25)

                playModeRow(
                    icon: "figure.fencing",
                    color: .orange,
                    title: "Practice",
                    subtitle: "Varied opponent responses, no hints",
                    action: { activeNavigation = .practice }
                )
            }
            .padding(.bottom, AppSpacing.xs)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.cardBackground)
                .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
        }
    }

    private func playModeRow(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
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
                    Text("Tap to practice a specific line")
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
                    let linePositions = positions.filter { $0.lineID == line.id }

                    lineRow(line: line, linePositions: linePositions)

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

    private func lineRow(line: OpeningLine, linePositions: [PositionMastery]) -> some View {
        return Button {
            activeNavigation = .guided(lineID: line.id)
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColor.guided.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.guided)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(line.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)

                    if !linePositions.isEmpty {
                        let mastered = linePositions.filter(\.isMastered).count
                        Text("\(mastered)/\(linePositions.count) positions mastered")
                            .font(.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
    }
}
