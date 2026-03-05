import Foundation
import SwiftUI

/// Unified per-ply coaching feed entry used across GamePlay, Trainer, and Session modes.
/// Per-ply is the atomic unit; move-pair grouping is done at the view layer via `FeedMovePair`.
///
/// Ply convention: always stored as 0-based internally (white = ply%2==0).
/// Use `init(oneBased:...)` when converting from 1-based sources (TrainerCoachingEntry).
@Observable
@MainActor
final class FeedEntry: Identifiable {
    let id: Int                 // Stable ID derived from ply
    let ply: Int                // 0-based ply index
    let moveNumber: Int         // 1-based full move number
    let moveSAN: String
    let moveUCI: String
    let isPlayerMove: Bool
    var coaching: String
    let category: MoveCategory
    let soundness: Int?
    let scoreCategory: ScoreCategory?
    let openingName: String?
    let isInBook: Bool
    var fen: String?
    var fenBeforeMove: String?

    // Deviation (session modes)
    var isDeviation: Bool
    var expectedSAN: String?
    var expectedUCI: String?
    var playedUCI: String?

    // Coaching tier
    var isLLMCoaching: Bool = false

    // On-demand LLM explanation
    var explanation: String?
    var isExplaining: Bool = false

    var isWhiteMove: Bool { ply % 2 == 0 }

    var moveLabel: String {
        isWhiteMove ? "\(moveNumber). \(moveSAN)" : "\(moveNumber)... \(moveSAN)"
    }

    init(
        ply: Int,
        moveNumber: Int,
        moveSAN: String,
        moveUCI: String = "",
        isPlayerMove: Bool,
        coaching: String,
        category: MoveCategory = .goodMove,
        soundness: Int? = nil,
        scoreCategory: ScoreCategory? = nil,
        openingName: String? = nil,
        isInBook: Bool = false,
        fen: String? = nil,
        fenBeforeMove: String? = nil,
        isDeviation: Bool = false,
        expectedSAN: String? = nil,
        expectedUCI: String? = nil,
        playedUCI: String? = nil
    ) {
        self.id = ply
        self.ply = ply
        self.moveNumber = moveNumber
        self.moveSAN = moveSAN
        self.moveUCI = moveUCI
        self.isPlayerMove = isPlayerMove
        self.coaching = coaching
        self.category = category
        self.soundness = soundness
        self.scoreCategory = scoreCategory
        self.openingName = openingName
        self.isInBook = isInBook
        self.fen = fen
        self.fenBeforeMove = fenBeforeMove
        self.isDeviation = isDeviation
        self.expectedSAN = expectedSAN
        self.expectedUCI = expectedUCI
        self.playedUCI = playedUCI
    }

    /// Create from a 1-based ply source (TrainerCoachingEntry convention where white = ply%2==1).
    /// Converts to 0-based internally.
    convenience init(
        oneBasedPly: Int,
        moveNumber: Int,
        moveSAN: String,
        moveUCI: String = "",
        isPlayerMove: Bool,
        coaching: String,
        category: MoveCategory = .goodMove,
        soundness: Int? = nil,
        scoreCategory: ScoreCategory? = nil,
        openingName: String? = nil,
        isInBook: Bool = false,
        fen: String? = nil
    ) {
        self.init(
            ply: oneBasedPly - 1,
            moveNumber: moveNumber,
            moveSAN: moveSAN,
            moveUCI: moveUCI,
            isPlayerMove: isPlayerMove,
            coaching: coaching,
            category: category,
            soundness: soundness,
            scoreCategory: scoreCategory,
            openingName: openingName,
            isInBook: isInBook,
            fen: fen
        )
    }
}

// MARK: - Move-Pair Grouping

/// A pair of white + black moves grouped by move number for display.
struct FeedMovePair: Identifiable {
    let white: FeedEntry?
    let black: FeedEntry?

    var id: String {
        "\(white?.id ?? 0)-\(black?.id ?? 0)"
    }

    var moveNumber: Int { white?.moveNumber ?? black?.moveNumber ?? 0 }
    var latestPly: Int { black?.ply ?? white?.ply ?? 0 }

