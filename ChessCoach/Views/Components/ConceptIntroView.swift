import SwiftUI

/// One-time introductory screens for key concepts.
/// Each concept is shown at most once, tracked via UserDefaults.
enum ConceptIntro: String, CaseIterable {
    case whatAreOpenings = "intro_what_are_openings"
    case howToLearn = "intro_how_to_learn"
    case whatIsPractice = "intro_what_is_practice"
    case whatIsReview = "intro_what_is_review"

    var title: String {
        switch self {
        case .whatAreOpenings: return "What Are Openings?"
        case .howToLearn: return "How Learning Works"
        case .whatIsPractice: return "Practice Mode"
        case .whatIsReview: return "Review & Remember"
        }
    }

    var icon: String {
        switch self {
        case .whatAreOpenings: return "book.pages.fill"
        case .howToLearn: return "lightbulb.fill"
        case .whatIsPractice: return "target"
        case .whatIsReview: return "arrow.clockwise"
        }
    }

    var iconColor: Color {
        switch self {
        case .whatAreOpenings: return .cyan
        case .howToLearn: return .blue
        case .whatIsPractice: return .orange
        case .whatIsReview: return .green
        }
    }

    var paragraphs: [String] {
        switch self {
        case .whatAreOpenings:
            return [
                "Every chess game starts with an \"opening\" — the first 10-15 moves that set up your game plan.",
                "Strong players have studied these plans for centuries. Instead of figuring out every move from scratch, you can learn proven strategies that work.",
                "Each opening has a plan: which pieces to develop, which squares to control, and what kind of game to aim for.",
                "We'll teach you the plan first, then help you practice until it feels natural."
            ]
        case .howToLearn:
            return [
                "Each opening has a learning journey with multiple stages.",
                "First, you'll learn the plan — why each move matters and what you're trying to achieve.",
                "Then you'll practice playing it, first with guidance and hints, then on your own.",
                "Finally, you'll face different opponent responses and learn how to adapt your plan."
            ]
        case .whatIsPractice:
            return [
                "In practice mode, the hints are off and your opponent will surprise you.",
                "They won't always play the main line — they'll try different moves to test your understanding.",
                "Don't worry about being perfect. The goal is to apply what you've learned and see how it holds up.",
                "Your accuracy score tracks how often you find the right moves."
            ]
        case .whatIsReview:
            return [
                "Spaced repetition is a proven technique for building long-term memory.",
                "You'll review positions at increasing intervals — first after a day, then a few days, then a week.",
                "Each time you get a position right, the next review is scheduled further out.",
                "This helps you truly learn the openings, not just memorize them temporarily."
            ]
        }
    }

    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: rawValue)
    }

    func markSeen() {
        UserDefaults.standard.set(true, forKey: rawValue)
    }
}

/// A full-screen introductory card for a concept. Shows once, then dismisses.
struct ConceptIntroView: View {
    let concept: ConceptIntro
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                Image(systemName: concept.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(concept.iconColor)

                Text(concept.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ForEach(Array(concept.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.body)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(.horizontal, AppSpacing.xxxl)

                Spacer()

                Button {
                    concept.markSeen()
                    onDismiss()
                } label: {
                    Text("Got It")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(concept.iconColor, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.xxxl)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Modifier that shows a concept intro once before allowing content through.
struct ConceptIntroModifier: ViewModifier {
    let concept: ConceptIntro
    @State private var showIntro: Bool

    init(concept: ConceptIntro) {
        self.concept = concept
        self._showIntro = State(initialValue: !concept.hasBeenSeen)
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showIntro) {
                ConceptIntroView(concept: concept) {
                    showIntro = false
                }
            }
    }
}

extension View {
    /// Shows a one-time concept introduction the first time the user encounters this view.
    func conceptIntro(_ concept: ConceptIntro) -> some View {
        modifier(ConceptIntroModifier(concept: concept))
    }
}
