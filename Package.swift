// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "whatever",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "whatever",
            targets: ["EnglishClozeCoach"]
        )
    ],
    targets: [
        .executableTarget(
            name: "EnglishClozeCoach",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
