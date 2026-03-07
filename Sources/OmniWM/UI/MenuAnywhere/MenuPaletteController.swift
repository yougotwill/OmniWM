import AppKit
import ApplicationServices
import SwiftUI
@MainActor
final class MenuPaletteController: ObservableObject {
    static let shared = MenuPaletteController()
    @Published var isVisible = false
    @Published var searchText = "" {
        didSet {
            updateSelectionAfterFilterChange()
        }
    }
    @Published var selectedItemId: UUID?
    @Published var menuItems: [MenuItemModel] = [] {
        didSet { updateSelectionAfterFilterChange() }
    }
    @Published var isLoading = false
    var showShortcuts = true
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private let fetcher = MenuAnywhereFetcher()
    private(set) weak var currentApp: NSRunningApplication?
    private var currentWindow: AXUIElement?
    private static let kAXPressAction = "AXPress" as CFString
    private static let appActivationDelay: TimeInterval = 0.1
    private func restoreFocusToTargetApp() {
        guard let app = currentApp, !app.isTerminated else { return }
        guard let window = currentWindow else {
            app.activate()
            return
        }
        guard let windowId = getWindowId(from: window) else {
            app.activate()
            return
        }
        SkyLight.shared.orderWindow(UInt32(windowId), relativeTo: 0, order: .above)
        var psn = ProcessSerialNumber()
        if GetProcessForPID(app.processIdentifier, &psn) == noErr {
            _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(windowId), kCPSUserGenerated)
            makeKeyWindow(psn: &psn, windowId: UInt32(windowId))
        }
        app.activate()
    }
    var filteredItems: [MenuItemModel] {
        filterItems(menuItems, query: searchText)
    }
    private init() {}
    private func filterItems(_ items: [MenuItemModel], query rawQuery: String) -> [MenuItemModel] {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return items
        }
        let query = trimmedQuery.lowercased()
        let scored: [(MenuItemModel, Int)] = items.compactMap { item in
            let titleLower = item.title.lowercased()
            let pathLower = item.fullPath.lowercased()
            if let range = titleLower.range(of: query) {
                let pos = titleLower.distance(from: titleLower.startIndex, to: range.lowerBound)
                return (item, pos)
            }
            if let range = pathLower.range(of: query) {
                let pos = pathLower.distance(from: pathLower.startIndex, to: range.lowerBound)
                return (item, 1000 + pos)
            }
            return nil
        }
        return scored
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.0.title.count != b.0.title.count { return a.0.title.count < b.0.title.count }
                return a.0.title < b.0.title
            }
            .map(\.0)
    }
    func show(
        at position: MenuAnywherePosition,
        showShortcuts: Bool,
        targetApp: NSRunningApplication,
        targetWindow: AXUIElement?
    ) {
        self.showShortcuts = showShortcuts
        currentApp = targetApp
        currentWindow = targetWindow
        searchText = ""
        let items = fetcher.fetchMenuItemsSync(for: targetApp.processIdentifier)
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        positionPanel(panel, at: position)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isVisible else { return event }
            switch event.keyCode {
            case 53:
                hide()
                return nil
            case 126:
                moveSelection(by: -1)
                return nil
            case 125:
                moveSelection(by: 1)
                return nil
            case 36:
                selectCurrent()
                return nil
            default:
                return event
            }
        }
        menuItems = items
        isLoading = false
        selectedItemId = items.first?.id
        isVisible = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.focusSearchField()
        }
    }
    private func positionPanel(_ panel: NSPanel, at position: MenuAnywherePosition) {
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 400
        let mouseLocation = NSEvent.mouseLocation
        let point: NSPoint
        switch position {
        case .cursor:
            point = NSPoint(
                x: mouseLocation.x - panelWidth / 2,
                y: mouseLocation.y - panelHeight / 2
            )
        case .centered, .menuBarLocation:
            guard let screen = NSScreen.screen(containing: mouseLocation) ?? NSScreen.main else {
                point = mouseLocation
                break
            }
            point = NSPoint(
                x: (screen.frame.width - panelWidth) / 2 + screen.frame.origin.x,
                y: (screen.frame.height - panelHeight) / 2 + screen.frame.origin.y + 100
            )
        }
        panel.setFrame(NSRect(x: point.x, y: point.y, width: panelWidth, height: panelHeight), display: true)
    }
    func hide() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isVisible = false
        panel?.orderOut(nil)
        restoreFocusToTargetApp()
        searchText = ""
        selectedItemId = nil
        menuItems = []
    }
    func selectCurrent() {
        let filtered = filteredItems
        guard let id = selectedItemId,
              let item = filtered.first(where: { $0.id == id }) else { return }
        hide()
        executeMenuItem(item)
    }
    private func executeMenuItem(_ item: MenuItemModel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.appActivationDelay) {
            AXUIElementPerformAction(item.axElement, Self.kAXPressAction)
        }
    }
    func moveSelection(by delta: Int) {
        let filtered = filteredItems
        guard !filtered.isEmpty else { return }
        let currentIndex: Int = if let id = selectedItemId,
                                   let idx = filtered.firstIndex(where: { $0.id == id })
        {
            idx
        } else {
            0
        }
        let newIndex = (currentIndex + delta + filtered.count) % filtered.count
        selectedItemId = filtered[newIndex].id
    }
    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        let hostingView = NSHostingView(rootView: MenuPaletteView(controller: self))
        panel.contentView = hostingView
        self.panel = panel
    }
    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }
    func focusSearchField() {
        guard let contentView = panel?.contentView,
              let textField = findTextField(in: contentView) else { return }
        panel?.makeFirstResponder(textField)
    }
    private func updateSelectionAfterFilterChange() {
        let filtered = filteredItems
        if filtered.isEmpty {
            selectedItemId = nil
            return
        }
        if let id = selectedItemId, !filtered.contains(where: { $0.id == id }) {
            selectedItemId = filtered.first?.id
        } else if selectedItemId == nil {
            selectedItemId = filtered.first?.id
        }
    }
}
