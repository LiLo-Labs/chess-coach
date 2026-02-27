import Foundation

/// A single step in a board-driven lesson for Layer 1 or Layer 3.
struct LessonStep: Codable, Sendable {
    let title: String              // "Aim the Bishop at f7"
    let description: String        // "The bishop on c4 pressures Black's weakest square"
    let fen: String                // Board position to show
    let highlights: [String]       // Squares to highlight (e.g. ["c4", "f7"])
    let arrows: [LessonArrow]     // Arrows to draw
    let style: StepStyle           // .good, .bad, .neutral, .theory
}

/// An arrow drawn on the board during a lesson step.
struct LessonArrow: Codable, Sendable {
    let from: String               // "c4"
    let to: String                 // "f7"
}

/// Visual style for a lesson step, indicating whether the position demonstrates
/// a recommended move, a mistake, general info, or a theoretical concept.
enum StepStyle: String, Codable, Sendable {
    case good      // Green border/tint — "Do this"
    case bad       // Red border/tint — "Don't do this"
    case neutral   // Blue border/tint — informational
    case theory    // Indigo border/tint — "Here's why this order matters"
}
