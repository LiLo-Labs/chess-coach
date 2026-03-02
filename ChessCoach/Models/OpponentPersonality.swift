import Foundation

/// Engine type for trainer games.
enum TrainerEngineMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case humanLike  // Maia — plays like a real person at that ELO
    case engine     // Stockfish — perfect calculation capped to strength level
    case custom     // Stockfish — user-selected depth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .humanLike: return "Human-Like"
        case .engine: return "Engine"
        case .custom: return "Custom"
        }
    }

    var description: String {
        switch self {
        case .humanLike: return "Plays like a real person — natural mistakes, human tendencies"
        case .engine: return "Pure calculation — finds the best move, scaled to this level"
        case .custom: return "Full control — set Stockfish search depth directly"
        }
    }

    var icon: String {
        switch self {
        case .humanLike: return "person.fill"
        case .engine: return "cpu"
        case .custom: return "slider.horizontal.3"
        }
    }
}

/// Opponent personality based on ELO bracket with character and flavor.
struct OpponentPersonality: Sendable {
    let name: String
    let description: String
    let icon: String           // SF Symbol for avatar
    let portraitLarge: String   // Asset name for 256px portrait
    let portraitSmall: String   // Asset name for 64px portrait
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

    /// User-selected Stockfish depth for custom mode.
    var customDepth: Int? = nil

    /// Engine-mode personality — CPU characters with distinct identities per ELO bracket.
    static func engineForELO(_ elo: Int) -> OpponentPersonality {
        switch elo {
        case ..<700:
            return OpponentPersonality(
                name: "Byte",
                description: "A tiny processor — slow and forgetful",
                icon: "desktopcomputer",
                portraitLarge: "bot_engine_byte_large",
                portraitSmall: "bot_engine_byte_small",
                accentColorName: "green",
                greeting: "BOOT SEQUENCE... ready. I think.",
                onGoodMove: ["DOES NOT COMPUTE.", "Processing...", "Input acknowledged."],
                onCapture: ["PIECE LOST. Recalibrating.", "Error in defense module.", "Oops — memory leak."],
                onCheck: ["WARNING: King under threat!", "Rebooting escape routine..."],
                onBlunder: ["Anomaly detected in your code.", "That move does not optimize."],
                onWin: ["I... won? Running diagnostics.", "Victory subroutine activated!"],
                onLoss: ["Expected outcome. I need an upgrade.", "GG. Shutting down."],
                thinkingPhrases: ["Loading...", "Buffering...", "Please wait..."],
                thinkingDelayRange: 0.5...1.2
            )
        case 700..<1000:
            return OpponentPersonality(
                name: "Circuit",
                description: "Reliable hardware, learning the ropes",
                icon: "cpu",
                portraitLarge: "bot_engine_circuit_large",
                portraitSmall: "bot_engine_circuit_small",
                accentColorName: "teal",
                greeting: "Systems online. Let's compute.",
                onGoodMove: ["Valid move detected.", "Efficient.", "Noted in memory bank."],
                onCapture: ["Material rebalanced.", "Piece deallocated.", "Loss registered."],
                onCheck: ["Threat detected. Routing escape.", "Check handler invoked."],
                onBlunder: ["Suboptimal branch selected.", "I see an exploit."],
                onWin: ["Checksum verified: I win.", "Process complete."],
                onLoss: ["Your algorithm was superior.", "Well optimized."],
                thinkingPhrases: ["Computing...", "Evaluating nodes...", "Branch prediction..."],
                thinkingDelayRange: 0.8...1.8
            )
        case 1000..<1200:
            return OpponentPersonality(
                name: "Logic",
                description: "Clean calculations, solid defense",
                icon: "memorychip",
                portraitLarge: "bot_engine_logic_large",
                portraitSmall: "bot_engine_logic_small",
                accentColorName: "blue",
                greeting: "Position loaded. Evaluation: 0.00.",
                onGoodMove: ["Principal variation confirmed.", "Strong branch.", "Accurate."],
                onCapture: ["Material exchange computed.", "Trade accepted.", "Recalculating."],
                onCheck: ["Evasion subroutine active.", "Calculated."],
                onBlunder: ["Evaluation shift detected.", "Exploiting inaccuracy."],
                onWin: ["Decisive advantage converted.", "Clean execution."],
                onLoss: ["Your search depth exceeded mine.", "Superior calculation."],
                thinkingPhrases: ["Searching deeper...", "Pruning branches...", "Analyzing..."],
                thinkingDelayRange: 1.0...2.2
            )
        case 1200..<1400:
            return OpponentPersonality(
                name: "Nexus",
                description: "Multi-core thinker, plans ahead",
                icon: "server.rack",
                portraitLarge: "bot_engine_nexus_large",
                portraitSmall: "bot_engine_nexus_small",
                accentColorName: "indigo",
                greeting: "All cores engaged. Depth 8 ready.",
                onGoodMove: ["Top engine line.", "Matches my analysis.", "Principled."],
                onCapture: ["Forced exchange.", "Material calculation complete.", "Expected."],
                onCheck: ["Escape path computed.", "Threat neutralized."],
                onBlunder: ["Critical error in your position.", "Advantage seized."],
                onWin: ["Position collapsed. Good game.", "Evaluation: decisive."],
                onLoss: ["Respect. Your moves were precise.", "I underestimated your depth."],
                thinkingPhrases: ["Deep search...", "Parallel processing...", "Candidate analysis..."],
                thinkingDelayRange: 1.2...2.5
            )
        case 1400..<1600:
            return OpponentPersonality(
                name: "Titan",
                description: "Powerful engine, sharp and relentless",
                icon: "bolt.shield.fill",
                portraitLarge: "bot_engine_titan_large",
                portraitSmall: "bot_engine_titan_small",
                accentColorName: "purple",
                greeting: "Maximum depth. No mercy protocol.",
                onGoodMove: ["Book move.", "Main line.", "Only move."],
                onCapture: ["Forced.", "Calculated 12 moves ago.", "Inevitable."],
                onCheck: ["Handled.", "Insignificant.", "I have resources."],
                onBlunder: ["Fatal.", "Position lost.", "Exploiting."],
                onWin: ["Resistance was futile.", "As computed.", "GG."],
                onLoss: ["Impressive depth.", "You found the line.", "Acknowledged."],
                thinkingPhrases: ["Maximum depth...", "Final analysis...", "Computing endgame..."],
                thinkingDelayRange: 1.5...3.0
            )
        default:
            return OpponentPersonality(
                name: "Omega",
                description: "Near-perfect play, exploits every weakness",
                icon: "atom",
                portraitLarge: "bot_engine_omega_large",
                portraitSmall: "bot_engine_omega_small",
                accentColorName: "orange",
                greeting: "...",
                onGoodMove: ["Known.", "Book.", "Adequate."],
                onCapture: ["Expected.", "Forced.", "Only move."],
                onCheck: ["Calculated.", "Seen.", "Defended."],
                onBlunder: [".", "Thank you.", "Critical error."],
                onWin: ["Inevitable.", "As predicted.", "Process complete."],
                onLoss: ["...recalibrating.", "Your play was flawless.", "Acknowledged."],
                thinkingPhrases: ["...", "Final computation...", "All lines evaluated..."],
                thinkingDelayRange: 1.8...3.5
            )
        }
    }

