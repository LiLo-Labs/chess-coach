import SwiftUI

/// Layer 1: "Understand the Plan"
/// Interactive lesson teaching the opening's strategic concept.
/// Every slide has a chess board. Quizzes are embedded inline and gate completion.
struct PlanUnderstandingView: View {
    let opening: Opening
    let onComplete: (Double) -> Void  // quiz score (0.0-1.0)

    @State private var currentCard = 0
    @State private var quizResults: [Int: Bool] = [:]  // item index → correct/wrong

    private var plan: OpeningPlan? { opening.plan }
    private var isWhiteOpening: Bool { opening.color == .white }

    // MARK: - Item Construction

    private var items: [LessonItem] {
        guard let plan = plan else {
            return [.board(LessonStep(
                title: opening.name,
                description: opening.description,
                fen: finalMainLineFen,
                highlights: [],
                arrows: [],
                style: .neutral
            ))]
        }

        var result: [LessonItem] = []

        // 1. Overview — main line final position
        result.append(.board(LessonStep(
            title: "The \(opening.name) Plan",
            description: plan.summary,
            fen: finalMainLineFen,
            highlights: [],
            arrows: [],
            style: .neutral
        )))

        // 2. Board lessons (do this / don't do this)
        if let lessons = plan.planLessons {
            for step in lessons {
                result.append(.board(step))
            }
        }

        // 3. First quiz (after plan lessons)
        if let quizzes = plan.planQuizzes, quizzes.count > 0 {
            result.append(.quiz(quizzes[0]))
        }

        // 4. Strategic goals as board slides
        for goal in plan.strategicGoals {
            result.append(.board(LessonStep(
                title: "Goal \(goal.priority)",
                description: goal.description,
                fen: fenForGoal(goal),
                highlights: plan.keySquares,
                arrows: [],
                style: .neutral
            )))
        }

        // 5. Piece targets as board slides
        for target in plan.pieceTargets {
            result.append(.board(LessonStep(
                title: target.piece.capitalized,
                description: "\(target.reasoning). Aim for: \(target.idealSquares.joined(separator: " or "))",
                fen: target.fen ?? finalMainLineFen,
                highlights: target.idealSquares,
                arrows: [],
                style: .neutral
            )))
        }

        // 6. Second quiz (after piece targets)
        if let quizzes = plan.planQuizzes, quizzes.count > 1 {
            result.append(.quiz(quizzes[1]))
        }

        // 7. Common mistakes as board slide
        if !plan.commonMistakes.isEmpty {
            let mistakes = plan.commonMistakes.map { "• \($0)" }.joined(separator: "\n")
            // Reuse a "bad" lesson FEN if available, otherwise use mid-line FEN
            let badFen = plan.planLessons?.first(where: { $0.style == .bad })?.fen ?? fenAtPly(4)
            result.append(.board(LessonStep(
                title: "Watch Out For",
                description: mistakes,
                fen: badFen,
                highlights: [],
                arrows: [],
                style: .bad
            )))
        }

        // 8. Typical plans as board slide
        if !plan.typicalPlans.isEmpty {
            let plans = plan.typicalPlans.map { "• \($0)" }.joined(separator: "\n")
            result.append(.board(LessonStep(
                title: "After the Opening",
                description: plans,
                fen: finalMainLineFen,
                highlights: [],
                arrows: [],
                style: .neutral
            )))
        }

        // 9. Third quiz (if available)
        if let quizzes = plan.planQuizzes, quizzes.count > 2 {
            result.append(.quiz(quizzes[2]))
        }

        // 10. Summary slide (always last)
        result.append(.summary)

        return result
    }

    private var quizCount: Int {
        items.filter { if case .quiz = $0 { return true }; return false }.count
    }

    private var quizzesCorrect: Int {
        quizResults.values.filter { $0 }.count
    }

    private var quizAccuracy: Double {
        guard quizCount > 0 else { return 1.0 }
        return Double(quizzesCorrect) / Double(quizCount)
    }

    /// Whether the current slide is a quiz that hasn't been answered yet.
    private var isBlockedByQuiz: Bool {
        let item = items[currentCard]
        if case .quiz = item {
            return quizResults[currentCard] == nil
        }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Learn the Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(currentCard + 1)/\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * CGFloat(currentCard + 1) / CGFloat(items.count), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Card content
            TabView(selection: $currentCard) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Group {
                        switch item {
                        case .board(let step):
                            BoardLessonCard(step: step, perspective: isWhiteOpening)
                        case .quiz(let quiz):
                            QuizLessonCard(quiz: quiz, perspective: isWhiteOpening) { correct in
                                quizResults[index] = correct
                            }
                        case .summary:
                            summaryView
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Key squares display
            if let plan = plan {
                HStack(spacing: 12) {
                    Text("Important Squares:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(plan.keySquares, id: \.self) { square in
                        Text(square)
                            .font(.caption.weight(.bold).monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal)
            }

            // Navigation
            HStack {
                if currentCard > 0 {
                    Button("Back") {
                        withAnimation { currentCard -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if case .summary = items[currentCard] {
                    // Summary slide: buttons handled inside summaryView
                } else if currentCard < items.count - 1 {
                    Button("Next") {
                        withAnimation { currentCard += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBlockedByQuiz)
                }
            }
            .padding()
        }
    }

    // MARK: - Summary View

    @ViewBuilder
    private var summaryView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: quizAccuracy >= 0.6 ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(quizAccuracy >= 0.6 ? .green : .orange)

            if quizCount > 0 {
                Text("You scored \(quizzesCorrect)/\(quizCount)!")
                    .font(.title2.weight(.bold))

                Text(quizAccuracy >= 0.6
                    ? "Great understanding of the \(opening.name) plan!"
                    : "You might want to review the material before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("Lesson Complete!")
                    .font(.title2.weight(.bold))
            }

            VStack(spacing: 12) {
                if quizAccuracy >= 0.6 || quizCount == 0 {
                    Button("I Got It — Let's Play!") {
                        onComplete(quizAccuracy)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Review Again") {
                        quizResults.removeAll()
                        withAnimation { currentCard = 0 }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Continue Anyway") {
                        onComplete(quizAccuracy)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - FEN Helpers

    /// Final position of the main line.
    private var finalMainLineFen: String {
        fenAtPly(opening.mainLine.count)
    }

    /// Replay the main line to a given ply and return the FEN.
    private func fenAtPly(_ ply: Int) -> String {
        let state = GameState()
        let moves = opening.mainLine
        for i in 0..<min(ply, moves.count) {
            state.makeMoveUCI(moves[i].uci)
        }
        return state.fen
    }

    /// Pick a relevant FEN for a strategic goal.
    /// Uses the goal's explicit FEN if available, otherwise falls back to heuristic.
    private func fenForGoal(_ goal: StrategicGoal) -> String {
        if let fen = goal.fen { return fen }
        let moves = opening.mainLine
        // Fallback: map goal priority to an approximate ply in the main line
        let ply = min(goal.priority * 2, moves.count)
        return fenAtPly(ply)
    }
}

// MARK: - Supporting Types

private enum LessonItem {
    case board(LessonStep)
    case quiz(LessonQuiz)
    case summary
}
