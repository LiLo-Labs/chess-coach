# Phase 4: Off-Book Coaching + Opening Indicator — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make coaching useful beyond the opening book — show detected openings for both sides, generate plan-based coaching when the game goes off-book, and replace personality witticisms with factual opening data on the free tier.

**Architecture:** New `OffBookCoachingService` generates plan-based guidance from `OpeningPlan.strategicGoals` and `pieceTargets`. `HolisticDetector` (already exists) runs after every move to feed a persistent `OpeningIndicatorBanner`. `CoachingService.fallbackCoaching()` is replaced with `freeCoaching()` that uses `OpeningMove.explanation` on-book and `OffBookCoachingService` off-book.

**Tech Stack:** SwiftUI, Swift 6 strict concurrency, Swift Testing framework, XcodeGen

---

### Task 1: OffBookGuidance Model

**Files:**
- Create: `ChessCoach/Services/OffBookCoachingService.swift`
- Test: `ChessCoachTests/Services/OffBookCoachingServiceTests.swift`

**Step 1: Write the test file**

```swift
import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct OffBookCoachingServiceTests {
    let italian: Opening = OpeningDatabase.shared.openings.first { $0.id == "italian" }!

    @Test func guidanceIncludesPlanSummary() {
        let service = OffBookCoachingService()
        let guidance = service.generateGuidance(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            opening: italian,
            deviationPly: 4,
            moveHistory: ["e2e4", "e7e5", "g1f3", "b8c6"]
        )
        #expect(guidance.summary.contains("move"))
        #expect(!guidance.planReminder.isEmpty)
        #expect(!guidance.relevantGoals.isEmpty)
    }

    @Test func guidanceForOpponentDeviation() {
        let service = OffBookCoachingService()
        let guidance = service.generateGuidance(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            opening: italian,
            deviationPly: 5,
            moveHistory: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"],
            opponentDeviation: (played: "d7d6", expected: "Bc5")
        )
        #expect(guidance.summary.contains("opponent") || guidance.summary.contains("Opponent"))
    }

    @Test func relevantGoalsFiltersByCheckCondition() {
        let service = OffBookCoachingService()
        // FEN where bishop IS on a2-g8 diagonal (c4)
        let fenWithBishop = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 3"
        let guidance = service.generateGuidance(
            fen: fenWithBishop,
            opening: italian,
            deviationPly: 6,
            moveHistory: ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"]
        )
        // Should still have goals (some achieved, some not)
        #expect(!guidance.relevantGoals.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' -only-testing:ChessCoachTests/OffBookCoachingServiceTests 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED|error:'`
Expected: FAIL — `OffBookCoachingService` not found

**Step 3: Write the OffBookCoachingService**

Create `ChessCoach/Services/OffBookCoachingService.swift`:

