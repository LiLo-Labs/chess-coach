import Testing
@testable import ChessCoach

@Suite
struct OpeningIndicatorBannerTests {
    @Test func detectsItalianAfterMoves() {
        let detector = HolisticDetector()
        let detection = detector.detect(moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
        #expect(detection.whiteFramework.primary != nil)
        let name = detection.whiteFramework.primary?.opening.name ?? ""
        #expect(name.lowercased().contains("italian"))
    }

    @Test func bothSidesDetected() {
        let detector = HolisticDetector()
        let detection = detector.detect(moves: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"])
        #expect(detection.whiteFramework.primary != nil)
        #expect(detection.blackFramework.primary != nil)
    }
}
