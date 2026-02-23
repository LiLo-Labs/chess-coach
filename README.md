# Chess Coach

An iOS app that teaches chess openings with real-time coaching. Uses Stockfish for evaluation, Maia 2 for human-like opponent moves, and an LLM for natural language coaching.

## Setup

### Prerequisites

- Xcode 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Clone and build

```bash
git clone https://github.com/MALathon/chess-coach.git
cd chess-coach
```

### Download the on-device LLM model

The Qwen3-4B model (2.3 GB) is required for on-device coaching. Download it into the Resources directory:

```bash
curl -L https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf \
  -o ChessCoach/Resources/qwen3-4b-q4_k_m.gguf
```

> The app works without this file — it falls back to Ollama or Claude API for coaching text. The on-device model enables fully offline coaching.

### Generate the Xcode project and open

```bash
xcodegen generate
open ChessCoach.xcodeproj
```

Build and run on a physical device (iPhone 15 Pro or later recommended for on-device LLM).

## Architecture

- **Stockfish** — position evaluation and best-move computation (via local fork of [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) with fixed I/O)
- **Maia 2** — neural network that plays human-like moves at a target ELO (Core ML)
- **LLM coaching** — natural language explanations of moves and positions
  - On-device: Qwen3-4B via llama.cpp (no network required)
  - Fallback: Ollama server, then Claude API
- **ChessboardKit** — board UI

## LLM provider priority

1. On-device Qwen3-4B (if GGUF is bundled)
2. Ollama on local network
3. Claude API