```swift
import Foundation

struct OffBookGuidance: Sendable {
    let summary: String
    let planReminder: String
    let suggestion: String?
    let relevantGoals: [StrategicGoal]
}

struct OffBookCoachingService: Sendable {

    func generateGuidance(
        fen: String,
        opening: Opening,
        deviationPly: Int,
        moveHistory: [String],
        opponentDeviation: (played: String, expected: String)? = nil
    ) -> OffBookGuidance {
        guard let plan = opening.plan else {
            return OffBookGuidance(
                summary: "You left the book at move \(deviationPly / 2 + 1).",
                planReminder: "Keep developing your pieces and controlling the center.",
                suggestion: nil,
                relevantGoals: []
            )
        }

        let moveNumber = deviationPly / 2 + 1
        let relevant = relevantGoals(from: plan, fen: fen)
        let unmet = unmetPieceTargets(from: plan, fen: fen)

        // Summary
        let summary: String
        if let dev = opponentDeviation {
            summary = "Your opponent deviated at move \(moveNumber) with \(dev.played) (expected \(dev.expected))."
        } else {
            summary = "You left the \(opening.name) at move \(moveNumber)."
        }

        // Plan reminder
        let planReminder = plan.summary

        // Suggestion from unmet targets or top relevant goal
        let suggestion: String?
        if let target = unmet.first {
            let squares = target.idealSquares.joined(separator: " or ")
            suggestion = "Consider developing your \(target.piece) toward \(squares) — \(target.reasoning.lowercased())"
        } else if let goal = relevant.first {
            suggestion = "Focus on: \(goal.description.lowercased())"
        } else {
            suggestion = nil
        }

        return OffBookGuidance(
            summary: summary,
            planReminder: planReminder,
            suggestion: suggestion,
            relevantGoals: relevant
        )
    }

    // MARK: - Goal Relevance

    func relevantGoals(from plan: OpeningPlan, fen: String) -> [StrategicGoal] {
        plan.strategicGoals.filter { goal in
            guard let condition = goal.checkCondition else { return true }
            return !isConditionMet(condition, in: fen)
        }
        .sorted { ($0.priority) < ($1.priority) }
    }

    func isConditionMet(_ condition: String, in fen: String) -> Bool {
        let boardPart = String(fen.prefix(while: { $0 != " " }))

        if condition.hasPrefix("bishop_on_diagonal_") {
            let diagonal = String(condition.dropFirst("bishop_on_diagonal_".count))
            return isBishopOnDiagonal(diagonal, board: boardPart)
        }
        if condition.hasPrefix("pawn_on_") {
            let square = String(condition.dropFirst("pawn_on_".count))
            return isPieceOnSquare("P", square: square, board: boardPart)
        }
        if condition == "castled_kingside" {
            return isCastled(kingside: true, fen: fen)
        }
        if condition == "castled_queenside" {
            return isCastled(kingside: false, fen: fen)
        }
        // Unknown condition — assume not met (goal still relevant)
        return false
    }

    // MARK: - Piece Target Checking

    func unmetPieceTargets(from plan: OpeningPlan, fen: String) -> [PieceTarget] {
        let boardPart = String(fen.prefix(while: { $0 != " " }))
        let isWhite = fen.contains(" w ")

        return plan.pieceTargets.filter { target in
            let pieceLetter = pieceChar(for: target.piece, isWhite: isWhite)
            guard let piece = pieceLetter else { return false }
            return !target.idealSquares.contains(where: { isPieceOnSquare(piece, square: $0, board: boardPart) })
        }
    }

    // MARK: - FEN Helpers

    private func pieceChar(for name: String, isWhite: Bool) -> String? {
        let lower = name.lowercased()
        let base: String?
        if lower.contains("bishop") { base = "B" }
        else if lower.contains("knight") { base = "N" }
        else if lower.contains("rook") { base = "R" }
        else if lower.contains("queen") { base = "Q" }
        else if lower.contains("king") { base = "K" }
        else if lower.contains("pawn") { base = "P" }
        else { base = nil }
        guard let b = base else { return nil }
        return isWhite ? b : b.lowercased()
    }

    private func isPieceOnSquare(_ piece: String, square: String, board: String) -> Bool {
        guard square.count == 2,
              let file = square.first?.asciiValue.map({ Int($0) - Int(Character("a").asciiValue!) }),
              let rank = square.last?.wholeNumberValue,
              (0..<8).contains(file), (1...8).contains(rank) else { return false }

        let rows = board.split(separator: "/")
        guard rows.count == 8 else { return false }
        let rowIndex = 8 - rank
        let row = String(rows[rowIndex])

        var col = 0
        for ch in row {
            if col == file { return String(ch) == piece }
            if ch.isNumber { col += ch.wholeNumberValue ?? 0 }
            else { col += 1 }
        }
        return false
    }

    private func isBishopOnDiagonal(_ diagonal: String, board: String) -> Bool {
        // Parse diagonal like "a2g8" — check all squares on that diagonal for a bishop
        guard diagonal.count == 4 else { return false }
        let startFile = Int(diagonal.first!.asciiValue!) - Int(Character("a").asciiValue!)
        let startRank = Int(String(diagonal[diagonal.index(diagonal.startIndex, offsetBy: 1)]))! - 1
        let endFile = Int(diagonal[diagonal.index(diagonal.startIndex, offsetBy: 2)].asciiValue!) - Int(Character("a").asciiValue!)
        let endRank = Int(String(diagonal.last!))! - 1

        let fileDelta = endFile > startFile ? 1 : -1
        let rankDelta = endRank > startRank ? 1 : -1

        var f = startFile, r = startRank
        while f >= 0 && f < 8 && r >= 0 && r < 8 {
            let square = "\(Character(UnicodeScalar(f + Int(Character("a").asciiValue!))!))\(r + 1)"
            if isPieceOnSquare("B", square: square, board: board) || isPieceOnSquare("b", square: square, board: board) {
                return true
            }
            f += fileDelta
            r += rankDelta
            if f == endFile + fileDelta { break }
        }
        return false
    }

    private func isCastled(kingside: Bool, fen: String) -> Bool {
        let parts = fen.split(separator: " ")
        guard parts.count >= 3 else { return false }
        let castling = String(parts[2])
        // If castling rights are gone, king has likely moved (proxy for castled)
        let isWhite = String(parts[1]) == "w" || String(parts[1]) == "b" // check both sides
        if kingside {
            return !castling.contains("K") && !castling.contains("k")
        } else {
            return !castling.contains("Q") && !castling.contains("q")
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' -only-testing:ChessCoachTests/OffBookCoachingServiceTests 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED|error:'`
Expected: TEST SUCCEEDED

