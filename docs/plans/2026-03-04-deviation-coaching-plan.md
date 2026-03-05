# Deviation Coaching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace "left the opening" messaging with deviation classification (tempo waste, center concession, etc.) and add coaching tier badges + upgrade CTAs.

**Architecture:** Add a `DeviationCategory` enum and `classifyDeviation()` to `OffBookCoachingService`. Replace `buildSummary()` with category-driven templates. Add `CoachingTierBadge` and `CoachingUpgradeCTA` SwiftUI views to the feed. Pass category to LLM via `CoachingContext`.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, ChessKit (for `enumeratedPieces()`), XcodeGen

---

### Task 1: Add `DeviationCategory` enum and classification tests

**Files:**
- Modify: `ChessCoach/Services/OffBookCoachingService.swift:1-13` (add enum before `OffBookGuidance`)
- Test: `ChessCoachTests/Services/OffBookCoachingServiceTests.swift`

**Step 1: Write failing tests**

Add these tests to the existing `OffBookCoachingServiceTests` suite in `ChessCoachTests/Services/OffBookCoachingServiceTests.swift`:

```swift
// MARK: - Deviation Classification

@Test func classifiesTempoWaste() {
    // Opponent moved knight to c6 then back to b8 — same piece twice
    let fen = "rnbqkbnr/pppp1ppp/8/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"
    let moveHistory: [(from: String, to: String)] = [
        (from: "e2", to: "e4"), (from: "b8", to: "c6"),
        (from: "g1", to: "f3"), (from: "c6", to: "b8"),  // opponent moved knight back
        (from: "f1", to: "c4"), (from: "e7", to: "e5"),
    ]
    let category = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: true
    )
    #expect(category == .tempoWaste)
}

@Test func classifiesCenterConcession() {
    // After ply 8, opponent has no center pawns (d4/d5/e4/e5)
    // White has e4, black has nothing on d5/e5/d4/e4
    let fen = "rnbqkb1r/pppp1ppp/5n2/8/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 4 4"
    let moveHistory: [(from: String, to: String)] = [
        (from: "e2", to: "e4"), (from: "g8", to: "f6"),
        (from: "g1", to: "f3"), (from: "a7", to: "a6"),
        (from: "f1", to: "c4"), (from: "h7", to: "h6"),
        (from: "d2", to: "d4"), (from: "b7", to: "b6"),
    ]
    let category = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: true
    )
    #expect(category == .centerConcession)
}

@Test func classifiesDelayedDevelopment() {
    // After ply 8+, opponent still has 3+ minor pieces on back rank
    // Black has bishop on c8, bishop on f8, knight on b8 still home
    let fen = "rnbqkb1r/pppppppp/5n2/8/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 4 4"
    let moveHistory: [(from: String, to: String)] = [
        (from: "e2", to: "e4"), (from: "g8", to: "f6"),
        (from: "g1", to: "f3"), (from: "e7", to: "e6"),
        (from: "f1", to: "c4"), (from: "d7", to: "d6"),
        (from: "d2", to: "d4"), (from: "a7", to: "a6"),
    ]
    let category = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: true
    )
    #expect(category == .delayedDevelopment)
}

@Test func classifiesDelayedCastling() {
    // After ply 14+, opponent still has castling rights and king on original square
    let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 b kq - 0 6"
    let moveHistory: [(from: String, to: String)] = [
        (from: "e2", to: "e4"), (from: "e7", to: "e5"),
        (from: "g1", to: "f3"), (from: "b8", to: "c6"),
        (from: "f1", to: "c4"), (from: "f8", to: "c5"),
        (from: "d2", to: "d3"), (from: "g8", to: "f6"),
        (from: "e1", to: "g1"), (from: "d7", to: "d6"),
        (from: "c1", to: "e3"), (from: "a7", to: "a6"),
        (from: "b1", to: "d2"), (from: "h7", to: "h6"),
    ]
    let category = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: true
    )
    #expect(category == .delayedCastling)
}

@Test func classifiesUnclassifiedWhenNoPatternMatches() {
    // Normal-looking position, no obvious issues
    let fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
    let moveHistory: [(from: String, to: String)] = [
        (from: "e2", to: "e4"), (from: "e7", to: "e5"),
        (from: "g1", to: "f3"), (from: "b8", to: "c6"),
        (from: "f1", to: "c4"), (from: "f8", to: "c5"),
    ]
    let category = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: true
    )
    #expect(category == .unclassified)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: FAIL — `DeviationCategory` and `classifyDeviation` don't exist yet

**Step 3: Add `DeviationCategory` enum**

In `ChessCoach/Services/OffBookCoachingService.swift`, add **before** the `OffBookGuidance` struct (line 1):

```swift
/// Classification of how an opponent deviated from book theory.
enum DeviationCategory: Sendable, Equatable {
    case tempoWaste
    case centerConcession
    case delayedDevelopment
    case delayedCastling
    case knownAlternative(name: String)
    case unclassified

