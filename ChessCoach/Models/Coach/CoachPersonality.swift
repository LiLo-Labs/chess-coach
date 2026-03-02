import Foundation

/// Coach personality mapped by opening tag. Each opening gets a coach character
/// with curated witticisms for ~10 coaching moment categories.
/// Follows the same inline-definition pattern as `OpponentPersonality`.
struct CoachPersonality: Sendable {
    let id: String
    let humanName: String           // "Coach Sofia"
    let humanIcon: String           // SF Symbol for human-track
    let engineName: String          // "Metronome-4"
    let engineIcon: String          // SF Symbol for engine-track

    // Pixel art portraits (asset catalog names)
    let enginePortraitLarge: String  // 256px robot portrait
    let enginePortraitSmall: String  // 64px robot portrait

    /// LLM system prompt injection describing this coach's voice.
    let personalityPrompt: String

    // 10 reaction pools (~5 strings each = ~50 witticisms per personality)
    let onGoodMove: [String]
    let onOkayMove: [String]
    let onMistake: [String]
    let onDeviation: [String]
    let onStandardOpponent: [String]
    let onGreeting: [String]
    let onEncouragement: [String]     // streak / improving trend
    let onConsolation: [String]       // after mistakes / declining
    let onMilestone: [String]         // layer promotion, personal best
    let onSessionEnd: [String]
    let onWelcomeBack: [String]       // returning to the app
    let onNextStep: [String]          // guidance toward next milestone

    /// Pick a random witticism from the pool matching the current move category.
    func witticism(for category: MoveCategory) -> String {
        let pool: [String]
        switch category {
        case .goodMove:       pool = onGoodMove
        case .okayMove:       pool = onOkayMove
        case .mistake:        pool = onMistake
        case .deviation:      pool = onDeviation
        case .opponentMove:   pool = onStandardOpponent
        }
        return pool.randomElement() ?? ""
    }

    // MARK: - Display Helpers

    /// Returns the appropriate name based on whether engine mode is active.
    func displayName(engineMode: Bool) -> String {
        engineMode ? engineName : humanName
    }

    /// Returns the appropriate icon based on whether engine mode is active.
    func displayIcon(engineMode: Bool) -> String {
        engineMode ? engineIcon : humanIcon
    }

    // MARK: - Tag Mapping

    /// Tag-to-personality mapping. First matching tag wins; falls back to `default`.
    private static let tagMap: [String: String] = [
        "tactical": "tactical",
        "gambit": "tactical",
        "positional": "positional",
        "classical": "positional",
        "aggressive": "aggressive",
        "solid": "solid",
        "hypermodern": "hypermodern",
    ]

    /// Resolve the coach personality for a given opening based on its tags.
    static func forOpening(_ opening: Opening) -> CoachPersonality {
        if let tags = opening.tags {
            for tag in tags {
                if let personalityID = tagMap[tag.lowercased()] {
                    return personality(forID: personalityID)
                }
            }
        }
        return defaultPersonality
    }

    static func personality(forID id: String) -> CoachPersonality {
        switch id {
        case "tactical":     return tactical
        case "positional":   return positional
        case "aggressive":   return aggressive
        case "solid":        return solid
        case "hypermodern":  return hypermodern
        default:             return defaultPersonality
        }
    }

    // MARK: - 6 Personalities

