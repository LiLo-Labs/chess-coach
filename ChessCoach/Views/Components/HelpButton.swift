import SwiftUI

/// Contextual help button that shows a popover with explanatory text.
/// Use throughout the app wherever users might be confused.
struct HelpButton: View {
    let title: String
    let message: String
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: 280)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Predefined help topics for consistent messaging across the app.
enum HelpTopic {
    case planScore
    case difficulty
    case learningJourney
    case moveSafety
    case followingPlan
    case popularity
    case sparkleExplain
    case paths
    case skillLevel
    case streak
    case dailyGoal
    case evalBar
    case review
    case practiceMode
    case accuracy

    var title: String {
        switch self {
        case .planScore: return "Plan Score"
        case .difficulty: return "Difficulty"
        case .learningJourney: return "Learning Journey"
        case .moveSafety: return "Move Safety"
        case .followingPlan: return "Following the Plan"
        case .popularity: return "Popularity"
        case .sparkleExplain: return "AI Explanation"
        case .paths: return "Paths"
        case .skillLevel: return "Skill Level"
        case .streak: return "Streak"
        case .dailyGoal: return "Daily Goal"
        case .evalBar: return "Evaluation Bar"
        case .review: return "Review"
        case .practiceMode: return "Practice Mode"
        case .accuracy: return "Accuracy"
        }
    }

    var message: String {
        switch self {
        case .planScore:
            return "Your Plan Score measures how well your moves follow the game plan. Higher is better. It combines move safety (was your move sound?) with how well it follows the strategy."
        case .difficulty:
            return "Difficulty ranges from 1 (beginner-friendly) to 5 (advanced). Start with lower difficulty openings to build confidence."
        case .learningJourney:
            return "Each opening has 5 stages. Learn the plan, practice it, discover the history, face different opponents, then play for real. Complete each stage to unlock the next."
        case .moveSafety:
            return "Move Safety measures whether your move was tactically sound — did you avoid blunders and maintain a good position?"
        case .followingPlan:
            return "This measures how closely your moves match the strategic goals of the opening plan."
        case .popularity:
            return "How often strong players choose this move. Popular moves are well-tested and reliable."
        case .sparkleExplain:
            return "Tap the sparkle icon to get an AI-powered explanation of why a move was good or what went wrong. Requires an AI coaching subscription."
        case .paths:
            return "Paths are different move sequences within an opening. Each path represents a different way the game can develop based on your opponent's choices."
        case .skillLevel:
            return "Your skill level adjusts the coaching difficulty and opponent strength. Don't worry about getting it exactly right — you can change it anytime in Settings."
        case .streak:
            return "Your streak counts how many days in a row you've practiced. Keep it going to build strong habits!"
        case .dailyGoal:
            return "Set a daily goal for how many games to play each day. You can adjust this in Settings."
        case .evalBar:
            return "The bar on the side shows which player has the advantage. White at the top means white is winning, black at the bottom means black is ahead. The number is the advantage in \"pawns\" — a chess unit of measurement."
        case .review:
            return "Review uses spaced repetition — you'll see positions again at increasing intervals to lock them into long-term memory. Get them right to space them out further."
        case .practiceMode:
            return "In practice mode, there are no hints. Your opponent will play different responses to test your understanding. Try to remember the plan!"
        case .accuracy:
            return "Accuracy shows the percentage of moves you played correctly. Don't worry about being perfect — even grandmasters make mistakes."
        }
    }
}

/// Convenience initializer using predefined help topics.
extension HelpButton {
    init(topic: HelpTopic) {
        self.title = topic.title
        self.message = topic.message
    }
}
