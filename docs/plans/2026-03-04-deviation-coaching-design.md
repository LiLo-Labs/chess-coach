# Deviation Coaching Redesign

## Problem

The current off-book coaching tells users "You/Your opponent left the Italian Game at move 5." This framing is wrong:

1. It treats any deviation from the memorized sequence as "leaving" the opening
2. It doesn't distinguish between a known alternative (Two Knights Defense) and a blunder (3...h6)
3. It doesn't help the user understand *why* the opponent's move is weak or how to exploit it
4. It frames deviations as problems when they're often opportunities

The purpose of learning openings isn't memorizing exact sequences — it's understanding the *plan*. When an opponent plays something suboptimal, the plan usually gets easier, not harder. Coaching should communicate this.

## Design

### Deviation Classification

When the opponent deviates, classify their move using FEN-based heuristics:

| Category | Detection | Free-tier template |
|----------|-----------|-------------------|
| **Tempo waste** | Same piece moved twice in first 10 moves (track from/to in moveHistory) | "Your opponent moved the same piece twice. Keep developing — you have a tempo advantage." |
| **Center concession** | Opponent has no pawns on d4/d5/e4/e5 by ply 8+ | "Your opponent hasn't contested the center. Your central control gives you the initiative." |
| **Delayed development** | 3+ opponent minor pieces still on back rank after ply 8+ | "Your opponent is behind in development. Keep developing and look for opportunities to open the position." |
| **Delayed castling** | Opponent hasn't castled by ply 14+ (castling rights present + king on original square) | "Your opponent hasn't castled yet. Consider opening the center to exploit their exposed king." |
| **Known alternative** | Holistic detector identifies a different named opening for opponent's side | No coaching — the OpeningIndicatorBanner already shows what they're playing |
| **Unclassified** | None of the above | Plan reminder + unmet piece targets (existing behavior) |

These are intentionally simple heuristics targeting common beginner mistakes (600-1200 ELO). They catch the most frequent "stupid" moves without requiring Stockfish.

### Coaching Tiers

| Tier | Coaching quality | Badge |
|------|-----------------|-------|
| **Free** | Deviation category template + plan reminder + unmet piece targets | "Basic" |
| **Pro (LLM)** | Full contextual coaching — why the move is weak, how to exploit it, tailored to ELO | "AI Coach" |

The current `FeatureAccess.isUnlocked(.llmCoaching)` gates the tier. This will be rewired when the 4-tier entitlement model is built (Free / A la carte / Enthusiast / Power User).

### Coaching UI Additions

**CoachingTierBadge** — small label on every coaching feed entry. "Basic" for free tier, "AI Coach" for LLM tier. Uses `AppColor.secondaryText` styling, doesn't dominate the UI.

**CoachingUpgradeCTA** — tappable prompt shown below coaching text: "Unlock deeper analysis". Appears:
- After the first deviation in a session
- After mistakes
- Maximum once per session to avoid annoyance

Links to existing paywall sheet.

### LLM Context Enhancement

For pro users, pass the `DeviationCategory` into `CoachingContext` so the LLM prompt can give targeted advice. Instead of "opponent deviated from the main line," the prompt says "opponent wasted a tempo by moving the same piece twice" — letting the LLM explain how to exploit it specifically.

### Architecture

**`DeviationCategory` enum** — Sendable, lives in OffBookCoachingService.swift. Each case has a `templateMessage` computed property for free-tier coaching.

**`OffBookCoachingService.classifyDeviation()`** — Pure function. Takes FEN, move history, player color. Returns `DeviationCategory`. Uses ChessKit `enumeratedPieces()` for piece positions, move history for tempo tracking.

**`OffBookGuidance.category`** — New field. `generateGuidance()` calls `classifyDeviation()` and includes the result.

**`CoachingContext.deviationCategory`** — New optional field. Prompt template uses it for LLM framing.

**`CoachingTierBadge`** — SwiftUI view, shown on feed entries.

**`CoachingUpgradeCTA`** — SwiftUI view, tappable, links to paywall. Gated by session state.

### What Gets Removed

- `buildSummary()` and all "left the opening" / "You left the X at move Y" messaging
- The `summary` field in `OffBookGuidance` is replaced by category-driven messaging
