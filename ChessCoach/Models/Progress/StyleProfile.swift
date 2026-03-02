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

    /// Compute a style profile from mastery data and the opening database.
    static func compute(mastery: [String: OpeningMastery], database: OpeningDatabase) -> StyleProfile {
        var tagCounts: [String: Double] = [:]
        var totalSessions = 0

        for (openingID, m) in mastery where m.sessionsPlayed > 0 {
            guard let opening = database.opening(byID: openingID),
                  let tags = opening.tags else { continue }
            let sessions = Double(m.sessionsPlayed)
            totalSessions += m.sessionsPlayed
            for tag in tags {
                tagCounts[tag, default: 0] += sessions
            }
        }

        guard totalSessions > 0 else {
            return StyleProfile(tagWeights: [], totalSessions: 0)
        }

        let maxCount = tagCounts.values.max() ?? 1.0
        let weights = tagCounts
            .map { TagWeight(tag: $0.key, weight: $0.value / maxCount) }
            .sorted { $0.weight > $1.weight }

        return StyleProfile(tagWeights: weights, totalSessions: totalSessions)
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
