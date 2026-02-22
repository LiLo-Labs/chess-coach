# ChessCoach Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a SwiftUI iOS app that teaches chess openings through play-first learning against curriculum-guided Maia 2, with real-time LLM coaching.

**Architecture:** Native SwiftUI app using ChessKit for game logic, ChessKit Engine for Stockfish analysis, ChessboardKit for the board UI, Maia 2 (Core ML) for human-like opponent, and a tiered LLM service (DGX Ollama primary, Claude API fallback) for coaching explanations.

**Tech Stack:** Swift 6, SwiftUI, ChessKit, ChessKit Engine (Stockfish 17), ChessboardKit, Core ML (Maia 2), GRDB.swift (SQLite), URLSession (LLM API)

**Development environment:** macOS, Xcode, Claude Code on Mac

---

## Task 1: Xcode Project Setup + Dependencies

Create Xcode iOS App project (SwiftUI lifecycle, "ChessCoach", bundle ID com.chesscoach.app).

Add Swift Package dependencies:
- `https://github.com/chesskit-app/chesskit-swift.git` (branch: main)
- `https://github.com/chesskit-app/chesskit-engine.git` (branch: main)
- `https://github.com/rohanrhu/ChessboardKit.git` (branch: main)
- `https://github.com/groue/GRDB.swift.git` (from: 7.0.0)

Create folder structure: App/, Models/, Engine/, Views/, Services/, Content/, Resources/

Build to verify (Cmd+B). Commit.

---

## Task 2: GameState Model + Chess Board View

### Step 1: Write failing test (GameState)

```swift
// ChessCoachTests/Models/GameStateTests.swift
import Testing
import ChessKit
@testable import ChessCoach

@Test func gameStateStartsFromInitialPosition() {
    let state = GameState()
    #expect(state.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    #expect(state.moveHistory.isEmpty)
    #expect(state.isWhiteTurn)
}

@Test func gameStateMakesLegalMove() {
    var state = GameState()
    let moved = state.makeMove(from: "e2", to: "e4")
    #expect(moved)
    #expect(state.moveHistory.count == 1)
}

@Test func gameStateRejectsIllegalMove() {
    var state = GameState()
    let moved = state.makeMove(from: "e2", to: "e5")
    #expect(!moved)
}
```

### Step 2: Implement GameState

```swift
// ChessCoach/Models/Chess/GameState.swift
import Foundation
import ChessKit

@Observable
class GameState {
    private(set) var board: Board
    private(set) var moveHistory: [(from: Square, to: Square)] = []

    var fen: String { board.position.fen }
    var isWhiteTurn: Bool { board.position.sideToMove == .white }

    init(fen: String? = nil) {
        if let fen {
            self.board = Board(position: Position(fen: fen)!)
        } else {
            self.board = Board()
        }
    }

    @discardableResult
    func makeMove(from: String, to: String) -> Bool {
        let fromSquare = Square(from)
        let toSquare = Square(to)
        let legalMoves = board.legalMoves(forPieceAt: fromSquare)
        guard legalMoves.contains(where: { $0.target == toSquare }) else { return false }
        board.move(pieceAt: fromSquare, to: toSquare)
        moveHistory.append((from: fromSquare, to: toSquare))
        return true
    }
}
```

### Step 3: Run tests (Cmd+U), verify pass

### Step 4: Implement GameBoardView

```swift
// ChessCoach/Views/Board/GameBoardView.swift
import SwiftUI
import ChessboardKit

struct GameBoardView: View {
    @Bindable var gameState: GameState
    var onMove: ((String, String) -> Void)?

    @State private var boardModel: ChessboardModel

    init(gameState: GameState, onMove: ((String, String) -> Void)? = nil) {
        self.gameState = gameState
        self.onMove = onMove
        self._boardModel = State(initialValue: ChessboardModel(fen: gameState.fen))
    }

    var body: some View {
        Chessboard(chessboardModel: boardModel)
            .onMove { move, isLegal, from, to, lan, promotionPiece in
                if isLegal {
                    gameState.makeMove(from: from.description, to: to.description)
                    boardModel.setFEN(gameState.fen)
                    onMove?(from.description, to.description)
                }
            }
            .onChange(of: gameState.fen) { _, newFen in
                boardModel.setFEN(newFen)
            }
    }
}
```

### Step 5: Wire into ContentView, build+run on simulator, commit

---

## Task 3: Stockfish Engine Integration

### Step 1: Download Stockfish NNUE files

Download `nn-1111cefa1111.nnue` and `nn-37f18f62d772.nnue`, add to Resources/ in Xcode bundle.

### Step 2: Write failing test

```swift
// ChessCoachTests/Engine/StockfishServiceTests.swift
import Testing
@testable import ChessCoach

@Test func stockfishFindsMove() async {
    let service = StockfishService()
    await service.start()
    let move = await service.bestMove(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        depth: 10
    )
    #expect(move != nil)
    #expect(!move!.isEmpty)
    await service.stop()
}
```

