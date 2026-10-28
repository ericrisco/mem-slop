import MemSlopCore
import SwiftUI

/// Auto-clean status in the panel: next check, pending closes with Keep, last result.
struct ReaperStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let reaper = model.reaper
        if !reaper.pending.isEmpty, let deadline = reaper.pendingDeadline {
            PendingCard(deadline: deadline)
        } else if reaper.learningPhase == .awaitingDecision {
            LearningSummaryCard()
        } else {
            HStack(spacing: 8) {
                Image(systemName: reaper.configuration.isEnabled ? "sparkles" : "sparkles.slash")
                    .foregroundStyle(reaper.configuration.isEnabled ? Theme.slop : .secondary)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    if reaper.configuration.isEnabled {
                        HStack(spacing: 4) {
                            Text("Auto-clean every \(reaper.configuration.intervalMinutes) min")
                            if reaper.isLearning {
                                Text("LEARNING")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .padding(.horizontal, 4)
                                    .background(Theme.cpu.opacity(0.2), in: Capsule())
                            } else if reaper.isDryRun {
                                Text("DRY RUN")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .padding(.horizontal, 4)
                                    .background(Theme.slop.opacity(0.2), in: Capsule())
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        statusLine(reaper)
                    } else {
                        Text("Auto-clean is off").font(.system(size: 11.5, weight: .semibold))
                        Text("\(model.slopMatches.count) processes match slop rules")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if reaper.configuration.isEnabled {
                    Button {
                        model.sweepNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Check for idle slop now")
                    .disabled(reaper.isClosing)
                }
                Toggle("", isOn: Binding(
                    get: { reaper.configuration.isEnabled },
                    set: { reaper.configuration.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Turn auto-clean on or off")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .safeAreaInset(edge: .bottom, spacing: 0) { CloseAllSlopRow() }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder private func statusLine(_ reaper: ReaperEngine) -> some View {
        HStack(spacing: 4) {
            if case let .learning(remaining) = reaper.learningPhase {
                Text("Closes nothing for \(Formatting.duration(remaining))")
                if reaper.learning.processCount > 0 {
                    Text("· would close \(reaper.learning.processCount) · \(Formatting.bytes(reaper.learning.memoryBytes))")
                }
            } else if reaper.isClosing {
                Text("Closing…")
            } else {
                Text("Next check")
                Text(reaper.nextSweep, style: .relative)
            }
            if reaper.isLearning {
                EmptyView()
            } else if reaper.freedToday > 0 {
                Text("· freed \(Formatting.bytes(reaper.freedToday)) today")
            } else if let summary = reaper.lastSummary {
                Text("· \(summary)")
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct PendingCard: View {
    @Environment(AppModel.self) private var model
    let deadline: Date

    var body: some View {
        let pending = model.reaper.pending
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "timer").foregroundStyle(Theme.slop)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(deadline.timeIntervalSince(context.date)))
                    Text("Closing \(pending.count) idle process\(pending.count == 1 ? "" : "es") in \(remaining) s")
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
                Spacer()
                Button("Keep all") { model.reaper.keepAll() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                Button("Close now") { model.reaper.closeNow(); model.sweepNow() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            ForEach(pending.prefix(4)) { candidate in
                HStack(spacing: 6) {
                    Text(candidate.process.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(candidate.ancestry.label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(Formatting.bytes(candidate.process.memoryBytes)).font(Theme.number(10.5)).foregroundStyle(.secondary)
                    Button("Keep") { model.reaper.keep(candidate.id) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5, weight: .semibold))
                }
            }
            if pending.count > 4 {
                Text("+ \(pending.count - 4) more").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Theme.slop.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.slop.opacity(0.35)))
    }
}

/// One click (plus a confirming second) closes every process the slop rules match.
private struct CloseAllSlopRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let slop = model.slopProcesses
        if !slop.isEmpty {
            HStack(spacing: 6) {
                Text("\(slop.count) slop process\(slop.count == 1 ? "" : "es") running · \(Formatting.bytes(slop.reduce(0) { $0 + $1.memoryBytes }))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                ConfirmButton(title: "Close all slop", confirmTitle: "Close \(slop.count)?", systemImage: "trash") {
                    model.quitAllSlop()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

/// End of the first day: what MemSlop would have done, and the choice to turn it on.
private struct LearningSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let learning = model.reaper.learning
        VStack(alignment: .leading, spacing: 8) {
            Label("Your first day with MemSlop", systemImage: "graduationcap.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.cpu)
            Text(learning.processCount == 0
                 ? "Nothing idle needed closing. Turn auto-clean on to keep it that way."
                 : "It would have closed \(learning.processCount) idle process\(learning.processCount == 1 ? "" : "es") and freed \(Formatting.bytes(learning.memoryBytes)). Everything is in the activity log.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Turn on auto-clean") { model.reaper.finishLearning(enable: true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Keep dry run") { model.reaper.finishLearning(enable: false) }
                    .controlSize(.small)
                Spacer()
                Button("See log") { WindowManager.shared.show(.dashboard) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
        .padding(10)
        .background(Theme.cpu.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cpu.opacity(0.3)))
    }
}

/// Small "slop" tag on processes that match a slop rule.
struct SlopBadge: View {
    let rule: String
    var pending = false

    var body: some View {
        Text(pending ? "closing" : "slop")
            .font(.system(size: 8.5, weight: .heavy))
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(pending ? .white : Theme.slop)
            .background(pending ? Theme.slop : Theme.slop.opacity(0.16), in: Capsule())
            .help("Matches slop rule “\(rule)”")
    }
}
