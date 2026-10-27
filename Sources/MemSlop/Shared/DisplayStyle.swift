import Foundation

/// How the menu bar indicator looks.
enum DisplayStyle: String, CaseIterable, Identifiable, Codable {
    case text
    case compact
    case bars
    case cpu
    case memory
    case icon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "CPU and RAM"
        case .compact: "Stacked"
        case .bars: "Mini bars"
        case .cpu: "CPU only"
        case .memory: "RAM only"
        case .icon: "Icon only"
        }
    }
}
