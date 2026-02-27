import Foundation

final class OpeningDatabase: Sendable {
    /// Shared singleton — use this instead of creating new instances to avoid redundant file I/O.
    static let shared = OpeningDatabase()

    let openings: [Opening]

    init() {
        // Merge JSON tree-based openings with built-in flat openings.
        // JSON versions take priority (by id) over built-in versions.
        let jsonOpenings = Self.loadFromJSON()
        let jsonIDs = Set(jsonOpenings.map(\.id))
        let remaining = Self.builtInOpenings.filter { !jsonIDs.contains($0.id) }
        self.openings = (jsonOpenings + remaining).sorted { $0.difficulty < $1.difficulty }
    }

    func opening(named name: String) -> Opening? {
        openings.first { $0.name == name }
    }

    func opening(byID id: String) -> Opening? {
        openings.first { $0.id == id }
    }

    func openings(forColor color: Opening.PlayerColor) -> [Opening] {
        openings.filter { $0.color == color }
    }

    // MARK: - JSON Loading

    private static func loadFromJSON() -> [Opening] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }

        // Look for JSON files in Openings subdirectory first, then bundle root
        let openingsDir = resourceURL.appendingPathComponent("Openings")
        let searchDir = FileManager.default.fileExists(atPath: openingsDir.path) ? openingsDir : resourceURL

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: searchDir,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) else {
            return []
        }

        var openings: [Opening] = []
        let decoder = JSONDecoder()

        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }

            // Decode the JSON tree format
            guard let jsonOpening = try? decoder.decode(JSONOpening.self, from: data) else {
                continue
            }

            // Convert to Opening, extracting main line from tree
            let mainLine = extractMainLine(from: jsonOpening.tree)
            let tree = convertTree(jsonOpening.tree)
            let lines = tree.allLines()

            let opening = Opening(
                id: jsonOpening.id,
                name: jsonOpening.name,
                description: jsonOpening.description,
                color: Opening.PlayerColor(rawValue: jsonOpening.color) ?? .white,
                difficulty: jsonOpening.difficulty,
                mainLine: mainLine,
                tree: tree,
                lines: lines,
                plan: jsonOpening.plan,
                opponentResponses: jsonOpening.opponentResponses
            )
            openings.append(opening)
        }

        return openings.sorted { $0.difficulty < $1.difficulty }
    }

    /// Extract the main line (following isMainLine flags) from a JSON tree.
    private static func extractMainLine(from tree: JSONOpeningTree) -> [OpeningMove] {
        var moves: [OpeningMove] = []
        var node = tree
        while let mainChild = node.children.first(where: { $0.isMainLine ?? false }) ?? node.children.first {
            if let move = mainChild.move {
                moves.append(move)
            }
            node = mainChild
        }
        return moves
    }

    /// Convert JSON tree to OpeningNode tree.
    private static func convertTree(_ json: JSONOpeningTree) -> OpeningNode {
        let children = json.children.map { convertTree($0) }
        return OpeningNode(
            id: json.id ?? UUID().uuidString,
            move: json.move,
            children: children,
            isMainLine: json.isMainLine ?? false,
            variationName: json.variationName,
            weight: json.weight ?? 0
        )
    }

    // MARK: - JSON Codable types

    private struct JSONOpening: Codable {
        let id: String
        let name: String
        let description: String
        let color: String
        let difficulty: Int
        let tree: JSONOpeningTree
        let plan: OpeningPlan?
        let opponentResponses: OpponentResponseCatalogue?
    }

    private struct JSONOpeningTree: Codable {
        let id: String?
        let move: OpeningMove?
        let children: [JSONOpeningTree]
        let isMainLine: Bool?
        let variationName: String?
        let weight: UInt16?
    }

    // MARK: - Built-in Openings (Legacy Fallback)

    private static let builtInOpenings: [Opening] = [
        Opening(
            id: "italian",
            name: "Italian Game",
            description: "A classic opening that develops pieces quickly toward the center and kingside.",
            color: .white,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center with your king's pawn. This opens lines for your bishop and queen."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors your move, also fighting for the center."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop your knight toward the center and attack Black's e5 pawn."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Black defends the e5 pawn with the knight while developing a piece."),
                OpeningMove(uci: "f1c4", san: "Bc4", explanation: "The Italian Bishop! Aims at the f7 square, which is Black's weakest point near the king."),
                OpeningMove(uci: "f8c5", san: "Bc5", explanation: "Black develops their bishop to an active diagonal, mirroring your strategy."),
                OpeningMove(uci: "d2d3", san: "d3", explanation: "Support your e4 pawn and open a path for your other bishop to develop."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops their last minor piece, attacking your e4 pawn."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle kingside to keep your king safe and connect your rooks."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black also castles for king safety. The opening phase is nearly complete."),
            ]
        ),
        Opening(
            id: "london",
            name: "London System",
            description: "A solid, easy-to-learn system that works against almost any Black response.",
            color: .white,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "Control the center with the queen's pawn."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black fights for the center symmetrically."),
                OpeningMove(uci: "c1f4", san: "Bf4", explanation: "The London Bishop! Develop outside the pawn chain before playing e3."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops a knight to a natural square."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "Support d4 and open a diagonal for your king's bishop."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "Black challenges your center. This is the main way to fight the London."),
                OpeningMove(uci: "c2c3", san: "c3", explanation: "Reinforce your d4 pawn. Your pawn structure is now rock-solid."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Black develops another piece and adds pressure to d4."),
                OpeningMove(uci: "b1d2", san: "Nd2", explanation: "Develop the knight without blocking the c-pawn. A key London System idea."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black prepares to develop the dark-squared bishop."),
            ]
        ),
        Opening(
            id: "sicilian",
            name: "Sicilian Defense",
            description: "The most popular and aggressive response to 1.e4. Leads to sharp, exciting games.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White opens with the most popular first move."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "The Sicilian! Fight for the center asymmetrically. You'll get counterplay on the queenside."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops the knight, preparing to control the center."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "Prepare to develop your pieces. This is the flexible Najdorf/Dragon setup."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White opens the center. This is the critical moment of the Sicilian."),
                OpeningMove(uci: "c5d4", san: "cxd4", explanation: "Capture! You've traded a side pawn for White's central pawn — a great deal."),
                OpeningMove(uci: "f3d4", san: "Nxd4", explanation: "White recaptures with the knight, which is now centralized."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop your knight and attack White's e4 pawn."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White defends e4 and develops."),
                OpeningMove(uci: "a7a6", san: "a6", explanation: "The Najdorf move! Prevents Bb5 and prepares b5 for queenside expansion."),
            ]
        ),
        Opening(
            id: "french",
            name: "French Defense",
            description: "A solid defense where Black builds a strong pawn structure and counterattacks the center.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White opens with the king's pawn."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "The French Defense! You prepare to challenge the center with d5 next move."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White takes a big center. Now is the time to challenge it."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Strike at the center! This creates tension — the key moment of the French."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White defends e4. This is the Classical French."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Add more pressure on e4. White must make a decision about the center."),
                OpeningMove(uci: "e4e5", san: "e5", explanation: "White advances, gaining space but locking the center."),
                OpeningMove(uci: "f6d7", san: "Nd7", explanation: "Retreat the knight — it was attacked. Now plan to undermine White's center with c5 and f6."),
                OpeningMove(uci: "f2f4", san: "f4", explanation: "White reinforces the e5 pawn. A typical aggressive setup."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "Attack White's center from the side! This is Black's main plan in the French."),
            ]
        ),
        Opening(
            id: "caro-kann",
            name: "Caro-Kann Defense",
            description: "A very solid defense that avoids the cramped positions of the French while keeping good piece activity.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White opens with the king's pawn."),
                OpeningMove(uci: "c7c6", san: "c6", explanation: "The Caro-Kann! Prepare d5 while keeping the light-squared bishop unblocked."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White takes a strong center."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Challenge the center. Unlike the French, your bishop on c8 isn't blocked."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White defends e4."),
                OpeningMove(uci: "d5e4", san: "dxe4", explanation: "Capture the pawn. This leads to the Main Line of the Caro-Kann."),
                OpeningMove(uci: "c3e4", san: "Nxe4", explanation: "White recaptures with the knight, which is now strong in the center."),
                OpeningMove(uci: "c8f5", san: "Bf5", explanation: "Develop your bishop to its best square before playing e6. This is why c6 was better than e6!"),
            ]
        ),
        Opening(
            id: "queens-gambit",
            name: "Queen's Gambit",
            description: "A classical opening where White offers a pawn to gain central control.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "Open with the queen's pawn for central control."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black fights for the center."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "The Queen's Gambit! Offer a pawn to lure Black's d-pawn away from the center."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black declines the gambit and solidly defends d5."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "Develop and add pressure to d5."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops a knight."),
                OpeningMove(uci: "c1g5", san: "Bg5", explanation: "Pin the knight against the queen. A key move in the Queen's Gambit."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Black breaks the pin and prepares to castle."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "Support the d4 pawn and free the bishop."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles to safety."),
            ]
        ),
        Opening(
            id: "kings-indian",
            name: "King's Indian Defense",
            description: "An aggressive defense where Black lets White build a big center, then counterattacks it.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White opens with the queen's pawn."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop the knight first. You'll fianchetto the bishop next."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "White grabs more space in the center."),
                OpeningMove(uci: "g7g6", san: "g6", explanation: "Prepare to fianchetto — put your bishop on g7 where it controls the long diagonal."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops a piece."),
                OpeningMove(uci: "f8g7", san: "Bg7", explanation: "The fianchettoed bishop! It's aimed at White's center and queenside."),
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White builds a massive center. Don't worry — you'll attack it later."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "A flexible move. Prepare to strike with e5 when the time is right."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops the last minor piece."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Castle and get your king safe. Now you're ready for the middlegame fight."),
            ]
        ),
        Opening(
            id: "ruy-lopez",
            name: "Ruy Lopez",
            description: "One of the oldest and most respected openings. White puts immediate pressure on Black's center.",
            color: .white,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors, fighting for the center."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and attack e5."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Defend the e5 pawn."),
                OpeningMove(uci: "f1b5", san: "Bb5", explanation: "The Ruy Lopez! Pin the knight that defends e5. This creates long-term pressure."),
                OpeningMove(uci: "a7a6", san: "a6", explanation: "The Morphy Defense — ask the bishop what it wants to do."),
                OpeningMove(uci: "b5a4", san: "Ba4", explanation: "Retreat but maintain the pressure on c6 and indirectly on e5."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops and counterattacks e4."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle for king safety. The e4 pawn looks loose but is tactically defended."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Black develops and prepares to castle."),
            ]
        ),
        Opening(
            id: "scotch",
            name: "Scotch Game",
            description: "An aggressive opening where White immediately opens the center for active piece play.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and attack e5."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Defend e5."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "The Scotch! Immediately challenge the center. More aggressive than the Italian."),
                OpeningMove(uci: "e5d4", san: "exd4", explanation: "Black captures, opening the center."),
                OpeningMove(uci: "f3d4", san: "Nxd4", explanation: "Recapture with the knight, which is now powerfully centralized."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops and attacks e4."),
            ]
        ),
        Opening(
            id: "pirc",
            name: "Pirc Defense",
            description: "A hypermodern defense where Black invites White to build a center, planning to undermine it later.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White claims the center."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "The Pirc! A flexible move that doesn't commit yet. You'll fianchetto and strike later."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White builds a big center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop and pressure e4."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White defends e4."),
                OpeningMove(uci: "g7g6", san: "g6", explanation: "Prepare the fianchetto. Your bishop on g7 will be a monster on the long diagonal."),
                OpeningMove(uci: "f2f4", san: "f4", explanation: "White plays aggressively with the Austrian Attack."),
                OpeningMove(uci: "f8g7", san: "Bg7", explanation: "Complete the fianchetto. Your bishop eyes White's center and queenside."),
            ]
        ),

        // MARK: - New White Openings

        Opening(
            id: "vienna",
            name: "Vienna Game",
            description: "A flexible opening where White delays committing to a pawn structure, keeping options for both quiet and aggressive play.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center with the king's pawn."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors, fighting for the center."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "The Vienna! Develop the knight and keep options open for f4."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops and pressures e4."),
                OpeningMove(uci: "f2f4", san: "f4", explanation: "The Vienna Gambit! Strike at the center aggressively."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black counterattacks in the center."),
                OpeningMove(uci: "f4e5", san: "fxe5", explanation: "Capture, opening the f-file for your rook."),
                OpeningMove(uci: "f6e4", san: "Nxe4", explanation: "Black centralizes the knight."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and prepare to castle."),
                OpeningMove(uci: "f8c5", san: "Bc5", explanation: "Black develops the bishop actively."),
            ]
        ),
        Opening(
            id: "kings-gambit",
            name: "King's Gambit",
            description: "One of the oldest and most romantic openings. White sacrifices a pawn for rapid development and attacking chances.",
            color: .white,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "f2f4", san: "f4", explanation: "The King's Gambit! Offer a pawn for a fast attack."),
                OpeningMove(uci: "e5f4", san: "exf4", explanation: "Black accepts the gambit."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and prevent Qh4+."),
                OpeningMove(uci: "g7g5", san: "g5", explanation: "Black tries to hold the extra pawn."),
                OpeningMove(uci: "f1c4", san: "Bc4", explanation: "Aim at f7, the weakest point."),
                OpeningMove(uci: "g5g4", san: "g4", explanation: "Black attacks the knight."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "The Muzio Gambit! Sacrifice the knight for a crushing attack."),
                OpeningMove(uci: "g4f3", san: "gxf3", explanation: "Black takes the knight."),
            ]
        ),
        Opening(
            id: "english",
            name: "English Opening",
            description: "A flexible opening where White controls the center from the flank.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "c2c4", san: "c4", explanation: "The English! Control d5 from the flank."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black takes the center directly."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "Develop toward the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops a knight."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop the other knight."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Black develops symmetrically."),
                OpeningMove(uci: "g2g3", san: "g3", explanation: "Prepare to fianchetto the bishop."),
                OpeningMove(uci: "f8b4", san: "Bb4", explanation: "Black pins the knight."),
                OpeningMove(uci: "f1g2", san: "Bg2", explanation: "Complete the fianchetto. The bishop controls the long diagonal."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles for safety."),
            ]
        ),
        Opening(
            id: "catalan",
            name: "Catalan Opening",
            description: "A sophisticated opening combining Queen's Gambit pawn structure with a fianchettoed bishop.",
            color: .white,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "Control the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "Grab more space."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black prepares d5."),
                OpeningMove(uci: "g2g3", san: "g3", explanation: "The Catalan! Fianchetto the bishop for long-term pressure."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black stakes a claim in the center."),
                OpeningMove(uci: "f1g2", san: "Bg2", explanation: "The Catalan bishop dominates the long diagonal."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Black develops solidly."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and prepare to castle."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles."),
            ]
        ),
        Opening(
            id: "reti",
            name: "Reti Opening",
            description: "A hypermodern opening where White controls the center with pieces rather than pawns.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "The Reti! Develop the knight first, keeping options open."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black takes the center."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "Challenge Black's center from the side."),
                OpeningMove(uci: "d5c4", san: "dxc4", explanation: "Black accepts the pawn."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "Prepare to recapture the pawn with the bishop."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "Black fights for space."),
                OpeningMove(uci: "f1c4", san: "Bxc4", explanation: "Recapture with an active bishop."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black solidifies."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle for safety."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops."),
            ]
        ),
        Opening(
            id: "four-knights",
            name: "Four Knights Game",
            description: "A solid, symmetrical opening where both sides develop their knights first.",
            color: .white,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop and attack e5."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Defend e5."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "Four Knights! Both sides develop symmetrically."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "All four knights are out."),
                OpeningMove(uci: "f1b5", san: "Bb5", explanation: "The Spanish Four Knights. Pin the knight."),
                OpeningMove(uci: "f8b4", san: "Bb4", explanation: "Black mirrors the pin."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle for safety."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles too."),
            ]
        ),
        Opening(
            id: "bishops-opening",
            name: "Bishop's Opening",
            description: "A simple but effective opening. White develops the bishop early aiming at f7.",
            color: .white,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "Control the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "f1c4", san: "Bc4", explanation: "The Bishop's Opening! Aim at f7 immediately."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops and attacks e4."),
                OpeningMove(uci: "d2d3", san: "d3", explanation: "Support e4 solidly."),
                OpeningMove(uci: "f8c5", san: "Bc5", explanation: "Black develops actively."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop the knight."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "Black supports e5."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle for king safety."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles too."),
            ]
        ),
        Opening(
            id: "kings-indian-attack",
            name: "King's Indian Attack",
            description: "A universal system for White. Set up with Nf3, g3, Bg2, d3, Nbd2 and e4 against almost anything.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Flexible development."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black takes the center."),
                OpeningMove(uci: "g2g3", san: "g3", explanation: "Prepare to fianchetto."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops."),
                OpeningMove(uci: "f1g2", san: "Bg2", explanation: "The fianchettoed bishop controls the center."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black builds a solid structure."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "Castle early."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Black develops."),
                OpeningMove(uci: "d2d3", san: "d3", explanation: "Support the e4 push."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Black castles."),
            ]
        ),
        Opening(
            id: "colle",
            name: "Colle System",
            description: "A beginner-friendly system. Set up with d4, Nf3, e3, Bd3, O-O and then push e4 when ready.",
            color: .white,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "Control the center."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black mirrors."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Develop the knight."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "The Colle! Support d4 and free the bishop."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Black builds a solid structure."),
                OpeningMove(uci: "f1d3", san: "Bd3", explanation: "Develop the bishop to its ideal square."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "Black challenges the center."),
                OpeningMove(uci: "c2c3", san: "c3", explanation: "Reinforce d4."),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Black develops."),
            ]
        ),
        Opening(
            id: "trompowsky",
            name: "Trompowsky Attack",
            description: "A surprise weapon where White develops the bishop before the knight, forcing Black to make early decisions.",
            color: .white,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "Control the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Black develops."),
                OpeningMove(uci: "c1g5", san: "Bg5", explanation: "The Trompowsky! Pin or challenge the knight immediately."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Black takes the center."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "Support d4 and keep options open."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "Black challenges the center."),
                OpeningMove(uci: "c2c3", san: "c3", explanation: "Reinforce d4."),
                OpeningMove(uci: "d8b6", san: "Qb6", explanation: "Black pressures b2."),
                OpeningMove(uci: "d1b3", san: "Qb3", explanation: "Trade queens to simplify."),
                OpeningMove(uci: "b6b3", san: "Qxb3", explanation: "Queens are exchanged."),
            ]
        ),

        // MARK: - New Black Openings

        Opening(
            id: "scandinavian",
            name: "Scandinavian Defense",
            description: "A straightforward defense where Black immediately challenges White's center.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White opens with the king's pawn."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "The Scandinavian! Challenge the center immediately."),
                OpeningMove(uci: "e4d5", san: "exd5", explanation: "White captures."),
                OpeningMove(uci: "d8d5", san: "Qxd5", explanation: "Recapture with the queen. She'll move again but you gain central control."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops and attacks the queen."),
                OpeningMove(uci: "d5a5", san: "Qa5", explanation: "The queen retreats to a safe but active square."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White grabs more center space."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop and fight for e4."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops."),
                OpeningMove(uci: "c8f5", san: "Bf5", explanation: "Develop the bishop outside the pawn chain. This is why the Scandinavian is great."),
            ]
        ),
        Opening(
            id: "nimzo-indian",
            name: "Nimzo-Indian Defense",
            description: "One of Black's most respected defenses. The bishop pins White's knight, controlling the center indirectly.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White opens with the queen's pawn."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop the knight."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "White grabs more space."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Prepare to pin the knight with Bb4."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops."),
                OpeningMove(uci: "f8b4", san: "Bb4", explanation: "The Nimzo-Indian! Pin the knight that controls e4."),
                OpeningMove(uci: "e2e3", san: "e3", explanation: "White supports d4."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Castle early for safety."),
                OpeningMove(uci: "f1d3", san: "Bd3", explanation: "White develops the bishop."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Strike at the center."),
            ]
        ),
        Opening(
            id: "queens-indian",
            name: "Queen's Indian Defense",
            description: "A solid, positional defense where Black fianchettoes the queenside bishop to control the center from a distance.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White opens with the queen's pawn."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "White grabs space."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Prepare the fianchetto."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops."),
                OpeningMove(uci: "b7b6", san: "b6", explanation: "The Queen's Indian! Prepare to fianchetto the bishop."),
                OpeningMove(uci: "g2g3", san: "g3", explanation: "White also fianchettoes."),
                OpeningMove(uci: "c8b7", san: "Bb7", explanation: "Your bishop controls the long diagonal, especially e4 and d5."),
                OpeningMove(uci: "f1g2", san: "Bg2", explanation: "White completes the fianchetto."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Develop and prepare to castle."),
            ]
        ),
        Opening(
            id: "slav",
            name: "Slav Defense",
            description: "A rock-solid defense that supports d5 with c6 while keeping the light-squared bishop free.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White controls the center."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "Fight for the center."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "The Queen's Gambit."),
                OpeningMove(uci: "c7c6", san: "c6", explanation: "The Slav! Support d5 without blocking the bishop."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop and fight for e4."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops."),
                OpeningMove(uci: "d5c4", san: "dxc4", explanation: "Capture! Now develop the bishop before playing e6."),
                OpeningMove(uci: "a2a4", san: "a4", explanation: "White prevents b5."),
                OpeningMove(uci: "c8f5", san: "Bf5", explanation: "Develop the bishop outside the pawn chain. This is the Slav's advantage."),
            ]
        ),
        Opening(
            id: "dutch",
            name: "Dutch Defense",
            description: "An aggressive defense where Black immediately fights for control of the e4 square.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White opens with the queen's pawn."),
                OpeningMove(uci: "f7f5", san: "f5", explanation: "The Dutch! Control e4 and prepare for a kingside attack."),
                OpeningMove(uci: "g2g3", san: "g3", explanation: "White fianchettoes."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop the knight."),
                OpeningMove(uci: "f1g2", san: "Bg2", explanation: "White completes the fianchetto."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Support the f-pawn and prepare to develop the bishop."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Develop and prepare to castle."),
                OpeningMove(uci: "e1g1", san: "O-O", explanation: "White castles."),
                OpeningMove(uci: "e8g8", san: "O-O", explanation: "Castle and start planning a kingside attack."),
            ]
        ),
        Opening(
            id: "grunfeld",
            name: "Grunfeld Defense",
            description: "A dynamic defense where Black allows White a big center then attacks it.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White controls the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "White grabs space."),
                OpeningMove(uci: "g7g6", san: "g6", explanation: "Prepare to fianchetto."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops."),
                OpeningMove(uci: "d7d5", san: "d5", explanation: "The Grunfeld! Challenge the center directly."),
                OpeningMove(uci: "c4d5", san: "cxd5", explanation: "White captures."),
                OpeningMove(uci: "f6d5", san: "Nxd5", explanation: "Recapture with the knight."),
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White builds a massive center."),
                OpeningMove(uci: "d5c3", san: "Nxc3", explanation: "Exchange the knight, damaging White's structure."),
            ]
        ),
        Opening(
            id: "philidor",
            name: "Philidor Defense",
            description: "A solid, old-fashioned defense where Black supports e5 with d6.",
            color: .black,
            difficulty: 1,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White claims the center."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops and attacks e5."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "The Philidor! Support e5 solidly with the pawn."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White seizes more space."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop and attack e4."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops."),
                OpeningMove(uci: "b8d7", san: "Nbd7", explanation: "Develop the other knight to support e5 and f6."),
                OpeningMove(uci: "f1c4", san: "Bc4", explanation: "White aims at f7."),
                OpeningMove(uci: "f8e7", san: "Be7", explanation: "Develop and prepare to castle."),
            ]
        ),
        Opening(
            id: "alekhine",
            name: "Alekhine Defense",
            description: "A provocative defense where Black invites White to advance pawns and then attacks the overextended center.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White claims the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "The Alekhine! Attack the e4 pawn immediately."),
                OpeningMove(uci: "e4e5", san: "e5", explanation: "White advances, chasing the knight."),
                OpeningMove(uci: "f6d5", san: "Nd5", explanation: "Retreat to a strong central square."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White builds a big center."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "Challenge the overextended center."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White develops."),
                OpeningMove(uci: "c8g4", san: "Bg4", explanation: "Pin the knight and add pressure."),
                OpeningMove(uci: "f1e2", san: "Be2", explanation: "White unpins."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Solidify and prepare to develop the bishop."),
            ]
        ),
        Opening(
            id: "benoni",
            name: "Modern Benoni",
            description: "An ambitious defense where Black creates an asymmetrical pawn structure and plays for a queenside pawn majority.",
            color: .black,
            difficulty: 3,
            mainLine: [
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White controls the center."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop."),
                OpeningMove(uci: "c2c4", san: "c4", explanation: "White grabs space."),
                OpeningMove(uci: "c7c5", san: "c5", explanation: "The Benoni! Challenge d4 from the side."),
                OpeningMove(uci: "d4d5", san: "d5", explanation: "White advances, creating an asymmetrical structure."),
                OpeningMove(uci: "e7e6", san: "e6", explanation: "Undermine the d5 pawn."),
                OpeningMove(uci: "b1c3", san: "Nc3", explanation: "White develops."),
                OpeningMove(uci: "e6d5", san: "exd5", explanation: "Open the e-file for counterplay."),
                OpeningMove(uci: "c4d5", san: "cxd5", explanation: "White recaptures."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "Support the structure and prepare kingside development."),
            ]
        ),
        Opening(
            id: "petroff",
            name: "Petroff Defense",
            description: "A solid, symmetrical defense where Black mirrors White's play. Very reliable.",
            color: .black,
            difficulty: 2,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "White opens."),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Black mirrors."),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "White attacks e5."),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "The Petroff! Instead of defending, Black counterattacks e4."),
                OpeningMove(uci: "f3e5", san: "Nxe5", explanation: "White takes the pawn."),
                OpeningMove(uci: "d7d6", san: "d6", explanation: "Chase the knight away."),
                OpeningMove(uci: "e5f3", san: "Nf3", explanation: "The knight retreats."),
                OpeningMove(uci: "f6e4", san: "Nxe4", explanation: "Win back the pawn with a strong knight."),
                OpeningMove(uci: "d2d4", san: "d4", explanation: "White takes the center."),
                OpeningMove(uci: "d6d5", san: "d5", explanation: "Establish a solid central pawn."),
            ]
        ),
    ]
}
