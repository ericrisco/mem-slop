import AppKit
import SwiftUI

/// Opens and reuses the app's windows. While any is open the app shows in the Dock and ⌘-Tab.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    enum Kind: String {
        case settings
        case dashboard
    }

    private var windows: [Kind: NSWindow] = [:]
    var model: AppModel?

    func show(_ kind: Kind) {
        guard let model else { return }
        let window = windows[kind] ?? makeWindow(kind, model: model)
        windows[kind] = window
        if kind == .dashboard { model.isDashboardVisible = true }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(_ kind: Kind, model: AppModel) -> NSWindow {
        let window: NSWindow
        switch kind {
        case .settings:
            window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(model)))
            window.title = "MemSlop Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
        case .dashboard:
            window = NSWindow(contentViewController: NSHostingController(rootView: DashboardView().environment(model)))
            window.title = "MemSlop"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 1080, height: 720))
            window.minSize = NSSize(width: 860, height: 560)
            window.setFrameAutosaveName("MemSlopDashboard")
        }
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let stillOpen = windows.values.contains { $0 !== closing && $0.isVisible }
        if !stillOpen {
            NSApp.setActivationPolicy(.accessory)
        }
        if windows[.dashboard] === closing { model?.isDashboardVisible = false }
    }
}