    /// The primary entry to display coaching for (prefer player move).
    var primaryEntry: FeedEntry? {
        if let w = white, w.isPlayerMove { return w }
        if let b = black, b.isPlayerMove { return b }
        return white ?? black
    }

    /// Group sorted entries into move pairs (newest first).
    @MainActor static func group(_ entries: [FeedEntry]) -> [FeedMovePair] {
        var pairs: [FeedMovePair] = []
        var i = 0
        let sorted = entries.sorted { $0.ply < $1.ply }
        while i < sorted.count {
            let entry = sorted[i]
            if entry.isWhiteMove {
                let blackEntry = (i + 1 < sorted.count && !sorted[i + 1].isWhiteMove)
                    ? sorted[i + 1] : nil
                pairs.append(FeedMovePair(white: entry, black: blackEntry))
                i += blackEntry != nil ? 2 : 1
            } else {
                pairs.append(FeedMovePair(white: nil, black: entry))
                i += 1
            }
        }
        return pairs.reversed()
    }
}

// MARK: - Shared Color Helpers

enum FeedColors {
    static func moveColor(_ entry: FeedEntry) -> SwiftUI.Color {
        if entry.category == .mistake { return AppColor.error }
        if entry.category == .deviation { return .orange }
        if !entry.isPlayerMove { return SwiftUI.Color(white: 0.65) }
        return .white
    }

    static func categoryColor(_ sc: ScoreCategory) -> SwiftUI.Color {
        switch sc {
        case .masterful: return AppColor.gold
        case .strong: return AppColor.success
        case .solid: return AppColor.info
        case .developing: return AppColor.warning
        case .needsWork: return AppColor.error
        }
    }

    static func moveCategoryColor(_ mc: MoveCategory) -> SwiftUI.Color {
        switch mc {
        case .goodMove: return AppColor.success
        case .okayMove: return AppColor.info
        case .mistake: return AppColor.error
        case .deviation: return AppColor.warning
        case .opponentMove: return AppColor.secondaryText
        }
    }
}

// MARK: - MoveCategory Feed Label

extension MoveCategory {
    var feedLabel: String {
        switch self {
        case .goodMove: return "Good"
        case .okayMove: return "OK"
        case .mistake: return "Mistake"
        case .deviation: return "Deviation"
        case .opponentMove: return "Opponent"
        }
    }
}

// MARK: - Bridging from Legacy Types

extension FeedEntry {
    /// Convert from CoachingEntry (already 0-based ply).
    static func from(_ entry: CoachingEntry) -> FeedEntry {
        let fe = FeedEntry(
            ply: entry.ply,
            moveNumber: entry.moveNumber,
            moveSAN: entry.moveSAN,
            moveUCI: entry.moveUCI,
            isPlayerMove: entry.isPlayerMove,
            coaching: entry.coaching,
            category: entry.category,
            soundness: entry.soundness,
            scoreCategory: entry.scoreCategory,
            openingName: entry.openingName,
            isInBook: entry.isInBook,
            fen: entry.fen,
            fenBeforeMove: entry.fenBeforeMove,
            isDeviation: entry.isDeviation,
            expectedSAN: entry.expectedSAN,
            expectedUCI: entry.expectedUCI,
            playedUCI: entry.playedUCI
        )
        fe.explanation = entry.explanation
        fe.isExplaining = entry.isExplaining
        return fe
    }

    /// Convert from TrainerCoachingEntry (1-based ply).
    static func from(_ entry: TrainerCoachingEntry) -> FeedEntry {
        let fe = FeedEntry(
            oneBasedPly: entry.ply,
            moveNumber: entry.moveNumber,
            moveSAN: entry.moveSAN,
            isPlayerMove: entry.isPlayerMove,
            coaching: entry.coaching,
            category: entry.category,
            soundness: entry.soundness,
            scoreCategory: entry.scoreCategory,
            openingName: entry.openingName,
            isInBook: entry.isInBook,
            fen: entry.fen
        )
        fe.explanation = entry.explanation
        fe.isExplaining = entry.isExplaining
        return fe
    }
}
