import Darwin
import Foundation
import MemSlopCore

enum MemSlopVersion {
    /// Version of the MemSlop.app this binary lives in (`Contents/Helpers/memslop` → `Contents/Info.plist`).
    static var current: String {
        let contents = Executable.resolvedURL.deletingLastPathComponent().deletingLastPathComponent()
        let info = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))
        return info?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

enum Executable {
    /// This binary, with symlinks (e.g. `/usr/local/bin/memslop`) resolved.
    static var resolvedURL: URL {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }
}

enum Terminal {
    static let isInteractive = isatty(STDIN_FILENO) == 1
    static let useColor = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func paint(_ text: String, _ code: String) -> String {
        useColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    static func bold(_ text: String) -> String { paint(text, "1") }
    static func dim(_ text: String) -> String { paint(text, "2") }
    static func orange(_ text: String) -> String { paint(text, "38;5;208") }
    static func blue(_ text: String) -> String { paint(text, "34") }
    static func green(_ text: String) -> String { paint(text, "32") }
    static func red(_ text: String) -> String { paint(text, "31") }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data("\(paint("error:", "1;31")) \(message)\n".utf8))
    }

    /// Pads or truncates to a visible width (ANSI-free input).
    static func cell(_ text: String, _ width: Int, right: Bool = false) -> String {
        let clipped = text.count > width ? String(text.prefix(max(0, width - 1))) + "…" : text
        let padding = String(repeating: " ", count: max(0, width - clipped.count))
        return right ? padding + clipped : clipped + padding
    }

    static func confirm(_ question: String) -> Bool {
        print("\(question) [y/N] ", terminator: "")
        fflush(stdout)
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return answer == "y" || answer == "yes"
    }

    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