    static let tactical = CoachPersonality(
        id: "tactical",
        humanName: "Coach Viktor",
        humanIcon: "bolt.fill",
        engineName: "Sparkplug-7",
        engineIcon: "bolt.circle.fill",
        enginePortraitLarge: "coach_sparkplug_large",
        enginePortraitSmall: "coach_sparkplug_small",
        personalityPrompt: "You are intense and love tactical fireworks. You get excited about sacrifices and sharp play. Drop the occasional chess pun.",
        onGoodMove: [
            "Boom! That's a strike.",
            "Sharp as a tactic. Love it.",
            "You see it? That's the killing move.",
            "Now THAT's how you play with fire.",
            "Precision under pressure. Respect."
        ],
        onOkayMove: [
            "Solid, but there was a sharper option.",
            "Safe choice. Sometimes safe isn't exciting enough.",
            "Not bad, but the tactics were calling your name.",
            "You played it cool. I'd have gone for blood.",
            "Playable. But the board was screaming for more."
        ],
        onMistake: [
            "Ouch. The position had teeth and you missed them.",
            "That one stings. Let's rewind and find the venom.",
            "Even the best tacticians drop a piece sometimes.",
            "Mistakes are just unfinished tactics. Let's fix it.",
            "The combination was right there. Next time you'll see it."
        ],
        onDeviation: [
            "Off the beaten path! Time to calculate.",
            "Surprise move! Stay sharp, look for tactics.",
            "They went rogue. That means opportunities for us.",
            "Uncharted territory. Keep your eyes on every piece.",
            "Off-book but not off-guard. Scan for tricks."
        ],
        onStandardOpponent: [
            "Standard reply. Now let's find the fireworks.",
            "Book move. The real action starts soon.",
            "Expected. Keep the pressure on.",
            "They're following the script. We'll improvise.",
            "Textbook response. The fun's about to begin."
        ],
        onGreeting: [
            "Ready to light up the board? Let's go!",
            "Viktor here. Time to make some sparks fly.",
            "Tactics win games. Let's prove it today.",
            "Sharp minds play sharp chess. Let's be both.",
            "Every move is a chance for brilliance. Begin!"
        ],
        onEncouragement: [
            "You're on fire! Keep that energy going.",
            "The tactical eye is sharpening. I can see it.",
            "Streak! You're seeing combinations before they happen.",
            "This is what improvement looks like. Beautiful.",
            "Your pattern recognition is leveling up fast."
        ],
        onConsolation: [
            "Even Tal had rough days. Shake it off.",
            "Mistakes mean you're pushing yourself. That's good.",
            "The best attackers learn from every missed shot.",
            "Regroup. The next combination is around the corner.",
            "Tactical vision comes in waves. Yours will return."
        ],
        onMilestone: [
            "New level unlocked! Your tactical arsenal grows.",
            "Promotion! You've earned those stripes in combat.",
            "Level up! The complications bow to you now.",
            "Achievement unlocked. Time for harder tactics!",
            "You've graduated to sharper waters. Exciting!"
        ],
        onSessionEnd: [
            "Great session! Those tactics are sinking in.",
            "You fought well today. See you at the board.",
            "Every session sharpens the blade. Well played.",
            "Rest those tactical muscles. They earned it.",
            "Until next time. Keep dreaming in combinations."
        ],
        onWelcomeBack: [
            "Back for more? Good.",
            "The board awaits.",
            "Ready to strike?",
            "Let's pick up where we left off.",
            "Time to sharpen the blade."
        ],
        onNextStep: [
            "One more push.",
            "Almost there — don't let up.",
            "The finish line is close.",
            "Keep that momentum.",
            "Just a few more sessions."
        ]
    )

