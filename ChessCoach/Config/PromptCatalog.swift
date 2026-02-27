import Foundation

/// All LLM prompt templates in one place. Each is a static function that takes
/// typed parameters and returns a String — no business logic, just text assembly.
enum PromptCatalog {

    // MARK: - Coaching Prompts

    /// Prompt for when the STUDENT just made a move.
    static func userMovePrompt(for context: CoachingContext, boardSummary: String) -> String {
        let studentColor = context.studentColor ?? "White"

        let feedback: String
        switch context.moveCategory {
        case .goodMove:
            feedback = "The student played the correct \(context.openingName) move (\(context.lastMove)). Tell them why this move is good."
        case .okayMove:
            let expected = context.expectedMoveSAN ?? "the book move"
            feedback = "The student played \(context.lastMove), but the book move was \(expected). Briefly explain why \(expected) is preferred."
        case .mistake:
            let expected = context.expectedMoveSAN ?? "the book move"
            feedback = "The student played \(context.lastMove) instead of the book move \(expected). Gently explain what they should have played."
        default:
            feedback = ""
        }

        return """
        Side to move: \(studentColor)

        Board:
        \(boardSummary)

        Opening: \(context.openingName)
        Last move: \(context.lastMove)

        \(feedback)

        IMPORTANT: REFS must ONLY list squares where pieces currently sit on the board.

        Respond with ONLY:
        REFS: <up to 3 key squares with pieces on them>
        COACHING: <one sentence>
        """
    }

    /// Prompt for when the OPPONENT just made a move.
    static func opponentMovePrompt(for context: CoachingContext, boardSummary: String) -> String {
        let studentColor = context.studentColor ?? "White"
        let opponentColor = studentColor == "White" ? "Black" : "White"

        let guidance: String
        if context.moveCategory == .deviation {
            guidance = "The opponent deviated from the \(context.openingName) by playing \(context.lastMove). Explain that the student is now out of book."
        } else {
            guidance = "The opponent (\(opponentColor)) played \(context.lastMove). Explain what this move means for the student's position."
        }

        return """
        Side to move: \(studentColor)

        Board:
        \(boardSummary)

        Opening: \(context.openingName)
        Opponent's last move: \(context.lastMove)

        \(guidance)

        IMPORTANT: REFS must ONLY list squares where pieces currently sit on the board.

        Respond with ONLY:
        REFS: <up to 3 key squares with pieces on them>
        COACHING: <one sentence from the student's perspective>
        """
    }

    /// Wrapper prompt for coaching both user + opponent moves in a single LLM call.
    static func batchedPrompt(userPrompt: String, opponentPrompt: String) -> String {
        """
        You will provide coaching for TWO consecutive moves. Respond with BOTH sections.

        === MOVE 1 (Student's move) ===
        \(userPrompt)

        === MOVE 2 (Opponent's response) ===
        \(opponentPrompt)

        IMPORTANT: Format your response EXACTLY as:
        STUDENT:
        REFS: <piece references or "none">
        COACHING: <coaching text>
        OPPONENT:
        REFS: <piece references or "none">
        COACHING: <coaching text>
        """
    }

    // MARK: - Chat Prompt

    /// Line study Q&A prompt (Pro feature).
    static func chatPrompt(
        question: String,
        openingName: String,
        lineName: String,
        fen: String,
        boardSummary: String,
        occupiedSquares: String,
        moveHistory: String,
        currentPly: Int,
        userELO: Int
    ) -> String {
        """
        You are a friendly chess coach. The student (ELO ~\(userELO)) is studying the \(openingName) (\(lineName)).

        Board:
        \(boardSummary)

        Move history: \(moveHistory)
        Current ply: \(currentPly)

        The student asks: \(question)

        Explain clearly. Use simple language.
        Keep your response concise (2-4 sentences). Spell out piece names, avoid algebraic notation symbols.

        Squares that currently have pieces: \(occupiedSquares)
        REFS must ONLY use squares from the list above. Any square not listed is EMPTY.

        Respond with ONLY:
        REFS: <up to 3 squares from the occupied list, or "none">
        COACHING: <your explanation>
        """
    }

