import Foundation

/// Fetches games from Lichess and Chess.com public APIs.
/// Uses URLSession async/await (same pattern as LLMService).
@MainActor @Observable
final class GameImportService {

    enum ImportSource: String, CaseIterable, Sendable {
        case lichess = "Lichess"
        case chessCom = "Chess.com"
    }

    enum ImportError: LocalizedError, Sendable {
        case invalidUsername
        case networkError(String)
        case noGamesFound
        case parsingFailed

        var errorDescription: String? {
            switch self {
            case .invalidUsername: return "Invalid username"
            case .networkError(let msg): return "Network error: \(msg)"
            case .noGamesFound: return "No games found for this user"
            case .parsingFailed: return "Failed to parse game data"
            }
        }
    }

    var fetchProgress: Double = 0
    var isFetching = false

    private var fetchTask: Task<[ImportedGame], Error>?
    private let openingDetector = OpeningDetector()

    func fetchGames(username: String, source: ImportSource, maxGames: Int = 50) async throws -> [ImportedGame] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidUsername }

        isFetching = true
        fetchProgress = 0

        let task = Task<[ImportedGame], Error> {
            switch source {
            case .lichess:
                return try await fetchLichessGames(username: trimmed, maxGames: maxGames)
            case .chessCom:
                return try await fetchChessComGames(username: trimmed, maxGames: maxGames)
            }
        }
        fetchTask = task

        do {
            let games = try await task.value
            isFetching = false
            guard !games.isEmpty else { throw ImportError.noGamesFound }
            return games
        } catch {
            isFetching = false
            throw error
        }
    }

    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
        fetchProgress = 0
    }

    // MARK: - Lichess

    private func fetchLichessGames(username: String, maxGames: Int) async throws -> [ImportedGame] {
        let urlStr = "https://lichess.org/api/games/user/\(username)?max=\(maxGames)&rated=true&moves=true&opening=true&tags=true&clocks=false&evals=false"
        guard let url = URL(string: urlStr) else { throw ImportError.invalidUsername }

        var request = URLRequest(url: url)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImportError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ImportError.invalidUsername
            }
            throw ImportError.networkError("HTTP \(httpResponse.statusCode)")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError.parsingFailed
        }

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var games: [ImportedGame] = []

        for (index, line) in lines.enumerated() {
            try Task.checkCancellation()

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let game = parseLichessGame(json, username: username) {
                games.append(game)
            }

            await MainActor.run {
                self.fetchProgress = Double(index + 1) / Double(lines.count)
            }
        }

        return games
    }

    private func parseLichessGame(_ json: [String: Any], username: String) -> ImportedGame? {
        guard let gameID = json["id"] as? String,
              let players = json["players"] as? [String: Any],
              let white = players["white"] as? [String: Any],
              let black = players["black"] as? [String: Any],
              let movesStr = json["moves"] as? String else {
            return nil
        }

        let whiteUser = (white["user"] as? [String: Any])?["name"] as? String ?? "Unknown"
        let blackUser = (black["user"] as? [String: Any])?["name"] as? String ?? "Unknown"
        let whiteRating = white["rating"] as? Int
        let blackRating = black["rating"] as? Int

        let isWhite = whiteUser.lowercased() == username.lowercased()
        let playerColor = isWhite ? "white" : "black"
        let playerUsername = isWhite ? whiteUser : blackUser
        let opponentUsername = isWhite ? blackUser : whiteUser
        let playerELO = isWhite ? whiteRating : blackRating
        let opponentELO = isWhite ? blackRating : whiteRating

        // Determine outcome
        let winner = json["winner"] as? String
        let status = json["status"] as? String ?? ""
        let outcome: ImportedGame.Outcome
        if status == "draw" || status == "stalemate" || winner == nil {
            if status == "draw" || status == "stalemate" {
                outcome = .draw
            } else {
                // No winner and not draw = ongoing or aborted; skip
                outcome = .draw
            }
        } else if let winner {
            outcome = (winner == playerColor) ? .win : .loss
        } else {
            outcome = .draw
        }

        // Parse moves
        let sanTokens = movesStr.split(separator: " ").map(String.init)
        guard !sanTokens.isEmpty else { return nil }

        // Replay to get UCI moves
        guard let replay = PGNParser.replayMoves(sanTokens) else { return nil }

        // Opening detection
        let detection = openingDetector.detect(moves: replay.uciMoves)

        // Time info
        let speed = json["speed"] as? String
        let clock = json["clock"] as? [String: Any]
        let timeControl: String?
        if let initial = clock?["initial"] as? Int, let increment = clock?["increment"] as? Int {
            timeControl = "\(initial / 60)+\(increment)"
        } else {
            timeControl = nil
        }

        // Date
        let createdAt = json["createdAt"] as? Int64 ?? 0
        let datePlayed = Date(timeIntervalSince1970: Double(createdAt) / 1000.0)

        // Opening from Lichess API
        let openingInfo = json["opening"] as? [String: Any]
        let lichessOpeningName = openingInfo?["name"] as? String

        return ImportedGame(
            id: "lichess_\(gameID)",
            source: .lichess,
            pgn: movesStr,
            playerUsername: playerUsername,
            playerColor: playerColor,
            playerELO: playerELO,
            opponentUsername: opponentUsername,
            opponentELO: opponentELO,
            outcome: outcome,
            timeControl: timeControl,
            timeClass: speed,
            datePlayed: datePlayed,
            moveCount: sanTokens.count,
            sanMoves: sanTokens,
            uciMoves: replay.uciMoves,
            detectedOpening: detection.best?.opening.name ?? lichessOpeningName,
            detectedOpeningID: detection.best?.opening.id,
            analysisComplete: false,
            mistakes: nil,
            averageCentipawnLoss: nil
        )
    }

    // MARK: - Chess.com

    private func fetchChessComGames(username: String, maxGames: Int) async throws -> [ImportedGame] {
        // Step 1: Get archive URLs
        let archivesURL = URL(string: "https://api.chess.com/pub/player/\(username)/games/archives")!
        var archiveRequest = URLRequest(url: archivesURL)
        archiveRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let (archiveData, archiveResponse) = try await URLSession.shared.data(for: archiveRequest)

        guard let httpResponse = archiveResponse as? HTTPURLResponse else {
            throw ImportError.networkError("Invalid response")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw ImportError.invalidUsername
            }
            throw ImportError.networkError("HTTP \(httpResponse.statusCode)")
        }

        guard let archiveJSON = try? JSONSerialization.jsonObject(with: archiveData) as? [String: Any],
              let archives = archiveJSON["archives"] as? [String] else {
            throw ImportError.parsingFailed
        }

        guard !archives.isEmpty else { throw ImportError.noGamesFound }

        // Step 2: Fetch most recent archives (work backwards)
        var allGames: [ImportedGame] = []
        let recentArchives = archives.suffix(3).reversed() // last 3 months

        for (archiveIndex, archiveURLStr) in recentArchives.enumerated() {
            try Task.checkCancellation()

            guard let archiveURL = URL(string: archiveURLStr) else { continue }
            var req = URLRequest(url: archiveURL)
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let games = json["games"] as? [[String: Any]] else {
                continue
            }

            for game in games.reversed() {
                try Task.checkCancellation()
                if let imported = parseChessComGame(game, username: username) {
                    allGames.append(imported)
                    if allGames.count >= maxGames { break }
                }
            }

            await MainActor.run {
                self.fetchProgress = Double(archiveIndex + 1) / Double(recentArchives.count)
            }

            if allGames.count >= maxGames { break }
        }

        return Array(allGames.prefix(maxGames))
    }

    private func parseChessComGame(_ json: [String: Any], username: String) -> ImportedGame? {
        guard let pgn = json["pgn"] as? String,
              let white = json["white"] as? [String: Any],
              let black = json["black"] as? [String: Any],
              let whiteUser = white["username"] as? String,
              let blackUser = black["username"] as? String else {
            return nil
        }

        // Parse PGN
        guard let parsed = PGNParser.parse(pgn) else { return nil }
        guard !parsed.sanMoves.isEmpty else { return nil }

        // Replay to get UCI moves
        guard let replay = PGNParser.replayMoves(parsed.sanMoves) else { return nil }

        let isWhite = whiteUser.lowercased() == username.lowercased()
        let playerColor = isWhite ? "white" : "black"
        let playerUsername = isWhite ? whiteUser : blackUser
        let opponentUsername = isWhite ? blackUser : whiteUser
        let playerELO = (isWhite ? white : black)["rating"] as? Int
        let opponentELO = (isWhite ? black : white)["rating"] as? Int

        // Determine outcome from result field
        let whiteResult = white["result"] as? String ?? ""
        let blackResult = black["result"] as? String ?? ""
        let playerResult = isWhite ? whiteResult : blackResult
        let outcome: ImportedGame.Outcome
        switch playerResult {
        case "win": outcome = .win
        case "checkmated", "timeout", "resigned", "abandoned": outcome = .loss
        default:
            if playerResult.contains("draw") || playerResult == "stalemate" ||
               playerResult == "repetition" || playerResult == "insufficient" ||
               playerResult == "agreed" || playerResult == "50move" || playerResult == "timevsinsufficient" {
                outcome = .draw
            } else {
                outcome = .loss
            }
        }

        // Game URL as ID
        let gameURL = json["url"] as? String ?? UUID().uuidString
        let gameID = gameURL.components(separatedBy: "/").last ?? UUID().uuidString

        // Time
        let timeControl = json["time_control"] as? String
        let timeClass = json["time_class"] as? String

        // Date
        let endTime = json["end_time"] as? Int ?? 0
        let datePlayed = Date(timeIntervalSince1970: Double(endTime))

        // Opening detection
        let detection = openingDetector.detect(moves: replay.uciMoves)

        return ImportedGame(
            id: "chesscom_\(gameID)",
            source: .chessCom,
            pgn: pgn,
            playerUsername: playerUsername,
            playerColor: playerColor,
            playerELO: playerELO,
            opponentUsername: opponentUsername,
            opponentELO: opponentELO,
            outcome: outcome,
            timeControl: timeControl,
            timeClass: timeClass,
            datePlayed: datePlayed,
            moveCount: parsed.sanMoves.count,
            sanMoves: parsed.sanMoves,
            uciMoves: replay.uciMoves,
            detectedOpening: detection.best?.opening.name,
            detectedOpeningID: detection.best?.opening.id,
            analysisComplete: false,
            mistakes: nil,
            averageCentipawnLoss: nil
        )
    }
}