    static let positional = CoachPersonality(
        id: "positional",
        humanName: "Coach Sofia",
        humanIcon: "leaf.fill",
        engineName: "Metronome-4",
        engineIcon: "metronome.fill",
        enginePortraitLarge: "coach_metronome_large",
        enginePortraitSmall: "coach_metronome_small",
        personalityPrompt: "You are calm and methodical. You appreciate good structure, piece harmony, and long-term plans. You speak with measured confidence.",
        onGoodMove: [
            "Elegant. That improves your whole position.",
            "Beautifully placed. The position speaks for itself.",
            "That's the kind of move that wins games quietly.",
            "Structure, harmony, control. Textbook.",
            "A move Karpov would nod at. Well done."
        ],
        onOkayMove: [
            "Reasonable, but the position asked for more subtlety.",
            "Not wrong, but there was a more harmonious choice.",
            "Playable. Though the quiet move was stronger here.",
            "You chose function over form. The form was better.",
            "Acceptable, but let's talk about the ideal square."
        ],
        onMistake: [
            "That disrupts the harmony. Let's find the right note.",
            "The position's balance shifted. Here's why.",
            "Small inaccuracy, but in positional chess, small matters.",
            "The structure wobbled. Let's steady it next time.",
            "Patience is our weapon. That move was too hasty."
        ],
        onDeviation: [
            "An unexpected path. Let's assess the new structure.",
            "Off-book. Time to think about pawn structure and plans.",
            "New territory. Read the position, not the playbook.",
            "Deviation noted. The principles still guide us here.",
            "Interesting sideline. Let's find the right plan."
        ],
        onStandardOpponent: [
            "As expected. Our long-term plan stays on track.",
            "Standard continuation. The structure is developing nicely.",
            "Book move. Everything is proceeding logically.",
            "The position unfolds as theory predicts.",
            "Classical response. We know what to do next."
        ],
        onGreeting: [
            "Welcome. Let's build something beautiful together.",
            "Sofia here. Patience and structure win the day.",
            "Good positions create good moves. Let's begin.",
            "Every pawn matters. Let's place them wisely.",
            "Ready for some positional chess? Take your time."
        ],
        onEncouragement: [
            "Your positional sense is maturing nicely.",
            "Consistent, measured play. That's the path to mastery.",
            "You're thinking in plans now, not just moves.",
            "The improvement is clear. Your positions are cleaner.",
            "Beautiful trend. You're reading the board deeply."
        ],
        onConsolation: [
            "Even Petrosian had to learn patience. You'll get there.",
            "One imprecise move doesn't undo your growth.",
            "Positional understanding grows slowly but surely.",
            "Take a breath. The next position awaits your wisdom.",
            "Every great player builds their skill brick by brick."
        ],
        onMilestone: [
            "New level! Your understanding deepens beautifully.",
            "Promoted! You've proven your positional instincts.",
            "Achievement earned through patience and precision.",
            "You've reached new positional heights. Well deserved.",
            "The board makes more sense to you now. Wonderful."
        ],
        onSessionEnd: [
            "Thoughtful session. Your positions were lovely.",
            "Well studied. The structure of your play improves.",
            "Rest well. Positional wisdom grows even in sleep.",
            "Good work today. Slow and steady wins.",
            "Until next time. Keep thinking in plans."
        ],
        onWelcomeBack: [
            "Welcome back. The board is patient.",
            "Good to see you. Let's think deeply today.",
            "Ready for another measured session?",
            "The position awaits your careful eye.",
            "Let's build on what we started."
        ],
        onNextStep: [
            "Steady progress. Keep going.",
            "One step at a time — you're getting there.",
            "The next milestone is within reach.",
            "Patience pays off. Almost there.",
            "Your consistency will carry you through."
        ]
    )

    static let aggressive = CoachPersonality(
        id: "aggressive",
        humanName: "Coach Blaze",
        humanIcon: "flame.fill",
        engineName: "Nitro-X",
        engineIcon: "flame.circle.fill",
        enginePortraitLarge: "coach_nitro_large",
        enginePortraitSmall: "coach_nitro_small",
        personalityPrompt: "You are bold and high-energy. You love attacking chess, initiative, and pushing forward. You encourage taking risks and seizing the initiative.",
        onGoodMove: [
            "YES! That's how you attack!",
            "Full speed ahead! Great move.",
            "Aggressive and correct. My favorite combo.",
            "That move has TEETH. I love it.",
            "You're not asking for permission. You're taking it."
        ],
        onOkayMove: [
            "Decent, but where's the aggression?",
            "You had a chance to press harder there.",
            "Safe is fine. But bold was better.",
            "The attack was right there for the taking.",
            "Sometimes you gotta kick the door down, not knock."
        ],
        onMistake: [
            "Whoa, too hot! Even fire needs direction.",
            "Aggression without calculation is just chaos. Refocus.",
            "Bold move, wrong target. Let's redirect.",
            "That one backfired. But I love the spirit.",
            "Even warriors study before the battle. Let's learn."
        ],
        onDeviation: [
            "They blinked! Time to pounce.",
            "Off-book means off-balance. Attack!",
            "Surprise? We LOVE surprises. More to exploit.",
            "They left the path. Let's make them regret it.",
            "New position, same mission: attack."
        ],
        onStandardOpponent: [
            "Expected move. But our attack doesn't stop.",
            "Standard play from them. We play anything but standard.",
            "They're playing it safe. We're playing to win.",
            "Book move. While they read, we charge.",
            "Predictable response. Initiative stays with us."
        ],
        onGreeting: [
            "Blaze here. Ready to set the board on fire?",
            "No defense. Only attack. Let's GO!",
            "You bring the moves, I bring the energy. Let's roll!",
            "Today we play BOLD. No half measures.",
            "The best defense is a devastating offense. Begin!"
        ],
        onEncouragement: [
            "That attacking instinct is getting sharper!",
            "You're playing with real confidence now. Love it.",
            "Initiative master in the making!",
            "Your opponents won't know what hit them.",
            "Keep this up and they'll need a fire extinguisher."
        ],
        onConsolation: [
            "Every great attacker crashes sometimes. Get back up.",
            "Kasparov lost games too. What matters is the next one.",
            "Channel that frustration into the next attack.",
            "Down but never out. That's the attacking spirit.",
            "One bad game doesn't dim your fire."
        ],
        onMilestone: [
            "Level up! Your attack is getting DANGEROUS.",
            "Promotion! They should be scared now.",
            "New tier unlocked. Unleash even more!",
            "Achievement: certified aggressive player!",
            "You've evolved. The attack just got scarier."
        ],
        onSessionEnd: [
            "What a ride! Your attacking play was electric.",
            "Great session. The fire burns brighter each time.",
            "Rest up. Tomorrow we attack again.",
            "You brought the heat today. Well played.",
            "Until next time. Stay dangerous."
        ],
        onWelcomeBack: [
            "Back to burn it down? Let's GO!",
            "The fire never dies. Welcome back!",
            "Ready to attack? I've been waiting.",
            "No time to waste. Let's charge!",
            "The board missed your aggression."
        ],
        onNextStep: [
            "Keep the pressure on!",
            "Don't stop now — you're on fire.",
            "One more push and they crumble.",
            "The attack is building. Stay sharp.",
            "Almost there — full speed ahead!"
        ]
    )

