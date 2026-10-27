import MemSlopCore
import SwiftUI

/// The full window: Overview · Processes · Activity · Rules.
struct DashboardView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview, processes, activity, rules
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .processes: "Processes"
            case .activity: "Activity"
            case .rules: "Rules"
            }
        }

        var symbol: String {
            switch self {
            case .overview: "gauge.with.dots.needle.67percent"
            case .processes: "square.stack.3d.up"
            case .activity: "clock.arrow.circlepath"
            case .rules: "list.bullet.rectangle"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("dashboardSection") private var section: Section = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: Binding(get: { section }, set: { if let value = $0 { section = value } })) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(badge(for: item))
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Wordmark(size: 14)
                    Spacer()
                    Button { WindowManager.shared.show(.settings) } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.borderless)
                        .help("Settings")
                }
                .padding(14)
            }
        } detail: {
            Group {
                switch section {
                case .overview: OverviewPage()
                case .processes: ProcessesPage()
                case .activity: ActivityPage()
                case .rules: RulesPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(section.title)
        }
        .onAppear { model.isDashboardVisible = true }
    }

    private func badge(for section: Section) -> Int {
        switch section {
        case .activity: model.reaper.pending.count
        default: 0
        }
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage("chartRange") private var range = 3600.0

    var body: some View {
        let system = model.system
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatCard(title: "CPU", value: Formatting.percent(system.cpuUsage),
                             detail: "\(Formatting.percent(system.cpuUser)) user · \(Formatting.percent(system.cpuSystem)) system",
                             ratio: system.cpuUsage, color: Theme.cpu)
                    StatCard(title: "Memory", value: Formatting.percent(system.memoryUsage),
                             detail: "\(Formatting.bytes(system.memoryUsed)) of \(Formatting.bytes(system.memoryTotal))",
                             ratio: system.memoryUsage, color: Theme.memory)
                    StatCard(title: "Pressure", value: system.pressure.title,
                             detail: "Swap \(Formatting.bytes(system.swapUsed)) · compressed \(Formatting.bytes(system.memoryCompressed))",
                             ratio: nil, color: system.pressure.color)
                    StatCard(title: "Load", value: String(format: "%.2f", system.loadAverage.first ?? 0),
                             detail: "5 min \(String(format: "%.2f", system.loadAverage[safe: 1] ?? 0)) · 15 min \(String(format: "%.2f", system.loadAverage[safe: 2] ?? 0)) · \(system.coreCount) cores",
                             ratio: min(1, (system.loadAverage.first ?? 0) / Double(max(1, system.coreCount))), color: Theme.cpu)
                }

                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("History").font(.headline)
                            Spacer()
                            Picker("Range", selection: $range) {
                                Text("1 h").tag(3600.0)
                                Text("6 h").tag(6 * 3600.0)
                                Text("24 h").tag(24 * 3600.0)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 180)
                        }
                        HistoryChart(range: range)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Card(padding: 16) { TopConsumers() }
                    Card(padding: 16) { AutoCleanSummary() }
                        .frame(width: 320)
                }
            }
            .padding(20)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let ratio: Double?
    let color: Color

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Theme.number(28, weight: .bold))
                    .foregroundStyle(ratio.map { Theme.load($0, base: color) } ?? color)
                if let ratio {
                    MiniMeter(value: ratio, color: Theme.load(ratio, base: color), width: 160)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TopConsumers: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Biggest right now").font(.headline)
                Spacer()
                Text("by memory").font(.caption).foregroundStyle(.secondary)
            }
            if model.topGroups.isEmpty {
                Text("Reading processes…").foregroundStyle(.secondary)
            }
            let maxMemory = Double(model.topGroups.first?.memoryBytes ?? 1)
            ForEach(model.topGroups) { group in
                HStack(spacing: 10) {
                    GroupIcon(group: group, size: 20)
                    Text(group.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        .frame(width: 170, alignment: .leading)
                    MiniMeter(value: Double(group.memoryBytes) / maxMemory, color: Theme.memory, width: 140)
                    Spacer()
                    Text(Formatting.cpu(group.cpuPercent)).font(Theme.number(11.5)).foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                    Text(Formatting.bytes(group.memoryBytes)).font(Theme.number(12))
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}

private struct AutoCleanSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let reaper = model.reaper
        let today = Calendar.current.startOfDay(for: Date())
        let closedToday = reaper.log.entries.filter { $0.date >= today && $0.outcome.freedMemory }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Auto-clean", systemImage: "sparkles").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(get: { reaper.configuration.isEnabled }, set: { reaper.configuration.isEnabled = $0 }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Formatting.bytes(reaper.freedToday)).font(Theme.number(30, weight: .bold)).foregroundStyle(Theme.slop)
                Text("freed today").foregroundStyle(.secondary)
            }
            Text("\(closedToday) process\(closedToday == 1 ? "" : "es") closed · \(model.slopMatches.count) slop running now")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            if reaper.configuration.isEnabled {
                HStack(spacing: 4) {
                    Text("Next check")
                    Text(reaper.nextSweep, style: .relative)
                }
                .font(.callout.monospacedDigit())
                if let summary = reaper.lastSummary {
                    Text("Last check: \(summary)").font(.caption).foregroundStyle(.secondary)
                }
                Button("Check now") { model.sweepNow() }
                    .disabled(reaper.isClosing)
            } else {
                Text("Turn it on to close idle dev servers, test browsers and agent leftovers every \(reaper.configuration.intervalMinutes) minutes.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Processes

private struct ProcessesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search name, PID or command", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Picker("Sort by", selection: $model.sortKey) {
                    Text("CPU").tag(SortKey.cpu)
                    Text("Memory").tag(SortKey.memory)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Spacer()
                Button(model.expandedGroups.isEmpty ? "Expand all" : "Collapse all") {
                    model.expandedGroups = model.expandedGroups.isEmpty ? Set(model.groups.map(\.id)) : []
                }
                let selected = model.selectedProcesses
                if !selected.isEmpty {
                    Text("\(selected.count) selected · \(Formatting.bytes(selected.reduce(0) { $0 + $1.memoryBytes }))")
                        .font(.callout.weight(.semibold))
                    ConfirmButton(title: "Quit selected", confirmTitle: "Quit \(selected.count)?") { model.quitSelection() }
                }
            }
            .padding(16)
            Divider()
            ProcessList()
        }
    }
}

