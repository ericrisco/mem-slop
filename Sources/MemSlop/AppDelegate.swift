import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WindowManager.shared.model = model
        statusController = StatusItemController(model: model)
        model.start()
        for argument in CommandLine.arguments where argument.hasPrefix("--open=") {
            if let kind = WindowManager.Kind(rawValue: String(argument.dropFirst("--open=".count))) {
                WindowManager.shared.show(kind)
            }
        }
        if DemoData.isEnabled {
            Task {
                try? await Task.sleep(for: .seconds(1))
                model.reaper.showDemoPending(model.snapshot)
            }
        }
        if CommandLine.arguments.contains("--show-panel") {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                statusController?.showPanel(pinned: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
