// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bracket",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Bracket", targets: ["Bracket"])],
    targets: [
        .target(name: "BracketCore"),
        .executableTarget(name: "Bracket", dependencies: ["BracketCore"], resources: [.copy("Resources")]),
        .testTarget(name: "BracketCoreTests", dependencies: ["BracketCore"])
    ]
)
