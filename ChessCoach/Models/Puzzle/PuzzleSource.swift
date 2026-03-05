import Foundation

/// Where puzzles originate from.
enum PuzzleSource {
    case standalone                // HomeView — mixed openings
    case opening(Opening)          // OpeningDetailView — scoped to that opening
}
