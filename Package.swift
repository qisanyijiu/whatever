// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnglishClozeCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "EnglishClozeCoach",
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
