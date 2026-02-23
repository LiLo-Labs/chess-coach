import Foundation

struct OpeningMove: Codable, Sendable, Equatable {
    let uci: String
    let san: String
    let explanation: String
}

struct Opening: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let color: PlayerColor
    let difficulty: Int // 1-5
    let mainLine: [OpeningMove]

    enum PlayerColor: String, Codable, Sendable {
        case white
        case black
    }

    func isDeviation(atPly ply: Int, move: String) -> Bool {
        guard ply < mainLine.count else { return true }
        return mainLine[ply].uci != move
    }

    func expectedMove(atPly ply: Int) -> OpeningMove? {
        guard ply < mainLine.count else { return nil }
        return mainLine[ply]
    }
}