// MARK: - Activity

private struct ActivityPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter: ActivityEntry.Outcome?
    @State private var query = ""

    var body: some View {
        let entries = model.reaper.log.entries
            .filter { filter == nil || $0.outcome == filter }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.commandLine.localizedCaseInsensitiveContains(query) }
            .sorted { $0.date > $1.date }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Show", selection: $filter) {
                    Text("All").tag(ActivityEntry.Outcome?.none)
                    Text("Closed").tag(ActivityEntry.Outcome?.some(.quit))
                    Text("Forced").tag(ActivityEntry.Outcome?.some(.forced))
                    Text("Kept").tag(ActivityEntry.Outcome?.some(.kept))
                    Text("Dry run").tag(ActivityEntry.Outcome?.some(.wouldQuit))
                    Text("Failed").tag(ActivityEntry.Outcome?.some(.failed))
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Spacer()
                Text("Last 24 hours").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing cleaned yet",
                    systemImage: "sparkles",
                    description: Text("When auto-clean closes or keeps a process, it shows up here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                Table(entries) {
                    TableColumn("Time") { Text($0.date, format: .dateTime.hour().minute().second()).monospacedDigit() }
                        .width(80)
                    TableColumn("Process") { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).fontWeight(.medium)
                            Text(entry.commandLine).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .help(entry.commandLine)
                    }
                    TableColumn("Rule", value: \.rule).width(140)
                    TableColumn("Why") { Text($0.reason).foregroundStyle(.secondary) }.width(150)
                    TableColumn("Memory") { Text(Formatting.bytes($0.memoryBytes)).monospacedDigit() }.width(70)
                    TableColumn("Result") { OutcomeBadge(outcome: $0.outcome) }.width(100)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct OutcomeBadge: View {
    let outcome: ActivityEntry.Outcome

    var body: some View {
        Text(outcome.title)
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch outcome {
        case .quit: Theme.memory
        case .forced: Theme.slop
        case .failed: Theme.danger
        case .wouldQuit: Theme.cpu
        case .kept: .secondary
        }
    }
}

// MARK: - Rules

private struct RulesPage: View {
    @State private var kind = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $kind) {
                Text("Slop rules").tag(0)
                Text("Protected").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding([.top, .horizontal], 20)
            RulesSettings(kind: kind == 0 ? .slop : .protected)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