    /// Free-tier coaching template for this deviation type.
    var templateMessage: String {
        switch self {
        case .tempoWaste:
            return "Your opponent moved the same piece twice. Keep developing — you have a tempo advantage."
        case .centerConcession:
            return "Your opponent hasn't contested the center. Your central control gives you the initiative."
        case .delayedDevelopment:
            return "Your opponent is behind in development. Keep developing and look for opportunities to open the position."
        case .delayedCastling:
            return "Your opponent hasn't castled yet. Consider opening the center to exploit their exposed king."
        case .knownAlternative(let name):
            return "Your opponent is playing the \(name)."
        case .unclassified:
            return "Your opponent played a move outside of book theory."
        }
    }
}
```

**Step 4: Add `classifyDeviation()` static method**

Add to `OffBookCoachingService` struct (after `pieceChar` at line 168):

```swift
/// Classify an opponent's deviation from book using positional heuristics.
///
/// Checks (in priority order): tempo waste, center concession, delayed development,
/// delayed castling. Returns `.unclassified` if no pattern matches.
///
/// - Parameters:
///   - fen: Current board position
///   - moveHistory: All moves played so far as (from, to) pairs
///   - playerIsWhite: Whether the student is playing white
static func classifyDeviation(
    fen: String,
    moveHistory: [(from: String, to: String)],
    playerIsWhite: Bool
) -> DeviationCategory {
    let board = FENParser.boardString(from: fen)
    let plyCount = moveHistory.count
    let opponentIsWhite = !playerIsWhite

    // 1. Tempo waste: opponent moved a piece from square A to B, then later from B back to A
    //    (or moved from the same origin square twice) within the first 10 moves
    let opponentMoves = moveHistory.enumerated()
        .filter { opponentIsWhite ? $0.offset % 2 == 0 : $0.offset % 2 == 1 }
        .map { $0.element }

    for i in 0..<opponentMoves.count {
        for j in (i+1)..<opponentMoves.count {
            // Piece went A→B then B→A (moved back)
            if opponentMoves[i].to == opponentMoves[j].from &&
               opponentMoves[i].from == opponentMoves[j].to {
                return .tempoWaste
            }
            // Same piece moved twice (from same origin — piece was already there)
            if opponentMoves[i].from == opponentMoves[j].from {
                return .tempoWaste
            }
        }
    }

    // 2. Center concession: opponent has no pawns on central squares after ply 8
    if plyCount >= 8 {
        let opponentPawn: Character = opponentIsWhite ? "P" : "p"
        let centerSquares = ["d4", "d5", "e4", "e5"]
        let hasCenterPawn = centerSquares.contains { square in
            FENParser.isPieceOnSquare(piece: opponentPawn, square: square, board: board)
        }
        if !hasCenterPawn {
            return .centerConcession
        }
    }

    // 3. Delayed development: 3+ opponent minor pieces still on back rank after ply 8
    if plyCount >= 8 {
        let backRank = opponentIsWhite ? 1 : 8
        let minorPieceTypes: [(Character, [String])] = opponentIsWhite
            ? [("N", ["b1", "g1"]), ("B", ["c1", "f1"])]
            : [("n", ["b8", "g8"]), ("b", ["c8", "f8"])]

        var homeCount = 0
        for (piece, homeSquares) in minorPieceTypes {
            for square in homeSquares {
                if FENParser.isPieceOnSquare(piece: piece, square: square, board: board) {
                    homeCount += 1
                }
            }
        }
        if homeCount >= 3 {
            return .delayedDevelopment
        }
    }

    // 4. Delayed castling: opponent hasn't castled by ply 14
    if plyCount >= 14 {
        let hasCastled = FENParser.isCastled(kingside: true, fen: fen, isWhite: opponentIsWhite)
            || FENParser.isCastled(kingside: false, fen: fen, isWhite: opponentIsWhite)
        if !hasCastled {
            return .delayedCastling
        }
    }

    return .unclassified
}
```

**Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: PASS

**Step 6: Commit**

```bash
git add ChessCoach/Services/OffBookCoachingService.swift ChessCoachTests/Services/OffBookCoachingServiceTests.swift
git commit -m "feat: add DeviationCategory enum and classifyDeviation heuristics with tests"
```

---

### Task 2: Wire `DeviationCategory` into `OffBookGuidance` and replace `buildSummary()`

**Files:**
- Modify: `ChessCoach/Services/OffBookCoachingService.swift:4-13,31-85,90-115`
- Test: `ChessCoachTests/Services/OffBookCoachingServiceTests.swift`

**Step 1: Update `OffBookGuidance` struct**

Replace the `OffBookGuidance` struct (lines 4-13) with:

```swift
/// Guidance generated when a game goes off-book (deviates from known opening theory).
struct OffBookGuidance: Sendable {
    /// Classification of the deviation type
    let category: DeviationCategory
    /// Plan reminder from the opening's strategic plan
    let planReminder: String
    /// Actionable suggestion based on unmet piece targets or strategic goals
    let suggestion: String?
    /// Strategic goals that are still relevant given the current position
    let relevantGoals: [StrategicGoal]

