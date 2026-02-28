import CoreML
import Foundation

/// Service wrapping the Maia 2 Core ML model for human-like move prediction.
/// Maia 2 predicts what a human at a given ELO would play, not the objectively best move.
///
/// Known upstream limitations (CSSLab/maia2):
/// - En passant probability ~0% due to training data encoding (Issue #7)
/// - Strange opening moves in some positions (Issue #5)
/// - Masked softmax bug in original code (PR #9) — mitigated here by
///   filtering to legal moves before applying softmax (see `predictMove`).
actor MaiaService: MovePredicting {
    private let model: MLModel
    private let moveList: [String] // 1880 UCI moves
    private let moveIndex: [String: Int] // UCI -> index

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        // Xcode compiles .mlpackage → .mlmodelc at build time
        guard let url = Bundle.main.url(forResource: AppConfig.maia.modelResourceName, withExtension: "mlmodelc") else {
            throw MaiaError.modelNotFound
        }
        self.model = try MLModel(contentsOf: url, configuration: config)
        let moves = try Self.loadMoveList()
        guard moves.count == AppConfig.maia.expectedMoveCount else {
            throw MaiaError.modelNotFound
        }
        self.moveList = moves
        var idx: [String: Int] = [:]
        for (i, m) in moves.enumerated() { idx[m] = i }
        self.moveIndex = idx
    }

    // MARK: - Public API

    /// Predict the most likely move a human at the given ELO would play.
    /// Returns top moves with probabilities, filtered to legal moves only.
    func predictMove(
        fen: String,
        legalMoves: [String],
        eloSelf: Int = 1500,
        eloOppo: Int = 1500
    ) throws -> [(move: String, probability: Float)] {
        let fenParts = fen.split(separator: " ")
        let isBlack = fenParts.count > 1 && fenParts[1] == "b"

        // Encode board (mirror if black)
        let boardTensor = encodeBoardFromFEN(fen, mirror: isBlack)

        // Map ELO to bucket index (0-10)
        let eloSelfIdx = eloToBucket(eloSelf)
        let eloOppoIdx = eloToBucket(eloOppo)

        // Create MLMultiArray inputs
        let boardsArray = try MLMultiArray(shape: [1, 1152], dataType: .float16)
        for i in 0..<1152 {
            boardsArray[[0, i] as [NSNumber]] = NSNumber(value: boardTensor[i])
        }

        let eloSelfArray = try MLMultiArray(shape: [1], dataType: .int32)
        eloSelfArray[0] = NSNumber(value: eloSelfIdx)

        let eloOppoArray = try MLMultiArray(shape: [1], dataType: .int32)
        eloOppoArray[0] = NSNumber(value: eloOppoIdx)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "boards": MLFeatureValue(multiArray: boardsArray),
            "elos_self": MLFeatureValue(multiArray: eloSelfArray),
            "elos_oppo": MLFeatureValue(multiArray: eloOppoArray),
        ])

        let output = try model.prediction(from: input)

        // Extract move logits (var_500, shape [1, 1880])
        guard let logitsArray = output.featureValue(for: "var_500")?.multiArrayValue else {
            throw MaiaError.predictionFailed
        }

        // Convert logits to probabilities via softmax, filtered to legal moves
        // If black, mirror the legal moves for lookup, then un-mirror results
        let adjustedLegal: [String]
        if isBlack {
            adjustedLegal = legalMoves.map { mirrorMove($0) }
        } else {
            adjustedLegal = legalMoves
        }

        // Get logits for legal moves only
        var legalLogits: [(originalMove: String, logit: Float)] = []
        for (i, move) in adjustedLegal.enumerated() {
            if let idx = moveIndex[move] {
                let logit = logitsArray[[0, idx] as [NSNumber]].floatValue
                legalLogits.append((legalMoves[i], logit))
            }
        }

        guard !legalLogits.isEmpty else {
            throw MaiaError.noLegalMoves
        }

        // Softmax over legal moves only
        guard let maxLogit = legalLogits.map(\.logit).max() else {
            throw MaiaError.noLegalMoves
        }
        let exps = legalLogits.map { exp($0.logit - maxLogit) }
        let sumExps = exps.reduce(0, +)
        let probs = exps.map { $0 / sumExps }

        var results: [(move: String, probability: Float)] = []
        for (i, item) in legalLogits.enumerated() {
            results.append((item.originalMove, probs[i]))
        }

        return results.sorted { $0.probability > $1.probability }
    }

    /// Sample a move from the probability distribution (more human-like than argmax).
    /// `recentMoves` is the game's UCI move history (both sides), used to avoid
    /// repetitive back-and-forth sequences (e.g. Ng1-f3, Nf3-g1, Ng1-f3…).
    func sampleMove(
        fen: String,
        legalMoves: [String],
        eloSelf: Int = 1500,
        eloOppo: Int = 1500,
        temperature: Float = 1.0,
        recentMoves: [String] = []
    ) throws -> String {
        var predictions = try predictMove(
            fen: fen,
            legalMoves: legalMoves,
            eloSelf: eloSelf,
            eloOppo: eloOppo
        )

        if temperature != 1.0 {
            // Apply temperature scaling
            let logProbs = predictions.map { log($0.probability) / temperature }
            guard let maxLP = logProbs.max() else { return predictions[0].move }
            let exps = logProbs.map { exp($0 - maxLP) }
            let sum = exps.reduce(0, +)
            predictions = zip(predictions, exps).map { ($0.0.move, $0.1 / sum) }
        }

        // Anti-repetition: detect and penalize moves that would continue a
        // back-and-forth pattern. Look at the last few bot moves (every other
        // ply) and suppress any move whose reverse was recently played.
        let penalized = applyRepetitionPenalty(predictions: predictions, recentMoves: recentMoves)

        let r = Float.random(in: 0..<1)
        var cumulative: Float = 0
        for pred in penalized {
            cumulative += pred.probability
            if r < cumulative {
                return pred.move
            }
        }
        return penalized.last?.move ?? predictions[0].move
    }

    // MARK: - Anti-Repetition

    /// Penalize moves that would create a back-and-forth pattern.
    /// Detects when a candidate move is the reverse of a recent bot move
    /// (e.g. bot played g1f3 two plies ago, now wants to play f3g1).
    private func applyRepetitionPenalty(
        predictions: [(move: String, probability: Float)],
        recentMoves: [String]
    ) -> [(move: String, probability: Float)] {
        guard recentMoves.count >= 2 else { return predictions }

        // Collect reverse moves the bot has played recently (last 6 bot moves = 12 plies).
        // Bot moves are at even or odd indices depending on color; we check all recent
        // moves and build a set of "reverse" UCI strings to penalize.
        let windowSize = min(recentMoves.count, 12)
        let window = recentMoves.suffix(windowSize)
        var reversesToPenalize: Set<String> = []
        for move in window {
            // Reverse of "e2e4" is "e4e2" (swap from/to squares)
            if move.count >= 4 {
                let from = String(move.prefix(2))
                let to = String(move.dropFirst(2).prefix(2))
                reversesToPenalize.insert("\(to)\(from)")
            }
        }

        // Check if any top predictions would be penalized
        let hasPenalizedMoves = predictions.contains { reversesToPenalize.contains(String($0.move.prefix(4))) }
        guard hasPenalizedMoves else { return predictions }

        // Penalize by reducing probability to near-zero (but not zero, in case all
        // moves are penalized). Redistribute weight to non-penalized moves.
        let penaltyFactor: Float = 0.01
        var adjusted = predictions.map { pred -> (move: String, probability: Float) in
            if reversesToPenalize.contains(String(pred.move.prefix(4))) {
                return (pred.move, pred.probability * penaltyFactor)
            }
            return pred
        }

        // Re-normalize
        let total = adjusted.map(\.probability).reduce(0, +)
        if total > 0 {
            adjusted = adjusted.map { ($0.move, $0.probability / total) }
        }

        return adjusted
    }

    // MARK: - Board Encoding

    /// Encode a FEN position into the 1152-float tensor Maia 2 expects.
    /// Channels: 0-5 white pieces (PNBRQK), 6-11 black pieces, 12 turn,
    /// 13-16 castling (WK, WQ, BK, BQ), 17 en passant.
    private func encodeBoardFromFEN(_ fen: String, mirror: Bool) -> [Float] {
        let parts = fen.split(separator: " ")
        let piecePlacement = String(parts[0])
        let castling = parts.count > 2 ? String(parts[2]) : "-"
        let enPassant = parts.count > 3 ? String(parts[3]) : "-"

        var tensor = [Float](repeating: 0, count: 18 * 8 * 8)

        // Parse piece placement
        // If mirroring (black's turn), we mirror the board by reversing rank order
        let ranks: [Substring]
        if mirror {
            ranks = piecePlacement.split(separator: "/").reversed()
        } else {
            ranks = Array(piecePlacement.split(separator: "/"))
        }

        // FEN ranks go from rank 8 (index 0) to rank 1 (index 7)
        // board_to_tensor uses row = square / 8, col = square % 8
        // where square 0 = a1, so row 0 = rank 1
        // FEN rank 0 in string = rank 8 = row 7
        for (rankIdx, rank) in ranks.enumerated() {
            let row = 7 - rankIdx // rank 8 -> row 7, rank 1 -> row 0
            var col = 0
            for ch in rank {
                if let digit = ch.wholeNumberValue {
                    col += digit
                } else {
                    let channelIdx = pieceToChannel(ch, mirror: mirror)
                    if channelIdx >= 0 {
                        tensor[channelIdx * 64 + row * 8 + col] = 1.0
                    }
                    col += 1
                }
            }
        }

        // Turn channel (12) - after mirroring, it's always white's turn
        if !mirror {
            // Original white's turn
            let turnStr = parts.count > 1 ? String(parts[1]) : "w"
            if turnStr == "w" {
                for i in 0..<64 {
                    tensor[12 * 64 + i] = 1.0
                }
            }
        } else {
            // Mirrored: black became white, so it's white's turn
            for i in 0..<64 {
                tensor[12 * 64 + i] = 1.0
            }
        }

        // Castling rights (channels 13-16)
        if !mirror {
            if castling.contains("K") { fillChannel(&tensor, channel: 13) }
            if castling.contains("Q") { fillChannel(&tensor, channel: 14) }
            if castling.contains("k") { fillChannel(&tensor, channel: 15) }
            if castling.contains("q") { fillChannel(&tensor, channel: 16) }
        } else {
            // Mirror: swap white/black castling
            if castling.contains("k") { fillChannel(&tensor, channel: 13) }
            if castling.contains("q") { fillChannel(&tensor, channel: 14) }
            if castling.contains("K") { fillChannel(&tensor, channel: 15) }
            if castling.contains("Q") { fillChannel(&tensor, channel: 16) }
        }

        // En passant (channel 17) - single square
        if enPassant != "-" {
            if let firstScalar = enPassant.unicodeScalars.first,
               let lastChar = enPassant.last,
               let rank = Int(String(lastChar)) {
                let file = Int(firstScalar.value) - Int(UnicodeScalar("a").value)
                let adjustedRank = mirror ? 7 - (rank - 1) : rank - 1
                tensor[17 * 64 + adjustedRank * 8 + file] = 1.0
            }
        }

        return tensor
    }

    private func pieceToChannel(_ piece: Character, mirror: Bool) -> Int {
        // Piece channels: 0=wP, 1=wN, 2=wB, 3=wR, 4=wQ, 5=wK, 6=bP...11=bK
        let mapping: [Character: Int] = [
            "P": 0, "N": 1, "B": 2, "R": 3, "Q": 4, "K": 5,
            "p": 6, "n": 7, "b": 8, "r": 9, "q": 10, "k": 11,
        ]
        guard var ch = mapping[piece] else { return -1 }
        if mirror {
            // Swap white and black pieces
            ch = ch < 6 ? ch + 6 : ch - 6
        }
        return ch
    }

    private func fillChannel(_ tensor: inout [Float], channel: Int) {
        let start = channel * 64
        for i in 0..<64 {
            tensor[start + i] = 1.0
        }
    }

    // MARK: - Move Mirroring

    /// Mirror a UCI move by flipping ranks (e.g., e2e4 -> e7e5).
    private func mirrorMove(_ uci: String) -> String {
        let chars = Array(uci)
        guard chars.count >= 4,
              let fromRankInt = Int(String(chars[1])),
              let toRankInt = Int(String(chars[3])) else {
            return uci // malformed UCI move: return as-is
        }
        let fromFile = chars[0]
        let fromRank = Character(String(9 - fromRankInt))
        let toFile = chars[2]
        let toRank = Character(String(9 - toRankInt))
        let promo = chars.count > 4 ? String(chars[4...]) : ""
        return "\(fromFile)\(fromRank)\(toFile)\(toRank)\(promo)"
    }

    // MARK: - ELO Mapping

    private func eloToBucket(_ elo: Int) -> Int32 {
        AppConfig.maia.eloToBucket(elo)
    }

    // MARK: - Move List

    /// Load the 1880 UCI moves from the bundled resource file.
    /// Order must match maia2's get_all_possible_moves() exactly.
    private static func loadMoveList() throws -> [String] {
        guard let url = Bundle.main.url(forResource: AppConfig.maia.movesResourceName, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MaiaError.modelNotFound
        }
        return content.split(separator: "\n").map(String.init)
    }

    // MARK: - Errors

    enum MaiaError: Error {
        case modelNotFound
        case predictionFailed
        case noLegalMoves
    }
}
