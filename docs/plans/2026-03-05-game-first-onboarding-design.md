# Phase 6: Game-First Onboarding Design

## Problem

The current onboarding is 8 pages of passive content (story, tech explainer, demo, pricing, privacy, ELO). Users scroll through walls of text before touching a chess piece. The app's core value — showing you what opening you already play and how powerful that is — doesn't land until well after onboarding.

## Goal

Replace the 8-page onboarding with a streamlined flow: **Welcome → ELO → Play a real game → Reveal your opening**. The user plays ~8 moves against Maia, and the app silently detects what opening they played. Then we reveal it: "You played the Italian Game!" with animated coaching tiles showing what the app can teach them.

## Design Decisions

1. **Trim onboarding to 3 functional pages + 1 game + 1 revelation overlay**
2. **Reuse `GamePlayView` entirely** — new `.onboarding` mode, same board, same coaching feed, same overlay pattern
3. **Hide opening detection during play** — the view layer suppresses opening names, deviation banners, and book status. The ViewModel still runs `HolisticDetector`/`OpeningDetector` internally.
4. **Coaching tiles animate in during play** — generic move-quality feedback ("Good move — this controls the center") without opening-specific language
5. **Revelation as completion overlay** — same pattern as `puzzleCompleteOverlay`/`sessionCompleteOverlay` in `GamePlayView+Overlays.swift`
6. **Fallback for weak matches** — if `HolisticDetector` best match depth < 3, present a curated popular opening instead
7. **Transposition-aware matching** — `HolisticDetector` already handles this (matches by position, not move order)

## Architecture

### Flow

```
OnboardingView (trimmed)
├─ Page 1: Welcome + animated coaching tile demo (existing stagger animation)
├─ Page 2: ELO picker (existing ELOAssessmentView or inline stepper)
└─ Page 3: "Let's play!" → presents GamePlayView(.onboarding)

GamePlayView(.onboarding)
├─ Board: user plays White vs Maia at assessed ELO
├─ Coaching feed: generic move feedback (no opening names)
├─ HolisticDetector runs silently after each move
├─ After 8 user moves (or game termination): trigger completion
└─ Overlay: OnboardingRevelationOverlay
   ├─ "You played the Italian Game!"
   ├─ Animated coaching tiles explaining the opening
   ├─ ELO assessment display
   ├─ Buttons: Learn This Opening / Browse Openings / Skip to Home
   └─ Dismiss → Pricing/Privacy page → hasSeenOnboarding = true → Home
```

### New GamePlayMode Case

```swift
case onboarding(playerELO: Int)
```

- `isSession` returns false (no session tracking)
- `isPuzzle` returns false
- `isTrainer` returns false
- New `isOnboarding` computed property
- `playerColor` returns `.white`
- No `opening`, no `lineID`, no `sessionMode`
- `playerELO` drives Maia's strength

### View Layer Hiding

The coaching feed and status banners already branch by mode. For `.onboarding`:

**`GamePlayView+CoachingFeed.swift`** — new `else if viewModel.mode.isOnboarding` branch:
- Renders `CoachingFeedView` without `header:` (no deviation banners, no variation banners)
- Feed entries use generic coaching text (no `openingName`)

**`GamePlayView+Overlays.swift`** — new `onboardingRevelationOverlay` case:
- Triggered when `viewModel.onboardingComplete == true`
- Reads `viewModel.currentOpening.best` or `viewModel.holisticDetection` for the match
- Shows opening name, description, coaching tiles

**`liveStatus` / `sessionActionButtons`** — guarded with `!mode.isOnboarding`

### ViewModel Changes

**`GamePlayViewModel.swift` init** — new onboarding branch:
- No `CurriculumService` (no familiarity-based coaching)
- No `CoachingService` (use simple template coaching)
- No `SpacedRepScheduler` (no mastery tracking)
- Initialize `HolisticDetector` for silent detection
- Set `opponentELO` from `playerELO` parameter