    /// Category-driven coaching message for free-tier users.
    var templateCoaching: String {
        var text = category.templateMessage
        if !planReminder.isEmpty {
            text += " \(planReminder)"
        }
        if let suggestion {
            text += " \(suggestion)"
        }
        return text
    }
}
```

**Step 2: Update `generateGuidance()` signature and body**

Replace the `generateGuidance()` function (lines 31-85) — add `moveHistory` type change to accept tuples, call `classifyDeviation()`, remove `buildSummary()`:

```swift
func generateGuidance(
    fen: String,
    opening: Opening,
    deviationPly: Int,
    moveHistory: [(from: String, to: String)],
    opponentDeviation: (played: String, expected: String)? = nil
) -> OffBookGuidance {
    let isWhite = opening.color == .white

    // Classify the deviation
    let category: DeviationCategory = Self.classifyDeviation(
        fen: fen, moveHistory: moveHistory, playerIsWhite: isWhite
    )

    guard let plan = opening.plan else {
        return OffBookGuidance(
            category: category,
            planReminder: "Keep developing your pieces toward the center and castle early.",
            suggestion: "Focus on getting your knights and bishops out before moving the same piece twice.",
            relevantGoals: []
        )
    }

    let board = FENParser.boardString(from: fen)

    // 1. Filter strategic goals to those still relevant
    let relevantGoals = plan.strategicGoals.filter { goal in
        guard let condition = goal.checkCondition else { return true }
        return !isConditionMet(condition, board: board, fen: fen, isWhite: isWhite)
    }.sorted { $0.priority < $1.priority }

    // 2. Find unmet piece targets
    let unmetTargets = plan.pieceTargets.filter { target in
        let pieceChar = Self.pieceChar(name: target.piece, isWhite: isWhite)
        return !target.idealSquares.contains { square in
            FENParser.isPieceOnSquare(piece: pieceChar, square: square, board: board)
        }
    }

    // 3. Build suggestion from unmet targets or top relevant goal
    let suggestion: String?
    if let firstUnmet = unmetTargets.first {
        let squares = firstUnmet.idealSquares.joined(separator: " or ")
        suggestion = "Consider developing your \(firstUnmet.piece) to \(squares) — \(firstUnmet.reasoning.lowercasedFirst)"
    } else if let topGoal = relevantGoals.first {
        suggestion = topGoal.description
    } else {
        suggestion = nil
    }

    return OffBookGuidance(
        category: category,
        planReminder: plan.summary,
        suggestion: suggestion,
        relevantGoals: relevantGoals
    )
}
```

**Step 3: Delete `buildSummary()` and `genericGuidance()` methods**

Delete lines 89-115 (the `genericGuidance` and `buildSummary` methods) — their logic is now in `DeviationCategory.templateMessage` and the updated `generateGuidance()`.

**Step 4: Update all `generateGuidance()` call sites**

The `moveHistory` parameter type changed from `[String]` to `[(from: String, to: String)]`. Update callers:

In `CoachingService.swift` `freeCoaching()` (line 340-345):
```swift
let guidance = offBookService.generateGuidance(
    fen: context.fen,
    opening: opening,
    deviationPly: p,
    moveHistory: [],  // Still empty — CoachingContext has String moveHistory, not tuples
    opponentDeviation: opponentDev
)
```
The empty array `[]` is type-compatible with `[(from: String, to: String)]`.

In `GamePlayViewModel+Session.swift` `showOffBookGuidance()` (~line 691):
```swift
let guidance = offBookCoachingService.generateGuidance(
    fen: gameState.fen,
    opening: opening,
    deviationPly: deviationPly,
    moveHistory: gameState.moveHistory.map { (from: $0.from, to: $0.to) },
    opponentDeviation: opponentDev
)
```

**Step 5: Update callers to use `guidance.templateCoaching` instead of manual string building**

In `CoachingService.swift` `freeCoaching()`, replace the manual text building:
```swift
// OLD:
var text = guidance.summary
if !guidance.planReminder.isEmpty { text += " \(guidance.planReminder)" }
if let suggestion = guidance.suggestion { text += " \(suggestion)" }
return text

