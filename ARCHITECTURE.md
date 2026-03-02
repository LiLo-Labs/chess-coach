# ChessCoach Architecture

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Platform | iOS 17.0+, Swift 6.0, Strict Concurrency |
| UI | SwiftUI, @Observable pattern |
| Chess Logic | ChessKit (local package) |
| Board Rendering | ChessboardKit (local package) |
| Engine | Stockfish (via ChessKitEngine, llama.xcframework) |
| Neural Net | Maia 2 Blitz (CoreML), Qwen3-4B (on-device GGUF) |
| Persistence | GRDB |
| IAP | StoreKit 2 |
| LLM Providers | On-device Qwen3-4B, Claude API, Ollama |

## Directory Structure

```
ChessCoach/
├── App/                          # Entry point, root environment, design system
│   ├── ChessCoachApp.swift       # @main, WindowGroup
│   ├── ContentView.swift         # Root navigation, LLM warmup, onboarding gate
│   ├── AppServices.swift         # Singleton holder for Stockfish + LLM
│   └── DesignSystem.swift        # AppColor, AppSpacing, AppRadius constants
│
├── Config/
│   ├── AppConfig.swift           # All tuning params: engine depths, token limits, LLM sampling
│   └── PromptCatalog.swift       # All LLM prompt templates (coaching, alignment, explanation)
│
├── Engine/
│   ├── StockfishService.swift    # Actor: position evaluation, best move, hints
│   ├── OnDeviceLLMService.swift  # Actor: llama.cpp inference (Qwen3-4B)
│   ├── MaiaService.swift         # CoreML: human-like move prediction
│   └── Protocols/EngineProtocols.swift  # TextGenerating
│
├── Models/
│   ├── Chess/GameState.swift     # @Observable game state, move history, FEN
│   ├── Opening/                  # Opening, OpeningDatabase, OpeningPlan, LessonStep, etc.
│   ├── Progress/                 # UserProgress, SessionResult, LineProgress, LearningPhase
│   ├── Scoring/                  # PlanExecutionScore, PopularityService, SoundnessCalculator
│   ├── SpacedRep/                # ReviewItem, SpacedRepScheduler
│   ├── Tokens/                  # TokenBalance, TokenTransaction, TokenError
│   ├── Puzzle/                  # Puzzle model (FEN, solution, theme, difficulty)
│   ├── Trainer/                 # TrainerGameResult, TrainerStats
│   ├── BoardTheme.swift          # Board color theme enum (8 themes)
│   └── OpponentPersonality.swift # Bot personality traits
│
├── Services/
│   ├── AppSettings.swift         # @Observable, UserDefaults-backed settings
│   ├── PersistenceService.swift  # GRDB: progress, sessions, review items
│   ├── SoundService.swift        # Move sounds, haptics
│   ├── FeedbackService.swift     # Bug reports via Cloudflare Worker → GitHub Issues
│   ├── PlanScoringService.swift  # PES computation (soundness + alignment + popularity)
│   ├── VariedOpponentService.swift # ELO-scaled opponent move selection
│   ├── CoachingService/          # LLM coaching: per-move, batched, chat, alignment
│   ├── CurriculumService/        # Learning phase progression logic
│   ├── LLMService/               # Provider abstraction (on-device, Claude, Ollama)
│   ├── TokenService.swift        # Token economy: balance, StoreKit consumable packs, rewards
│   ├── PuzzleService.swift       # Puzzle generation from openings, mistakes, Stockfish
│   ├── ModelDownloadService.swift # Background download of GGUF model to Documents
│   └── Subscription/             # SubscriptionService, FeatureAccess, ProFeature, tiers
│
├── Views/
│   ├── Board/                    # GameBoardView, arrow overlays, square highlights
│   ├── Components/               # HelpButton, FeedbackButton, BoardLessonCard, QuizLessonCard
│   ├── Effects/                  # ConfettiView
│   ├── Home/                     # HomeView, OpeningDetailView, PuzzleModeView, TrainerModeView
│   ├── Onboarding/               # OnboardingView (6-page), FreeOpeningPickerView
│   ├── Paywall/                  # ProUpgradeView (multi-tier + per-path + token unlock), TokenStoreView
│   ├── Review/                   # QuickReviewView (spaced repetition)
│   ├── Session/                  # SessionView, SessionViewModel, CoachChatPanel, LineStudy, etc.
│   └── Settings/                 # SettingsView, DebugStateView
│
└── Resources/
    ├── Openings/                 # 27 opening tree JSON files
    ├── OpeningData/              # ECO classification TSVs (a-e)
    ├── Qwen3-4B-Q4_K_M.gguf     # On-device LLM model (3.2GB)
    ├── Maia2Blitz.mlpackage      # CoreML move prediction
    └── *.nnue                    # Stockfish neural network weights
```

