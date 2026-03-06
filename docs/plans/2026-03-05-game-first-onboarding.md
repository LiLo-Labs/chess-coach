# Phase 6: Game-First Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace 8-page passive onboarding with a 3-page intro → real game → opening revelation flow, reusing `GamePlayView` entirely.

**Architecture:** Add `GamePlayMode.onboarding(playerELO:)` case. User plays ~8 moves against Maia through the existing `GamePlayView`. `HolisticDetector` runs silently. Revelation overlay shows detected opening. View layer hides opening info during play.

**Tech Stack:** SwiftUI, GamePlayView, HolisticDetector, Maia engine, Stockfish, Swift Testing

---

### Task 1: Add `GamePlayMode.onboarding` case

**Files:**
- Modify: `ChessCoach/Models/GamePlay/GamePlayMode.swift`
- Test: `ChessCoachTests/Models/GamePlayModeTests.swift`

**Step 1: Write failing tests**

Add to `ChessCoachTests/Models/GamePlayModeTests.swift`:

```swift
// MARK: - .onboarding

@Test func onboardingIsNotTrainer() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.isTrainer == false)
}

@Test func onboardingIsNotPuzzle() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.isPuzzle == false)
}

@Test func onboardingIsNotSession() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.isSession == false)
}

@Test func onboardingIsOnboarding() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.isOnboarding == true)
}

@Test func onboardingPlayerColorIsWhite() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.playerColor == .white)
}

@Test func onboardingOpeningIsNil() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.opening == nil)
}

@Test func onboardingSessionModeIsNil() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.sessionMode == nil)
}

@Test func onboardingShowsNoArrows() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.showsArrows == false)
}

@Test func onboardingShowsNoProactiveCoaching() {
    let mode = GamePlayMode.onboarding(playerELO: 800)
    #expect(mode.showsProactiveCoaching == false)
}
```

**Step 2: Run tests to verify they fail**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild test -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ChessCoachTests/GamePlayModeTests 2>&1 | tail -20
```

Expected: Compilation error — `onboarding` case doesn't exist.

**Step 3: Add the case and computed properties**

In `ChessCoach/Models/GamePlay/GamePlayMode.swift`, add the new case and update all switch statements:

```swift
enum GamePlayMode {
    case trainer(personality: OpponentPersonality, engineMode: TrainerEngineMode, playerColor: PieceColor, botELO: Int)
    case guided(opening: Opening, lineID: String?)
    case unguided(opening: Opening, lineID: String?)
    case practice(opening: Opening, lineID: String?)
    case puzzle(opening: Opening?, source: PuzzleSource)
    case onboarding(playerELO: Int)

    var isTrainer: Bool {
        if case .trainer = self { return true }
        return false
    }

    var isPuzzle: Bool {
        if case .puzzle = self { return true }
        return false
    }

    var isOnboarding: Bool {
        if case .onboarding = self { return true }
        return false
    }

    var isSession: Bool { !isTrainer && !isPuzzle && !isOnboarding }

    var opening: Opening? {
        switch self {
        case .trainer, .onboarding: return nil
        case .guided(let o, _), .unguided(let o, _), .practice(let o, _): return o
        case .puzzle(let o, _): return o
        }
    }

    var lineID: String? {
        switch self {
        case .trainer, .onboarding: return nil
        case .guided(_, let id), .unguided(_, let id), .practice(_, let id): return id
        case .puzzle: return nil
        }
    }

    var playerColor: PieceColor {
        switch self {
        case .trainer(_, _, let color, _): return color
        case .guided(let o, _), .unguided(let o, _), .practice(let o, _):
            return o.color == .white ? .white : .black
        case .puzzle(let o, _):
            guard let o else { return .white }
            return o.color == .white ? .white : .black
        case .onboarding: return .white
        }
    }

    var showsArrows: Bool {
        if case .guided = self { return true }
        return false
    }

    var showsProactiveCoaching: Bool {
        if case .guided = self { return true }
        return false
    }