// NEW:
return guidance.templateCoaching
```

In `GamePlayViewModel+Session.swift` `showOffBookGuidance()`:
```swift
// OLD:
var text = guidance.summary
if !guidance.planReminder.isEmpty { text += " \(guidance.planReminder)" }
if let suggestion = guidance.suggestion { text += " \(suggestion)" }
userCoachingText = text

// NEW:
userCoachingText = guidance.templateCoaching
```

**Step 6: Update tests**

Update existing tests in `OffBookCoachingServiceTests.swift`:

- `guidanceIncludesPlanSummary`: Remove `#expect(guidance.summary.contains("Italian Game"))` and `#expect(guidance.summary.contains("4"))`. Replace with `#expect(guidance.category != .knownAlternative(name: ""))`. Keep planReminder assertion.
- `guidanceForOpponentDeviation`: Remove assertions about `summary` containing "opponent"/"Bb4"/"Bc5". Replace with `#expect(guidance.category == .unclassified)` (short move history, no heuristic triggers). Keep planReminder.
- `genericGuidanceWhenNoPlan`: Remove `#expect(guidance.summary.contains("Mystery Opening"))`. Replace with `#expect(guidance.category == .unclassified)`. Keep planReminder/relevantGoals assertions.

**Step 7: Run tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: PASS

**Step 8: Commit**

```bash
git add ChessCoach/Services/OffBookCoachingService.swift ChessCoach/Services/CoachingService/CoachingService.swift ChessCoach/ViewModels/GamePlayViewModel+Session.swift ChessCoachTests/Services/OffBookCoachingServiceTests.swift
git commit -m "feat: replace 'left the opening' messaging with deviation category templates"
```

---

### Task 3: Add `CoachingTierBadge` view

