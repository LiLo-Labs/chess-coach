import Foundation

/// Computes a weighted style profile from the user's opening mastery data.
struct StyleProfile {
    struct TagWeight: Identifiable {
        let tag: String
        let weight: Double  // 0.0-1.0, normalized
        var id: String { tag }
    }

    let tagWeights: [TagWeight]
    let totalSessions: Int

    /// Human-readable label like "Tactical and Aggressive".
    var styleLabel: String {
        let topTags = tagWeights.prefix(2).map { $0.tag.capitalized }
        guard !topTags.isEmpty else { return "No style yet" }
        return topTags.joined(separator: " and ") + " player"
    }

    /// Whether the user has enough data for a meaningful profile (5+ sessions).
    var isReady: Bool { totalSessions >= 5 }

    /// Compute a style profile from familiarity data and the opening database.
    static func compute(familiarity: [String: OpeningFamiliarity], database: OpeningDatabase) -> StyleProfile {
        var tagCounts: [String: Double] = [:]
        var totalPositions = 0

        for (openingID, fam) in familiarity where !fam.positions.isEmpty {
            guard let opening = database.opening(byID: openingID),
                  let tags = opening.tags else { continue }
            let count = fam.positions.count
            totalPositions += count
            for tag in tags {
                tagCounts[tag, default: 0] += Double(count)
            }
        }

        guard totalPositions > 0 else {
            return StyleProfile(tagWeights: [], totalSessions: 0)
        }

        let maxCount = tagCounts.values.max() ?? 1.0
        let weights = tagCounts
            .map { TagWeight(tag: $0.key, weight: $0.value / maxCount) }
            .sorted { $0.weight > $1.weight }

        return StyleProfile(tagWeights: weights, totalSessions: totalPositions)
    }

    /// Returns openings matching the user's top tags that they haven't played yet.
    func recommendedOpenings(from database: OpeningDatabase, played: Set<String>) -> [Opening] {
        guard isReady else { return [] }
        let topTags = Set(tagWeights.prefix(3).map(\.tag))
        return database.openings(withAnyTag: topTags)
            .filter { !played.contains($0.id) }
            .sorted { ($0.difficulty, $0.name) < ($1.difficulty, $1.name) }
    }
}
