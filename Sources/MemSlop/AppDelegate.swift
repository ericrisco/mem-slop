import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(model: model)
        model.start()
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
