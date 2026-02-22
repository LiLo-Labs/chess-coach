# ChessCoach — Design Document

## Vision

A SwiftUI iOS app that teaches chess openings through play-first learning against a human-like AI opponent with real-time coaching. The app feels like playing chess with a patient coach — you learn by doing, not by reading.

## Target Audience

Beginners (< 1000 ELO) who want to understand *why* moves are good, not just memorize sequences.

## Tech Stack

- **SwiftUI** — native iOS UI
- **Stockfish** (C++ bridge) — position evaluation, best move analysis
- **Maia 2** (ONNX → Core ML) — human-like opponent at adjustable ELO
- **LLM (tiered):**
  - Primary: DGX Ollama (Qwen 2.5 32B) when on WiFi (192.168.4.62:11434)
  - Fallback: Claude API when off WiFi

## Core Loop

```
Pick opening → Play from move 1 vs guided Maia → Real-time coaching → Session summary
                         ↑                                                    |
                         └────── Spaced repetition queues positions ───────────┘
```

## Opening Study Flow

### Always From Move 1

Every session starts from the initial board position. The app has a target opening to teach.

### Guided Maia (Curriculum-Controlled Opponent)

Maia doesn't play freely — it follows a curriculum:

1. **Phase 1 (Learning the main line):** Maia plays the main line responses. The app coaches the user through each move, explaining the strategic purpose. ("Play Nf3 — this develops a piece and attacks the center.")

2. **Phase 2 (Natural deviations):** Once the user knows the main line, Maia starts deviating with moves a player at the user's ELO would actually try. The app recognizes the deviation and coaches the response. ("They played Bd7 instead of castling. This is passive — you can take advantage by...")

3. **Phase 3 (Wider variations):** Maia deviates earlier and plays trickier lines. The user encounters more of the opening tree naturally through gameplay.

4. **Phase 4 (Free play):** Maia plays whatever it wants at the user's ELO. The user has internalized the opening and handles deviations on their own. Coaching only fires on mistakes.

### Playing Black (Defenses)

Same flow in reverse. Maia plays the attacking side with the target opening. The app coaches the user's defensive responses.

### Session Length

Through the opening phase (~10-15 moves) by default. User can choose to continue into the middlegame.

## Real-time Coaching

After each move (user's or Maia's), the app may show a coaching bubble. Not every move — only when there's something worth saying.

### Coaching Categories

- **User's good move:** Brief reinforcement + why it's good
- **User's okay move:** What's better and why (gentle, not annoying)
- **User's mistake:** What goes wrong, what was better, show the line
- **Opponent's move:** What they're threatening, what the user's plan should be
- **Deviation from theory:** Name the variation, explain how the plan changes

### LLM Prompt Context

Each coaching call includes: FEN, move played, Stockfish eval (before and after), opening name/line, user's current ELO band, what phase of learning they're in.

## Spaced Repetition (Through Play)

- Positions the user struggled with get queued with SM-2 intervals
- Next session, the app starts from move 1 but steers Maia toward that problem position
- The "flashcard" is a mini-game, not a static board
- Intervals expand as the user demonstrates mastery

## Progression System

Three criteria combined into a composite score:

1. **Performance:** Accuracy vs Stockfish top-3 moves in the opening phase
2. **Win rate:** Against current Maia level
3. **Concept mastery:** Demonstrated understanding of concepts for current ELO band (center control, development, king safety, piece activity, etc.)

When the composite score crosses a threshold → Maia levels up, coaching introduces harder concepts.

## Board UI

- Drag-and-drop pieces with spring animations
- Move arrows (yellow=last move, green=suggested, red=threat)
- Square highlighting for tactical patterns
- Haptic feedback on captures, checks, checkmate
- Piece themes and board themes
- Coordinate toggle
- Flip board
- Sound effects for moves, captures, checks

## Explorer Mode (Secondary)

Free-form board where the user can:
- Make any moves and ask "why?" on any position
- Get LLM-generated explanations using Stockfish eval as context
- Explore "what if" variations after a coaching session
- Unlocks progressively as the user advances

## Data Model

**SQLite** (via GRDB.swift or similar):
- Opening tree: positions (FEN), moves, theory annotations, phase requirements
- User progress per opening: current phase, accuracy history, games played
- Spaced repetition schedule: position, interval, next review date, ease factor
- Game history: moves, coaching moments, key positions

**UserDefaults/SwiftData** for preferences and settings.

## Network Architecture

```
App startup → check WiFi → ping DGX (192.168.4.62:11434)
  ├── Reachable → use Ollama (Qwen 2.5 32B) for all LLM calls
  └── Not reachable → use Claude API (fallback)
```

Both use OpenAI-compatible API format — same Swift HTTP client, different base URL.

## Project Structure

```
ChessCoach/
├── App/                 # App entry, navigation, tab bar, settings
├── Models/
│   ├── Chess/           # Position, Move, Game, FEN/PGN parsing
│   ├── Opening/         # Opening tree, lines, curriculum phases
│   ├── Progress/        # ELO tracking, concept mastery, composite score
│   └── SpacedRep/       # SM-2 scheduler, review queue
├── Engine/
│   ├── Stockfish/       # C++ bridge for evaluation
│   └── Maia/            # Core ML model, ELO-adjustable play, curriculum steering
├── Views/
│   ├── Board/           # Board view, pieces, drag gestures, animations, overlays
│   ├── Home/            # Dashboard, opening picker, progress overview
│   ├── Session/         # Active play session + coaching bubbles
│   ├── Summary/         # Post-game recap, key moments replay
│   └── Explorer/        # Free exploration mode
├── Services/
│   ├── LLMService/      # Ollama/Claude client, tiered fallback, prompt builder
│   ├── CoachingService/ # Determines when to coach, generates context for LLM
│   └── CurriculumService/ # Controls Maia's opening selection, phase progression
├── Content/
│   └── openings.sqlite  # Bundled opening database with theory annotations
└── Resources/           # Piece SVGs, board themes, sounds, haptic patterns
```

## v1 Scope

**In scope:**
- Opening study: 5-10 popular openings (Italian, Sicilian, French, Caro-Kann, London, Queen's Gambit, King's Indian, Ruy Lopez, Scotch, Pirc)
- Play vs curriculum-guided Maia from move 1
- Real-time LLM coaching
- Spaced repetition through play
- Basic progression system
- Game-quality board with animations and haptics
- DGX Ollama + Claude API fallback

**Future (v2+):**
- Tactical pattern training
- Endgame training
- Positional concept lessons
- On-device small LLM for offline coaching
- More openings
- Daily training / streak system
