// swift-tools-version: 6.0
import PackageDescription

// Models plus the launchd/plist logic, deliberately free of SwiftUI so it builds and
// tests under plain Command Line Tools — Xcode is only needed for the app in ../App.
let package = Package(
    name: "LaunchdCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchdCore", targets: ["LaunchdCore"]),
        .executable(name: "CoreChecks", targets: ["CoreChecks"]),
    ],
    targets: [
        .target(name: "LaunchdCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // Assertion runner rather than a test target: Command Line Tools ships neither
        // XCTest nor Swift Testing, so `swift run CoreChecks` is the Xcode-free way to
        // verify the port.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["LaunchdCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
