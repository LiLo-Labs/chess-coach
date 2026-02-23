//
//  MovingTranslations.swift
//  ChessKit
//
//  Created by Alexander Perechnev on 13.07.2020.
//  Copyright © 2020 Päike Mikrosüsteemid OÜ. All rights reserved.
//
//  Fix: Changed lazy var to let to eliminate thread-safety data race.
//  lazy var is not thread-safe in Swift; concurrent first access from
//  multiple threads causes EXC_BAD_ACCESS.

class MovingTranslations {

    static let `default` = MovingTranslations()

    let diagonal: [(Int, Int)] = [
        (-1, -1), (1, 1), (-1, 1), (1, -1)
    ]
    let cross: [(Int, Int)] = [
        (-1, 0), (0, 1), (1, 0), (0, -1)
    ]
    let crossDiagonal: [(Int, Int)]
    let knight: [(Int, Int)] = [
        (-2, 1), (-1, 2), (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1)
    ]
    let pawnTaking: [(Int, Int)] = [
        (-1, 1), (1, 1)
    ]

    private init() {
        self.crossDiagonal = [
            (-1, 0), (0, 1), (1, 0), (0, -1),
            (-1, -1), (1, 1), (-1, 1), (1, -1)
        ]
    }

}