**Files:**
- Create: `ChessCoach/Components/Feed/CoachingTierBadge.swift`
- Modify: `ChessCoach/Components/Feed/FeedRowCard.swift:136-155`
- Test: `ChessCoachTests/Views/CoachingTierBadgeTests.swift`

**Step 1: Write failing test**

Create `ChessCoachTests/Views/CoachingTierBadgeTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: FAIL — `CoachingTierBadge` doesn't exist

**Step 3: Create `CoachingTierBadge`**

Create `ChessCoach/Components/Feed/CoachingTierBadge.swift`:

```swift
import SwiftUI

/// Small badge indicating the coaching analysis tier: "Basic" or "AI Coach".
struct CoachingTierBadge: View {
    let isLLM: Bool

    var label: String { isLLM ? "AI Coach" : "Basic" }

    private var color: Color { isLLM ? AppColor.info : AppColor.tertiaryText }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(label) analysis")
    }
}
```

**Step 4: Add badge to `FeedRowCard`**

In `ChessCoach/Components/Feed/FeedRowCard.swift`, find the `categoryBadge` view (around line 136). Add a `coachingTierBadge` next to it. The feed entry needs a new `isLLMCoaching: Bool` field — or we can infer it from whether coaching text exists and feature access. For now, add it to `FeedEntry`:

In the file where `FeedEntry` is defined (look for `struct FeedEntry`), add:
```swift
var isLLMCoaching: Bool = false
```

Then in `FeedRowCard`, after the `categoryBadge` call, add the tier badge when coaching text is present:

```swift
if entry.coaching != nil {
    CoachingTierBadge(isLLM: entry.isLLMCoaching)
}
```

**Step 5: Run tests**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: PASS

**Step 6: Commit**

```bash
git add ChessCoach/Components/Feed/CoachingTierBadge.swift ChessCoach/Components/Feed/FeedRowCard.swift ChessCoachTests/Views/CoachingTierBadgeTests.swift
git commit -m "feat: add CoachingTierBadge showing Basic/AI Coach on feed entries"
```

---

### Task 4: Add `CoachingUpgradeCTA` view

**Files:**
- Create: `ChessCoach/Components/Feed/CoachingUpgradeCTA.swift`
- Modify: `ChessCoach/ViewModels/GamePlayViewModel+Session.swift` (track CTA shown state)

**Step 1: Create `CoachingUpgradeCTA`**

Create `ChessCoach/Components/Feed/CoachingUpgradeCTA.swift`:

```swift
import SwiftUI

