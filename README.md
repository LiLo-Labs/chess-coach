# Chess Coach

An iOS app that teaches chess openings with real-time coaching. Uses Stockfish for evaluation, Maia 2 for human-like opponent moves, and an LLM for natural language coaching.

## Setup

### Prerequisites

- Xcode 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Git LFS](https://git-lfs.github.com/) (`brew install git-lfs && git lfs install`)

### Clone and build

This repo uses **Git LFS** for large binary files (`.gguf` model, `.nnue` engine weights, vendored frameworks). Install Git LFS before cloning so these files are pulled automatically.

```bash
git lfs install          # one-time setup (if you haven't already)
git clone https://github.com/MALathon/chess-coach.git
cd chess-coach
```

> If you cloned without LFS, run `git lfs pull` to fetch the large files.

### Generate the Xcode project and open

The project file (`ChessCoach.xcodeproj`) is committed to the repo so you can open it directly. However, if you add or remove source files you should regenerate it:

```bash
xcodegen generate
open ChessCoach.xcodeproj
```

### Configure signing

1. Open the project in Xcode
2. Select the **ChessCoach** target → **Signing & Capabilities**
3. Set your **Team** and **Bundle Identifier**
4. For TestFlight: set the same team and bundle ID used in App Store Connect

### Build and run

Build and run on a physical device (iPhone 15 Pro or later recommended for on-device LLM). The Simulator works for UI testing but cannot run the LLM or Maia neural network.

## On-device AI model

The Qwen3-4B model (~2.3 GB GGUF) powers offline coaching. It is tracked via Git LFS and bundled in the app binary.

**For beta testers:** The AI model is bundled inside the app — it installs automatically when you install from TestFlight. No separate download is required. The first time you open an opening and see coaching text, the on-device model loads in a few seconds.

> The app also works without the on-device model by falling back to Ollama (local network) or Claude API (cloud). You can switch providers in Settings → AI Coach.

### Downloading a fresh model (developers only)

If you need to replace the bundled model or the LFS file is missing:

```bash
curl -L https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf \
  -o ChessCoach/Resources/qwen3-4b-q4_k_m.gguf
```

## Architecture

- **Stockfish** — position evaluation and best-move computation (via local fork of [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) with fixed I/O)
- **Maia 2** — neural network that plays human-like moves at a target ELO (ONNX Runtime)
- **LLM coaching** — natural language explanations of moves and positions
  - On-device: Qwen3-4B via llama.cpp (no network required)
  - Cloud: Claude API (Anthropic)
  - Local: Ollama server on your network
- **ChessboardKit** — board UI
- **Lichess Puzzles** — CC0-licensed puzzles for skill assessment

## LLM provider priority

1. On-device Qwen3-4B (if GGUF is bundled)
2. Ollama on local network
3. Claude API

## Deploying to TestFlight

### One-time App Store Connect setup

1. Create an app record in [App Store Connect](https://appstoreconnect.apple.com/) with your bundle ID
2. Add internal or external testers to a TestFlight group

### Archive and upload

1. In Xcode, select **Any iOS Device** as the destination
2. **Product → Archive**
3. When the archive completes, click **Distribute App → App Store Connect**
4. Choose **Upload** (not Export) and follow the prompts
5. Once processing completes (~10 minutes), the build appears in TestFlight
6. For external testers: submit the build for Beta App Review (usually approved within 24 hours)

### For beta testers

Install the [TestFlight](https://apps.apple.com/app/testflight/id899247664) app, then accept the invitation link. Updates are installed automatically.

When you first open the app after onboarding, you'll see a **Beta Testing Guide** that explains:
- What to test (openings, trainer mode, puzzles, assessment)
- How to leave feedback (bug icon on any screen, or Settings → About → Send Feedback)
- Known limitations

## Debug mode (DEBUG builds only)

Debug builds include extra developer tools not visible in release/TestFlight builds:

### Debug States (Settings → Developer → Debug States)

- **Token presets** — simulate free and paid tier token balances
- **Free user state** — see the app as a free user (3 openings, limited puzzles)
- **Pro state** — unlock everything to test all features
- **On-Device AI / Cloud AI** — switch between coaching providers
- **Export/Import** — save and restore complete app state snapshots

Changes take effect immediately — the app reloads when you switch states.

### How to access

Debug tools appear in **Settings → Developer** only in debug builds (i.e., when running from Xcode). They are stripped from release and TestFlight builds via `#if DEBUG` compiler flags.

## Skill Assessment

The app includes a 10-puzzle adaptive skill assessment that estimates the user's ELO rating. Puzzles are sourced from the Lichess puzzle database (CC0 licensed) and bundled as `assessment_puzzles.json`.

The assessment uses an Elo formula with K=150 to adjust difficulty after each puzzle. Puzzles are selected from a band of ±200 rating points around the current estimate, widening to ±400 if no close matches are available.

## Acknowledgments

- [ChessKit](https://github.com/aperechnev/ChessKit) — MIT
- [ChessboardKit](https://github.com/nickkxsper/ChessboardKit) — MIT
- [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) — MIT (wraps GPL engines)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — MIT
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) — MIT
- [Lichess Puzzle Database](https://database.lichess.org/#puzzles) — CC0 1.0
- [Lichess Piece Assets (Cburnett)](https://github.com/lichess-org/lila) — GPL 2.0+
