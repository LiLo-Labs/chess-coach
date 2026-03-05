import Foundation
import ChessKit

/// Unified mode enum for all gameplay screens.
enum GamePlayMode {
    case trainer(personality: OpponentPersonality, engineMode: TrainerEngineMode, playerColor: PieceColor, botELO: Int)
    case guided(opening: Opening, lineID: String?)
    case unguided(opening: Opening, lineID: String?)
    case practice(opening: Opening, lineID: String?)
    case puzzle(opening: Opening?, source: PuzzleSource)

    var isTrainer: Bool {
        if case .trainer = self { return true }
        return false
    }

    var isPuzzle: Bool {
        if case .puzzle = self { return true }
        return false
    }

    var isSession: Bool { !isTrainer && !isPuzzle }

    var opening: Opening? {
        switch self {
        case .trainer: return nil
        case .guided(let o, _), .unguided(let o, _), .practice(let o, _): return o
        case .puzzle(let o, _): return o
        }
    }

    var lineID: String? {
        switch self {
        case .trainer: return nil
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
        case .trainer: return nil
        case .guided: return .guided
        case .unguided: return .unguided
        case .practice: return .practice
        case .puzzle: return nil
        }
    }
}
