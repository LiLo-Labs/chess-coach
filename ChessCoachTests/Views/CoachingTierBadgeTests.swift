import Testing
@testable import ChessCoach

@Suite
struct CoachingTierBadgeTests {
    @Test func basicBadgeShowsCorrectText() {
        let badge = CoachingTierBadge(isLLM: false)
        #expect(badge.label == "Basic")
    }

    @Test func aiCoachBadgeShowsCorrectText() {
        let badge = CoachingTierBadge(isLLM: true)
        #expect(badge.label == "AI Coach")
    }
}
