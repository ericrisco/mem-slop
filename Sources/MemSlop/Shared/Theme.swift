import SwiftUI

enum Theme {
    static let cpu = Color(red: 0.42, green: 0.48, blue: 1.0)
    static let memory = Color(red: 0.18, green: 0.82, blue: 0.62)
    static let slop = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let danger = Color(red: 1.0, green: 0.33, blue: 0.36)

    /// Shifts toward warning colours as load grows (0...1).
    static func load(_ ratio: Double, base: Color) -> Color {
        switch ratio {
        case ..<0.75: base
        case ..<0.9: slop
        default: danger
        }
    }

    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// A rounded "glass" card used across the panel and the dashboard.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.06))
            )
    }
}
