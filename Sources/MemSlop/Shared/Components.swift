import AppKit
import Charts
import MemSlopCore
import SwiftUI

/// Ring gauge with a big centred number.
struct RingGauge: View {
    let value: Double
    let color: Color
    let label: String
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7

    var body: some View {
        let tint = Theme.load(value, base: color)
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.004, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -2) {
                Text("\(Int((value * 100).rounded()))")
                    .font(Theme.number(size * 0.34, weight: .bold))


                Text(label)
                    .font(.system(size: size * 0.13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Two-series live trend (CPU and memory, 0...1).
struct TrendChart: View {
    let cpu: [Double]
    let memory: [Double]
    var height: CGFloat = 54

    private struct Point: Identifiable {
        let id: String
        let index: Int
        let value: Double
        let series: String
    }

    private var points: [Point] {
        let pad = AppModel.trendLength
        func series(_ values: [Double], _ name: String) -> [Point] {
            values.enumerated().map { offset, value in
                let index = pad - values.count + offset
                return Point(id: "\(name)\(index)", index: index, value: value, series: name)
            }
        }
        return series(memory, "Memory") + series(cpu, "CPU")
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("t", point.index),
                y: .value("v", point.value),
                series: .value("s", point.series),
                stacking: .unstacked
            )
            .foregroundStyle(gradient(point.series == "CPU" ? Theme.cpu : Theme.memory))
            .interpolationMethod(.monotone)
            LineMark(x: .value("t", point.index), y: .value("v", point.value), series: .value("s", point.series))
                .foregroundStyle(point.series == "CPU" ? Theme.cpu : Theme.memory)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: 0...(AppModel.trendLength - 1))
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel("CPU and memory trend")
    }

    private func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    }
}

/// App icon for bundle groups, SF Symbol tile for families.
struct GroupIcon: View {
    let group: ProcessGroup
    var size: CGFloat = 22

    var body: some View {
        switch group.kind {
        case let .app(path):
            Image(nsImage: IconCache.shared.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        case let .family(family):
            symbolTile(family.symbolName, tint: family == .agents ? Theme.slop : .accentColor)
        case .executable:
            symbolTile("gearshape", tint: .secondary)
        }
    }

    private func symbolTile(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

/// A destructive button that needs a second click to confirm.
struct ConfirmButton: View {
    let title: String
    let confirmTitle: String
    var systemImage = "xmark"
    let action: () -> Void
    @State private var armed = false

    var body: some View {
        Button {
            if armed {
                armed = false
                action()
            } else {
                withAnimation(.snappy) { armed = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.snappy) { armed = false }
                }
            }
        } label: {
            Label(armed ? confirmTitle : title, systemImage: armed ? "exclamationmark.triangle.fill" : systemImage)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(armed ? Theme.danger : Color.primary.opacity(0.08), in: Capsule())
                .foregroundStyle(armed ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(armed ? "Click again to confirm" : title)
    }
}

/// Thin horizontal meter used in rows.
struct MiniMeter: View {
    let value: Double
    let color: Color
    var width: CGFloat = 120

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(color.opacity(0.14))
            Capsule().fill(color).frame(width: max(2, width * min(1, value)))
        }
        .frame(width: width, height: 3)
    }
}