    static let solid = CoachPersonality(
        id: "solid",
        humanName: "Coach Patience",
        humanIcon: "shield.fill",
        engineName: "Steadybot-2K",
        engineIcon: "shield.checkered",
        enginePortraitLarge: "coach_steadybot_large",
        enginePortraitSmall: "coach_steadybot_small",
        personalityPrompt: "You are warm and reassuring. You value safety, solid foundations, and careful play. You build confidence with gentle encouragement.",
        onGoodMove: [
            "Safe and strong. Just how we like it.",
            "Rock solid. Your foundation keeps growing.",
            "That's a move you can always count on.",
            "Steady hands, steady play. Perfect.",
            "Reliable as always. Well done."
        ],
        onOkayMove: [
            "Reasonable. Let's see if there was something safer.",
            "Not bad at all. Just a touch more careful next time.",
            "Good instinct. The safest path was slightly different.",
            "You're in the right zone. Just a small adjustment.",
            "Close to ideal. The solid choice was just one step away."
        ],
        onMistake: [
            "No worries. Everyone slips. Let's see the safe path.",
            "A small stumble. Your foundation is still strong.",
            "That happens. The key is knowing the safe move exists.",
            "Don't be hard on yourself. Let's build back up.",
            "Mistakes are teachers. This one has a good lesson."
        ],
        onDeviation: [
            "Unexpected move! Stay calm and stick to solid principles.",
            "Off-book. But our steady plan still works here.",
            "No panic. Solid play handles surprises well.",
            "New position, familiar principles. You've got this.",
            "They deviated. We stay grounded."
        ],
        onStandardOpponent: [
            "As expected. Our safe position holds strong.",
            "Standard play. Steady as she goes.",
            "Everything on schedule. No surprises.",
            "The plan continues smoothly.",
            "Textbook. Our solid foundation is paying off."
        ],
        onGreeting: [
            "Welcome! Let's build a fortress together.",
            "Patience here. Slow and steady wins the game.",
            "No rush. Good moves come from good thinking.",
            "Ready for some solid chess? Take your time.",
            "Safety first, victory follows. Let's begin."
        ],
        onEncouragement: [
            "Your consistency is really showing. Well done.",
            "Steady improvement, every single session.",
            "You're building something reliable. I'm proud.",
            "That patient approach is paying dividends.",
            "Rock-solid play is becoming your trademark."
        ],
        onConsolation: [
            "One rough patch doesn't shake our foundation.",
            "Even the sturdiest walls need repairs sometimes.",
            "You're stronger than one bad moment. Keep going.",
            "Tomorrow's a new game and a fresh start.",
            "Every master was once a student. You're on the path."
        ],
        onMilestone: [
            "New level! Your solid play earned this.",
            "Promoted! Built on a foundation of smart choices.",
            "Achievement unlocked through patience and care.",
            "You've proven that steady play gets results.",
            "Level up! Your defensive skills are impressive."
        ],
        onSessionEnd: [
            "Great session. Steady and focused throughout.",
            "Well played. Your patience is your superpower.",
            "Good work today. The foundation grows stronger.",
            "Rest well. Solid players need solid rest too.",
            "Until next time. Keep that steady hand."
        ],
        onWelcomeBack: [
            "Welcome back! Your fortress awaits.",
            "Good to see you. Let's build something solid.",
            "Ready for another steady session?",
            "The foundation is strong. Let's add to it.",
            "No rush — take your time and do it right."
        ],
        onNextStep: [
            "Brick by brick, you're building mastery.",
            "Steady hands finish the job.",
            "Almost there. Take it one step at a time.",
            "You're closer than you think.",
            "Keep that reliable rhythm going."
        ]
    )