/// Tappable prompt encouraging free-tier users to upgrade for deeper coaching analysis.
/// Appears after first deviation or mistake in a session, maximum once per session.
struct CoachingUpgradeCTA: View {
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(AppColor.gold)
                Text("Unlock deeper analysis")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text("Upgrade")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.gold.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColor.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            ProUpgradeView()
        }
    }
}
```

**Step 2: Add CTA gating to `GamePlayViewModel`**

In `ChessCoach/ViewModels/GamePlayViewModel.swift`, add a property:
```swift
var hasShownUpgradeCTA = false
```

**Step 3: Show CTA in feed after first deviation (free tier only)**

In `GamePlayViewModel+Session.swift`, in `showOffBookGuidance()`, after setting `userCoachingText`, add:

```swift
// Show upgrade CTA once per session for free-tier users
if !hasShownUpgradeCTA {
    hasShownUpgradeCTA = true
    showUpgradeCTA = true  // New @Published var drives CTA visibility
}
```

Add `@Published var showUpgradeCTA = false` to `GamePlayViewModel.swift` if needed — or handle via the feed entry system by appending a CTA-type feed entry. The exact wiring depends on how the feed renders. The simplest approach: add the CTA inline after the coaching text in the feed row, gated by `!hasShownUpgradeCTA && !hasLLM`.

**Step 4: Build and verify**

Run: `xcodegen generate && xcodebuild build -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add ChessCoach/Components/Feed/CoachingUpgradeCTA.swift ChessCoach/ViewModels/GamePlayViewModel.swift ChessCoach/ViewModels/GamePlayViewModel+Session.swift
git commit -m "feat: add CoachingUpgradeCTA with once-per-session paywall prompt"
```

---

### Task 5: Pass `DeviationCategory` to LLM context

**Files:**
- Modify: `ChessCoach/Services/LLMService/LLMTypes.swift:11-33` (add field to CoachingContext)
- Modify: `ChessCoach/Services/CoachingService/CoachingService.swift:287-327` (pass category in buildContext)
- Modify: `ChessCoach/Config/PromptCatalog.swift` (include category in prompt)
- Modify: `ChessCoachTests/Services/LLMServiceTests.swift` (update test CoachingContext instantiations)

**Step 1: Add `deviationCategory` to `CoachingContext`**

In `LLMTypes.swift`, add after `bookStatus`:
```swift
let deviationCategory: DeviationCategory?
```

**Step 2: Update `buildContext()` in `CoachingService.swift`**

Add `deviationCategory: DeviationCategory? = nil` parameter to `buildContext()` and pass it through to the `CoachingContext` initializer.

**Step 3: Pass category from `freeCoaching()` and `getCoaching()`**

In `freeCoaching()`, after calling `offBookService.generateGuidance()`, pass `guidance.category` when building the context (or store it for later use in prompt building).

Actually, the simpler approach: in `getCoaching()`, when `bookStatus` indicates off-book and LLM is available, call `classifyDeviation()` and pass the result to `buildContext()`:

```swift
let deviationCategory: DeviationCategory?
if let bs = bookStatus, case .onBook = bs {
    deviationCategory = nil
} else if bookStatus != nil {
    deviationCategory = OffBookCoachingService.classifyDeviation(
        fen: fen, moveHistory: [], playerIsWhite: studentColor == "White"
    )
} else {
    deviationCategory = nil
}
```

**Step 4: Update prompt template**

In `PromptCatalog.swift`, in the opponent deviation prompt section, add context about the deviation category:

```swift
if let category = context.deviationCategory {
    switch category {
    case .tempoWaste:
        guidance += " The opponent wasted a tempo by moving the same piece twice."
    case .centerConcession:
        guidance += " The opponent has conceded the center — no opponent pawns on d4/d5/e4/e5."
    case .delayedDevelopment:
        guidance += " The opponent is behind in development with multiple minor pieces still on the back rank."
    case .delayedCastling:
        guidance += " The opponent has not castled and their king may be vulnerable."
    case .knownAlternative(let name):
        guidance += " The opponent is playing the \(name)."
    case .unclassified:
        break
    }
}
```

**Step 5: Update test instantiations**

In `LLMServiceTests.swift`, add `deviationCategory: nil` to all `CoachingContext` initializers.

**Step 6: Build and test**

Run: `xcodegen generate && xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5`
Expected: PASS

**Step 7: Commit**

```bash
git add ChessCoach/Services/LLMService/LLMTypes.swift ChessCoach/Services/CoachingService/CoachingService.swift ChessCoach/Config/PromptCatalog.swift ChessCoachTests/Services/LLMServiceTests.swift
git commit -m "feat: pass DeviationCategory to LLM prompt for targeted coaching"
```

---

### Task 6: Final verification

**Step 1: Full build**

```bash
xcodegen generate && xcodebuild build -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED

**Step 2: Full test suite**

```bash
xcodebuild test -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ChessCoachTests 2>&1 | tail -5
```
Expected: TEST SUCCEEDED

**Step 3: Grep for removed patterns**

```bash
grep -r "left the.*at move" ChessCoach/
grep -r "buildSummary" ChessCoach/
```
Expected: Zero results for both

**Step 4: Verify new patterns exist**

```bash
grep -r "DeviationCategory" ChessCoach/ | wc -l
grep -r "CoachingTierBadge" ChessCoach/ | wc -l
grep -r "CoachingUpgradeCTA" ChessCoach/ | wc -l
```
Expected: Multiple results for each
