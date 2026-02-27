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
- [ ] **Per-Path Unlock**: Buy individual opening paths à la carte (StoreKit product per path)
- [ ] **Free tier opening limits**: Enforce freeOpeningIDs gating in HomeView/OpeningDetailView

## Queued
- [ ] HomeView needs full rework
- [ ] Real bots with varying skill levels — actual win condition, not just opening trainer
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
- [ ] LLM upsell: when user taps locked sparkle, show animated video demo of AI coaching quality
- [x] Side panel chat: CoachChatPanel integrated into SessionView with spring animation, full board context, Pro-gated
- [x] Feed entry titles: human-friendly names ("Knight to f3") instead of raw algebraic notation
  - Algebraic notation still visible as secondary/optional text
  - Black moves have black-tinted header, white moves have white-tinted header
  - Feed tiles use a background color that complements both black and white text
- [x] Themes: user-selectable board color themes (8 options with visual swatch picker in Settings). Piece style enum prepared for future expansion (only Classic/USCF currently bundled).
- [ ] HomeView modes: Puzzle mode and Trainer mode accessible from home screen
  - Puzzle mode: tactical puzzles (pin, fork, skewer, mate-in-N), difficulty scaling, daily puzzle
  - Trainer mode: practice openings against bot with real win/loss condition
  - These should be prominent entry points alongside the learning journey

## First-Time User Experience (FTU) Rework
- [ ] Onboarding doesn't explain what the app does — needs a clear "here's what you'll get" screen
- [ ] Missing context on what experience level is expected, what openings are, why they matter
- [ ] Should be animated and fun, not static text walls
- [ ] Add a personal philosophy screen: "We believe you learn best when you understand WHY — not by memorizing moves"
- [ ] Add a heartfelt, caring privacy notice: "We will never use your data for anything. Your progress is yours."
- [ ] Overall FTU should feel warm, inviting, and build excitement

## Assets & Polish
- [ ] More chess piece styles: pro/premium piece art sets (Staunton, modern, wood, metal, etc.) — gated by tier
- [ ] Pro board styles: premium board textures (wood grain, marble, tournament green) beyond the flat color schemes
- [ ] Piece animations: smooth move animations, capture effects

## Infrastructure
- [ ] LLM model as background download asset: don't bundle the 3.2GB GGUF in the app binary. When user unlocks on-device AI tier, trigger a background download. Support model updates and potentially additional/alternative models in the future.

## Performance
- [ ] Coach chat response is very slow — investigate CoachChatPanel latency (LLM init on first message, provider detection, inference speed). Tackle at end.
