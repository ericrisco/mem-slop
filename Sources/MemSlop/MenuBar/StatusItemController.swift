import AppKit
import SwiftUI

/// Owns the menu bar item: renders the indicator and toggles the panel popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var lastRendered: IndicatorRenderer.Values?

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: PanelView(onOpenWindow: { [weak self] in self?.popover.performClose(nil) })
                .environment(model)
        )
        // The panel has a fixed size; letting the hosting controller publish its ideal size
        // makes AppKit re-run constraint layout of the whole popover on every update.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: PanelView.width, height: PanelView.height)

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("MemSlop")
        }
        model.onIndicatorChange = { [weak self] in self?.render() }
        render()
    }

    private func render() {
        let values = IndicatorRenderer.Values(
            style: model.displayStyle,
            cpu: model.system.cpuUsage,
            memory: model.system.memoryUsage
        )
        guard values != lastRendered, let button = item.button else { return }
        lastRendered = values
        button.image = IndicatorRenderer.image(for: values)
        button.toolTip = "CPU \(values.cpu)% · RAM \(values.memory)%"
        button.setAccessibilityValue(button.toolTip)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    /// Shows the panel. `pinned` keeps it open when focus moves away (used for screenshots).
    func showPanel(pinned: Bool = false) {
        guard let button = item.button, !popover.isShown else { return }
        popover.behavior = pinned ? .applicationDefined : .transient
        model.isListVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    private func showMenu() {
        let menu = NSMenu()
        let styles = NSMenuItem(title: "Menu Bar Style", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for style in DisplayStyle.allCases {
            let entry = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = style.rawValue
            entry.state = style == model.displayStyle ? .on : .off
            submenu.addItem(entry)
        }
        styles.submenu = submenu
        menu.addItem(styles)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MemSlop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = DisplayStyle(rawValue: raw) {
            model.displayStyle = style
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.isListVisible = false
    }
}
