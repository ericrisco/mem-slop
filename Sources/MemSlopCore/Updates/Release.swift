import Foundation

/// `MAJOR.MINOR.PATCH`, compared numerically. A leading `v` is accepted.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }

    public var description: String { components.map(String.init).joined(separator: ".") }
}

/// What MemSlop needs from a GitHub release.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let notes: String
    public let pageURL: URL
    public let archiveURL: URL
    public let checksumURL: URL

    public static let repository = "ericrisco/mem-slop"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Parses the GitHub "latest release" response. Drafts, pre-releases and releases without the
    /// app archive and its checksum are rejected.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String, let version = SemanticVersion(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(_ name: String) -> URL? {
            assets.first { $0["name"] as? String == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        guard let archive = asset("MemSlop.zip"), let checksum = asset("MemSlop.zip.sha256") else { return nil }
        return ReleaseInfo(version: version, notes: json["body"] as? String ?? "", pageURL: page, archiveURL: archive, checksumURL: checksum)
    }

    /// The first hex token of a `shasum` line.
    public static func parseChecksum(_ text: String) -> String? {
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)?.lowercased()
        guard let token, token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}