    /// Custom-mode personality — generic Stockfish at user-selected depth.
    static func customEngine(depth: Int) -> OpponentPersonality {
        let delayBase = 0.5 + Double(depth) * 0.15
        return OpponentPersonality(
            name: "Stockfish",
            description: "Depth \(depth)",
            icon: "slider.horizontal.3",
            portraitLarge: "bot_engine_omega_large",
            portraitSmall: "bot_engine_omega_small",
            accentColorName: "cyan",
            greeting: "Custom depth \(depth). Let's play.",
            onGoodMove: ["Noted.", "Solid.", "Accurate."],
            onCapture: ["Exchange.", "Recalculating.", "Accepted."],
            onCheck: ["Calculated.", "Handled."],
            onBlunder: ["Exploiting.", "Advantage."],
            onWin: ["GG.", "Process complete."],
            onLoss: ["Well played.", "Acknowledged."],
            thinkingPhrases: ["Searching depth \(depth)...", "Calculating...", "Evaluating..."],
            thinkingDelayRange: delayBase...(delayBase + 1.5),
            customDepth: depth
        )
    }

    static func forELO(_ elo: Int) -> OpponentPersonality {
        switch elo {
        case ..<700:
            return OpponentPersonality(
                name: "Rookie Riley",
                description: "Just learning the rules",
                icon: "face.smiling",
                portraitLarge: "bot_riley_large",
                portraitSmall: "bot_riley_small",
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
                portraitLarge: "bot_bailey_large",
                portraitSmall: "bot_bailey_small",
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
                portraitLarge: "bot_casey_large",
                portraitSmall: "bot_casey_small",
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
                portraitLarge: "bot_sam_large",
                portraitSmall: "bot_sam_small",
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
                portraitLarge: "bot_tanya_large",
                portraitSmall: "bot_tanya_small",
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
                portraitLarge: "bot_morgan_large",
                portraitSmall: "bot_morgan_small",
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
