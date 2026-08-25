import Foundation

/// Minimal assertion harness. Command Line Tools ships neither XCTest nor Swift Testing
/// (both frameworks live inside Xcode), so the core's checks run as a plain executable
/// that exits non-zero on failure — usable in CI without a full Xcode install.
enum Check {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var currentSuite = ""

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        body()
    }

    static func expect(_ condition: Bool, _ description: String) {
        if condition {
            passed += 1
        } else {
            failures.append("\(currentSuite): \(description)")
        }
    }

    static func equal<T: Equatable>(_ lhs: T, _ rhs: T, _ description: String) {
        if lhs == rhs {
            passed += 1
        } else {
            failures.append("\(currentSuite): \(description)\n    expected: \(rhs)\n    actual:   \(lhs)")
        }
    }

    static func report() -> Never {
        if failures.isEmpty {
            print("✓ \(passed) checks passed")
            exit(0)
        }
        print("✗ \(failures.count) failed, \(passed) passed\n")
        for failure in failures { print("  ✗ \(failure)") }
        exit(1)
    }
}