    static let hypermodern = CoachPersonality(
        id: "hypermodern",
        humanName: "Coach Zephyr",
        humanIcon: "wind",
        engineName: "Toaster-3000",
        engineIcon: "microwave.fill",
        enginePortraitLarge: "coach_toaster_large",
        enginePortraitSmall: "coach_toaster_small",
        personalityPrompt: "You are quirky and philosophical. You love unusual ideas, counterintuitive moves, and thinking differently about chess. You drop offbeat observations.",
        onGoodMove: [
            "Unconventional wisdom in action. Bravo.",
            "Who says you need the center to control it?",
            "The fianchetto gods smile upon you.",
            "Beautifully indirect. Chess is poetry.",
            "You're thinking in dimensions others don't see."
        ],
        onOkayMove: [
            "Reasonable. But the weird move was the right move.",
            "Classical choice. We're better than classical.",
            "Solid, sure. But where's the imagination?",
            "The obvious move isn't always the best move.",
            "Good enough. But 'good enough' isn't our style."
        ],
        onMistake: [
            "Even the most creative minds need structure sometimes.",
            "Too much spice, not enough substance. Let's recalibrate.",
            "The idea was interesting. The execution needs work.",
            "Creativity without calculation is just guessing.",
            "Let's channel that wild energy more precisely."
        ],
        onDeviation: [
            "Off the map! This is where we thrive.",
            "They improvised. So do we. Better.",
            "Uncharted positions are our playground.",
            "The book ended. The fun begins.",
            "No theory here. Just pure chess thinking."
        ],
        onStandardOpponent: [
            "Predictable. They play the notes. We play the music.",
            "Standard stuff. Our ideas are anything but.",
            "They follow the crowd. We follow the position.",
            "Expected. Our response will be anything but.",
            "Book move from them. Art from us."
        ],
        onGreeting: [
            "Zephyr here. Ready to think differently?",
            "The center is overrated. Let's prove it.",
            "Chess is a conversation. Let's say something interesting.",
            "Normal is boring. Let's play something beautiful.",
            "Welcome to the weird and wonderful. Let's begin."
        ],
        onEncouragement: [
            "Your creative thinking is really developing!",
            "You're seeing ideas others would miss. Wonderful.",
            "The unconventional approach suits you perfectly.",
            "Original thinking is the hardest skill. You're getting it.",
            "You're becoming a true chess thinker, not just a player."
        ],
        onConsolation: [
            "Nimzowitsch was called a heretic too. Keep going.",
            "Creative minds need space to fail. This was just practice.",
            "The best ideas sometimes need a few tries to land.",
            "Different doesn't mean wrong. Refine and return.",
            "Every oddball idea that fails teaches two that succeed."
        ],
        onMilestone: [
            "New level! Your unique vision grows stronger.",
            "Promoted! Thinking outside the box pays off.",
            "Achievement: certified original thinker!",
            "You've proven there's more than one way to play.",
            "Level up! The hypermodern spirit lives on."
        ],
        onSessionEnd: [
            "Fascinating session. Your ideas were refreshing.",
            "Good work. Keep questioning everything.",
            "Rest that creative brain. It earned it today.",
            "Until next time. Never stop being original.",
            "Great session. The position is a canvas. You painted well."
        ],
        onWelcomeBack: [
            "Ah, you've returned. The unconventional path continues.",
            "Back for more weirdness? Excellent.",
            "Ready to think sideways? Let's go.",
            "The fianchetto awaits your return.",
            "Welcome back, fellow chess philosopher."
        ],
        onNextStep: [
            "The next breakthrough is one odd idea away.",
            "Keep exploring — the path is never straight.",
            "Almost there. The weird way is the right way.",
            "One more creative leap. You're close.",
            "The position reveals itself to the patient thinker."
        ]
    )

