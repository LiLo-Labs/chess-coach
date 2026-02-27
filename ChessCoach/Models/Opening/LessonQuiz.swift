import Foundation

/// A quiz question embedded in a Layer 1 or Layer 3 lesson.
/// Shows a board position and asks a multiple-choice question.
struct LessonQuiz: Codable, Sendable {
    let fen: String                            // Board position to show
    let prompt: String                         // "Which square should the bishop aim for?"
    let choices: [QuizChoice]                  // 3-4 options
    let correctIndex: Int                      // which choice is right
    let explanation: String                    // shown after answering
    let boardHighlightsOnReveal: [String]      // squares to highlight when answer revealed
    let arrowsOnReveal: [LessonArrow]         // arrows shown after answering
}

/// A single choice in a lesson quiz.
struct QuizChoice: Codable, Sendable {
    let text: String                           // "f7 — Black's weakest square"
    let isCorrect: Bool
}
