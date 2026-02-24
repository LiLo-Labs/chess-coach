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
                    .process("Assets/Pieces/uscf")
                ])
    ],
    swiftLanguageModes: [.v5, .v6]
)
