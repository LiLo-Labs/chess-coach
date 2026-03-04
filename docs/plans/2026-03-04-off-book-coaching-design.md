# Phase 4: Off-Book Coaching + Opening Indicator — Design

## Overview

Three sub-features that make coaching useful beyond the opening book:

1. **Opening Indicator** — persistent dual-side banner showing detected openings
2. **OffBookCoachingService** — plan-based coaching when the game leaves book
3. **Free-Tier Coaching Fix** — replace personality witticisms with factual opening data

## 1. Opening Indicator

### Component: `OpeningIndicatorBanner`

Persistent view below the top bar in GamePlayView. Shows both sides' detected openings.

**Layout**: `"You: Italian Game"` left-aligned, `"Opp: Two Knights"` right-aligned. Hidden until first detection, animates in.

**Data flow**:
- `GamePlayViewModel` holds `@Published var detection: HolisticDetection?`
- After every move, call `holisticDetector.detect(moves:)` to update
- HolisticDetector is cheap (tree lookup) — safe to call every move

**Feed integration**:
- New coaching entry type for opening detection events
- Fired when: (a) first detection for either side, (b) primary detection changes
- Example: "Your opponent switched to the Philidor Defense"

## 2. OffBookCoachingService

### Purpose

When the game leaves book, generate coaching that references the opening's plan instead of generic "focus on development" text.

### Interface

```swift
struct OffBookCoachingService: Sendable {
    func generateGuidance(
        fen: String,
        opening: Opening,
        bookStatus: BookStatus,
        moveHistory: [String]
    ) -> OffBookGuidance
}

struct OffBookGuidance: Sendable {
    let summary: String          // "You left the Italian Game at move 7"
    let planReminder: String     // "The plan is to target f7 with your bishop"
    let suggestion: String?      // "Consider developing your bishop to c4"
    let relevantGoals: [StrategicGoal]
}
```

### How It Works (Free Tier)

1. Check which `StrategicGoal`s are still achievable by parsing `checkCondition` against current FEN
2. Identify unachieved `PieceTarget`s (piece not on ideal squares)
3. Build template: "You left the book at move {ply}. The plan was: {summary}. From here, focus on: {unmet goal}. Consider developing your {piece} toward {squares}."
4. For opponent deviations: "Your opponent deviated with {san}. The plan still works: {adapted advice}."

### Goal Relevance Checking

Simple FEN parsing for `checkCondition` strings like `"bishop_on_diagonal_a2g8"`, `"pawn_on_e4"`, `"castled_kingside"`. If nil or unparseable, assume relevant.

### Paid Tier Enhancement

Pass plan context + current FEN to CoachingService's existing LLM flow. The prompt already accepts plan data — add off-book context flag.

### When Called

- On transition to off-book: immediate guidance
- Subsequent off-book moves: re-generate every ~3 moves to avoid spam
- Results go into coaching feed as special entries

## 3. Free-Tier Coaching Fix

### Problem

`fallbackCoaching()` returns personality witticisms + "The book move is X" which is often wrong or unhelpful.

### Solution

Replace `fallbackCoaching()` → `freeCoaching()` with factual data:

**On-book**: Use `OpeningMove.explanation` directly — every move has a 1-2 sentence explanation.

**Off-book**: Delegate to `OffBookCoachingService.generateGuidance()`.

**Opponent moves**: Show opponent move's explanation if in tree, otherwise "Your opponent played {san}. Stay focused on {next plan goal}."

**Personality**: Keep for session completion celebrations only. Remove from move-by-move coaching.

### CoachingService Changes

- Rename `fallbackCoaching()` → `freeCoaching()`
- Add `Opening` object to `CoachingContext` (currently only has `openingName`)
- `freeCoaching()` reads from `OpeningMove.explanation` (on-book) or `OffBookCoachingService` (off-book)

## Architecture Decisions

- **Standalone OffBookCoachingService** (not inline in CoachingService) for clean separation and testability
- **HolisticDetector called every move** — cheap tree lookup, acceptable cost
- **Template-only free tier** — no Stockfish dependency for free off-book coaching
- **Opening indicator: banner + feed entries** — persistent banner for current state, feed entries for changes
