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
- [x] LLM upsell: locked sparkle visible to free users, tapping shows paywall
  - [ ] Future: animated video demo of AI coaching quality in the paywall
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
- [ ] Animations: should be more animated and playful (pulse effects added, but could do more with Lottie/custom transitions)

## Content & UX Bugs
- [x] Algebraic notation still shown first in "Learn the Plan" and likely other places — should lead with human-friendly names
- [ ] Reevaluate each learning plan completely: text may not line up with the moves being played
- [x] Full-screen overlays (learning plan, etc.) have no exit/close button

## Assets & Polish
- [ ] More chess piece styles: pro/premium piece art sets (Staunton, modern, wood, metal, etc.) — gated by tier
- [ ] Pro board styles: premium board textures (wood grain, marble, tournament green) beyond the flat color schemes
- [ ] Piece animations: smooth move animations, capture effects

## Infrastructure
- [ ] LLM model as background download asset: don't bundle the 3.2GB GGUF in the app binary. When user unlocks on-device AI tier, trigger a background download. Support model updates and potentially additional/alternative models in the future.

## Performance
- [ ] Coach chat response is very slow — investigate CoachChatPanel latency (LLM init on first message, provider detection, inference speed). Tackle at end.
