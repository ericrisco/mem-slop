import MemSlopCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AutoCleanSettings()
                .tabItem { Label("Auto-clean", systemImage: "sparkles") }
                .tag("autoclean")
            AgentsSettings()
                .tabItem { Label("Agents", systemImage: "terminal") }
                .tag("agents")
            RulesSettings(kind: .slop)
                .tabItem { Label("Slop rules", systemImage: "list.bullet.rectangle") }
                .tag("rules")
            RulesSettings(kind: .protected)
                .tabItem { Label("Protected", systemImage: "lock.shield") }
                .tag("protected")
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
        .frame(width: 680, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Menu bar") {
                Picker("Style", selection: $model.displayStyle) {
                    ForEach(DisplayStyle.allCases) { style in
                        HStack {
                            Image(nsImage: IndicatorRenderer.image(for: .init(style: style, cpu: 0.23, memory: 0.61)))
                            Text(style.title)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Refresh every", selection: $model.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            }
            UpdatesSection()
            Section("Startup") {
                Toggle("Open MemSlop at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Theme.danger)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription). Move MemSlop to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Auto-clean

private struct AutoCleanSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var reaper = model.reaper
        Form {
            Section {
                Toggle(isOn: $reaper.configuration.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean up idle dev slop automatically")
                        Text("Closes forgotten dev servers, test browsers and leftovers from AI agents.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Check every", selection: $reaper.configuration.intervalMinutes) {
                    ForEach(ReaperConfiguration.intervalChoices, id: \.self) { minutes in
                        Text(minutes == 60 ? "1 h" : "\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                Text("A process must have been idle for this whole time to be closed.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $reaper.configuration.cleanOnPressure) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean early when memory is critical")
                        Text("If memory pressure stays red for 30 s, check right away. Processes idle for 5 min qualify. Same warning and Keep button.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Safety") {
                Toggle("Warn \(reaper.configuration.graceSeconds) s before closing, with a Keep button", isOn: $reaper.configuration.notifyBefore)
                Toggle("Dry run: only log what would be closed", isOn: $reaper.configuration.dryRun)
                LabeledContent("Idle means CPU below") {
                    Stepper(value: $reaper.configuration.cpuThreshold, in: 0.1...5, step: 0.1) {
                        Text(String(format: "%.1f%%", reaper.configuration.cpuThreshold)).monospacedDigit()
                    }
                }
                LabeledContent("and memory changing less than") {
                    Stepper(value: $reaper.configuration.memoryChangeFraction, in: 0.01...0.5, step: 0.01) {
                        Text("\(Int((reaper.configuration.memoryChangeFraction * 100).rounded()))%").monospacedDigit()
                    }
                }
            }
            Section("A process is only ever closed when") {
                VStack(alignment: .leading, spacing: 6) {
                    SafetyLine("It matches an enabled slop rule and no protected rule")
                    SafetyLine("It belongs to you and is not a regular app (except test browsers)")
                    SafetyLine("It is not attached to a terminal or IDE, unless an AI agent started it")
                    SafetyLine("It and its children were idle for the whole interval and stayed idle during the warning")
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SafetyLine: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.memory)
        }
    }
}

// MARK: - Rules

struct RulesSettings: View {
    enum Kind { case slop, protected }

    @Environment(AppModel.self) private var model
    let kind: Kind

    var body: some View {
        @Bindable var reaper = model.reaper
        let rules = kind == .slop ? $reaper.configuration.rules : $reaper.configuration.protected
        VStack(alignment: .leading, spacing: 10) {
            Text(kind == .slop
                 ? "Processes matching these rules may be closed when idle. Changes apply on the next check."
                 : "Processes matching these rules are never closed automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            RuleEditor(rules: rules, allowsApps: kind == .slop, running: runningCount)
            HStack {
                Button {
                    rules.wrappedValue.insert(ProcessRule(name: "New rule", field: kind == .slop ? .command : .app, pattern: ""), at: 0)
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                Spacer()
                Button("Restore defaults") {
                    if kind == .slop { model.reaper.restoreDefaultRules() } else { model.reaper.restoreDefaultProtected() }
                }
            }
        }
        .padding(20)
    }

    private func runningCount(_ rule: ProcessRule) -> Int {
        model.snapshot.processes.reduce(0) { $0 + (rule.matches($1) ? 1 : 0) }
    }
}

struct RuleEditor: View {
    @Binding var rules: [ProcessRule]
    let allowsApps: Bool
    let running: (ProcessRule) -> Int

    var body: some View {
        List {
            ForEach($rules) { $rule in
                HStack(spacing: 10) {
                    Toggle("", isOn: $rule.isEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    TextField("Name", text: $rule.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 150)
                    Picker("", selection: $rule.field) {
                        ForEach(ProcessRule.Field.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    TextField("Pattern", text: $rule.pattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .overlay(alignment: .trailing) {
                            if !rule.isValid {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.slop)
                                    .padding(.trailing, 6)
                                    .help("Empty rules never match")
                            }
                        }
                    if allowsApps, rule.matchesApps {
                        Image(systemName: "macwindow").foregroundStyle(.secondary).help("May close regular apps (test browsers)")
                    }
                    let count = running(rule)
                    Text(count == 0 ? "–" : "\(count) running")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(count == 0 ? .tertiary : .secondary)
                        .frame(width: 70, alignment: .trailing)
                    Button {
                        rules.removeAll { $0.id == rule.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove rule")
                }
                .opacity(rule.isEnabled ? 1 : 0.55)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Wordmark(size: 28)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Your AI agents leave slop running. MemSlop cleans it up.")
                .font(.callout)
            Link("github.com/ericrisco/mem-slop", destination: URL(string: "https://github.com/ericrisco/mem-slop")!)
            Text("MIT License · No telemetry. Only network use: a daily update check to GitHub.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Updates

private struct UpdatesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var updater = model.updater
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.checkAutomatically)
            Toggle("Install updates automatically", isOn: $updater.installAutomatically)
                .disabled(!updater.checkAutomatically)
            LabeledContent {
                switch updater.state {
                case .checking:
                    ProgressView().controlSize(.small)
                case let .available(release):
                    Button("Install \(release.version.description) and Relaunch") { Task { await updater.install(release) } }
                case .installing:
                    ProgressView().controlSize(.small)
                default:
                    Button("Check Now") { Task { await updater.check() } }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MemSlop \(Updater.currentVersion?.description ?? "dev")")
                    Text(status(updater))
                        .font(.caption)
                        .foregroundStyle(isFailure(updater.state) ? Theme.danger : .secondary)
                }
            }
            if let release = updater.availableRelease {
                Text(release.notes.isEmpty ? "No release notes." : release.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                Link("Release page", destination: release.pageURL).font(.caption)
            }
        }
    }

    private func status(_ updater: Updater) -> String {
        switch updater.state {
        case .checking: return "Checking GitHub…"
        case let .available(release): return "Version \(release.version) is available."
        case let .installing(release): return "Installing \(release.version)… MemSlop will relaunch."
        case let .failed(message): return message
        case .upToDate, .idle:
            guard let last = updater.lastCheck else { return "Never checked." }
            return "Up to date · checked \(last.formatted(.relative(presentation: .named)))."
        }
    }

    private func isFailure(_ state: Updater.State) -> Bool {
        if case .failed = state { return true }
        return false
    }
}
