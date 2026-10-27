import Charts
import MemSlopCore
import SwiftUI

/// CPU and memory over time, with a hover inspector that names the biggest consumers.
struct HistoryChart: View {
    @Environment(AppModel.self) private var model
    let range: TimeInterval
    @State private var selection: Date?

    private struct Sample: Identifiable {
        let id: String
        let time: Date
        let value: Double
        let series: String
    }

    var body: some View {
        let now = Date()
        let points = MetricHistory.downsample(model.history.points(lastSeconds: range, now: now), to: 240)
        if points.count < 2 {
            ContentUnavailableView(
                "Collecting data",
                systemImage: "chart.xyaxis.line",
                description: Text("History appears after a minute and is kept for 24 hours.")
            )
            .frame(height: 260)
        } else {
            chart(points: points, now: now)
        }
    }

    private func chart(points: [MetricPoint], now: Date) -> some View {
        let samples = points.flatMap { point in
            [Sample(id: "m\(point.time.timeIntervalSince1970)", time: point.time, value: point.memory, series: "Memory"),
             Sample(id: "c\(point.time.timeIntervalSince1970)", time: point.time, value: point.cpu, series: "CPU")]
        }
        let selected = selection.flatMap { date in points.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) } }
        return Chart {
            ForEach(samples) { sample in
                AreaMark(x: .value("Time", sample.time), y: .value("Usage", sample.value),
                         series: .value("Series", sample.series), stacking: .unstacked)
                    .foregroundStyle(gradient(sample.series == "CPU" ? Theme.cpu : Theme.memory))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.time), y: .value("Usage", sample.value), series: .value("Series", sample.series))
                    .foregroundStyle(sample.series == "CPU" ? Theme.cpu : Theme.memory)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .interpolationMethod(.monotone)
            }
            if let selected {
                RuleMark(x: .value("Time", selected.time))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Inspector(point: selected, detail: model.history.minutePoint(near: selected.time))
                    }
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-range)...now)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel { Text("\(Int((value.as(Double.self) ?? 0) * 100))%") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartForegroundStyleScale(["CPU": Theme.cpu, "Memory": Theme.memory])
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: $selection)
        .frame(height: 260)
    }

    private func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    }
}

private struct Inspector: View {
    let point: MetricPoint
    let detail: MetricPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.time, format: .dateTime.hour().minute()).font(.caption.weight(.semibold))
            HStack(spacing: 10) {
                Label(Formatting.percent(point.cpu), systemImage: "cpu").foregroundStyle(Theme.cpu)
                Label(Formatting.percent(point.memory), systemImage: "memorychip").foregroundStyle(Theme.memory)
            }
            .font(Theme.number(12))
            if let top = detail?.top, !top.isEmpty {
                Divider()
                ForEach(top.prefix(4), id: \.name) { usage in
                    HStack {
                        Text(usage.name).lineLimit(1)
                        Spacer(minLength: 12)
                        Text(Formatting.bytes(usage.memoryBytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}
