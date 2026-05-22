// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mh",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mh", targets: ["mh"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "mh",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            resources: [
                .copy("Resources/triage_schema.json"),
                .copy("Resources/analysis_schema.json")
            ]
        ),
        .testTarget(
            name: "mhTests",
            dependencies: ["mh"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