**`GamePlayViewModel+Session.swift`** or new `+Onboarding.swift`:
- `onboardingMoveCount` tracker — counts user moves
- After each user move: run `HolisticDetector.detect(moves:)`, update `holisticDetection`
- Generate generic coaching entry (move quality only, no opening context)
- When `onboardingMoveCount >= 8` or game terminates: set `onboardingComplete = true`
- `bestOnboardingMatch` computed property — returns best opening match or curated fallback

### Coaching During Onboarding

Use Stockfish eval only (no LLM, no CurriculumService):
- Centipawn loss < 30: "Good move — [generic positional comment]"
- Centipawn loss 30-100: "Interesting choice — [brief feedback]"
- Centipawn loss > 100: "There might be a stronger option here"

Template coaching only — no LLM calls during onboarding regardless of subscription tier.

### Revelation Overlay

Reuses the overlay pattern from `GamePlayView+Overlays.swift`:

```swift
private var onboardingRevelationOverlay: some View {
    ZStack {
        Color.black.opacity(0.75).ignoresSafeArea()
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Opening icon + name
                // "You played the [Opening Name]!"
                // ELO assessment: "We've assessed you at ~[ELO]"
                // Animated coaching tiles about the opening
                // "Every game follows an opening pattern..."
                // Action buttons
            }
        }
    }
}
```

Action buttons:
- **"Learn This Opening"** → dismiss GamePlayView, set `pickedFreeOpeningID`, route to Home
- **"Browse Openings"** → dismiss, route to Home with opening browser tab
- **"Skip to Home"** → dismiss, route to Home

### Fallback Logic

```swift
var bestOnboardingMatch: Opening? {
    if let best = holisticDetection.whiteFramework.primary,
       best.matchDepth >= 3 {
        return best.opening
    }
    // Fallback: curated popular opening
    return OpeningDatabase.shared.curatedFallbackOpening()
}
```

Curated fallbacks: Italian Game (e4 e5), Sicilian Defense (e4 c5), Queen's Gambit (d4 d5), English (c4). Pick based on user's first move if possible.

### OnboardingView Changes

**Delete pages:** Story (0), "Missing Piece" (1), "Under the Hood" (2), "How We Teach" (3), Pro details (5)

**Keep/modify:**
- **Page 1 (new):** Welcome — app name, tagline, the existing animated coaching tile stagger showing what feedback looks like. Reuse the coaching demo animation from current page 3.
- **Page 2 (new):** ELO picker — existing stepper or ELOAssessmentView
- **Page 3 (new):** "Let's play!" — transition text, then present GamePlayView

**After GamePlayView dismisses:**
- **Pricing/Privacy page** — combined into one page (Free vs Pro comparison + privacy bullets)
- Then `hasSeenOnboarding = true`

### ContentView Changes

Minimal — the existing routing already handles `hasSeenOnboarding`. The free opening picker flow (`hasPickedFreeOpening`) can be seeded by the revelation overlay's "Learn This Opening" button.

## What We Reuse

| Component | How It's Reused |
|-----------|----------------|
| `GamePlayView` | Whole view, new mode |
| Board + pieces | Unchanged |
| Coaching feed | New branch, no header |
| `HolisticDetector` | Silent detection during play |
| `OpeningDetector` | Called by HolisticDetector |
| Maia engine | Opponent at user's ELO |
| Stockfish | Move evaluation for coaching |
| `SessionSummaryCard` | Stats in revelation overlay |
| Overlay pattern | Same ZStack + dismiss pattern |
| ELO stepper | From current onboarding |
| Stagger animations | From current onboarding page 3 |
| `CoachingFeedView` | Existing component |

## What's New

| Component | Purpose |
|-----------|---------|
| `GamePlayMode.onboarding(playerELO:)` | New mode case |
| `GamePlayViewModel+Onboarding.swift` | Move counting, detection, generic coaching |
| `onboardingRevelationOverlay` | Revelation overlay in GamePlayView+Overlays |
| `OnboardingView` trimmed pages | 3 pages instead of 8 |
| Curated fallback openings | For weak matches |

## Not In Scope

- LLM coaching during onboarding (template only)
- Mastery/spaced-rep tracking during onboarding game
- Saving the onboarding game for review
- Multi-game onboarding (one game is enough)
- Black-side onboarding games (always White for simplicity)