## Data Flow

```
AppSettings (UserDefaults) ──┐
SubscriptionService (StoreKit) ──┤── injected via .environment() at WindowGroup
TokenService (token economy) ──┤
ModelDownloadService ──┤
AppServices (Stockfish + LLM) ──┘

ContentView
  └── HomeView
        └── OpeningDetailView
              └── SessionView ← SessionViewModel (owns GameState, CoachingService, etc.)
                    ├── GameBoardView (reads AppSettings.boardTheme from environment)
                    ├── Feed (coaching entries, move-by-move)
                    └── CoachChatPanel (sliding side panel)
```

## Key Protocols

| Protocol | Purpose | Conformers |
|----------|---------|-----------|
| `TextGenerating` | LLM text generation | `OnDeviceLLMService`, `ClaudeProvider`, `OllamaProvider` |
| `FeatureAccessProviding` | Subscription gating | `SubscriptionService`, `StaticFeatureAccess`, `UnlockedAccess` |
| `ChessboardColorScheme` | Board colors | `ChessComColorScheme`, 8 built-in schemes |

## Subscription Tiers

| Tier | AI | Openings | Status |
|------|-----|----------|--------|
| Free | None | Limited | Enum defined, gating partial |
| On-Device AI | Qwen3-4B | All | Enum defined |
| Cloud AI | Claude/Ollama | All | Enum defined |
| Pro | All providers | All | Enum defined |
| Per-Path | None | Individual | Enum defined |

Debug: `DebugStateView` has presets for each tier. `AppSettings.debugTierOverride` overrides.

## Learning Phases (per opening path)

1. **Learning Main Line** → guided walkthrough with coaching
2. **Practicing Recall** → play from memory, hints available
3. **Handling Variations** → opponent deviates, student responds
4. **Review** → spaced repetition of learned lines

## Board Theme System

11 themes available: 8 free (Chess.com default, Classic, Dark, Blue, Green, Purple, Orange, Red) + 3 pro (Walnut, Marble, Tournament).
Pro themes gated by `isPro` flag, shown with lock icon in Settings for free users.
Selected via `AppSettings.boardTheme`. Applied to `GameBoardView` via environment.
Piece styles: 5 styles using free Lichess assets (GPLv2+). Free: Classic (USCF), Lichess (cburnett). Pro: Merida, Staunty, California. Selected via `AppSettings.pieceStyle`, applied to `ChessboardModel.pieceStyleFolder`.

## Onboarding Flow

1. Welcome — animated crown, minimal tagline
2. What Are Openings — 3 animated bullet points (plan, why, obvious)
3. How It Works — 4-step animated number circles
4. Your Privacy — 4 animated privacy rows (no selling, no tracking, on-device, yours)
5. Skill Level — large ELO picker with +/- buttons
7. **Free Opening Picker** (free tier only) — choose ONE opening to fully unlock

`OnboardingView.onComplete` callback → ContentView decides whether to show picker or go straight to HomeView.

## Concept Intro System

`ConceptIntroView` + `.conceptIntro()` modifier shows one-time full-screen cards.
Tracked via UserDefaults keys per `ConceptIntro` enum case.
Applied on: OpeningDetailView (.whatAreOpenings), PracticeOpeningView (.whatIsPractice), QuickReviewView (.whatIsReview).

