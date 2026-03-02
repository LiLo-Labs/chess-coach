# Chess Coach

iOS app for learning chess openings. Stockfish evaluates positions, Maia 2 plays human-like opponent moves, and an on-device LLM explains what's happening in plain English.

## Setup

Requires Xcode 17+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and [Git LFS](https://git-lfs.github.com/).

```bash
brew install xcodegen git-lfs
git lfs install
git clone https://github.com/MALathon/chess-coach.git
cd chess-coach
```

The `.xcodeproj` is committed, so you can open it directly. Regenerate after adding/removing files:

```bash
xcodegen generate
open ChessCoach.xcodeproj
```

Set your signing team and bundle ID in **Target → Signing & Capabilities**, then build to a physical device. Simulator works for UI but can't run the LLM or Maia neural net.

## On-device model

Qwen3-4B (~2.3 GB GGUF) is tracked via Git LFS and bundled in the binary. Beta testers get it automatically through TestFlight.

Fallback providers: Ollama (local network) or Claude API (cloud), configurable in Settings.

To re-download the model manually:

```bash
curl -L https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf \
  -o ChessCoach/Resources/qwen3-4b-q4_k_m.gguf
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layout.

- **Stockfish** — evaluation + best move (local [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) fork)
- **Maia 2** — human-like moves at target ELO (ONNX Runtime)
- **LLM** — move explanations via llama.cpp (on-device), Claude API, or Ollama
- **ChessboardKit** — board rendering

## TestFlight

1. Create an app record in [App Store Connect](https://appstoreconnect.apple.com/)
2. In Xcode: **Any iOS Device → Product → Archive → Distribute App → App Store Connect → Upload**
3. Build appears in TestFlight after ~10 min processing
4. External testers need Beta App Review (~24h)

## Debug tools

`#if DEBUG` only. Settings → Developer → Debug States:

- Tier presets (free, pro, on-device AI, cloud AI)
- Token balance simulation
- State export/import snapshots

## Acknowledgments

- [ChessKit](https://github.com/aperechnev/ChessKit) — MIT
- [ChessboardKit](https://github.com/nickkxsper/ChessboardKit) — MIT
- [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) — MIT (wraps GPL engines)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) — MIT
- [ONNX Runtime](https://github.com/microsoft/onnxruntime) — MIT
- [Lichess Puzzle Database](https://database.lichess.org/#puzzles) — CC0 1.0
- [Lichess Piece Assets (Cburnett)](https://github.com/lichess-org/lila) — GPL 2.0+
