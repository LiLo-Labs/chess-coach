import Foundation

final class OpeningDatabase: Sendable {
    let openings: [Opening]

    init() {
        self.openings = Self.builtInOpenings
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

    // MARK: - Built-in Openings

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
    ]
}