    // MARK: - Explanation Prompts

    /// Groups the parameters for explanation prompts.
    struct ExplanationPromptParams {
        let openingName: String
        let studentColor: String
        let opponentColor: String
        let userELO: Int
        let perspective: String
        let moveHistoryStr: String
        let boardState: String
        let occupiedSquares: String
        let moveDisplay: String
        let moveUCI: String
        let moveFraming: String
        let coachingText: String
        let forUserMove: Bool
    }

    /// Detailed explanation prompt (3–5 sentences) for a user or opponent move.
    static func explanationPrompt(params: ExplanationPromptParams) -> String {
        """
        You are a friendly chess coach inside an opening trainer app. A student is learning the \(params.openingName) as \(params.studentColor) (ELO ~\(params.userELO)).
        The app plays the \(params.opponentColor) side automatically — the opponent's moves are not choices by a real person. Your job is to help the student understand EVERY move on the board from the student's perspective: what it means for THEIR position, THEIR plan, and what THEY should watch out for.
        \(params.perspective)

        CRITICAL: Always use colors (\(params.studentColor)/\(params.opponentColor)) or "the opponent" to identify whose piece you mean. NEVER write ambiguous phrases like "your pieces" without specifying the color.

        Moves so far: \(params.moveHistoryStr)
        Current board position:
        \(params.boardState)

        \(params.moveFraming)
        Quick summary already shown: "\(params.coachingText)"

        Give a deeper explanation (3-5 sentences) of WHY this move \(params.forUserMove ? "is the right choice here" : "matters for the student's position"):
        - What squares or pieces does it affect?
        - What plan or idea does it support \(params.forUserMove ? "for the student" : "for the opponent, and what threat does the student need to be aware of")?
        - How does it fit into the \(params.openingName) strategy?
        \(params.forUserMove ? "" : "- Frame it from the student's perspective: what does this mean for YOU (the student), not for the opponent.")

        Squares that currently have pieces: \(params.occupiedSquares)
        REFS must ONLY use squares from the list above. Any square not listed is EMPTY.

        Respond with ONLY:
        REFS: <up to 3 squares from the occupied list, or "none">
        COACHING: <your explanation>

        Rules:
        - Use simple language a beginner can understand.
        - Do not use algebraic notation symbols — spell out piece names.
        - Always speak TO the student. Say "you" to mean the student (\(params.studentColor)), "your opponent" for \(params.opponentColor).
        """
    }

    /// Groups the parameters for off-book explanation prompts.
    struct OffBookExplanationPromptParams {
        let openingName: String
        let studentColor: String
        let opponentColor: String
        let userELO: Int
        let moveHistoryStr: String
        let boardState: String
        let occupiedSquares: String
        let who: String
        let playedMove: String
        let expectedSan: String
        let expectedUci: String
        let evalNote: String
    }

    /// Prompt for explaining why a move deviated from the book.
    static func offBookExplanationPrompt(params: OffBookExplanationPromptParams) -> String {
        """
        You are a friendly chess coach. Your student (ELO ~\(params.userELO)) is learning the \(params.openingName) as \(params.studentColor).
        Always use colors (\(params.studentColor)/\(params.opponentColor)) to identify whose piece you mean. Never write ambiguous "your" without the color.

        Moves so far: \(params.moveHistoryStr)
        Current board position:
        \(params.boardState)

        \(params.who) played \(params.playedMove) instead of the book move \(params.expectedSan) (\(params.expectedUci)).
        \(params.evalNote)

        Explain in 2-3 sentences:
        1. Why the book move (\(params.expectedSan)) is the standard choice in the \(params.openingName)
        2. Whether the played move (\(params.playedMove)) is actually bad, or if it's a reasonable alternative
        3. What the student should focus on from here

        Squares that currently have pieces: \(params.occupiedSquares)
        REFS must ONLY use squares from the list above. Any square not listed is EMPTY.

        Respond with ONLY:
        REFS: <up to 3 squares from the occupied list, or "none">
        COACHING: <your explanation>

        Rules:
        - Be honest — if the played move is fine or even good, say so.
        - Use simple language. Spell out piece names, no algebraic notation.
        """
    }

