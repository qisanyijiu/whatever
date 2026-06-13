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
            targets: ["whatever"]
        )
    ],
    targets: [
        .target(
            name: "EnglishClozeCoach",
            path: "Sources/EnglishClozeCoach",
            exclude: [
                "App"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"])
            ]
        ),
        .executableTarget(
            name: "whatever",
            dependencies: ["EnglishClozeCoach"],
            path: "Sources/EnglishClozeCoach/App"
        ),
        .executableTarget(
            name: "EnglishClozeCoachUnitTests",
            dependencies: ["EnglishClozeCoach"],
            path: "Tests/EnglishClozeCoachUnitTests"
        ),
        .testTarget(
            name: "EnglishClozeCoachTests",
            dependencies: ["EnglishClozeCoach"],
            path: "Tests/EnglishClozeCoachTests"
        )
    ]
)
