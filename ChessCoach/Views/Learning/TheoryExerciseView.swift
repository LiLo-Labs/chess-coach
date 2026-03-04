import SwiftUI
import ChessKit

/// Layer 3 sub-milestones: "Name That Opening" and "Spot the Variation."
/// Auto-generates questions from opening.opponentResponses.
struct TheoryExerciseView: View {
    let opening: Opening
    let mode: ExerciseMode
    let onComplete: (Bool) -> Void // true if passed

    enum ExerciseMode: Equatable {
        case naming   // Show position, pick correct variation name
        case spotting // Show partial moves, identify variation
    }

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var correctCount = 0
    @State private var selectedAnswer: String?
    @State private var showResult = false
    @State private var isFinished = false
    @Environment(\.dismiss) private var dismiss

    private var totalRequired: Int { mode == .naming ? 8 : 6 }
    private var passThreshold: Int { mode == .naming ? 6 : 4 }

    struct Question: Identifiable {
        let id = UUID()
        let prompt: String       // Board FEN or move text
        let correctAnswer: String
        let options: [String]
        let fen: String?         // For board display
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                VStack(spacing: AppSpacing.xxxs) {
                    Text(mode == .naming ? "Name That Opening" : "Spot the Variation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("\(currentIndex + 1)/\(questions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                // Score
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.success)
                    Text("\(correctCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AppColor.success)
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.md)

            if isFinished {
                finishedView
            } else if currentIndex < questions.count {
                questionView(questions[currentIndex])
            }

            Spacer()
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .onAppear { generateQuestions() }
    }

    // MARK: - Question View

    @ViewBuilder
    private func questionView(_ question: Question) -> some View {
        VStack(spacing: AppSpacing.lg) {
            // Board or move display
            if let fen = question.fen {
                let state = GameState(fen: fen)
                let perspective: PieceColor = opening.color == .white ? .white : .black
                GameBoardView(gameState: state, perspective: perspective, allowInteraction: false)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: 280)
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .allowsHitTesting(false)
            } else {
                // Move sequence display for spotting mode
                Text(question.prompt)
                    .font(.title3.weight(.medium).monospaced())
                    .foregroundStyle(AppColor.primaryText)
                    .padding(AppSpacing.cardPadding)
                    .frame(maxWidth: .infinity)
                    .cardBackground()
                    .padding(.horizontal, AppSpacing.screenPadding)
            }

            Text(mode == .naming ? "Which variation is this?" : "Which variation do these moves belong to?")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)

            // Answer options
            VStack(spacing: AppSpacing.sm) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        guard selectedAnswer == nil else { return }
                        selectedAnswer = option
                        showResult = true
                        if option == question.correctAnswer {
                            correctCount += 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            selectedAnswer = nil
                            showResult = false
                            currentIndex += 1
                            if currentIndex >= questions.count {
                                isFinished = true
                            }
                        }
                    } label: {
                        HStack {
                            Text(option)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(answerColor(option, correct: question.correctAnswer))
                            Spacer()
                            if showResult && option == question.correctAnswer {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColor.success)
                            } else if showResult && option == selectedAnswer && option != question.correctAnswer {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.error)
                            }
                        }
                        .padding(.horizontal, AppSpacing.cardPadding)
                        .padding(.vertical, AppSpacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(answerBackground(option, correct: question.correctAnswer))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAnswer != nil)
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
        }
    }

    private func answerColor(_ option: String, correct: String) -> Color {
        guard showResult else { return AppColor.primaryText }
        if option == correct { return AppColor.success }
        if option == selectedAnswer { return AppColor.error }
        return AppColor.tertiaryText
    }

    private func answerBackground(_ option: String, correct: String) -> Color {
        guard showResult else { return AppColor.cardBackground }
        if option == correct { return AppColor.success.opacity(0.1) }
        if option == selectedAnswer { return AppColor.error.opacity(0.1) }
        return AppColor.cardBackground.opacity(0.5)
    }

    // MARK: - Finished View

    private var finishedView: some View {
        VStack(spacing: AppSpacing.lg) {
            let passed = correctCount >= passThreshold

            Image(systemName: passed ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(passed ? AppColor.success : AppColor.warning)

            Text(passed ? "Great job!" : "Keep practicing!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            Text("\(correctCount)/\(questions.count) correct")
                .font(.title3.monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)

            Text(passed
                 ? "You know your variations well."
                 : "You need \(passThreshold) correct to pass. Try again!")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpacing.sm) {
                Button {
                    onComplete(passed)
                    dismiss()
                } label: {
                    Text(passed ? "Continue" : "Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .buttonBackground(passed ? AppColor.success : AppColor.cardBackground)
                }

                if !passed {
                    Button {
                        // Reset and retry
                        currentIndex = 0
                        correctCount = 0
                        isFinished = false
                        generateQuestions()
                    } label: {
                        Text("Try Again")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppColor.layer(.discoverTheory))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xxl)
        }
        .padding(.top, AppSpacing.xxxl)
    }

    // MARK: - Question Generation

    private func generateQuestions() {
        guard let responses = opening.opponentResponses?.responses, responses.count >= 2 else {
            // Fallback: generate from lines
            generateFromLines()
            return
        }

        switch mode {
        case .naming:
            questions = generateNamingQuestions(from: responses)
        case .spotting:
            questions = generateSpottingQuestions(from: responses)
        }
    }

    private func generateNamingQuestions(from responses: [OpponentResponse]) -> [Question] {
        // Generate positions by replaying moves, then ask which variation
        var qs: [Question] = []
        let allNames = responses.map(\.name)

        for response in responses.shuffled().prefix(totalRequired) {
            // Build FEN by replaying afterMoves + response move
            let state = GameState()
            if let afterMoves = opening.opponentResponses?.afterMoves {
                for uci in afterMoves {
                    state.makeMoveUCI(uci)
                }
            }
            state.makeMoveUCI(response.move.uci)

            // Generate wrong answers from other responses
            var options = [response.name]
            let wrongs = allNames.filter { $0 != response.name }.shuffled().prefix(3)
            options.append(contentsOf: wrongs)
            // Pad if needed
            while options.count < 4 {
                options.append("Unknown Variation")
            }

            qs.append(Question(
                prompt: response.name,
                correctAnswer: response.name,
                options: options.shuffled(),
                fen: state.fen
            ))
        }

        return Array(qs.prefix(totalRequired))
    }

    private func generateSpottingQuestions(from responses: [OpponentResponse]) -> [Question] {
        var qs: [Question] = []
        let allNames = responses.map(\.name)

        for response in responses.shuffled().prefix(totalRequired) {
            // Show the move sequence as text
            let moveText: String
            if let afterMoves = opening.opponentResponses?.afterMoves {
                let sanMoves = afterMoves.enumerated().map { i, uci in
                    let state = GameState()
                    for prev in afterMoves.prefix(i) {
                        state.makeMoveUCI(prev)
                    }
                    return state.sanForUCI(uci) ?? uci
                }
                moveText = (sanMoves + [response.move.san]).joined(separator: " ")
            } else {
                moveText = response.move.san
            }

            var options = [response.name]
            let wrongs = allNames.filter { $0 != response.name }.shuffled().prefix(3)
            options.append(contentsOf: wrongs)
            while options.count < 4 {
                options.append("Unknown Variation")
            }

            qs.append(Question(
                prompt: moveText,
                correctAnswer: response.name,
                options: options.shuffled(),
                fen: nil
            ))
        }

        return Array(qs.prefix(totalRequired))
    }

    private func generateFromLines() {
        guard let lines = opening.lines, lines.count >= 2 else {
            // Not enough data — just complete
            isFinished = true
            return
        }

        let allNames = lines.map(\.name)

        switch mode {
        case .naming:
            questions = lines.shuffled().prefix(totalRequired).map { line in
                let state = GameState()
                for move in line.moves {
                    state.makeMoveUCI(move.uci)
                }
                var options = [line.name]
                options.append(contentsOf: allNames.filter { $0 != line.name }.shuffled().prefix(3))
                return Question(
                    prompt: line.name,
                    correctAnswer: line.name,
                    options: options.shuffled(),
                    fen: state.fen
                )
            }
        case .spotting:
            questions = lines.shuffled().prefix(totalRequired).map { line in
                let moveText = line.moves.prefix(6).map(\.san).joined(separator: " ")
                var options = [line.name]
                options.append(contentsOf: allNames.filter { $0 != line.name }.shuffled().prefix(3))
                return Question(
                    prompt: moveText,
                    correctAnswer: line.name,
                    options: options.shuffled(),
                    fen: nil
                )
            }
        }
    }
}
