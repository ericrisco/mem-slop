import AppKit
import CryptoKit
import MemSlopCore
import Observation
import UserNotifications

/// Checks GitHub for new releases once a day and installs them in place.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case installing(ReleaseInfo)
        case failed(String)
    }

    enum Failure: LocalizedError {
        case notWritable(String)
        case badChecksum
        case invalidBundle(String)
        case tool(String)

        var errorDescription: String? {
            switch self {
            case let .notWritable(folder): "\(folder) is not writable. Update with: curl -fsSL https://raw.githubusercontent.com/\(ReleaseInfo.repository)/main/install.sh | bash"
            case .badChecksum: "The download did not match its checksum. Nothing was changed."
            case let .invalidBundle(reason): "The downloaded app failed verification (\(reason)). Nothing was changed."
            case let .tool(message): message
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var lastCheck: Date? = UserDefaults.standard.object(forKey: "updateLastCheck") as? Date

    var checkAutomatically: Bool = UserDefaults.standard.object(forKey: "updateCheckAutomatically") as? Bool ?? true {
        didSet { UserDefaults.standard.set(checkAutomatically, forKey: "updateCheckAutomatically") }
    }
    var installAutomatically: Bool = UserDefaults.standard.object(forKey: "updateInstallAutomatically") as? Bool ?? true {
        didSet { UserDefaults.standard.set(installAutomatically, forKey: "updateInstallAutomatically") }
    }

    /// Returns true while auto-install must wait (a cleanup warning is on screen).
    @ObservationIgnored var isBusy: () -> Bool = { false }
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let checkInterval: TimeInterval = 24 * 3600
    static var currentVersion: SemanticVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(SemanticVersion.init)
    }

    var availableRelease: ReleaseInfo? {
        if case let .available(release) = state { return release }
        return nil
    }

    func start() {
        guard loop == nil, !DemoData.isEnabled else { return }
        announceCompletedUpdate()
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func tick() async {
        if checkAutomatically, Date().timeIntervalSince(lastCheck ?? .distantPast) >= Self.checkInterval {
            await check()
        }
        if installAutomatically, let release = availableRelease, !isBusy() {
            await install(release)
        }
    }

    // MARK: - Check

    func check() async {
        guard state != .checking, Self.currentVersion != nil else { return }
        if case .installing = state { return }
        state = .checking
        do {
            var request = URLRequest(url: ReleaseInfo.latestURL, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MemSlop/\(Self.currentVersion?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = ReleaseInfo.parse(data) else {
                throw Failure.tool("GitHub did not return a usable release.")
            }
            lastCheck = Date()
            UserDefaults.standard.set(lastCheck, forKey: "updateLastCheck")
            if let current = Self.currentVersion, release.version > current {
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Install

    func install(_ release: ReleaseInfo) async {
        state = .installing(release)
        do {
            try await performInstall(release)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func performInstall(_ release: ReleaseInfo) async throws {
        let app = Bundle.main.bundleURL
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw Failure.notWritable(folder.path) }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MemSlop-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let (archive, _) = try await URLSession.shared.download(from: release.archiveURL)
        let (checksumData, _) = try await URLSession.shared.data(from: release.checksumURL)
        guard let expected = ReleaseInfo.parseChecksum(String(decoding: checksumData, as: UTF8.self)) else { throw Failure.badChecksum }
        let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw Failure.badChecksum }

        let unpacked = work.appendingPathComponent("unpacked")
        try await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let candidate = unpacked.appendingPathComponent("MemSlop.app")
        let info = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { throw Failure.invalidBundle("wrong bundle identifier") }
        guard (info?["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init) == release.version else {
            throw Failure.invalidBundle("wrong version")
        }
        do {
            try await Self.run("/usr/bin/codesign", ["--verify", "--strict", "--deep", candidate.path])
        } catch {
            throw Failure.invalidBundle("invalid code signature")
        }

        // Stage next to the running app so the final swap is a rename on the same volume.
        let staged = folder.appendingPathComponent("MemSlop.app.new")
        try? FileManager.default.removeItem(at: staged)
        try await Self.run("/usr/bin/ditto", [candidate.path, staged.path])
        try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        UserDefaults.standard.set(release.version.description, forKey: "updateInstalledVersion")
        try Self.launchSwap(app: app, staged: staged)
        NSApp.terminate(nil)
    }

    /// A detached script waits for MemSlop to quit, swaps the bundles, and reopens the app.
    private static func launchSwap(app: URL, staged: URL) throws {
        let script = """
        pid="$1"; app="$2"; staged="$3"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "${app}.old"
        if mv "$app" "${app}.old" && mv "$staged" "$app"; then
          rm -rf "${app}.old"
        else
          [ -d "$app" ] || mv "${app}.old" "$app"
        fi
        open "$app"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "memslop-update", String(getpid()), app.path, staged.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Failure.tool("\((tool as NSString).lastPathComponent) failed (\(process.terminationStatus))"))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// After an update relaunch: say so once.
    private func announceCompletedUpdate() {
        guard let installed = UserDefaults.standard.string(forKey: "updateInstalledVersion") else { return }
        UserDefaults.standard.removeObject(forKey: "updateInstalledVersion")
        guard installed == Self.currentVersion?.description else { return }
        let content = UNMutableNotificationContent()
        content.title = "MemSlop updated to \(installed)"
        content.body = "See what's new in Settings → About."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "memslop.updated", content: content, trigger: nil))
    }
}
