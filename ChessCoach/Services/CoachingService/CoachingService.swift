import Foundation

actor CoachingService {
    private let llmService: LLMService
    private let curriculumService: CurriculumService

    init(llmService: LLMService, curriculumService: CurriculumService) {
        self.llmService = llmService
        self.curriculumService = curriculumService
    }

    /// Determine whether coaching should be shown for this move.
    func shouldCoach(moveCategory: MoveCategory, phase: LearningPhase) -> Bool {
        switch phase {
        case .learningMainLine:
            // Always coach during learning phase
            return true
        case .naturalDeviations:
            // Coach on all non-trivial moments
            return true
        case .widerVariations:
            // Coach on mistakes and deviations
            return moveCategory != .goodMove
        case .freePlay:
            // Only coach on mistakes
            return moveCategory == .mistake
        }
    }

    /// Get coaching text for a move.
    func getCoaching(
        fen: String,
        lastMove: String,
        scoreBefore: Int,
        scoreAfter: Int,
        ply: Int,
        userELO: Int,
        moveHistory: String = "",
        isUserMove: Bool = true
    ) async -> String? {
        let moveCategory = curriculumService.categorizeUserMove(
            atPly: ply,
            move: lastMove,
            stockfishScore: scoreAfter - scoreBefore
        )

        let phase = curriculumService.phase

        guard shouldCoach(moveCategory: moveCategory, phase: phase) else {
            return nil
        }

        // For deviations, check if it's the opponent deviating
        let isOpponentMove = (ply % 2 == 0 && curriculumService.opening.color == .black) ||
                             (ply % 2 == 1 && curriculumService.opening.color == .white)

        let category: MoveCategory
        if isOpponentMove && curriculumService.isDeviation(atPly: ply, move: lastMove) {
            category = .deviation
        } else if isOpponentMove {
            category = .opponentMove
        } else {
            category = moveCategory
        }

        let context = CoachingContext(
            fen: fen,
            lastMove: lastMove,
            scoreBefore: scoreBefore,
            scoreAfter: scoreAfter,
            openingName: curriculumService.opening.name,
            userELO: userELO,
            phase: phase,
            moveCategory: category,
            moveHistory: moveHistory,
            isUserMove: isUserMove
        )

        do {
            return try await llmService.getCoaching(for: context)
        } catch {
            print("[ChessCoach] LLM coaching failed: \(error)")
            return nil
        }
    }
}
