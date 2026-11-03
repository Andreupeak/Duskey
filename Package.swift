// swift-tools-version: 5.9
import PackageDescription

// The app compiles these same sources through Xcode's synchronized Duskey group.
// This package makes policy, persistence, and solar calculations testable without hardware.
let package = Package(
    name: "DuskeyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DuskeyCore", targets: ["DuskeyCore"])],
    targets: [
        .target(name: "DuskeyCore", path: "Duskey/Core"),
        .testTarget(name: "DuskeyCoreTests", dependencies: ["DuskeyCore"])
    ]
)
