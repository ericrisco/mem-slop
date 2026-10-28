import Foundation
import MemSlopCore

/// Typed access to UserDefaults.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static var displayStyle: DisplayStyle {
        get { defaults.string(forKey: "displayStyle").flatMap(DisplayStyle.init) ?? .text }
        set { defaults.set(newValue.rawValue, forKey: "displayStyle") }
    }

    static var sortKey: SortKey {
        get { defaults.string(forKey: "sortKey").flatMap(SortKey.init) ?? .memory }
        set { defaults.set(newValue.rawValue, forKey: "sortKey") }
    }

    static var groupingMode: GroupingMode {
        get { defaults.string(forKey: "groupingMode").flatMap(GroupingMode.init) ?? .kind }
        set { defaults.set(newValue.rawValue, forKey: "groupingMode") }
    }

    /// Seconds between samples.
    static var refreshInterval: Double {
        get { defaults.object(forKey: "refreshInterval") as? Double ?? 2 }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }
}
