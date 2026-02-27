import Foundation

/// Engine type for trainer games.
enum TrainerEngineMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case humanLike  // Maia — plays like a real person at that ELO
    case engine     // Stockfish — perfect calculation capped to strength level

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .humanLike: return "Human-Like"
        case .engine: return "Engine"
        }
    }

    var description: String {
        switch self {
        case .humanLike: return "Plays like a real person — natural mistakes, human tendencies"
        case .engine: return "Pure calculation — finds the best move, scaled to this level"
        }
    }

    var icon: String {
        switch self {
        case .humanLike: return "person.fill"
        case .engine: return "cpu"
        }
    }
}

/// Opponent personality based on ELO bracket with character and flavor.
struct OpponentPersonality: Sendable {
    let name: String
    let description: String
    let icon: String           // SF Symbol for avatar
    let accentColorName: String // Color name for theming
    let greeting: String       // Said at game start
    let onGoodMove: [String]   // Reactions when player makes a good move
    let onCapture: [String]    // Reactions when player captures
    let onCheck: [String]      // Reactions when player checks
    let onBlunder: [String]    // Reactions when player blunders (if detectable)
    let onWin: [String]        // Bot wins
    let onLoss: [String]       // Bot loses
    let thinkingPhrases: [String] // While "thinking"

    /// Thinking delay range in seconds — scales with difficulty.
    let thinkingDelayRange: ClosedRange<Double>

    static func forELO(_ elo: Int) -> OpponentPersonality {
        switch elo {
        case ..<700:
            return OpponentPersonality(
                name: "Rookie Riley",
                description: "Just learning the rules",
                icon: "face.smiling",
                accentColorName: "green",
                greeting: "Hi! I'm still learning, so go easy on me!",
                onGoodMove: ["Ooh, nice one!", "I didn't see that!", "Wow, good move!"],
                onCapture: ["Hey, I needed that piece!", "Oh no!", "Oops..."],
                onCheck: ["Yikes! Check!", "I better move my king!", "Scary!"],
                onBlunder: ["Hmm, are you sure about that?", "I think I can use that..."],
                onWin: ["I won?! I can't believe it!", "Yay! Good game though!"],
                onLoss: ["Good game! You're really good!", "I'll get you next time!"],
                thinkingPhrases: ["Hmm...", "Let me think...", "Which piece should I move?"],
                thinkingDelayRange: 0.5...1.2
            )
        case 700..<1000:
            return OpponentPersonality(
                name: "Beginner Bailey",
                description: "Knows the basics, still learning",
                icon: "graduationcap",
                accentColorName: "teal",
                greeting: "Ready for a game? I've been practicing!",
                onGoodMove: ["Good move!", "Nice, I see what you did.", "Solid."],
                onCapture: ["Fair trade!", "I'll miss that piece.", "Good capture."],
                onCheck: ["Check! I need to be careful.", "Close call!"],
                onBlunder: ["Interesting choice...", "I might have something here."],
                onWin: ["Good game! I got lucky there.", "That was close!"],
                onLoss: ["Well played! I need to study more.", "You got me!"],
                thinkingPhrases: ["Thinking...", "Let me see...", "What about..."],
                thinkingDelayRange: 0.8...1.8
            )
        case 1000..<1200:
            return OpponentPersonality(
                name: "Club Casey",
                description: "Solid fundamentals, some tactics",
                icon: "person.crop.square",
                accentColorName: "blue",
                greeting: "Let's have a good game.",
                onGoodMove: ["Well played.", "Strong move.", "I respect that."],
                onCapture: ["Material exchange.", "Interesting trade.", "Hmm, that opens things up."],
                onCheck: ["Check — I'll handle it.", "Keeping me honest!"],
                onBlunder: ["That might cost you.", "I'll take advantage of that."],
                onWin: ["Good effort. Study the endgame!", "Tight game — I edged it out."],
                onLoss: ["Strong play. Well deserved.", "You outplayed me there."],
                thinkingPhrases: ["Calculating...", "Interesting position...", "Several options here..."],
                thinkingDelayRange: 1.0...2.2
            )
        case 1200..<1400:
            return OpponentPersonality(
                name: "Strategic Sam",
                description: "Plans ahead, understands structure",
                icon: "brain.head.profile",
                accentColorName: "indigo",
                greeting: "I hope you've prepared. I have.",
                onGoodMove: ["Correct.", "That's theory.", "Principled move."],
                onCapture: ["A necessary exchange.", "That simplifies nicely.", "Tactical shot."],
                onCheck: ["Check — forcing moves.", "A discovered check, nice."],
                onBlunder: ["That's a mistake.", "You'll regret that."],
                onWin: ["Study the middle game. GG.", "Positional advantage was decisive."],
                onLoss: ["You played accurately. Respect.", "Clean technique."],
                thinkingPhrases: ["Evaluating...", "Complex position...", "Deep calculation..."],
                thinkingDelayRange: 1.2...2.5
            )
        case 1400..<1600:
            return OpponentPersonality(
                name: "Tournament Tanya",
                description: "Strong positional play, sharp tactics",
                icon: "trophy",
                accentColorName: "purple",
                greeting: "Tournament conditions. No takebacks.",
                onGoodMove: ["Theory approved.", "Accurate.", "Main line."],
                onCapture: ["Tactical sequence.", "Exchange evaluated.", "Forced."],
                onCheck: ["Check — but I have resources.", "Calculated."],
                onBlunder: ["Inaccuracy detected.", "That weakens your position."],
                onWin: ["Instructive game. Review the critical moments.", "GG WP."],
                onLoss: ["Impressive preparation.", "You found the key moves."],
                thinkingPhrases: ["Deep think...", "Critical moment...", "Candidate moves..."],
                thinkingDelayRange: 1.5...3.0
            )
        default:
            return OpponentPersonality(
                name: "Master Morgan",
                description: "Near-perfect play, exploits every weakness",
                icon: "crown.fill",
                accentColorName: "orange",
                greeting: "...",
                onGoodMove: ["Known.", "Book.", "Adequate."],
                onCapture: ["Expected.", "Forced.", "Only move."],
                onCheck: ["Calculated.", "Seen.", "I have a defense."],
                onBlunder: [".", "Thank you.", "Critical error."],
                onWin: ["Study more.", "Predictable.", "Better luck next time."],
                onLoss: ["...well played.", "I miscalculated.", "Impressive."],
                thinkingPhrases: ["...", "Calculating deeply...", "Evaluating all lines..."],
                thinkingDelayRange: 1.8...3.5
            )
        }
    }

    func randomReaction(from pool: [String]) -> String {
        pool.randomElement() ?? ""
    }
}
