# ChessCoach TODO

## Completed
- [x] Feed bugs: deviation creates orphan entry, undo doesn't sync feed, opponent move missing from deviation entries
- [x] Full copy rebrand: remove all chess jargon, beginner-friendly language throughout
- [x] LLM-free path: app works fully without LLM configured, no AI references for free users
- [x] Opening name shown twice when entering an opening — removed duplicate large title
- [x] Stars for difficulty → dots, and label it "Difficulty" explicitly
- [x] Replace feedback toolbar button with bug icon (ladybug SF Symbol)
- [x] PES removed from learning journey entirely (OpeningDetailView, HomeView, OnboardingView)
- [x] Pro LLM configuration: simple "AI Coach" toggle, hide model names behind Advanced
- [x] Settings: "ELO" → "Skill Level" everywhere
- [x] LLM warmup skipped for free users (ContentView + SessionViewModel)

## Subscription Tiers (new model)
- [x] **Tier enum + service**: SubscriptionTier (free/onDeviceAI/cloudAI/pro), SubscriptionService with multi-tier StoreKit 2
- [x] **ProUpgradeView**: Multi-tier paywall with tier cards, per-tier pricing, feature lists
- [x] **Debug states**: DebugStateView with presets for each tier, debugTierOverride in AppSettings
- [x] **Per-Path Unlock**: Buy individual opening paths à la carte (StoreKit product per path)
- [x] **Token/credit system**: Users buy tokens/credits to unlock whatever they want (openings, features, etc.) — flexible alternative to fixed tiers
- [x] **Free tier: pick one opening**: On first install, free users get to choose ONE opening line to unlock fully (all layers, all features). Everything else is paywalled or available as a package.
- [x] **Free tier opening limits**: Lock icon + paywall on non-free openings in HomeView, accessible openings checked via SubscriptionService

## Queued
- [x] HomeView modes section added with Puzzle and Trainer card links
- [x] Real bots with varying skill levels — actual win condition, not just opening trainer
- [ ] PES rethink:
  - Don't ask user to self-identify the opening
  - Auto-identify which opening the user is playing
  - Detect when user deviates from one opening into another (transpositions)
  - Collapse opening identification into PES scoring
  - How to calculate PES after the opening sequence is complete (middlegame?)
  - PES belongs on front/home screen only, and only for bot/practice games
- [x] Introductory screens: one-time concept intros (openings, practice, review) shown via ConceptIntroView before user first encounters each area
- [x] Help icon (?) accessible in every area where user might be confused — contextual tooltips/popovers
  - Added 6 new topics: streak, dailyGoal, evalBar, review, practiceMode, accuracy
  - Added help buttons to HomeView (streak), QuickReviewView (toolbar), PracticeOpeningView
- [x] Feedback bug icon: Beta shows everywhere (toolbar + session menu), Release only in Settings + SessionComplete
- [x] LLM upsell: locked sparkle visible to free users, tapping shows paywall
- [x] Side panel chat: CoachChatPanel integrated into SessionView with spring animation, full board context, Pro-gated
- [x] Feed entry titles: human-friendly names ("Knight to f3") instead of raw algebraic notation
  - Algebraic notation still visible as secondary/optional text
  - Black moves have black-tinted header, white moves have white-tinted header
  - Feed tiles use a background color that complements both black and white text
- [x] Themes: user-selectable board color themes (8 options with visual swatch picker in Settings). Piece style enum prepared for future expansion (only Classic/USCF currently bundled).
- [x] HomeView modes: Puzzle and Trainer cards as prominent entries (stub views with "Coming soon")
  - [x] Puzzle mode implementation: puzzle database, solving UI, difficulty scaling, daily puzzle
  - [x] Trainer mode implementation: bot game loop, varying skill levels, win/loss tracking

## First-Time User Experience (FTU) Rework
- [x] Onboarding rewritten as 6-page flow: Welcome, What Are Openings, Our Belief (learning philosophy), How It Works, Privacy Promise, Skill Level
- [x] Philosophy page: "We believe you learn best when you understand WHY — not by memorizing moves"
- [x] Privacy page: heartfelt notice — no data selling, no tracking, on-device AI, your progress is yours
- [x] Explains what openings are and why they matter before user starts
- [x] Animations: staggered entry animations on each page (icon scale+fade, title slide-up, content slide-up, button fade), symbol effects on all icons

## Content & UX Bugs
- [x] Algebraic notation still shown first in "Learn the Plan" and likely other places — should lead with human-friendly names
- [x] Learning plan FEN alignment: added optional `fen` field to StrategicGoal and PieceTarget so plan slides can show exact board positions instead of heuristic approximations. JSON data can now specify explicit FENs per goal/target.
- [x] Full-screen overlays (learning plan, etc.) have no exit/close button

## Assets & Polish
- [x] Pro board styles: Walnut, Marble, Tournament color schemes added with pro-gating + lock icons in Settings picker. Enum infrastructure ready for texture-based boards when assets are available.
- [x] Pro piece styles: 5 styles using free Lichess assets (cburnett, merida, staunty, california + classic USCF). GPLv2+. Picker in Settings with pro-gating.
- [x] Piece animations: smooth move spring animation (already existed in ChessboardKit), capture burst ring effect added