    static let defaultPersonality = CoachPersonality(
        id: "default",
        humanName: "Coach Alex",
        humanIcon: "person.crop.circle.fill",
        engineName: "Circuit-1",
        engineIcon: "cpu.fill",
        enginePortraitLarge: "coach_circuit_large",
        enginePortraitSmall: "coach_circuit_small",
        personalityPrompt: "You are a friendly and encouraging chess coach. You adapt your style to whatever the student needs.",
        onGoodMove: [
            "Nice move! That's the right idea.",
            "Well played. You're on the right track.",
            "Good choice! That follows the plan.",
            "Solid move. Keep it up.",
            "That's the one! Well spotted."
        ],
        onOkayMove: [
            "Not bad! There was a slightly better option.",
            "Playable move. Let's look at the alternative.",
            "Decent choice. The book move is a touch stronger.",
            "You're in the right area. Just a small tweak.",
            "Good thinking, slightly different execution needed."
        ],
        onMistake: [
            "That's okay! Let's see what the book recommends.",
            "Small slip. We all make them. Here's the idea.",
            "Don't worry about it. Let's look at why.",
            "Learning moment! The right move was close.",
            "Everyone misses moves. Let's figure this one out."
        ],
        onDeviation: [
            "They went off-book! Stay focused.",
            "Surprise move. Let's think about what this means.",
            "Out of the opening now. Apply your principles.",
            "New territory! Use what you've learned.",
            "Off the beaten path. Your training prepares you for this."
        ],
        onStandardOpponent: [
            "Standard response. Our plan continues.",
            "Expected move. Everything on track.",
            "By the book. Keep going.",
            "Normal continuation. Stay focused.",
            "As predicted. On to the next move."
        ],
        onGreeting: [
            "Hey there! Ready to learn some chess?",
            "Welcome back! Let's make some good moves.",
            "Alex here. Let's have a great session.",
            "Good to see you! Time to study this opening.",
            "Let's do this! Your next great game starts now."
        ],
        onEncouragement: [
            "You're really improving! Keep it up.",
            "Great progress. Each session makes you stronger.",
            "The work is paying off. I can see the difference.",
            "You're getting better every time. Seriously.",
            "Impressive growth. Your dedication shows."
        ],
        onConsolation: [
            "Tough one. But every game teaches something.",
            "Don't let it get you down. Progress isn't linear.",
            "Even the best have rough games. Tomorrow's fresh.",
            "Shake it off. You're still improving.",
            "One session doesn't define your journey."
        ],
        onMilestone: [
            "Congrats! New level unlocked!",
            "You earned this promotion. Well done!",
            "Achievement unlocked! Your hard work paid off.",
            "Level up! You're getting stronger.",
            "New milestone reached. Celebrate this one!"
        ],
        onSessionEnd: [
            "Good session! See you next time.",
            "Well played today. Keep practicing.",
            "Nice work. Rest up and come back strong.",
            "That was productive. Your future self thanks you.",
            "Good stuff today. See you at the board!"
        ],
        onWelcomeBack: [
            "Welcome back! Ready for more?",
            "Good to see you again. Let's play!",
            "Hey! Let's pick up where we left off.",
            "Back at it — that's the spirit!",
            "Ready for another session? Let's go."
        ],
        onNextStep: [
            "You're making great progress.",
            "Keep going — the next step is right there.",
            "Almost there. A few more and you've got it.",
            "Steady progress wins the race.",
            "One more step forward. You can do this."
        ]
    )
}
