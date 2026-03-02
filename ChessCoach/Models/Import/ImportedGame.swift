import Foundation

struct ImportedGame: Codable, Sendable, Identifiable {
    let id: String                    // platform game ID
    let source: Source
    let pgn: String                   // raw PGN
    let playerUsername: String
    let playerColor: String           // "white" or "black"
    let playerELO: Int?
    let opponentUsername: String
    let opponentELO: Int?
    let outcome: Outcome
    let timeControl: String?
    let timeClass: String?            // rapid, blitz, bullet, classical
    let datePlayed: Date
    let moveCount: Int
    let sanMoves: [String]
    let uciMoves: [String]           // for OpeningDetector

    // Populated at import
    var detectedOpening: String?
    var detectedOpeningID: String?

    // Populated by background analysis
    var analysisComplete: Bool
    var mistakes: [AnalyzedMove]?
    var averageCentipawnLoss: Double?

    enum Source: String, Codable, Sendable { case lichess, chessCom }
    enum Outcome: String, Codable, Sendable { case win, loss, draw }
}

struct AnalyzedMove: Codable, Sendable, Identifiable {
    let id: Int                       // ply number
    let san: String
    let uci: String
    let fen: String                   // position before the move
    let evalBefore: Int               // centipawns
    let evalAfter: Int
    let bestMoveUCI: String?
    let bestMoveSAN: String?
    let centipawnLoss: Int
    let classification: MoveClass

    enum MoveClass: String, Codable, Sendable {
        case good         // <30cp
        case inaccuracy   // 30-100cp
        case mistake      // 100-300cp
        case blunder      // 300cp+
    }
}
