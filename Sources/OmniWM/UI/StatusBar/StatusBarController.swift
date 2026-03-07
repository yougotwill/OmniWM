import AppKit
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var menuBuilder: StatusBarMenuBuilder?
    private var menu: NSMenu?
    private let settings: SettingsStore
    private weak var controller: WMController?
    init(settings: SettingsStore, controller: WMController) {
        self.settings = settings
        self.controller = controller
        super.init()
    }
    func setup() {
        guard statusItem == nil, let controller else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "o.circle", accessibilityDescription: "OmniWM")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem?.autosaveName = "omniwm_main"
        menuBuilder = StatusBarMenuBuilder(settings: settings, controller: controller)
        menu = menuBuilder?.buildMenu()
    }
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            handleRightClick()
        } else {
            showMenu()
        }
    }
    private func showMenu() {
        guard let button = statusItem?.button, let menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }
    private func handleRightClick() {
        guard settings.hiddenBarEnabled else {
            showMenu()
            return
        }
        controller?.toggleHiddenBar()
    }
    func refreshMenu() {
        menuBuilder?.updateToggles()
    }
    func cleanup() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        menuBuilder = nil
        menu = nil
    }
}
