#!/usr/bin/env swift
// Validates assessment_puzzles.json using ChessKit
// Run from project root: swift Scripts/validate_puzzles.swift

import Foundation

struct Puzzle: Codable {
    let id: String
    let fen: String
    let setupMoveUCI: String
    let solutionUCI: String
    let solutionSAN: String
    let themes: [String]
    let rating: Int
    let explanation: String?
}

let url = URL(fileURLWithPath: "ChessCoach/Resources/assessment_puzzles.json")
let data = try Data(contentsOf: url)
let puzzles = try JSONDecoder().decode([Puzzle].self, from: data)

print("Loaded \(puzzles.count) puzzles")

// Basic FEN validation
for p in puzzles {
    let parts = p.fen.split(separator: " ")
    if parts.count != 6 {
        print("❌ \(p.id): FEN has \(parts.count) fields, expected 6")
        continue
    }

    let ranks = parts[0].split(separator: "/")
    if ranks.count != 8 {
        print("❌ \(p.id): FEN has \(ranks.count) ranks, expected 8")
        continue
    }

    // Check each rank has 8 squares
    for (i, rank) in ranks.enumerated() {
        var squares = 0
        for ch in rank {
            if ch.isNumber {
                squares += Int(String(ch))!
            } else {
                squares += 1
            }
        }
        if squares != 8 {
            print("❌ \(p.id): Rank \(8-i) has \(squares) squares, expected 8")
        }
    }

    // Check solution UCI format
    let uci = p.solutionUCI
    if uci.count < 4 || uci.count > 5 {
        print("❌ \(p.id): solution UCI '\(uci)' has wrong length")
    }
    let fromFile = uci[uci.startIndex]
    let fromRank = uci[uci.index(after: uci.startIndex)]
    let toFile = uci[uci.index(uci.startIndex, offsetBy: 2)]
    let toRank = uci[uci.index(uci.startIndex, offsetBy: 3)]

    let validFiles: Set<Character> = ["a","b","c","d","e","f","g","h"]
    let validRanks: Set<Character> = ["1","2","3","4","5","6","7","8"]

    if !validFiles.contains(fromFile) || !validRanks.contains(fromRank) ||
       !validFiles.contains(toFile) || !validRanks.contains(toRank) {
        print("❌ \(p.id): solution UCI '\(uci)' has invalid squares")
    }

    // Check whose turn it is in FEN
    let turn = String(parts[1])

    // Check that the solution move's origin square has a piece of the right color
    let boardStr = String(parts[0])
    // Parse board to check piece placement
    var board: [String: Character] = [:]
    let files = ["a","b","c","d","e","f","g","h"]
    for (rankIdx, rank) in ranks.enumerated() {
        var fileIdx = 0
        for ch in rank {
            if ch.isNumber {
                fileIdx += Int(String(ch))!
            } else {
                let sq = "\(files[fileIdx])\(8-rankIdx)"
                board[sq] = ch
                fileIdx += 1
            }
        }
    }

    let fromSq = "\(fromFile)\(fromRank)"
    let toSq = "\(toFile)\(toRank)"

    if let piece = board[fromSq] {
        let isWhitePiece = piece.isUppercase
        let isWhiteTurn = turn == "w"
        if isWhitePiece != isWhiteTurn {
            print("❌ \(p.id): Solution moves \(isWhitePiece ? "white" : "black") piece but it's \(turn)'s turn (from \(fromSq)=\(piece))")
        }
    } else {
        print("❌ \(p.id): No piece at origin square \(fromSq) for solution \(uci)")
    }
}

print("\nValidation complete")
