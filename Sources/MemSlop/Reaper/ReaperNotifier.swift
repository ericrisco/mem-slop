import Foundation
import MemSlopCore
import UserNotifications

/// Posts "about to close" and "closed" notifications, with Keep / Close now actions.
@MainActor
final class ReaperNotifier: NSObject, UNUserNotificationCenterDelegate {
    var onKeepAll: (() -> Void)?
    var onCloseNow: (() -> Void)?

    private static let category = "memslop.reap"
    private static let keepAction = "memslop.keep"
    private static let closeAction = "memslop.close"
    private static let pendingID = "memslop.pending"

    /// Notifications need a real app bundle; `swift run` has none.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleIdentifier == nil ? nil : .current()
    private var authorized = false

    override init() {
        super.init()
        guard let center else { return }
        center.delegate = self
        let keep = UNNotificationAction(identifier: Self.keepAction, title: "Keep them", options: [])
        let close = UNNotificationAction(identifier: Self.closeAction, title: "Close now", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [keep, close], intentIdentifiers: [], options: []),
        ])
        Task {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func announce(_ candidates: [ReapCandidate], in seconds: Int) {
        let names = candidates.prefix(3).map(\.process.name).joined(separator: ", ")
        let more = candidates.count > 3 ? " and \(candidates.count - 3) more" : ""
        let memory = Formatting.bytes(candidates.reduce(0) { $0 + $1.process.memoryBytes })
        post(
            id: Self.pendingID,
            title: "Cleaning up \(candidates.count) idle process\(candidates.count == 1 ? "" : "es") in \(seconds) s",
            body: "\(names)\(more) · \(memory)",
            actionable: true
        )
    }

    func report(closed: Int, freed: UInt64) {
        withdraw()
        guard closed > 0 else { return }
        post(id: UUID().uuidString, title: "Freed \(Formatting.bytes(freed))",
             body: "Closed \(closed) idle process\(closed == 1 ? "" : "es").", actionable: false)
    }

    func learningFinished(processes: Int, memory: UInt64) {
        let body = processes == 0
            ? "Nothing idle needed closing. Open MemSlop to turn auto-clean on."
            : "It would have closed \(processes) idle process\(processes == 1 ? "" : "es"), freeing \(Formatting.bytes(memory)). Open MemSlop to turn auto-clean on."
        post(id: "memslop.learning", title: "Your first day with MemSlop", body: body, actionable: false)
    }

    func withdraw() {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.pendingID])
        center?.removePendingNotificationRequests(withIdentifiers: [Self.pendingID])
    }

    private func post(id: String, title: String, body: String, actionable: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if actionable { content.categoryIdentifier = Self.category }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.keepAction: onKeepAll?()
            case Self.closeAction: onCloseNow?()
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
