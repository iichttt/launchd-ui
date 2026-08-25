// swift-tools-version: 6.0
import PackageDescription

// The SwiftUI app. Requires Xcode: SwiftUI's @State is a macro whose plugin ships only
// with Xcode, not with Command Line Tools.
let package = Package(
    name: "LaunchdUI",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LaunchdUI", targets: ["LaunchdUI"])
    ],
    dependencies: [.package(path: "../Core")],
    targets: [
        .executableTarget(
            name: "LaunchdUI",
            dependencies: [.product(name: "LaunchdCore", package: "Core")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