    var sessionMode: SessionMode? {
        switch self {
        case .trainer, .onboarding: return nil
        case .guided: return .guided
        case .unguided: return .unguided
        case .practice: return .practice
        case .puzzle: return nil
        }
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild test -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ChessCoachTests/GamePlayModeTests 2>&1 | tail -20
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add ChessCoach/Models/GamePlay/GamePlayMode.swift ChessCoachTests/Models/GamePlayModeTests.swift
git commit -m "feat: add GamePlayMode.onboarding case with tests"
```

---

### Task 2: Add onboarding properties and init to GamePlayViewModel

**Files:**
- Modify: `ChessCoach/ViewModels/GamePlayViewModel.swift`

**Context:** The ViewModel needs onboarding-specific state: move counter, completion flag, and best detected opening match. The init needs an onboarding branch that skips CurriculumService/CoachingService/SpacedRep but keeps HolisticDetector (already exists as a property).

**Step 1: Add onboarding state properties**

After the puzzle properties block (around line 96), add:

```swift
// Onboarding mode
var onboardingMoveCount = 0
var onboardingComplete = false
var onboardingDetectedOpening: Opening?
```

**Step 2: Add onboarding branch to init**

In the `init` method (around line 295, after the trainer init block), add:

```swift
// Onboarding-specific init — set opponent ELO from player ELO
if case .onboarding(let playerELO) = mode {
    opponentELO = playerELO
}
```

**Step 3: Add onboarding branch to `startGame()`**

In `startGame()` (around line 348-353, the trainer else-if), add a new branch BEFORE the trainer branch:

```swift
} else if mode.isOnboarding {
    isModelLoading = false
    // User plays white, Maia plays black — no extra setup needed
```

**Step 4: Build to verify compilation**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add ChessCoach/ViewModels/GamePlayViewModel.swift
git commit -m "feat: add onboarding state properties and init branch to GamePlayViewModel"
```

---

### Task 3: Create GamePlayViewModel+Onboarding.swift

**Files:**
- Create: `ChessCoach/ViewModels/GamePlayViewModel+Onboarding.swift`

**Context:** This extension handles the onboarding game flow: user moves, opponent responses, opening detection after each move, move counting, generic coaching entries, and triggering the revelation at 8 user moves or game end.

**Step 1: Create the file**

```swift
import Foundation
import SwiftUI

/// Onboarding-mode logic: user plays ~8 moves, Maia responds, HolisticDetector runs silently.
extension GamePlayViewModel {

    /// Handle user move during onboarding game.
    func onboardingUserMoved(from: String, to: String) {
        onboardingMoveCount += 1

        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        // Run opening detection silently
        updateOpeningDetection()

        // Store best white opening match
        if let best = holisticDetection.whiteFramework.primary {
            onboardingDetectedOpening = best.opening
        }

        // Add generic coaching entry (no opening names)
        addOnboardingFeedEntry()

        // Check if we should end
        if onboardingMoveCount >= 8 || gameState.isCheckmate || gameState.isStalemate {
            completeOnboarding()
            return
        }

        // Opponent responds
        makeOnboardingOpponentMove()
    }

    /// Maia plays the opponent move.
    private func makeOnboardingOpponentMove() {
        isThinking = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let fen = self.gameState.fen

            // Try Maia first, fall back to Stockfish
            var moveUCI: String?
            if let maia = self.maiaService {
                moveUCI = try? await maia.bestMove(fen: fen, elo: self.opponentELO)
            }
            if moveUCI == nil {
                moveUCI = await self.stockfish.bestMove(fen: fen, depth: 8)
            }

            guard let move = moveUCI else {
                self.isThinking = false
                return
            }

            self.gameState.makeMoveUCI(move)
            SoundService.shared.play(.move)
            self.isThinking = false

            // Update detection after opponent move too
            self.updateOpeningDetection()
            if let best = self.holisticDetection.whiteFramework.primary {
                self.onboardingDetectedOpening = best.opening
            }

            // Check game end after opponent move
            if self.gameState.isCheckmate || self.gameState.isStalemate {
                self.completeOnboarding()
            }
        }
    }

    /// Add a generic coaching feed entry (no opening names revealed).
    private func addOnboardingFeedEntry() {
        let moveNumber = (gameState.plyCount + 1) / 2
        let lastMove = gameState.moveHistory.last
        let san = lastMove.map { GameState.sanForUCI("\($0.from)\($0.to)", inFEN: gameState.fen) } ?? "..."

        // Generic move feedback
        let coaching: String
        switch onboardingMoveCount {
        case 1: coaching = "Good start! Let's see how you play."
        case 2: coaching = "Developing your pieces — nice."
        case 3: coaching = "Building your position..."
        case 4: coaching = "You're finding a rhythm."
        case 5: coaching = "Solid play so far."
        case 6: coaching = "Interesting choice."
        case 7: coaching = "Almost there — one more move."
        default: coaching = "Let's see what you've got."
        }

        let entry = CoachingEntry(
            ply: gameState.plyCount - 1,
            moveNumber: moveNumber,
            moveSAN: san,
            isPlayerMove: true,
            coaching: coaching,
            category: .goodMove
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    /// Finalize onboarding: apply fallback if needed, trigger revelation overlay.
    private func completeOnboarding() {
        // If no good match, use a curated fallback
        if onboardingDetectedOpening == nil || (holisticDetection.whiteFramework.primary?.matchDepth ?? 0) < 3 {
            onboardingDetectedOpening = curatedFallbackOpening()
        }
        onboardingComplete = true
    }

    /// Pick a curated opening based on the user's first move.
    private func curatedFallbackOpening() -> Opening? {
        let db = OpeningDatabase.shared
        let firstMove = gameState.moveHistory.first.map { "\($0.from)\($0.to)" }

        switch firstMove {
        case "e2e4":
            return db.opening(named: "Italian Game") ?? db.openings(forColor: .white).first
        case "d2d4":
            return db.opening(named: "Queen's Gambit") ?? db.openings(forColor: .white).first
        case "c2c4":
            return db.opening(named: "English Opening") ?? db.openings(forColor: .white).first
        default:
            return db.opening(named: "Italian Game") ?? db.openings(forColor: .white).first
        }
    }
}
```

**Step 2: Build to verify compilation**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. If `OpeningDatabase.opening(named:)` doesn't exist, use `openings(forColor:).first(where: { $0.name == name })` instead.

**Step 3: Commit**

```bash
git add ChessCoach/ViewModels/GamePlayViewModel+Onboarding.swift
git commit -m "feat: add GamePlayViewModel+Onboarding extension for onboarding game flow"
```

---

### Task 4: Wire onboarding move dispatch in GamePlayView+Board

**Files:**
- Modify: `ChessCoach/Views/GamePlay/GamePlayView+Board.swift:25-35`

**Context:** The board's move callback dispatches to different handlers based on mode. Add the onboarding case.

**Step 1: Add onboarding branch**

In the move callback closure (around line 26-35), add an onboarding branch BEFORE the trainer check:

```swift
} { from, to in
    viewModel.clearArrowAndHint()
    if viewModel.mode.isPuzzle {
        viewModel.puzzleUserMoved(from: from, to: to)
    } else if viewModel.mode.isOnboarding {
        viewModel.onboardingUserMoved(from: from, to: to)
    } else if viewModel.mode.isTrainer {
        viewModel.trainerUserMoved(from: from, to: to)
    } else if viewModel.mode.sessionMode == .practice {
        Task { await viewModel.practiceUserMoved(from: from, to: to) }
    } else {
        Task { await viewModel.sessionUserMoved(from: from, to: to) }
    }
}
```

Also update the `allowInteraction` closure to handle onboarding:

```swift
allowInteraction: {
    if viewModel.mode.isPuzzle {
        return !viewModel.isPuzzleShowingSolution && !viewModel.isPuzzleComplete
    }
    if viewModel.mode.isOnboarding {
        return !viewModel.onboardingComplete && !viewModel.isThinking
    }
    return isPlayerTurn && !viewModel.isThinking && !viewModel.isGameOver && !viewModel.sessionComplete && !viewModel.isReplaying
}()
```

**Step 2: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add ChessCoach/Views/GamePlay/GamePlayView+Board.swift
git commit -m "feat: wire onboarding move dispatch in board view"
```

---

### Task 5: Hide opening info in coaching feed for onboarding mode

**Files:**
- Modify: `ChessCoach/Views/GamePlay/GamePlayView+CoachingFeed.swift`

**Context:** The coaching feed branches by mode. Add an onboarding branch that shows the feed without headers (no deviation banners, no opening names).

**Step 1: Add onboarding branch**

In the `coachingFeed` computed property, add BEFORE the puzzle check (around line 10):

```swift
if viewModel.mode.isOnboarding {
    CoachingFeedView(
        entries: feedEntries,
        isLoading: false,
        explainStyle: .textAndIcon,
        scrollAnchor: "live",
        onTapEntry: { _ in },
        onRequestExplanation: { _ in }
    )
    .background(AppColor.background)
} else if viewModel.mode.isPuzzle {
```

**Step 2: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add ChessCoach/Views/GamePlay/GamePlayView+CoachingFeed.swift
git commit -m "feat: hide opening info in coaching feed for onboarding mode"
```

---

### Task 6: Add revelation overlay to GamePlayView+Overlays

**Files:**
- Modify: `ChessCoach/Views/GamePlay/GamePlayView+Overlays.swift`

**Context:** The overlays view already has cases for trainer game over, practice complete, session complete, and puzzle complete. Add onboarding revelation as a new case.

**Step 1: Add onboarding overlay case**

In the `overlays` computed property (around line 25-27, after the puzzle complete check), add:

```swift
// Onboarding revelation
if viewModel.onboardingComplete {
    onboardingRevelationOverlay
}
```

**Step 2: Add the revelation overlay view**

Add a new `MARK` section after the puzzle complete overlay:

```swift
// MARK: - Onboarding Revelation

private var onboardingRevelationOverlay: some View {
    let detected = viewModel.onboardingDetectedOpening
    let matchDepth = viewModel.holisticDetection.whiteFramework.primary?.matchDepth ?? 0
    let openingName = detected?.name ?? "a classic opening"
    let userELO: Int = {
        if case .onboarding(let elo) = viewModel.mode { return elo }
        return 800
    }()

    return ZStack {
        Color.black.opacity(0.85).ignoresSafeArea()

        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Spacer(minLength: 60)

                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                    .symbolEffect(.pulse, options: .repeating.speed(0.5))

                VStack(spacing: AppSpacing.sm) {
                    Text("You played the")
                        .font(.title3)
                        .foregroundStyle(AppColor.secondaryText)

                    Text(openingName)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)
                        .multilineTextAlignment(.center)
                }

                if let description = detected?.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxl)
                }

                // Stats card
                SessionSummaryCard(
                    stats: [
                        .init(label: "Your Level", value: "\(userELO)"),
                        .init(label: "Moves Played", value: "\(viewModel.onboardingMoveCount)"),
                        .init(label: "Match Depth", value: matchDepth >= 3 ? "\(matchDepth) moves" : "Partial"),
                    ],
                    icon: "crown.fill",
                    iconColor: .yellow,
                    title: "Game Summary"
                )

                VStack(spacing: AppSpacing.xs) {
                    Text("Every game you play follows an opening pattern.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)

                    Text("We'll show you how to use these patterns to win — no memorization needed.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)

                // Action buttons
                VStack(spacing: AppSpacing.md) {
                    if detected != nil {
                        Button {
                            onboardingPickOpening(detected)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "book.fill")
                                Text("Learn \(openingName)")
                                    .font(.body.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    Button {
                        onboardingSkip()
                    } label: {
                        Text("Browse All Openings")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onboardingSkip()
                    } label: {
                        Text("Skip to Home")
                            .font(.caption)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer(minLength: AppSpacing.xl)
            }
            .padding(AppSpacing.xxxl)
        }
    }
}

private func onboardingPickOpening(_ opening: Opening?) {
    if let opening {
        // Store as free opening pick so ContentView routes correctly
        let settings = AppSettings.shared
        settings.pickedFreeOpeningID = opening.id
        settings.hasPickedFreeOpening = true
    }
    dismiss()
}

private func onboardingSkip() {
    dismiss()
}
```

**Step 3: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. If `AppSettings.shared` doesn't exist (it's `@Environment`-based), use a different approach — pass a callback or post a notification. Check how the existing overlays handle dismiss + state changes.

**Step 4: Commit**

```bash
git add ChessCoach/Views/GamePlay/GamePlayView+Overlays.swift
git commit -m "feat: add onboarding revelation overlay with opening detection results"
```

---

### Task 7: Guard existing view branches for onboarding mode

**Files:**
- Modify: `ChessCoach/Views/GamePlay/GamePlayView.swift`
- Modify: `ChessCoach/Views/GamePlay/GamePlayView+TopBar.swift` (if it exists)

**Context:** Several parts of GamePlayView conditionally show UI based on mode (eval bar, session players bar, progress bar, replay bar, trainer status). These need guards so onboarding mode shows a minimal UI.

**Step 1: Update the main body in GamePlayView.swift**

In the `VStack(spacing: 0)` body (lines 30-59), update the conditionals. The onboarding mode should show:
- `topBar` — yes, but simplified (just a back button, no chat)
- `statusBanners` — no
- `practiceLineStatusBar` — no
- `sessionPlayersBar` / `trainerPlayersBar` — no
- `boardArea` — yes
- `progressBar` — no
- `trainerStatusSlot` / `personalityQuipView` — no
- `replayBar` — no
- `coachingFeed` — yes (already handled in Task 5)

Update the conditionals:

```swift
VStack(spacing: 0) {
    topBar

    if !viewModel.mode.isOnboarding {
        statusBanners
        practiceLineStatusBar
    }

    if viewModel.mode.isTrainer {
        trainerPlayersBar
    } else if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding {
        sessionPlayersBar
    }

    boardArea(boardSize: boardSize, evalWidth: viewModel.mode.isOnboarding ? 0 : evalWidth)

    if viewModel.mode.isSession && !viewModel.mode.isOnboarding {
        progressBar
    }

    if viewModel.mode.isTrainer {
        trainerStatusSlot(boardSize: boardSize)
    } else if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding,
              viewModel.showPersonalityQuip, let quip = viewModel.personalityQuip {
        personalityQuipView(quip: quip)
    }

    if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding {
        replayBar
    }

    coachingFeed
}
```

Also update the eval bar width calculation (line 25-26):

```swift
let evalWidth: CGFloat = (viewModel.mode.isSession && !viewModel.mode.isOnboarding) ? 12 : 0
let evalGap: CGFloat = (viewModel.mode.isSession && !viewModel.mode.isOnboarding) ? 4 : 0
```

**Step 2: Check the top bar**

Read `GamePlayView+TopBar.swift`. The top bar likely has a chat button and other controls. For onboarding, we want just a minimal bar (maybe just a back/close button). Add a guard:

```swift
// In the chat button area:
if !viewModel.mode.isOnboarding {
    // chat button, etc.
}
```

**Step 3: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

**Step 4: Commit**

```bash
git add ChessCoach/Views/GamePlay/GamePlayView.swift ChessCoach/Views/GamePlay/GamePlayView+TopBar.swift
git commit -m "feat: guard view branches for onboarding mode — minimal UI"
```

---

### Task 8: Trim OnboardingView to 3 pages

**Files:**
- Modify: `ChessCoach/Views/Onboarding/OnboardingView.swift`

**Context:** Current 8 pages: Story(0), Openings(1), Tech(2), CoachingDemo(3), Pro(4), ProShowcase(5), Privacy(6), Skill(7). Keep: Welcome/CoachingDemo (merged), ELO picker, then a "Let's Play" transition page. Delete: Story, Openings, Tech, Pro, ProShowcase, Privacy.

**Step 1: Restructure to 3 pages**

Rewrite OnboardingView to have 3 pages:

- **Page 0: Welcome** — App name + tagline + the coaching demo tile stagger animation (reuse `coachingTiles` and `coachingTileRow` from current page 3). Show a static board with the Italian Game position. Coaching tiles animate in from the bottom. This shows the core value prop: "we explain every move."

- **Page 1: Your Level** — ELO picker (reuse current `skillPage` content with the stepper and "Assess My Level" button).

- **Page 2: Let's Play** — Brief text: "Now let's see how you play. Make your moves — we'll show you something cool at the end." Big "Start Game" button that presents `GamePlayView(.onboarding(playerELO: settings.userELO))` as a full-screen cover.

The `onComplete` callback should be called when GamePlayView dismisses (after the revelation overlay is dismissed).

**Key changes:**
- `totalPages = 3`
- Delete `storyPage`, `openingsPage`, `techPage`, `proPage`, `proShowcasePage`, `privacyPage`
- Keep `coachingTiles`, `coachingTileRow`, `setupCoachingDemo`, `handleDemoMove` for the welcome page
- Keep `skillPage` content for page 1
- New page 2 with `.fullScreenCover` presenting GamePlayView
- After GamePlayView dismisses, show a brief pricing/privacy page OR just call `onComplete()`

**Step 2: Add state for game presentation**

```swift
@State private var showOnboardingGame = false
```

**Step 3: Add the fullScreenCover**

On the main ZStack:

```swift
.fullScreenCover(isPresented: $showOnboardingGame) {
    NavigationStack {
        GamePlayView(
            mode: .onboarding(playerELO: settings.userELO),
            isPro: false,
            stockfish: appServices.stockfish
        )
    }
}
.onChange(of: showOnboardingGame) { _, showing in
    if !showing {
        // Game dismissed — onboarding complete
        onComplete()
    }
}
```

**Step 4: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

**Step 5: Commit**

```bash
git add ChessCoach/Views/Onboarding/OnboardingView.swift
git commit -m "feat: trim OnboardingView to 3 pages — welcome, ELO, play"
```

---

### Task 9: Update ContentView routing for onboarding → game → home

**Files:**
- Modify: `ChessCoach/App/ContentView.swift`

**Context:** Currently `OnboardingView.onComplete` either shows `FreeOpeningPickerView` or sets `hasSeenOnboarding = true`. With the new flow, the revelation overlay inside GamePlayView handles the opening pick. So `onComplete` should check if a free opening was already picked (from the revelation overlay) and skip the picker.

**Step 1: Update the onComplete callback**

```swift
OnboardingView(onComplete: {
    // If the user picked an opening during the onboarding game revelation,
    // skip the free opening picker
    if settings.hasPickedFreeOpening || subscriptionService.currentTier != .free {
        withAnimation { settings.hasSeenOnboarding = true }
    } else {
        withAnimation { showOpeningPicker = true }
    }
})
```

This is a minor change — the existing logic mostly works, but now `hasPickedFreeOpening` may already be true from the revelation overlay.

**Step 2: Build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | tail -10
```

**Step 3: Commit**

```bash
git add ChessCoach/App/ContentView.swift
git commit -m "feat: update ContentView routing for onboarding game flow"
```

---

### Task 10: Fix any remaining compilation issues

**Files:**
- Various — depends on what breaks

**Context:** Adding a new enum case to `GamePlayMode` may cause exhaustive switch warnings or compilation errors in files that switch on mode. Common locations:
- `GamePlayView+Board.swift` — eval bar conditional
- `GamePlayView+TopBar.swift` — top bar buttons
- Any other file that checks `mode.isSession` — since `isSession` now returns false for onboarding, code that assumed "not trainer and not puzzle = session" may need updates.

**Step 1: Do a full build**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|warning:.*switch" | head -20
```

**Step 2: Fix any errors**

Common fixes:
- Add `case .onboarding:` to any switch on `GamePlayMode` that doesn't use default
- Guard any `mode.isSession` checks that should also exclude onboarding

**Step 3: Run full test suite**

```bash
cd /Users/mark/dev/chess-coach/.worktrees/phase-4-off-book-coaching && \
xcodebuild test -project ChessCoach.xcodeproj -scheme ChessCoach \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: resolve compilation issues from onboarding mode addition"
```

---

### Task 11: Manual testing and polish

**Context:** Run the app in the simulator, reset onboarding state, and verify the full flow.

**Step 1: Reset onboarding state**

In the simulator, delete the app or use the debug menu to reset `hasSeenOnboarding`.

**Step 2: Verify the flow**

1. App launches → Welcome page with coaching tile animations
2. Swipe to ELO picker → set level
3. Swipe to "Let's Play" → tap "Start Game"
4. GamePlayView appears — user plays White against Maia
5. Coaching feed shows generic move feedback (no opening names)
6. No deviation banners, no book status, no eval bar
7. After 8 user moves → revelation overlay appears
8. Shows detected opening name, match depth, ELO
9. "Learn This Opening" button → dismisses to Home
10. Home loads with the picked opening available

**Step 3: Fix any issues found during testing**

**Step 4: Final commit**

```bash
git add -A
git commit -m "polish: onboarding flow refinements from manual testing"
```

---

## Verification Checklist

1. `xcodebuild build` succeeds with zero errors
2. `xcodebuild test` — all existing tests pass, new `GamePlayModeTests` pass
3. Fresh install → 3-page onboarding → real game → opening revealed
4. Coaching feed shows generic text during onboarding game (no opening names)
5. No deviation banners, eval bar, replay bar, or session UI during onboarding
6. `HolisticDetector` correctly identifies opening (test with 1.e4 e5 2.Nf3 Nc6 3.Bc4 → Italian Game)
7. Fallback works when match depth < 3 (play random moves)
8. "Learn This Opening" sets `pickedFreeOpeningID` and routes to Home
9. After onboarding, normal app flow works (HomeView loads, can play sessions)
