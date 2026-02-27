import Foundation

/// A structured description of what an opening is trying to achieve,
/// independent of exact move order. This is the core of the plan-first
/// learning approach.
struct OpeningPlan: Codable, Sendable {
    let summary: String                    // 1-2 sentence elevator pitch
    let strategicGoals: [StrategicGoal]    // ordered by priority
    let pawnStructureTarget: String        // e.g., "e4/d3 vs e5/d6 — classical center"
    let keySquares: [String]              // e.g., ["f7", "d4", "c4"]
    let pieceTargets: [PieceTarget]       // where pieces ideally develop
    let typicalPlans: [String]            // middlegame ideas
    let commonMistakes: [String]          // beginner pitfalls
    let historicalNote: String?           // "Named after a café in Rome..."
    let planLessons: [LessonStep]?       // Layer 1 board examples (do this / don't do this)
    let theoryLessons: [LessonStep]?     // Layer 3 board examples (why this move order)
    let planQuizzes: [LessonQuiz]?       // Layer 1 inline quizzes
    let theoryQuizzes: [LessonQuiz]?     // Layer 3 inline quizzes
}

/// A single strategic objective for the opening.
struct StrategicGoal: Codable, Sendable {
    let description: String               // "Aim your bishop at the f7 square"
    let priority: Int                     // 1 = most important
    let measurable: Bool?                 // can we check this positionally?
    let checkCondition: String?           // e.g., "bishop_on_diagonal_a2g8"

    init(description: String, priority: Int, measurable: Bool? = nil, checkCondition: String? = nil) {
        self.description = description
        self.priority = priority
        self.measurable = measurable
        self.checkCondition = checkCondition
    }
}

/// Where a specific piece should ideally develop in this opening.
struct PieceTarget: Codable, Sendable {
    let piece: String                     // "light-squared bishop"
    let idealSquares: [String]            // ["c4", "b5"]
    let reasoning: String                 // "Aims at f7, Black's weakest point"
}
