// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChessboardKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "ChessboardKit",
            targets: ["ChessboardKit"]),
    ],
    dependencies: [.package(path: "../ChessKit")],
    targets: [
        .target(name: "ChessboardKit",
                dependencies: ["ChessKit"],
                resources: [
                    .copy("Assets/Pieces/uscf"),
                    .copy("Assets/Pieces/cburnett"),
                    .copy("Assets/Pieces/merida"),
                    .copy("Assets/Pieces/staunty"),
                    .copy("Assets/Pieces/california"),
                ])
    ],
    swiftLanguageModes: [.v5, .v6]
)