## Infrastructure
- [x] LLM model as background download asset: ModelDownloadService downloads GGUF to Documents directory on demand. OnDeviceLLMService checks Documents first, then Bundle. Download progress UI in Settings. Delete option to free space.

## Performance
- [x] Coach chat response is very slow — fixed: CoachChatPanel now reuses shared LLMService from AppServices instead of creating a new one + re-detecting provider on every first message. Eliminates ~500ms redundant model init.

## UX / Design
- [ ] Settings page cleanup: too busy and disorganized — needs logical grouping, collapsing sections, visual hierarchy
- [ ] Puzzle/Trainer navigation bugs: clicking Puzzle from HomeView has weird navigation issues — broken push/presentation

## Trainer Mode — Make It Fun
Currently clinical and lifeless. Engine setup is right (Maia + Stockfish), experience is wrong.

### Engine Mode as a Differentiator
No other app lets you choose between a perfect engine and a human-like opponent. This is our unique selling point.
- [ ] **Dual engine mode picker**: before each game, user picks "Human-Like" (Maia — plays like a real person at that ELO, makes human mistakes, has human tendencies) vs "Engine" (Stockfish — plays perfectly at capped strength, punishes every mistake). Clear UI explaining the difference.
- [ ] **Separate stat tracks**: independent ELO, win rate, and game history for Human-Like vs Engine games. "You beat 1200 humans consistently but struggle against 1000 engines" is actionable insight.
- [ ] **Engine mode descriptions**: Human-Like = "Plays like a real opponent at this level — makes natural mistakes, has preferences." Engine = "Pure calculation — finds the best move every time, scaled to this level."

### Bugs
- [ ] **1600 bot knight repetition**: bot at 1600 ELO just moves knight back and forth — likely Maia returning same top prediction in a loop with no anti-repetition logic. Need: detect repeated move sequences and force alternative moves (pick 2nd/3rd Maia prediction, or fall back to Stockfish).

### Experience & Polish
- [ ] **Bot move pacing**: add realistic "thinking" delay (0.5-2s scaled by difficulty), bot move should animate smoothly onto the board, not snap
- [ ] **Bot personalities with character**: unique avatars/icons per bot, chat bubbles with personality-flavored reactions ("Nice move!", "Hmm, interesting...", "I didn't see that coming"), emoji reactions to captures/checks
- [ ] **Bot move animations**: smooth spring animation with proper timing, not instant snap. Coordinate with sound effects.
- [ ] **Game atmosphere**: move sounds, capture effects, check warnings, endgame tension

### Coaching Integration
- [ ] **Opening detection during play**: auto-identify which opening the user is playing in real time by matching move sequences against opening book. Core building block for everything below.
- [ ] **Cross-correlation with learning**: when user plays an opening they've studied, recognize it and coach them: "You're in the Italian Game! Remember, your plan is to target f7." When they deviate from what they learned: "You learned Bc4 here — you played d3. Here's why Bc4 is stronger."
- [ ] **Coaching during bot play**: if LLM is available, bring in the chat panel + per-move explanations. Even without LLM, show basic tips from opening data (plan reminders, key squares).
- [ ] **Post-game review**: tie game moves back to studied openings — show where they followed/deviated from their repertoire, highlight key moments, suggest what to practice next

## The Core Loop: Learn → Play → See Progress → Learn More
The retention engine. What makes this worth paying for and opening every day.
- [ ] **Opening detection engine**: auto-identify which opening the user is playing from move sequences. Detect transpositions. Know when they've left book. This is the foundation — everything below depends on it.
- [ ] **Progress analytics & ELO estimation**: estimated ELO from bot games (win/loss/draw vs known bot ELO using Glicko-2 or similar), per-opening accuracy trends, mastery percentages, improvement velocity over time
- [ ] **Home screen dashboard**: visual progress — ELO trend chart, per-opening mastery rings, streak, weekly improvement, personalized suggestions ("You're struggling with the Sicilian after move 6 — practice this variation?")
- [ ] **Spaced rep feedback loop**: failed bot game positions feed back into review queue. Openings where user deviates get bumped up in practice priority.
- [ ] **Post-game → learning connection**: after bot game, show which opening was played, compare to what they studied, offer to drill the variation they got wrong

## New Features

### Chess.com / Lichess Account Connection
- [ ] **Account linking**: connect Chess.com and/or Lichess accounts (both have public APIs — Chess.com REST, Lichess OAuth + API)
- [ ] **Import game history**: pull recent games, filter by time control, show in a browsable list
- [ ] **Collaborative game review**: walk through an imported game move-by-move WITH AI coaching — "Here you played d4, but your Italian Game plan calls for Bc4. Let's look at why."
- [ ] **Opening detection on imported games**: auto-identify which openings they played, cross-reference with what they've studied in ChessCoach, surface gaps ("You played the Sicilian 12 times this week but haven't studied it yet")
- [ ] **Pull real ELO**: import their actual Chess.com/Lichess rating to calibrate bot difficulty and coaching level
- [ ] **Track improvement**: show their online rating trend alongside their ChessCoach practice — "You drilled the Italian for 2 weeks and your blitz rating went up 50 points"

### Other
- [ ] Future: animated video demo of AI coaching quality in the paywall
