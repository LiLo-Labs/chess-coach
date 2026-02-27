# ChessCoach Architecture

> Auto-maintained. Last updated: 2026-02-26

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
│   └── Protocols/EngineProtocols.swift  # TextGenerating, PositionEvaluating, MovePredicting
│
├── Models/
│   ├── Chess/GameState.swift     # @Observable game state, move history, FEN
│   ├── Opening/                  # Opening, OpeningDatabase, OpeningPlan, LessonStep, etc.
│   ├── Progress/                 # UserProgress, SessionResult, LineProgress, LearningPhase
│   ├── Scoring/                  # PlanExecutionScore, PopularityService, SoundnessCalculator
│   ├── SpacedRep/                # ReviewItem, SpacedRepScheduler
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
│   └── Subscription/             # SubscriptionService, FeatureAccess, ProFeature, tiers
│
├── Views/
│   ├── Board/                    # GameBoardView, arrow overlays, square highlights
│   ├── Components/               # HelpButton, FeedbackButton, BoardLessonCard, QuizLessonCard
│   ├── Effects/                  # ConfettiView
│   ├── Home/                     # HomeView, OpeningDetailView, OpeningPreviewBoard
│   ├── Onboarding/               # OnboardingView (4-page tutorial)
│   ├── Paywall/                  # ProUpgradeView
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
| `PositionEvaluating` | Chess position eval | `StockfishService` |
| `MovePredicting` | Human-like moves | `MaiaService` |
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

## Largest Files (refactoring candidates)

| File | Lines | Notes |
|------|-------|-------|
| SessionViewModel.swift | ~2000 | Main session logic, could split |
| SessionView.swift | ~800 | Large but mostly layout |
| OpeningDetailView.swift | ~700 | Opening detail + layers |
| DebugStateView.swift | ~600 | Debug presets |
| PromptCatalog.swift | ~400 | All LLM prompts |

## Board Theme System

8 themes available: Chess.com (default), Classic, Dark, Blue, Green, Purple, Orange, Red.
Selected via `AppSettings.boardTheme`. Applied to `GameBoardView` via environment.
Piece style: only Classic/USCF bundled (prepared for expansion).

## Onboarding (6 pages)

1. Welcome — animated crown, warm greeting
2. What Are Openings — explains the concept for complete beginners
3. Our Belief — learning philosophy (understand WHY, not memorize)
4. How It Works — 4-step learning journey overview
5. Privacy Promise — heartfelt data pledge (no tracking, no selling, on-device AI)
6. Skill Level — adjustable ELO picker

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
- HomeView shows lock icons on non-free openings, tapping opens paywall
- `SubscriptionService.isOpeningAccessible()` checks tier + per-path unlocks
- AI features gated by `hasAI` (tier != .free)