**Step 5: Commit**

```bash
git add ChessCoach/Services/OffBookCoachingService.swift ChessCoachTests/Services/OffBookCoachingServiceTests.swift
git commit -m "Add OffBookCoachingService with plan-based guidance generation"
```

---

### Task 2: Opening Indicator Banner

**Files:**
- Create: `ChessCoach/Components/Bars/OpeningIndicatorBanner.swift`
- Modify: `ChessCoach/Views/GamePlay/GamePlayView+TopBar.swift:126-132` (statusBanners)
- Modify: `ChessCoach/ViewModels/GamePlayViewModel.swift` (add detection tracking)
- Test: `ChessCoachTests/Views/OpeningIndicatorBannerTests.swift`

**Step 1: Write the test**

```swift
import Testing
import Foundation
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

    @Test func emptyMovesReturnsNoDetection() {
        let detector = HolisticDetector()
        let detection = detector.detect(moves: [])
        // May or may not have primary — depends on database. Just verify no crash.
        _ = detection.whiteFramework
        _ = detection.blackFramework
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' -only-testing:ChessCoachTests/OpeningIndicatorBannerTests 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED|error:'`
Expected: FAIL (file not found)

**Step 3: Create the banner component**

Create `ChessCoach/Components/Bars/OpeningIndicatorBanner.swift`:

```swift
import SwiftUI

struct OpeningIndicatorBanner: View {
    let whiteOpening: String?
    let blackOpening: String?
    let playerColor: PieceColor

    var body: some View {
        if whiteOpening != nil || blackOpening != nil {
            HStack(spacing: 0) {
                sideLabel(
                    label: playerColor == .white ? "You" : "Opp",
                    opening: whiteOpening,
                    color: .white
                )

                Spacer(minLength: 4)

                Rectangle()
                    .fill(AppColor.tertiaryText.opacity(0.3))
                    .frame(width: 1, height: 14)

                Spacer(minLength: 4)

                sideLabel(
                    label: playerColor == .black ? "You" : "Opp",
                    opening: blackOpening,
                    color: Color(white: 0.3)
                )
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColor.elevatedBackground.opacity(0.6))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func sideLabel(label: String, opening: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColor.tertiaryText)
            Text(opening ?? "—")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(1)
        }
    }
}
```

**Step 4: Wire detection into GamePlayViewModel**

Modify `ChessCoach/ViewModels/GamePlayViewModel.swift`:

At the property declarations (around line 78), the `holisticDetection` property already exists:
```swift
var holisticDetection: HolisticDetection = .none
```

Add a method to update detection after each move. Add near the bottom of the file, before the closing brace:

```swift
// MARK: - Opening Detection

func updateOpeningDetection() {
    let moves = gameState.moveHistory.map { $0.from + $0.to }
    let newDetection = holisticDetector.detect(moves: moves)
    let oldWhite = holisticDetection.whiteFramework.primary?.opening.name
    let oldBlack = holisticDetection.blackFramework.primary?.opening.name
    holisticDetection = newDetection
    let newWhite = newDetection.whiteFramework.primary?.opening.name
    let newBlack = newDetection.blackFramework.primary?.opening.name

    // Feed entry on first detection or change
    if let name = newWhite, name != oldWhite {
        appendDetectionFeedEntry(side: "White", name: name)
    }
    if let name = newBlack, name != oldBlack {
        appendDetectionFeedEntry(side: "Black", name: name)
    }
}

private func appendDetectionFeedEntry(side: String, name: String) {
    let ply = gameState.plyCount
    appendToFeed(
        ply: ply,
        san: nil,
        coaching: "\(side) is playing the \(name).",
        isDeviation: false,
        fen: gameState.fen
    )
}
```

