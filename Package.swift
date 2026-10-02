// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MusicCore", platforms: [.macOS("27.0"), .iOS("27.0")], products: [.library(name: "MusicCore", targets: ["MusicCore"])], targets: [.target(name: "MusicCore", path: "Sources/Core"), .testTarget(name: "MusicCoreTests", dependencies: ["MusicCore"], path: "Tests/Core")])