## Help System

`HelpButton` with `HelpTopic` enum (15 topics). Contextual popovers throughout:
- HomeView: streak
- OnboardingView: skillLevel
- OpeningDetailView: difficulty, learningJourney, paths
- SessionCompleteView: planScore, moveSafety, followingPlan
- PracticeOpeningView: practiceMode
- QuickReviewView: review (toolbar)

## Free Tier Gating

- 3 free openings: Italian, London, Sicilian (configured in AppConfig)
- **Free opening pick**: Post-onboarding, free users choose ONE additional opening to unlock fully
  - Stored in `AppSettings.pickedFreeOpeningID`
  - `FreeOpeningPickerView` shown between onboarding and HomeView for free tier
- HomeView shows lock icons on non-free openings, tapping opens paywall with per-path option
- `SubscriptionService.isOpeningAccessible()` checks: tier + free IDs + picked free + per-path unlocks
- AI features gated by `hasAI` (tier != .free)

## Per-Path Unlock (à la carte)

- `SubscriptionService.purchasePath(openingID:)` — StoreKit non-consumable IAP
- Product IDs follow convention: `com.chesscoach.opening.<openingID>`
- ProUpgradeView shows "Just this opening" card when launched for a specific locked opening
- Users can choose per-path purchase, token unlock, OR tier upgrade from the same paywall

## Token Economy

- `TokenService` (@Observable, @MainActor) — manages balance, purchases, rewards, daily bonus
- `TokenBalance` — balance, totalEarned, totalSpent with credit/debit operations
- `TokenTransaction` — audit trail with reason enum (purchase, dailyBonus, unlockOpening, reward)
- **Earning tokens**: daily login bonus (5/day), layer completion rewards (25 tokens), StoreKit consumable packs
- **Spending tokens**: unlock individual openings (100 tokens each)
- **Token packs**: Small (50), Medium (150), Large (400) — StoreKit consumable IAP
- `TokenStoreView` — purchase packs, claim daily bonus, view balance and transaction history
- Config: `AppConfig.tokenEconomy` (costs, rewards, pack definitions — all tunable)
- Persistence: UserDefaults (balance + last 100 transactions)
- HomeView stats section shows token balance with tap-to-open store
- ProUpgradeView per-path card includes "Use Tokens" button alongside IAP purchase

## Puzzle Mode

- `PuzzleService` generates puzzles from 3 sources:
  1. **Opening Knowledge** — positions from opening book, user finds the book move
  2. **Mistake Review** — positions where user historically makes errors (from MistakeTracker)
  3. **Find the Best Move** — Stockfish-evaluated positions with clear best move (>30cp advantage)
- `Puzzle` model: FEN, solutionUCI/SAN, theme, difficulty (1-5), optional explanation
- `PuzzleModeView`: interactive board, progress bar, streak tracking, hints, feedback, session results
- Free: 5 puzzles/day. Pro: unlimited (gated via `ProFeature.unlimitedPuzzles`)

## Trainer Mode

- Full games against bots with Maia (human-like play) + Stockfish fallback
- 6 bot difficulties: 500-1600 ELO, each with `OpponentPersonality` name/description
- Player chooses color and opponent, plays until checkmate/stalemate/resign
- `TrainerGameResult` persisted (date, outcome, bot ELO, move count)
- `TrainerStats` — wins/losses/draws/win rate across all games

## Move Display Convention

Human-friendly names shown first everywhere ("Knight to f3"), algebraic notation as secondary text.
Canonical converter: `OpeningMove.friendlyName(from:)` — handles captures, promotions, castling.
Applied in: LineStudyView, OpeningPreviewBoard, SessionView feed, deviation banners.

## On-Device Model

GGUF is bundled via Git LFS. `ModelDownloadService` also supports downloading on demand to Documents (checked first by `OnDeviceLLMService.resolvedModelPath`). Gated by `ProFeature.onDeviceModelDownload`.
