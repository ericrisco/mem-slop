import Foundation

public enum Formatting {
    /// `1.2 GB`, `640 MB`, `12 KB` — compact, memory style.
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = Double(value)
        var unit = 0
        while amount >= 1024, unit < units.count - 1 {
            amount /= 1024
            unit += 1
        }
        if unit <= 1 { return "\(Int(amount)) \(units[unit])" }
        if unit == 2 { return amount >= 100 ? "\(Int(amount.rounded())) MB" : String(format: "%.0f MB", amount) }
        return String(format: amount >= 100 ? "%.0f %@" : "%.1f %@", amount, units[unit])
    }

    /// `42%` from a 0...1 ratio.
    public static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    /// Activity-Monitor-style process CPU (100 = one core).
    public static func cpu(_ percent: Double) -> String {
        percent < 10 ? String(format: "%.1f%%", percent) : "\(Int(percent.rounded()))%"
    }

    /// `3h 12m`, `5m`, `42s`.
    public static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