### Step 3: Implement StockfishService

```swift
// ChessCoach/Engine/StockfishService.swift
import Foundation
import ChessKitEngine

actor StockfishService {
    private var engine: Engine?

    func start() async {
        engine = Engine(type: .stockfish)
        if let path = Bundle.main.path(forResource: "nn-1111cefa1111", ofType: "nnue") {
            await engine?.send(.setoption(id: "EvalFile", value: path))
        }
        engine?.start()
        try? await Task.sleep(for: .milliseconds(500))
    }

    func stop() async {
        await engine?.send(.quit)
        engine = nil
    }

    func bestMove(fen: String, depth: Int = 15) async -> String? {
        guard let engine else { return nil }
        await engine.send(.position(fen: fen))
        await engine.send(.go(depth: depth))
        // Parse bestmove from response stream
        for await response in await engine.responseStream! {
            if case .bestMove(let move) = response {
                return move
            }
        }
        return nil
    }

    func topMoves(fen: String, count: Int = 3, depth: Int = 15) async -> [String] {
        guard let engine else { return [] }
        await engine.send(.setoption(id: "MultiPV", value: "\(count)"))
        await engine.send(.position(fen: fen))
        await engine.send(.go(depth: depth))
        var moves: [String] = []
        for await response in await engine.responseStream! {
            if case .bestMove(let move) = response {
                moves.append(move)
                break
            }
        }
        await engine.send(.setoption(id: "MultiPV", value: "1"))
        return moves
    }
}
```

> **Note:** Exact ChessKitEngine response parsing API may need adjustment. Consult library docs during implementation.

### Step 4: Run tests, verify pass, commit

---

## Task 4: LLM Service (Ollama + Claude Fallback)

### Step 1: Write failing test

```swift
// ChessCoachTests/Services/LLMServiceTests.swift
import Testing
@testable import ChessCoach

@Test func llmServiceBuildsPrompt() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 30,
        openingName: "King's Pawn Opening",
        userELO: 600,
        phase: .learningMainLine,
        moveCategory: .goodMove
    )
    let prompt = LLMService.buildPrompt(for: context)
    #expect(prompt.contains("e4"))
    #expect(prompt.contains("beginner"))
}
```

### Step 2: Implement types and LLMService

```swift
// ChessCoach/Services/LLMService.swift
import Foundation

enum MoveCategory { case goodMove, okayMove, mistake, opponentMove, deviation }
enum LearningPhase: Codable { case learningMainLine, naturalDeviations, widerVariations, freePlay }

struct CoachingContext {
    let fen: String
    let lastMove: String
    let scoreBefore: Int
    let scoreAfter: Int
    let openingName: String
    let userELO: Int
    let phase: LearningPhase
    let moveCategory: MoveCategory
}

actor LLMService {
    private let config = LLMConfig()
    private var provider: LLMProvider = .claude

    func detectProvider() async { provider = await config.detectProvider() }

    static func buildPrompt(for context: CoachingContext) -> String {
        let level = context.userELO < 800 ? "complete beginner" : "beginner"
        let change = context.scoreAfter - context.scoreBefore
        return """
        You are a friendly chess coach teaching a \(level) (ELO ~\(context.userELO)).
        Opening: \(context.openingName)
        Position (FEN): \(context.fen)
        Last move: \(context.lastMove)
        Score change: \(change > 0 ? "+" : "")\(change) centipawns
        Give a brief (1-2 sentence) explanation for a beginner. Focus on WHY, not just WHAT.
        Use simple language. Reference concrete pieces and squares on the board.
        """
    }

    func getCoaching(for context: CoachingContext) async throws -> String {
        let prompt = Self.buildPrompt(for: context)
        switch provider {
        case .ollama: return try await callOllama(prompt: prompt)
        case .claude: return try await callClaude(prompt: prompt)
        }
    }

    private func callOllama(prompt: String) async throws -> String {
        let url = config.ollamaBaseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "qwen2.5:32b",
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return resp.message.content
    }

    private func callClaude(prompt: String) async throws -> String {
        let url = config.claudeBaseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 200,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return resp.content.first?.text ?? ""
    }
}

// LLMConfig.swift
enum LLMProvider { case ollama, claude }

class LLMConfig {
    var ollamaBaseURL: URL { URL(string: "http://192.168.4.62:11434")! }
    var claudeBaseURL: URL { URL(string: "https://api.anthropic.com")! }
    var claudeAPIKey: String { UserDefaults.standard.string(forKey: "claude_api_key") ?? "" }

    func detectProvider() async -> LLMProvider {
        let url = ollamaBaseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return .ollama }
        } catch {}
        return .claude
    }
}

struct OllamaResponse: Codable { struct Message: Codable { let content: String }; let message: Message }
struct ClaudeResponse: Codable { struct Content: Codable { let text: String }; let content: [Content] }
```

### Step 3: Run tests, verify pass, commit

