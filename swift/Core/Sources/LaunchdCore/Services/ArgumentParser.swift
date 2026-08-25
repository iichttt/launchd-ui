import Foundation

/// Splits and rejoins the single-line "Program Arguments" field, honouring quotes so
/// arguments containing spaces survive a round trip. Mirrors parseArguments/formatArguments
/// in src/components/JobForm.tsx.
public enum ArgumentParser {
    public static func parse(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inDouble = false
        var inSingle = false

        for ch in input {
            if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == " " && !inDouble && !inSingle {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    public static func format(_ args: [String]) -> String {
        args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}
