import MemSlopCore
import SwiftUI

/// Grouped, expandable process list shared by the panel and the dashboard.
struct ProcessList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.snapshot.processes.isEmpty {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading processes…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.groups.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.groups) { group in
                        GroupRow(group: group, coreCount: model.system.coreCount, memoryTotal: model.system.memoryTotal)
                        if model.expandedGroups.contains(group.id) || !model.searchText.isEmpty {
                            ForEach(group.processes) { process in
                                ProcessRow(process: process)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
        }
    }
}

struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: ProcessGroup
    let coreCount: Int
    let memoryTotal: UInt64
    @State private var hovering = false

    var body: some View {
        let expanded = model.expandedGroups.contains(group.id)
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)
            GroupIcon(group: group)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(group.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    let slop = group.processes.filter { model.slopMatches[$0.id] != nil }.count
                    if slop > 0 {
                        Text("\(slop) slop")
                            .font(.system(size: 8.5, weight: .heavy))
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .foregroundStyle(Theme.slop)
                            .background(Theme.slop.opacity(0.16), in: Capsule())
                    }
                    if group.processes.count > 1 {
                        Text("\(group.processes.count)")
                            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                MiniMeter(
                    value: model.sortKey == .cpu
                        ? group.cpuPercent / Double(max(1, coreCount) * 100)
                        : Double(group.memoryBytes) / Double(max(1, memoryTotal)),
                    color: model.sortKey == .cpu ? Theme.cpu : Theme.memory
                )
            }
            Spacer(minLength: 6)
            if hovering {
                ConfirmButton(
                    title: group.processes.count > 1 ? "Quit all" : "Quit",
                    confirmTitle: group.processes.count > 1 ? "Quit \(group.processes.count)?" : "Sure?"
                ) { model.quit(group) }
                .transition(.opacity)
            }
            metrics(cpu: group.cpuPercent, memory: group.memoryBytes)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { model.toggleExpanded(group) } }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Collapse" : "Expand")
    }

    private func metrics(cpu: Double, memory: UInt64) -> some View {
        HStack(spacing: 0) {
            Text(Formatting.cpu(cpu))
                .foregroundStyle(model.sortKey == .cpu ? .primary : .secondary)
                .frame(width: 52, alignment: .trailing)
            Text(Formatting.bytes(memory))
                .foregroundStyle(model.sortKey == .memory ? .primary : .secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .font(Theme.number(11.5))
    }
}

struct ProcessRow: View {
    @Environment(AppModel.self) private var model
    let process: ProcessSample
    @State private var hovering = false

    var body: some View {
        let selected = model.selection.contains(process.id)
        let quitting = model.quitting.contains(process.id)
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { selected }, set: { _ in model.toggleSelection(process) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!model.isQuittable(process))
                .padding(.leading, 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(process.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text("\(process.pid)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    if let rule = model.slopMatches[process.id] {
                        SlopBadge(rule: rule, pending: model.reaper.isPending(process.id))
                    }
                }
                if let error = model.errors[process.id] {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.danger)
                } else {
                    Text(process.commandLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .help(process.commandLine)
            Spacer(minLength: 6)
            if quitting {
                ProgressView().controlSize(.mini)
            } else if hovering, model.isQuittable(process) {
                Button { model.quit(process) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit \(process.name)")
            }
            HStack(spacing: 0) {
                Text(Formatting.cpu(process.cpuPercent)).frame(width: 52, alignment: .trailing)
                Text(Formatting.bytes(process.memoryBytes)).frame(width: 64, alignment: .trailing)
            }
            .font(Theme.number(11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            selected ? Color.accentColor.opacity(0.14) : (hovering ? Color.primary.opacity(0.05) : .clear),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .opacity(quitting ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if model.isQuittable(process) { model.toggleSelection(process) } }
        .onHover { hovering = $0 }
    }
}