---

## Task 5: Opening Database

### Step 1: Write failing test

```swift
// ChessCoachTests/Models/OpeningTests.swift
import Testing
@testable import ChessCoach

@Test func databaseHasItalianGame() {
    let db = OpeningDatabase()
    let italian = db.opening(named: "Italian Game")
    #expect(italian != nil)
    #expect(italian!.mainLine.count >= 6)
}

@Test func openingDetectsDeviation() {
    let db = OpeningDatabase()
    let italian = db.opening(named: "Italian Game")!
    #expect(italian.isDeviation(atPly: 1, move: "d7d5"))
    #expect(!italian.isDeviation(atPly: 1, move: "e7e5"))
}
```

### Step 2: Implement Opening + OpeningDatabase

Opening model with name, color, mainLine (array of OpeningMove with uci, san, explanation), difficulty.

OpeningDatabase with built-in Italian Game and London System (6 moves each with beginner-friendly explanations).

### Step 3: Run tests, verify pass, commit

---

## Task 6: Curriculum Service

### Step 1: Write failing test

Test that phase 1 forces main line, phase 2 allows late deviations, phase 4 never overrides.

### Step 2: Implement CurriculumService

`getMaiaOverride(atPly:)` returns forced UCI move or nil based on learning phase.
`categorizeUserMove(atPly:move:stockfishScore:)` returns MoveCategory.

### Step 3: Run tests, verify pass, commit

---

## Task 7: Coaching Service

### Step 1: Write failing test

Test shouldCoach() logic: always coaches during learning phase, only mistakes during free play.

### Step 2: Implement CoachingService

Decides when to coach based on phase + move category. Uses pre-written explanations for main line moves, LLM for everything else.

### Step 3: Run tests, verify pass, commit

---

## Task 8: Session View (Main Play Screen)

### Step 1: Implement SessionViewModel

Orchestrates: GameState + CurriculumService + CoachingService + StockfishService. Handles user moves, gets coaching, plays Maia/Stockfish responses.

### Step 2: Implement CoachingBubble (SwiftUI)

Material background, lightbulb icon, text with loading state. Spring animation on appear.

### Step 3: Implement SessionView

Board + coaching bubble + header (opening name, move count) + end session button. Session complete overlay when opening phase finishes.

### Step 4: Build+run on simulator, commit

---

## Task 9: Home Screen + Opening Picker

### Step 1: Implement OpeningCard

Shows name, description, difficulty stars, color indicator.

### Step 2: Implement HomeView

NavigationStack with ScrollView of OpeningCards. Tap navigates to SessionView via fullScreenCover.

### Step 3: Update ContentView, build+run, commit

---

## Task 10: Maia 2 Core ML Conversion (DGX)

Run on DGX: install maia2 + coremltools, inspect model architecture, trace with torch.jit, convert to .mlpackage via coremltools. Copy to Mac.

**Note:** Input shapes must be verified from maia2 source. Conversion script is a starting point that needs adaptation.

---

## Task 11: Maia Move Service (Core ML on device)

### Step 1: Add .mlpackage to Xcode, implement MaiaService

FEN encoding (matching maia2's training format), Core ML inference, move probability decoding.

### Step 2: Wire into SessionViewModel as opponent (replacing Stockfish placeholder)

### Step 3: Test on device, commit

---

## Task 12: Spaced Repetition (SM-2)

### Step 1: Write failing test for ReviewItem and SpacedRepScheduler

### Step 2: Implement SM-2 algorithm

ReviewItem tracks interval, ease factor, repetitions. SpacedRepScheduler manages queue and returns due items as gameplay targets.

### Step 3: Run tests, verify pass, commit

---

## Task 13: Progress Tracking + Persistence

### Step 1: Implement UserProgress

Tracks per-opening accuracy, games played/won, current phase. Auto-promotes phases based on composite score (accuracy + win rate + games played).

### Step 2: Implement PersistenceService

Save/load UserProgress and ReviewItems via UserDefaults (JSON encoded). Upgrade to GRDB later if needed.

### Step 3: Wire into SessionViewModel and HomeView, commit

---

## Build Order

| Task | Component | Depends On |
|------|-----------|------------|
| 1 | Xcode project + deps | — |
| 2 | Board + GameState | 1 |
| 3 | Stockfish integration | 1 |
| 4 | LLM service | 1 |
| 5 | Opening database | 1 |
| 6 | Curriculum service | 5 |
| 7 | Coaching service | 3, 4, 6 |
| 8 | Session view | 2, 7 |
| 9 | Home screen | 5, 8 |
| 10 | Maia Core ML (DGX) | — |
| 11 | Maia service | 10 |
| 12 | Spaced repetition | 5 |
| 13 | Progress + persistence | 6, 12 |

**Tasks 1-9 = working app with Stockfish as placeholder opponent.**
**Tasks 10-11 = human-like Maia opponent.**
**Tasks 12-13 = learning progression system.**
