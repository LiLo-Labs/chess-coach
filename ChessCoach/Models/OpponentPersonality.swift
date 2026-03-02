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
                greeting: "B00T SEQUENCE... hello? Is this chess?",
                onGoodMove: ["I... did not predict that.", "DOES NOT COMPUTE.", "Hm. Unexpected input.", "???"],
                onCapture: ["Piece loss detected. Oops.", "That was mine. I think.", "Memory error."],
                onCheck: ["KING IN DANGER. KING IN DANGER.", "Rebooting..."],
                onBlunder: ["Error in your logic tree.", "That move caused a warning."],
                onWin: ["I won?? Running victory diagnostics...", "W-win condition met! I think!"],
                onLoss: ["Expected. I require more RAM.", "GG. Shutting down to recharge."],
                thinkingPhrases: ["Loading...", "Buffering... please wait...", "Thinking... maybe..."],
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
                greeting: "Systems online. Ready to play.",
                onGoodMove: ["Registered.", "Valid branch detected.", "Efficient move."],
                onCapture: ["Material delta updated.", "Piece removed from registry.", "Loss logged."],
                onCheck: ["Threat level elevated. Routing escape.", "Check interrupt handled."],
                onBlunder: ["Suboptimal input detected.", "I see an opening."],
                onWin: ["Match resolved. I win.", "Output: Victory."],
                onLoss: ["Your approach was well-structured.", "Noted for next iteration."],
                thinkingPhrases: ["Computing...", "Evaluating move tree...", "Branch analysis..."],
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
                greeting: "Position evaluated. Score: 0.0. Let's begin.",
                onGoodMove: ["Accurate.", "Matches principal variation.", "Strong line."],
                onCapture: ["Trade computed and accepted.", "Recalculating score.", "Material balance updated."],
                onCheck: ["Evasion sequence initiated.", "Handled."],
                onBlunder: ["Evaluation shift: +1.3 in my favor.", "Exploiting inaccuracy.", "Noted."],
                onWin: ["Decisive advantage converted.", "Position was objectively won."],
                onLoss: ["Your search exceeded my projection.", "Excellent calculation."],
                thinkingPhrases: ["Pruning branches...", "Searching deeper...", "Analyzing..."],
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
                greeting: "All cores engaged. Let's see what you have.",
                onGoodMove: ["Top engine line.", "Principled.", "That matches my analysis."],
                onCapture: ["Material sequence complete.", "Forced exchange.", "Expected."],
                onCheck: ["Neutralized.", "Escape path was computed three moves ago."],
                onBlunder: ["Critical divergence from best play.", "Advantage secured."],
                onWin: ["Position was beyond saving. Good game.", "Evaluation: decisive. GG."],
                onLoss: ["Your depth was impressive.", "I underestimated that line. Noted."],
                thinkingPhrases: ["Parallel processing...", "Candidate analysis...", "Deep search in progress..."],
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
                greeting: "Full depth engaged. Let's begin.",
                onGoodMove: ["Book.", "Only move.", "Main line."],
                onCapture: ["Calculated fourteen moves ago.", "Inevitable.", "Forced."],
                onCheck: ["Handled.", "I have resources.", "Irrelevant."],
                onBlunder: ["Fatal.", "Position lost.", "Thank you."],
                onWin: ["As computed.", "GG.", "The position left you no choice."],
                onLoss: ["You found the refutation.", "Impressive.", "That line was not in my book."],
                thinkingPhrases: ["Final analysis...", "Maximum depth search...", "Endgame table lookup..."],
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
                greeting: ".",
                onGoodMove: ["Known.", "Adequate."],
                onCapture: ["Forced.", "Expected."],
                onCheck: ["Seen.", "Irrelevant."],
                onBlunder: [".", "Thank you."],
                onWin: ["Inevitable.", "Predicted."],
                onLoss: ["...interesting.", "You found the only winning sequence.", "Acknowledged."],
                thinkingPhrases: ["...", "..."],
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
            greeting: "Depth \(depth) loaded. Ready when you are.",
            onGoodMove: ["Accurate.", "Solid.", "Good move."],
            onCapture: ["Recalculating.", "Trade accepted.", "Exchange noted."],
            onCheck: ["Handled.", "Response calculated."],
            onBlunder: ["Exploiting.", "That's a mistake."],
            onWin: ["GG.", "Match concluded."],
            onLoss: ["Well played.", "You earned that."],
            thinkingPhrases: ["Searching at depth \(depth)...", "Evaluating...", "Calculating..."],
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
                greeting: "Hi!! I'm still learning so please don't go too hard on me :)",
                onGoodMove: ["Ooh!", "Wait — how did you do that?", "I didn't even see that coming!", "Wow."],
                onCapture: ["Hey! I needed that!", "Nooo not my knight...", "Oh no oh no oh no."],
                onCheck: ["Eek! Check!", "Yikes, I gotta move my king!", "That's scary!"],
                onBlunder: ["Umm... are you sure about that move?", "Oh! I think I can do something now..."],
                onWin: ["Wait I WON?? No way!!", "Yay!! Good game though, for real!"],
                onLoss: ["You're so good at this!", "Okay okay I'm gonna study and rematch you.", "Good game!"],
                thinkingPhrases: ["Hmmmm...", "Okay which piece do I move...", "Let me think for a sec..."],
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
                greeting: "Hey! I've been practicing — hope it shows.",
                onGoodMove: ["Oh nice, I like that.", "Good move!", "Hah, didn't see that one."],
                onCapture: ["Alright, fair trade I guess.", "I'll miss that piece honestly.", "Nice capture."],
                onCheck: ["Check! Okay, gotta think here.", "Yep, saw that coming. Mostly."],
                onBlunder: ["Hmm, interesting choice...", "Oh wait — I think I have something."],
                onWin: ["Yes! Though honestly I got a bit lucky.", "That was really close, good game!"],
                onLoss: ["Ugh, you got me. Well played.", "Okay I need to hit the books."],
                thinkingPhrases: ["Thinking...", "Let me see here...", "Okay what if I..."],
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
                greeting: "Good to play. Let's have a clean game.",
                onGoodMove: ["Nice.", "Solid move.", "Respect — I didn't see that."],
                onCapture: ["Fair enough, that opens things up.", "Interesting trade.", "Hmm. Okay."],
                onCheck: ["Check — I'll handle it.", "Keeping me on my toes!", "Alright, not worried."],
                onBlunder: ["That might cost you.", "Ooh, I can work with that."],
                onWin: ["Good game. Work on those endgames — that's where it was decided.", "Close one, but I'll take it."],
                onLoss: ["Well played. You earned it.", "You outplayed me in the middle game."],
                thinkingPhrases: ["Hmm, interesting...", "A few options here...", "Calculating..."],
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
                onGoodMove: ["Correct.", "That's the principled move.", "Theory."],
                onCapture: ["That simplifies into something I like.", "Tactical shot.", "A necessary exchange."],
                onCheck: ["I have resources.", "Check — forcing, but I'm fine."],
                onBlunder: ["That's a mistake.", "You'll want to avoid that kind of move.", "I'll remember that."],
                onWin: ["Review the middlegame — that's where it turned. GG.", "Structure wins. Good game."],
                onLoss: ["Accurate play throughout. Well done.", "Clean technique. Respect."],
                thinkingPhrases: ["Evaluating...", "This position is rich...", "Deep calculation..."],
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
                greeting: "Clock's running. No takebacks.",
                onGoodMove: ["Main line.", "That's accurate.", "Okay, good."],
                onCapture: ["Forced sequence.", "Evaluated that trade already.", "Expected."],
                onCheck: ["I have resources.", "That's check — and I'm fine."],
                onBlunder: ["That weakens your structure.", "Inaccuracy. I'll take it.", "That's going to cost you."],
                onWin: ["Review the critical moments — there were two or three turning points. GG.", "Well contested. GG WP."],
                onLoss: ["You found the key moves. Impressive.", "Good prep. I wasn't ready for that line."],
                thinkingPhrases: ["Candidate moves...", "Critical moment...", "Let me think this through..."],
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
                greeting: "Let's play.",
                onGoodMove: ["Mm.", "Yes."],
                onCapture: ["Expected.", "Fine."],
                onCheck: ["I know.", "Seen it."],
                onBlunder: ["Thank you.", "That changes things."],
                onWin: ["Study the position.", "You'll understand it later."],
                onLoss: ["You played very well.", "...I misjudged that. Well played."],
                thinkingPhrases: ["...", "...", "Thinking."],
                thinkingDelayRange: 1.8...3.5
            )
        }
    }

    func randomReaction(from pool: [String]) -> String {
        pool.randomElement() ?? ""
    }
}