    // MARK: - Alignment Prompt

    /// Groups the many parameters for the PES alignment prompt.
    struct AlignmentPromptParams {
        let fen: String
        let fenBeforeMove: String
        let move: String
        let moveSAN: String
        let openingName: String
        let openingDescription: String
        let planSummary: String
        let strategicGoals: String
        let pawnStructureTarget: String
        let keySquares: String
        let pieceTargets: String
        let ply: Int
        let playerIsWhite: Bool
        let userELO: Int
        let moveHistory: String
        let soundness: Int
        let cpLoss: Int
        let boardSummary: String
        let boardSummaryBefore: String
        let stockfishTopStr: String
        let maiaActualMoveProbStr: String
        let maiaTopStr: String
        let moveFreq: String
    }

    /// PES alignment scoring prompt.
    static func alignmentPrompt(params: AlignmentPromptParams) -> String {
        let studentColor = params.playerIsWhite ? "White" : "Black"

        return """
        You are evaluating a chess move for plan alignment in an opening trainer.

        OPENING: \(params.openingName) — \(params.openingDescription)
        STUDENT: \(studentColor), ELO ~\(params.userELO)
        MOVE PLAYED: \(params.moveSAN) (\(params.move)) at ply \(params.ply) (move \(params.ply / 2 + 1))
        MOVE HISTORY: \(params.moveHistory)

        BOARD BEFORE MOVE:
        \(params.boardSummaryBefore)

        BOARD AFTER MOVE:
        \(params.boardSummary)

        THE OPENING PLAN:
        Summary: \(params.planSummary)
        Strategic Goals (in priority order):
        \(params.strategicGoals)
        Pawn Structure Target: \(params.pawnStructureTarget)
        Key Squares: \(params.keySquares)
        Piece Development Targets:
        \(params.pieceTargets)

        ENGINE DATA:
        Soundness: \(params.soundness)/100 (centipawn loss: \(params.cpLoss))
        Stockfish top 3 moves at this position:
        \(params.stockfishTopStr)

        HUMAN PLAY DATA:
        Maia probability for played move (\(params.moveSAN)): \(params.maiaActualMoveProbStr)
        Maia top predictions (what a ~\(params.userELO)-rated player would likely play):
        \(params.maiaTopStr)
        Polyglot book frequency for this move: \(params.moveFreq)

        EVALUATION RUBRIC — Score 0-100 on plan alignment:
        1. Development progress: Does this move develop a piece or improve piece activity?
        2. Pawn structure alignment: Does this maintain or advance the opening's target pawn structure?
        3. Strategic goal advancement: Does this move work toward the opening's specific objectives?
        4. King safety: Does this move contribute to getting the king safe?
        5. Was there a significantly better plan-aligned alternative?

        REASONING REQUIREMENTS:
        - Lead with what this move accomplishes for the plan
        - If alignment < 80, briefly mention ONE better alternative and what it achieves — phrase it
          as a constructive tip (e.g. "Next time, consider Bf4 first to claim the diagonal before
          locking in the pawn structure") rather than criticizing the played move
        - Do NOT say "However" or contradict yourself — frame the reasoning so positive and
          constructive parts flow naturally together
        - Keep reasoning to 2-3 sentences, suitable for a beginner

        Respond in EXACTLY this JSON format (no markdown, no extra text):
        {"alignment": <0-100>, "reasoning": "<2-3 sentence explanation>", "development": <true/false>, "pawnStructure": <true/false>, "strategicGoal": <true/false>, "kingSafety": "<positive/negative/neutral>"}
        """
    }

    // MARK: - Puzzle Prompt

    /// Puzzle move selection prompt.
    static func puzzlePrompt(
        fen: String,
        openingName: String,
        planSummary: String,
        goalsStr: String,
        candidateStr: String
    ) -> String {
        """
        Given this position (FEN: \(fen)) in the \(openingName):

        Plan: \(planSummary)
        Strategic Goals:
        \(goalsStr)

        Which of these moves BEST serves the plan?
        \(candidateStr)

        Reply with ONLY the number (1, 2, 3, or 4) of the best plan-aligned move.
        """
    }
}
