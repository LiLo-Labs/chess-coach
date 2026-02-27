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
- [ ] **Free**: No LLM, no AI features. Book explanations, arrows, hints, template coaching. Limited openings.
- [ ] **On-Device AI**: Bundled on-device LLM (Qwen3-4B). AI coaching, explanations, sparkle per-move.
- [ ] **Cloud AI**: Add your own Anthropic key or Ollama server. Better quality AI coaching.
- [ ] **Per-Path Unlock**: Buy individual opening paths à la carte (for users who want just one opening).
- [ ] **Pro**: Everything + all future updates.
- [ ] Need testable/debuggable states for each tier — easy to switch in debug builds.

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
- [ ] Introductory screens: what are openings, what is PES, key concepts explained before user encounters them
- [ ] Help icon (?) accessible in every area where user might be confused — contextual tooltips/popovers
- [ ] Feedback bug icon: Beta shows everywhere (toolbar on all screens), Release only in Settings
- [ ] LLM upsell: when user taps locked sparkle, show animated video demo of AI coaching quality
- [ ] Side panel chat: sliding panel with LLM chat, has full board context, available anytime during session (big beta feature)
  - Already have LineChatView — needs to be promoted to always-available side panel
  - Should have board context, move history, opening info pre-loaded
- [x] Feed entry titles: human-friendly names ("Knight to f3") instead of raw algebraic notation
  - Algebraic notation still visible as secondary/optional text
  - Black moves have black-tinted header, white moves have white-tinted header
  - Feed tiles use a background color that complements both black and white text
- [x] Themes: user-selectable board color themes (8 options with visual swatch picker in Settings). Piece style enum prepared for future expansion (only Classic/USCF currently bundled).
- [ ] HomeView modes: Puzzle mode and Trainer mode accessible from home screen
  - Puzzle mode: tactical puzzles (pin, fork, skewer, mate-in-N), difficulty scaling, daily puzzle
  - Trainer mode: practice openings against bot with real win/loss condition
  - These should be prominent entry points alongside the learning journey
