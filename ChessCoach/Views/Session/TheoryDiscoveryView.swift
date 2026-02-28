import SwiftUI

/// Layer 3: "Discover the Theory"
/// After executing the plan, learn the classical names and canonical move orders.
/// Every slide shows a chess board. Quizzes are embedded inline and gate completion.
struct TheoryDiscoveryView: View {
    let opening: Opening
    let onComplete: (Double) -> Void  // quiz score (0.0-1.0)

    @State private var currentSection = 0
    @State private var quizResults: [Int: Bool] = [:]  // item index → correct/wrong
    @Environment(\.dismiss) private var dismiss

    private var plan: OpeningPlan? { opening.plan }
    private var responses: [OpponentResponse] { opening.opponentResponses?.responses ?? [] }
    private var afterMoves: [String] { opening.opponentResponses?.afterMoves ?? [] }
    private var isWhiteOpening: Bool { opening.color == .white }

    // MARK: - Item Construction

    private var items: [TheoryItem] {
        var result: [TheoryItem] = []

        // 1. "What You've Been Playing" — final main line position
        result.append(.board(LessonStep(
            title: "What You've Been Playing",
            description: "The game plan you've been practicing is called the \(opening.name). It has a rich history in competitive chess.",
            fen: finalMainLineFen,
            highlights: [],
            arrows: [],
            style: .neutral
        )))

        // 2. First curated theory lesson (e.g., Giuoco Piano)
        if let theoryLessons = plan?.theoryLessons, let first = theoryLessons.first {
            result.append(.board(first))
        }

        // 3. "Why This Move Order?" — canonical position
        if let plan = plan {
            result.append(.board(LessonStep(
                title: "Why This Specific Order?",
                description: "Masters refined this move order over centuries. The standard order ensures: \(plan.strategicGoals.prefix(2).map(\.description).joined(separator: ", and ")).",
                fen: fenAtPly(opening.mainLine.count / 2),
                highlights: [],
                arrows: [],
                style: .neutral
            )))
        }

        // 4. "Wrong order" example (second theory lesson)
        if let theoryLessons = plan?.theoryLessons, theoryLessons.count > 1 {
            result.append(.board(theoryLessons[1]))
        }

        // 5. First theory quiz (e.g., "Why must Nf3 come before Bc4?")
        if let quizzes = plan?.theoryQuizzes, quizzes.count > 0 {
            result.append(.quiz(quizzes[0]))
        }

        // 6. Remaining curated theory lessons
        if let theoryLessons = plan?.theoryLessons, theoryLessons.count > 2 {
            for step in theoryLessons.dropFirst(2) {
                result.append(.board(step))
            }
        }

        // 7. Named variations — overview board
        if !responses.isEmpty {
            let responseNames = responses.prefix(3).map { "\($0.name) (\($0.eco))" }.joined(separator: ", ")
            result.append(.board(LessonStep(
                title: "Named Variations",
                description: "When your opponent responds, each major choice has a name: \(responseNames). Knowing these names helps you find resources and discuss positions.",
                fen: decisionPointFen,
                highlights: [],
                arrows: [],
                style: .neutral
            )))

            // Auto-generated board for each opponent response
            for response in responses {
                let step = lessonStepForResponse(response)
                result.append(.board(step))
            }
        }

        // 8. Second theory quiz (e.g., variation identification)
        if let quizzes = plan?.theoryQuizzes, quizzes.count > 1 {
            result.append(.quiz(quizzes[1]))
        }

        // 9. Historical context
        if let note = plan?.historicalNote {
            result.append(.board(LessonStep(
                title: "A Bit of History",
                description: note,
                fen: finalMainLineFen,
                highlights: [],
                arrows: [],
                style: .neutral
            )))
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

    private var isBlockedByQuiz: Bool {
        guard currentSection < items.count else { return false }
        let item = items[currentSection]
        if case .quiz = item {
            return quizResults[currentSection] == nil
        }
        return false
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Close button + progress dots
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Circle()
                            .fill(i <= currentSection ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                // Balance the close button
                Color.clear.frame(width: 30, height: 30)
            }
            .padding(.horizontal)
            .padding(.top)

            // Content
            TabView(selection: $currentSection) {
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

            // Navigation
            HStack {
                if currentSection > 0 {
                    Button("Back") {
                        withAnimation { currentSection -= 1 }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentSection < items.count, case .summary = items[currentSection] {
                    // Summary slide: buttons handled inside summaryView
                } else if currentSection < items.count - 1 {
                    Button("Next") {
                        withAnimation { currentSection += 1 }
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
                    ? "You've got a solid grasp of the \(opening.name) story!"
                    : "You might want to review the material before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("History Complete!")
                    .font(.title2.weight(.bold))
            }

            VStack(spacing: 12) {
                if quizAccuracy >= 0.6 || quizCount == 0 {
                    Button("I've Got It") {
                        onComplete(quizAccuracy)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Review Again") {
                        quizResults.removeAll()
                        withAnimation { currentSection = 0 }
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

    private var finalMainLineFen: String {
        fenAtPly(opening.mainLine.count)
    }

    /// The position at the decision point where opponent responses branch.
    private var decisionPointFen: String {
        let state = GameState()
        for move in afterMoves {
            state.makeMoveUCI(move)
        }
        return state.fen
    }

    private func fenAtPly(_ ply: Int) -> String {
        let state = GameState()
        let moves = opening.mainLine
        for i in 0..<min(ply, moves.count) {
            state.makeMoveUCI(moves[i].uci)
        }
        return state.fen
    }

    /// Auto-generate a LessonStep for an opponent response by replaying moves.
    private func lessonStepForResponse(_ response: OpponentResponse) -> LessonStep {
        let state = GameState()
        for move in afterMoves {
            state.makeMoveUCI(move)
        }
        state.makeMoveUCI(response.move.uci)
        let fen = state.fen
        let toSquare = String(response.move.uci.dropFirst(2).prefix(2))

        return LessonStep(
            title: "\(response.name) (\(response.eco))",
            description: response.description,
            fen: fen,
            highlights: [toSquare],
            arrows: [LessonArrow(
                from: String(response.move.uci.prefix(2)),
                to: toSquare
            )],
            style: .theory
        )
    }
}

// MARK: - Supporting Types

private enum TheoryItem {
    case board(LessonStep)
    case quiz(LessonQuiz)
    case summary
}