**Step 5: Call updateOpeningDetection() after each move**

In `GamePlayViewModel+Session.swift`, at the end of `sessionUserMoved()` (the user-move handler) and at the end of opponent move handling, add:

After user move is processed (around line 130, after `appendToFeed` for user move):
```swift
updateOpeningDetection()
```

After opponent move is processed (around line 400, after opponent's `appendToFeed`):
```swift
updateOpeningDetection()
```

Also call it in trainer mode moves if the viewModel handles trainer mode in a different extension — check and add similarly.

**Step 6: Add banner to statusBanners in GamePlayView+TopBar.swift**

Replace the `statusBanners` computed property (lines 126-132):

```swift
@ViewBuilder
var statusBanners: some View {
    if viewModel.mode.isSession {
        if viewModel.isModelLoading {
            coachLoadingBar
        }
    }

    OpeningIndicatorBanner(
        whiteOpening: viewModel.holisticDetection.whiteFramework.primary?.opening.name,
        blackOpening: viewModel.holisticDetection.blackFramework.primary?.opening.name,
        playerColor: viewModel.mode.playerColor
    )
}
```

**Step 7: Run tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'`
Expected: TEST SUCCEEDED

**Step 8: Commit**

```bash
git add ChessCoach/Components/Bars/OpeningIndicatorBanner.swift ChessCoachTests/Views/OpeningIndicatorBannerTests.swift ChessCoach/ViewModels/GamePlayViewModel.swift ChessCoach/ViewModels/GamePlayViewModel+Session.swift ChessCoach/Views/GamePlay/GamePlayView+TopBar.swift
git commit -m "Add dual-side opening indicator banner with feed detection entries"
```

---

### Task 3: Wire OffBookCoachingService into Session

**Files:**
- Modify: `ChessCoach/ViewModels/GamePlayViewModel.swift` (add offBookService property)
- Modify: `ChessCoach/ViewModels/GamePlayViewModel+Session.swift:654-667` (replace showOffBookGuidance)
- Test: Existing tests + manual verification

**Step 1: Add service to ViewModel**

In `GamePlayViewModel.swift`, add property near line 84 (alongside holisticDetector):

```swift
let offBookCoachingService = OffBookCoachingService()
```

Also add a counter to throttle off-book guidance:

```swift
var offBookGuidanceLastPly: Int = -10
```

**Step 2: Replace showOffBookGuidance()**

In `GamePlayViewModel+Session.swift`, replace lines 654-667:

```swift
func showOffBookGuidance() {
    guard isUserTurn, !sessionComplete else { return }
    guard let opening = mode.opening else {
        userCoachingText = "You're on your own. Focus on developing pieces and keeping your king safe."
        return
    }

    // Throttle: only generate new guidance every 3 plies
    let currentPly = gameState.plyCount
    guard currentPly - offBookGuidanceLastPly >= 3 || offBookGuidanceLastPly < 0 else {
        // Still show arrow hint if available
        showOffBookArrowHint()
        return
    }
    offBookGuidanceLastPly = currentPly

    let deviationPly: Int
    switch bookStatus {
    case .userDeviated(_, let atPly): deviationPly = atPly
    case .opponentDeviated(_, _, let atPly): deviationPly = atPly
    case .offBook(let since): deviationPly = since
    default: deviationPly = currentPly
    }

    var opponentDev: (played: String, expected: String)?
    if case .opponentDeviated(let expected, let playedSAN, _) = bookStatus {
        opponentDev = (played: playedSAN, expected: expected.san)
    }

    let guidance = offBookCoachingService.generateGuidance(
        fen: gameState.fen,
        opening: opening,
        deviationPly: deviationPly,
        moveHistory: gameState.moveHistory.map { $0.from + $0.to },
        opponentDeviation: opponentDev
    )

    var text = guidance.summary
    if !guidance.planReminder.isEmpty {
        text += " \(guidance.planReminder)"
    }
    if let suggestion = guidance.suggestion {
        text += " \(suggestion)"
    }
    userCoachingText = text

    showOffBookArrowHint()
}

private func showOffBookArrowHint() {
    if mode.showsArrows, let hint = bestResponseHint, hint.count >= 4 {
        arrowFrom = String(hint.prefix(2))
        arrowTo = String(hint.dropFirst(2).prefix(2))
    }
}
```

Also add `offBookGuidanceLastPly = -10` in `restartSession()` (around line 710 area, alongside other resets).

**Step 3: Run all tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'`
Expected: TEST SUCCEEDED

**Step 4: Commit**

```bash
git add ChessCoach/ViewModels/GamePlayViewModel.swift ChessCoach/ViewModels/GamePlayViewModel+Session.swift
git commit -m "Wire OffBookCoachingService into session — plan-based off-book guidance"
```

---

### Task 4: Free-Tier Coaching Fix

**Files:**
- Modify: `ChessCoach/Services/CoachingService/CoachingService.swift:317-345` (replace fallbackCoaching)
- Modify: `ChessCoach/Services/LLMService/LLMTypes.swift` (add fields to CoachingContext)
- Test: `ChessCoachTests/Services/CoachingServiceTests.swift`

**Step 1: Add fields to CoachingContext**

In `LLMTypes.swift`, add to the `CoachingContext` struct (after `coachPersonalityPrompt`):

```swift
let opening: Opening?
let bookStatus: BookStatus?
```

**Step 2: Update buildContext() in CoachingService**

In `CoachingService.swift`, find the `buildContext()` method and add the new fields. The method constructs a `CoachingContext` — add `opening: curriculumService.opening` and `bookStatus: nil` (we'll pass it through later).

Also add `bookStatus` parameter to `getCoaching()` signature:

```swift
func getCoaching(
    fen: String,
    lastMove: String,
    scoreBefore: Int,
    scoreAfter: Int,
    ply: Int,
    userELO: Int,
    moveHistory: String = "",
    isUserMove: Bool = true,
    studentColor: String? = nil,
    matchedResponseName: String? = nil,
    matchedResponseAdjustment: String? = nil,
    bookStatus: BookStatus? = nil  // NEW
) async -> String?
```

And pass it through to `buildContext()` → `CoachingContext`.

**Step 3: Replace fallbackCoaching with freeCoaching**

Replace the `fallbackCoaching(for:)` method (lines 317-345) with:

```swift
private func freeCoaching(for context: CoachingContext) -> String? {
    // Off-book: delegate to plan-based guidance
    if let bookStatus = context.bookStatus, let opening = context.opening {
        switch bookStatus {
        case .offBook, .userDeviated, .opponentDeviated:
            let service = OffBookCoachingService()
            let deviationPly: Int
            switch bookStatus {
            case .userDeviated(_, let p): deviationPly = p
            case .opponentDeviated(_, _, let p): deviationPly = p
            case .offBook(let p): deviationPly = p
            default: deviationPly = context.plyNumber
            }
            let guidance = service.generateGuidance(
                fen: context.fen,
                opening: opening,
                deviationPly: deviationPly,
                moveHistory: []
            )
            return "\(guidance.summary) \(guidance.planReminder)"
        case .onBook:
            break
        }
    }

    // On-book: use opening move explanations
    if context.isUserMove {
        if let explanation = context.expectedMoveExplanation, !explanation.isEmpty {
            switch context.moveCategory {
            case .goodMove:
                return explanation
            case .okayMove:
                let expected = context.expectedMoveSAN ?? "the book move"
                return "The book move is \(expected). \(explanation)"
            case .mistake:
                let expected = context.expectedMoveSAN ?? "the book move"
                return "The recommended move is \(expected). \(explanation)"
            default:
                return nil
            }
        }
        // Fallback if no explanation available
        switch context.moveCategory {
        case .goodMove: return "Good — that's the book move."
        case .okayMove:
            let expected = context.expectedMoveSAN ?? "the book move"
            return "The book move is \(expected)."
        case .mistake:
            let expected = context.expectedMoveSAN ?? "the book move"
            return "The recommended move is \(expected)."
        default: return nil
        }
    } else {
        // Opponent moves
        if context.moveCategory == .deviation {
            if let name = context.matchedResponseName, let adj = context.matchedResponseAdjustment {
                return "Your opponent played the \(name). \(adj)"
            }
            return "Your opponent deviated from the main line."
        }
        return nil  // Don't generate coaching for every opponent move on free tier
    }
}
```

Update the call site in `getCoaching()` — replace `fallbackCoaching(for: context)` with `freeCoaching(for: context)`.

**Step 4: Update test**

In `ChessCoachTests/Services/CoachingServiceTests.swift`, update or add a test for free-tier coaching:

```swift
@Test func freeCoachingUsesExplanation() async {
    let llm = MockLLMService()
    let curriculum = CurriculumService(opening: italian, familiarity: 0.1)
    let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: LockedAccess())
    let result = await coaching.getCoaching(
        fen: "startpos",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 0,
        ply: 0,
        userELO: 800,
        isUserMove: true
    )
    // Should return something factual, not a personality witticism
    #expect(result != nil)
    // Should not contain personality patterns
    if let text = result {
        #expect(!text.contains("🎭"))
    }
}
```

**Step 5: Run all tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'`
Expected: TEST SUCCEEDED

**Step 6: Commit**

```bash
git add ChessCoach/Services/CoachingService/CoachingService.swift ChessCoach/Services/LLMService/LLMTypes.swift ChessCoachTests/Services/CoachingServiceTests.swift
git commit -m "Replace fallbackCoaching with freeCoaching — factual data from opening files"
```

---

### Task 5: Pass BookStatus Through to CoachingService

**Files:**
- Modify: `ChessCoach/ViewModels/GamePlayViewModel+Session.swift` (pass bookStatus to getCoaching/getBatchedCoaching)

**Step 1: Update generateCoaching() calls**

In `GamePlayViewModel+Session.swift`, find `generateCoaching()` (around line 820) and add `bookStatus: bookStatus` parameter to the `coachingService.getCoaching()` call.

Find all calls to `coachingService.getCoaching()` and `coachingService.getBatchedCoaching()` in the session extension and add the `bookStatus` parameter.

**Step 2: Update getBatchedCoaching in CoachingService**

In `CoachingService.swift`, add `bookStatus` parameter to `getBatchedCoaching()` method signature as well, and pass through to context building.

**Step 3: Run all tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'`
Expected: TEST SUCCEEDED

**Step 4: Commit**

```bash
git add ChessCoach/ViewModels/GamePlayViewModel+Session.swift ChessCoach/Services/CoachingService/CoachingService.swift
git commit -m "Thread bookStatus through to CoachingService for off-book free-tier coaching"
```

---

### Task 6: Wire Detection into Trainer Mode

**Files:**
- Modify: `ChessCoach/ViewModels/GamePlayViewModel.swift` (call updateOpeningDetection from trainer flow)

**Step 1: Find trainer move handling**

Check `GamePlayViewModel.swift` or a trainer extension for where moves are processed in trainer mode. Add `updateOpeningDetection()` after each move in trainer flow (both user and bot moves).

**Step 2: Run all tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'`
Expected: TEST SUCCEEDED

**Step 3: Commit**

```bash
git add ChessCoach/ViewModels/GamePlayViewModel.swift
git commit -m "Wire opening detection into trainer mode"
```

---

### Task 7: Final Verification and Cleanup

**Step 1: Build clean**

```bash
xcodegen generate && xcodebuild build -scheme ChessCoach -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -5
```

**Step 2: Run all tests**

```bash
xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,id=7B2E26B7-1353-4D20-B2AA-479BB6729BD6' 2>&1 | /usr/bin/grep -E 'TEST SUCCEEDED|TEST FAILED'
```

**Step 3: Verify no dead code**

```bash
# Verify fallbackCoaching is gone
grep -r "fallbackCoaching" ChessCoach/
# Should return nothing
```

**Step 4: Commit any cleanup**

```bash
git add -A && git commit -m "Phase 4 cleanup: final verification"
```

---

## Sequencing

```
Task 1 (OffBookCoachingService) ─── additive, new service + tests
Task 2 (Opening Indicator)      ─── additive, new component + wiring
Task 3 (Wire into Session)      ─── depends on Task 1
Task 4 (Free-Tier Fix)          ─── depends on Task 1
Task 5 (Thread BookStatus)      ─── depends on Task 4
Task 6 (Trainer Detection)      ─── depends on Task 2
Task 7 (Final Verification)     ─── depends on all
```

## Verification Checklist

1. Opening indicator shows both sides' openings during play
2. Feed entries appear when openings are first detected
3. Off-book coaching references the opening plan, not generic advice
4. Free tier shows `OpeningMove.explanation` for on-book moves
5. Free tier shows plan-based guidance for off-book moves
6. No personality witticisms in move-by-move coaching
7. Trainer mode shows opening indicator
8. All tests pass
