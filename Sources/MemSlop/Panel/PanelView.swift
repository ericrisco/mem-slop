import MemSlopCore
import SwiftUI

/// The popover shown when the menu bar item is clicked.
struct PanelView: View {
    static let width: CGFloat = 420
    static let height: CGFloat = 680

    @Environment(AppModel.self) private var model
    var onOpenWindow: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
                .padding([.horizontal, .top], 14)
            SystemOverview()
                .padding(.horizontal, 14)
                .padding(.top, 10)
            ReaperStrip()
                .padding(.horizontal, 14)
                .padding(.top, 8)
            ProcessToolbar()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider().opacity(0.5)
            ProcessList()
            Divider().opacity(0.5)
            PanelFooter()
        }
        .frame(width: Self.width, height: Self.height)
    }
}

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            Wordmark()
            Spacer()
            Button {
                WindowManager.shared.show(.settings)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Menu {
                Picker("Menu Bar Style", selection: $model.displayStyle) {
                    ForEach(DisplayStyle.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button("Check for Idle Slop Now") { model.sweepNow() }
                Button("Settings…") { WindowManager.shared.show(.settings) }
                    .keyboardShortcut(",")
                Divider()
                Button("Quit MemSlop") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Options")
        }
    }
}

struct Wordmark: View {
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 0) {
            Text("mem").foregroundStyle(.primary)
            Text("slop").foregroundStyle(
                LinearGradient(colors: [Theme.slop, Theme.danger], startPoint: .leading, endPoint: .trailing)
            )
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .accessibilityLabel("MemSlop")
    }
}

private struct SystemOverview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.system
        Card {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    RingGauge(value: system.cpuUsage, color: Theme.cpu, label: "CPU")
                    RingGauge(value: system.memoryUsage, color: Theme.memory, label: "RAM")
                    VStack(alignment: .leading, spacing: 5) {
                        StatLine(title: "Memory", value: "\(Formatting.bytes(system.memoryUsed)) / \(Formatting.bytes(system.memoryTotal))")
                        StatLine(title: "Pressure", value: system.pressure.title, tint: system.pressure.color)
                        StatLine(title: "Load", value: system.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                        StatLine(title: "Swap", value: Formatting.bytes(system.swapUsed))
                    }
                    Spacer(minLength: 0)
                }
                TrendChart(cpu: model.cpuTrend, memory: model.memoryTrend, height: 40)
            }
        }
    }
}

private struct StatLine: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(Theme.number(11.5, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

extension MemoryPressure {
    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    var color: Color {
        switch self {
        case .normal: Theme.memory
        case .warning: Theme.slop
        case .critical: Theme.danger
        }
    }
}

private struct ProcessToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search name, PID or command", text: $model.searchText)
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("Sort by", selection: $model.sortKey) {
                Text("CPU").tag(SortKey.cpu)
                Text("Memory").tag(SortKey.memory)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            .help("Sort by CPU or memory")
        }
    }
}

private struct PanelFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            let selected = model.selectedProcesses
            if selected.isEmpty {
                Text("\(model.snapshot.processes.count) processes · \(model.groups.count) groups")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("\(selected.count) selected · \(Formatting.bytes(selected.reduce(0) { $0 + $1.memoryBytes }))")
                    .font(.system(size: 11, weight: .semibold))
                Button("Clear") { model.selection.removeAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Spacer()
                ConfirmButton(title: "Quit selected", confirmTitle: "Quit \(selected.count)?") {
                    model.quitSelection()
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .animation(.snappy, value: model.selection.isEmpty)
    }
}
