import AppKit
import CZigLayout
import Foundation

@MainActor @Observable
final class WMController {
    var isEnabled: Bool = true
    var hotkeysEnabled: Bool = true
    private(set) var focusFollowsMouseEnabled: Bool = false
    private(set) var moveMouseToFocusedWindowEnabled: Bool = false
    private(set) var workspaceBarVersion: Int = 0

    let settings: SettingsStore
    let workspaceManager: WorkspaceManager
    let lockScreenObserver = LockScreenObserver()
    let appInfoCache = AppInfoCache()
    let animationClock = AnimationClock()

    var isLockScreenActive: Bool = false
    var focusedHandle: WindowHandle? {
        didSet {
            updateActiveMonitorFromFocusedHandle(focusedHandle)
            focusNotificationDispatcher.notifyFocusChangesIfNeeded()
        }
    }
    var activeMonitorId: Monitor.ID? {
        didSet {
            focusNotificationDispatcher.notifyFocusChangesIfNeeded()
        }
    }
    var previousMonitorId: Monitor.ID?

    var zigNiriEngine: ZigNiriEngine?
    var dwindleEngine: DwindleLayoutEngine?
    var isTransferringWindow: Bool = false
    var hiddenAppPIDs: Set<pid_t> = []
    var hasStartedServices = false

    private(set) var appRulesByBundleId: [String: AppRule] = [:]

    @ObservationIgnored
    private let coreRuntime: ZigCoreRuntime
    @ObservationIgnored
    private lazy var workspaceBarManager: WorkspaceBarManager = .init()
    @ObservationIgnored
    private lazy var hiddenBarController: HiddenBarController = .init(settings: settings)
    @ObservationIgnored
    private lazy var quakeTerminalController: QuakeTerminalController = .init(settings: settings)
    @ObservationIgnored
    private lazy var overviewController: OverviewController = {
        let controller = self
        let overview = OverviewController(wmController: controller)
        overview.onActivateWindow = { [weak self] handle, workspaceId in
            self?.navigateToWindowInternal(handle: handle, workspaceId: workspaceId)
        }
        overview.onCloseWindow = { [weak self] handle in
            self?.closeWindowFromOverview(handle: handle)
        }
        return overview
    }()
    @ObservationIgnored
    private lazy var focusNotificationDispatcher = FocusNotificationDispatcher(controller: self)

    private var suppressActiveMonitorUpdate = false

    init(
        settings: SettingsStore,
        createBorderRuntime: @escaping () -> OpaquePointer? = { omni_border_runtime_create() }
    ) {
        _ = createBorderRuntime
        self.settings = settings
        workspaceManager = WorkspaceManager(settings: settings)
        coreRuntime = ZigCoreRuntime(workspaceRuntimeHandle: workspaceManager.runtimeHandle)
        coreRuntime.controller = self
        coreRuntime.onSecureInputStateChange = { isSecure in
            if isSecure {
                SecureInputIndicatorController.shared.show()
            } else {
                SecureInputIndicatorController.shared.hide()
            }
        }
        coreRuntime.onTapHealthNotification = { tapKind, reason in
            NSLog("Input runtime tap health tap=%u reason=%u", tapKind, reason)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            coreRuntime.start(
                settings: settings,
                focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
                moveMouseToFocusedWindow: moveMouseToFocusedWindowEnabled
            )
        } else {
            coreRuntime.stop()
        }
        hasStartedServices = coreRuntime.started
    }

    func setHotkeysEnabled(_ enabled: Bool) {
        hotkeysEnabled = enabled
        coreRuntime.setHotkeysEnabled(enabled, settings: settings)
    }

    func setGapSize(_ size: Double) {
        workspaceManager.setGaps(to: size)
    }

    func setOuterGaps(left: Double, right: Double, top: Double, bottom: Double) {
        workspaceManager.setOuterGaps(left: left, right: right, top: top, bottom: bottom)
    }

    func setBordersEnabled(_ enabled: Bool) {
        settings.bordersEnabled = enabled
        refreshBorderPresentation(forceHide: !enabled)
    }

    func updateBorderConfig() {
        refreshBorderPresentation()
    }

    func setWorkspaceBarEnabled(_ enabled: Bool) {
        if enabled {
            workspaceBarManager.setup(controller: self, settings: settings)
        } else {
            workspaceBarManager.removeAllBars()
        }
    }

    func cleanupUIOnStop() {
        workspaceBarManager.cleanup()
        hiddenBarController.cleanup()
    }

    func setPreventSleepEnabled(_ enabled: Bool) {
        if enabled {
            SleepPreventionManager.shared.preventSleep()
        } else {
            SleepPreventionManager.shared.allowSleep()
        }
    }

    func setHiddenBarEnabled(_ enabled: Bool) {
        if enabled {
            hiddenBarController.setup()
        } else {
            hiddenBarController.cleanup()
        }
    }

    func toggleHiddenBar() {
        guard settings.hiddenBarEnabled else { return }
        hiddenBarController.toggle()
    }

    func setQuakeTerminalEnabled(_ enabled: Bool) {
        if enabled {
            quakeTerminalController.setup()
        } else {
            quakeTerminalController.cleanup()
        }
    }

    func toggleQuakeTerminal() {
        guard settings.quakeTerminalEnabled else { return }
        quakeTerminalController.toggle()
    }

    func reloadQuakeTerminalOpacity() {
        quakeTerminalController.reloadOpacityConfig()
    }

    func updateWorkspaceBar() {
        workspaceBarVersion += 1
        workspaceBarManager.update()
    }

    func updateWorkspaceBarSettings() {
        workspaceBarManager.updateSettings()
    }

    func updateMonitorOrientations() {
        refreshLayout()
    }

    func updateMonitorNiriSettings() {
        refreshLayout()
    }

    func updateMonitorDwindleSettings() {
        guard let engine = dwindleEngine else { return }
        for monitor in workspaceManager.monitors {
            let resolved = settings.resolvedDwindleSettings(for: monitor)
            engine.updateMonitorSettings(resolved, for: monitor.id)
        }
        refreshLayout()
    }

    func workspaceBarItems(for monitor: Monitor, deduplicate: Bool, hideEmpty: Bool) -> [WorkspaceBarItem] {
        WorkspaceBarDataSource.workspaceBarItems(
            for: monitor,
            deduplicate: deduplicate,
            hideEmpty: hideEmpty,
            workspaceManager: workspaceManager,
            appInfoCache: appInfoCache,
            zigNiriEngine: zigNiriEngine,
            focusedHandle: focusedHandle,
            settings: settings
        )
    }

    func focusWorkspaceFromBar(named name: String) {
        guard let workspaceId = workspaceManager.workspaceId(for: name, createIfMissing: true) else { return }
        guard submitCoreCommand(
            kind: rawEnumValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE),
            workspaceId: workspaceId
        ) else {
            return
        }
        _ = workspaceManager.syncRuntimeStateFromCore()
        focusedHandle = nil
        updateWorkspaceBar()
    }

    func focusWindowFromBar(windowId: Int) {
        guard let entry = workspaceManager.entry(forWindowId: windowId) else { return }
        navigateToWindowInternal(handle: entry.handle, workspaceId: entry.workspaceId)
    }

    func setFocusFollowsMouse(_ enabled: Bool) {
        focusFollowsMouseEnabled = enabled
        coreRuntime.applyControllerSettings(
            focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: moveMouseToFocusedWindowEnabled
        )
    }

    func setMoveMouseToFocusedWindow(_ enabled: Bool) {
        moveMouseToFocusedWindowEnabled = enabled
        coreRuntime.applyControllerSettings(
            focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: moveMouseToFocusedWindowEnabled
        )
    }

    func setMouseWarpEnabled(_ enabled: Bool) {
        _ = enabled
    }

    func insetWorkingFrame(for monitor: Monitor) -> CGRect {
        let scale = monitor.scale > 0
            ? monitor.scale
            : NSScreen.screens.first(where: { $0.displayId == monitor.displayId })?.backingScaleFactor ?? 2.0
        return insetWorkingFrame(from: monitor.visibleFrame, scale: scale)
    }

    func insetWorkingFrame(from frame: CGRect, scale: CGFloat = 2.0) -> CGRect {
        let outer = workspaceManager.outerGaps
        let struts = Struts(
            left: outer.left,
            right: outer.right,
            top: outer.top,
            bottom: outer.bottom
        )
        return computeWorkingArea(parentArea: frame, scale: scale, struts: struts)
    }

    func updateHotkeyBindings(_ bindings: [HotkeyBinding]) {
        coreRuntime.updateBindings(bindings)
    }

    func updateWorkspaceConfig() {
        workspaceManager.applySettings()
        refreshLayout()
        updateWorkspaceBar()
    }

    func rebuildAppRulesCache() {
        appRulesByBundleId = Dictionary(
            settings.appRules.map { ($0.bundleId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func updateAppRules() {
        rebuildAppRulesCache()
        refreshLayout()
    }

    var hotkeyRegistrationFailures: Set<HotkeyCommand> {
        coreRuntime.registrationFailures
    }

    func enableNiriLayout(
        maxWindowsPerColumn: Int = 3,
        centerFocusedColumn _: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn _: Bool = false
    ) {
        if zigNiriEngine == nil {
            zigNiriEngine = ZigNiriEngine(
                maxWindowsPerColumn: maxWindowsPerColumn,
                maxVisibleColumns: settings.niriMaxVisibleColumns,
                infiniteLoop: settings.niriInfiniteLoop
            )
        } else {
            zigNiriEngine?.updateConfiguration(maxWindowsPerColumn: maxWindowsPerColumn)
        }
        refreshLayout()
    }

    func updateNiriConfig(
        maxWindowsPerColumn: Int? = nil,
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil,
        centerFocusedColumn _: CenterFocusedColumn? = nil,
        alwaysCenterSingleColumn _: Bool? = nil,
        singleWindowAspectRatio _: SingleWindowAspectRatio? = nil,
        columnWidthPresets _: [Double]? = nil
    ) {
        zigNiriEngine?.updateConfiguration(
            maxWindowsPerColumn: maxWindowsPerColumn,
            maxVisibleColumns: maxVisibleColumns,
            infiniteLoop: infiniteLoop
        )
        refreshLayout()
    }

    func enableDwindleLayout() {
        let engine = DwindleLayoutEngine()
        engine.animationClock = animationClock
        dwindleEngine = engine
        refreshLayout()
    }

    func updateDwindleConfig(
        smartSplit: Bool? = nil,
        defaultSplitRatio: CGFloat? = nil,
        splitWidthMultiplier: CGFloat? = nil,
        singleWindowAspectRatio: CGSize? = nil,
        innerGap: CGFloat? = nil,
        outerGapTop: CGFloat? = nil,
        outerGapBottom: CGFloat? = nil,
        outerGapLeft: CGFloat? = nil,
        outerGapRight: CGFloat? = nil
    ) {
        guard let engine = dwindleEngine else { return }
        if let v = smartSplit { engine.settings.smartSplit = v }
        if let v = defaultSplitRatio { engine.settings.defaultSplitRatio = v }
        if let v = splitWidthMultiplier { engine.settings.splitWidthMultiplier = v }
        if let v = singleWindowAspectRatio { engine.settings.singleWindowAspectRatio = v }
        if let v = innerGap { engine.settings.innerGap = v }
        if let v = outerGapTop { engine.settings.outerGapTop = v }
        if let v = outerGapBottom { engine.settings.outerGapBottom = v }
        if let v = outerGapLeft { engine.settings.outerGapLeft = v }
        if let v = outerGapRight { engine.settings.outerGapRight = v }
        refreshLayout()
    }

    func monitorForInteraction() -> Monitor? {
        if let focused = focusedHandle,
           let workspaceId = workspaceManager.workspace(for: focused),
           let monitor = workspaceManager.monitor(for: workspaceId)
        {
            return monitor
        }
        return workspaceManager.monitors.first
    }

    private func updateActiveMonitorFromFocusedHandle(_ handle: WindowHandle?) {
        guard !suppressActiveMonitorUpdate else { return }
        guard let handle,
              let workspaceId = workspaceManager.workspace(for: handle),
              let monitorId = workspaceManager.monitor(for: workspaceId)?.id
        else {
            return
        }
        if let currentId = activeMonitorId, currentId != monitorId {
            previousMonitorId = currentId
        }
        if activeMonitorId != monitorId {
            activeMonitorId = monitorId
        }
    }

    func activeWorkspace() -> WorkspaceDescriptor? {
        guard let monitor = monitorForInteraction() else { return nil }
        return workspaceManager.activeWorkspaceOrFirst(on: monitor.id)
    }

    func resolveWorkspaceForNewWindow(
        axRef: AXWindowRef,
        pid: pid_t,
        fallbackWorkspaceId: WorkspaceDescriptor.ID?
    ) -> WorkspaceDescriptor.ID {
        if let bundleId = appInfoCache.bundleId(for: pid),
           let rule = appRulesByBundleId[bundleId],
           let wsName = rule.assignToWorkspace,
           let wsId = workspaceManager.workspaceId(for: wsName, createIfMissing: true)
        {
            return wsId
        }
        if let monitor = monitorForInteraction(),
           let workspace = workspaceManager.activeWorkspaceOrFirst(on: monitor.id)
        {
            return workspace.id
        }
        if let frame = AXWindowService.framePreferFast(axRef) {
            let center = frame.center
            if let monitor = center.monitorApproximation(in: workspaceManager.monitors),
               let workspace = workspaceManager.activeWorkspaceOrFirst(on: monitor.id)
            {
                return workspace.id
            }
        }
        if let fallbackWorkspaceId {
            return fallbackWorkspaceId
        }
        if let workspaceId = workspaceManager.primaryWorkspace()?.id ?? workspaceManager.workspaces.first?.id {
            return workspaceId
        }
        if let createdWorkspaceId = workspaceManager.workspaceId(for: "1", createIfMissing: true) {
            return createdWorkspaceId
        }
        return workspaceManager.workspaceId(for: "1", createIfMissing: true)!
    }

    func workspaceAssignment(pid: pid_t, windowId: Int) -> WorkspaceDescriptor.ID? {
        workspaceManager.entry(forPid: pid, windowId: windowId)?.workspaceId
    }

    func openWindowFinder() {
        let entries = workspaceManager.allEntries()
        var items: [WindowFinderItem] = []
        for entry in entries {
            guard entry.layoutReason == .standard else { continue }
            let title = AXWindowService.titlePreferFast(windowId: UInt32(entry.windowId)) ?? ""
            let info = appInfoCache.info(for: entry.handle.pid)
            let workspaceName = workspaceManager.descriptor(for: entry.workspaceId)?.name ?? "?"
            items.append(WindowFinderItem(
                id: entry.handle.id,
                handle: entry.handle,
                title: title,
                appName: info?.name ?? "Unknown",
                appIcon: info?.icon,
                workspaceName: workspaceName,
                workspaceId: entry.workspaceId
            ))
        }
        items.sort { ($0.appName, $0.title) < ($1.appName, $1.title) }
        WindowFinderController.shared.show(windows: items) { [weak self] item in
            self?.navigateToWindowInternal(handle: item.handle, workspaceId: item.workspaceId)
        }
    }

    func openMenuAnywhere() {
        guard settings.menuAnywhereNativeEnabled else { return }
        MenuAnywhereController.shared.showNativeMenu(at: settings.menuAnywherePosition)
    }

    func openMenuPalette() {
        guard settings.menuAnywherePaletteEnabled else { return }
        let ownBundleId = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let targetApp: NSRunningApplication
        if let app = frontmost, app.bundleIdentifier != ownBundleId {
            targetApp = app
        } else if let app = MenuPaletteController.shared.currentApp, !app.isTerminated {
            targetApp = app
        } else {
            return
        }
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var windowValue: AnyObject?
        var targetWindow: AXUIElement?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let windowValue,
           CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        {
            targetWindow = (windowValue as! AXUIElement)
        }
        MenuPaletteController.shared.show(
            at: settings.menuAnywherePosition,
            showShortcuts: settings.menuAnywhereShowShortcuts,
            targetApp: targetApp,
            targetWindow: targetWindow
        )
    }

    func toggleOverview() {
        overviewController.toggle()
    }

    func raiseAllFloatingWindows() {
        guard let monitor = monitorForInteraction() else { return }
        let windows = SkyLight.shared.queryAllVisibleWindows().filter { info in
            let center = ScreenCoordinateSpace.toAppKit(rect: info.frame).center
            return monitor.visibleFrame.contains(center)
        }
        let windowsByPid = Dictionary(grouping: windows) { $0.pid }
        let windowIdSet = Set(windows.map(\.id))
        var lastRaisedPid: pid_t?
        var lastRaisedWindowId: UInt32?
        var ownAppHasFloatingWindows = false
        let ownPid = ProcessInfo.processInfo.processIdentifier

        for (pid, _) in windowsByPid {
            guard let info = appInfoCache.info(for: pid),
                  info.activationPolicy != .prohibited else { continue }

            let axApp = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let appWindows = windowsRef as? [AXUIElement] else { continue }

            for window in appWindows {
                guard let axRef = try? AXWindowRef(element: window),
                      windowIdSet.contains(UInt32(axRef.windowId)) else { continue }

                let windowId = axRef.windowId
                let alwaysFloat = info.bundleId.flatMap { appRulesByBundleId[$0]?.alwaysFloat } == true
                let windowType = AXWindowService.windowType(
                    axRef,
                    appPolicy: info.activationPolicy,
                    bundleId: info.bundleId
                )
                guard windowType == .floating || alwaysFloat else { continue }

                SkyLight.shared.orderWindow(UInt32(windowId), relativeTo: 0, order: .above)
                if pid == ownPid {
                    ownAppHasFloatingWindows = true
                } else {
                    lastRaisedPid = pid
                    lastRaisedWindowId = UInt32(windowId)
                }
            }
        }

        if let pid = lastRaisedPid,
           let windowId = lastRaisedWindowId,
           let app = NSRunningApplication(processIdentifier: pid)
        {
            app.activate()
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            OmniWM.focusWindow(pid: app.processIdentifier, windowId: windowId, windowRef: appElement)
        }
        if ownAppHasFloatingWindows {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func isOverviewOpen() -> Bool {
        overviewController.isOpen
    }

    @discardableResult
    func resolveAndSetWorkspaceFocus(for workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
        let entries = workspaceManager.entries(in: workspaceId).filter { $0.layoutReason == .standard }
        guard let handle = entries.first?.handle else {
            focusedHandle = nil
            return nil
        }
        focusWindow(handle)
        return handle
    }

    func recoverSourceFocusAfterMove(
        in workspaceId: WorkspaceDescriptor.ID,
        preferredNodeId _: NodeId?
    ) {
        _ = resolveAndSetWorkspaceFocus(for: workspaceId)
    }

    @discardableResult
    func syncZigNiriWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        selectedNodeId: NodeId? = nil
    ) -> ZigNiriWorkspaceView? {
        guard let zigNiriEngine else { return nil }
        let handles = workspaceManager.entries(in: workspaceId).map(\.handle)
        _ = zigNiriEngine.syncWindows(
            handles,
            in: workspaceId,
            selectedNodeId: selectedNodeId ?? zigNiriEngine.selectedNodeId(in: workspaceId),
            focusedHandle: focusedHandle
        )
        return zigNiriEngine.workspaceView(for: workspaceId)
    }

    func selectedNodeId(in workspaceId: WorkspaceDescriptor.ID) -> NodeId? {
        if let selected = zigNiriEngine?.selectedNodeId(in: workspaceId) {
            return selected
        }
        _ = syncZigNiriWorkspace(workspaceId: workspaceId)
        return zigNiriEngine?.selectedNodeId(in: workspaceId)
    }

    @discardableResult
    func setSelectedNodeId(
        _ nodeId: NodeId?,
        for workspaceId: WorkspaceDescriptor.ID,
        focusedWindowId: NodeId? = nil
    ) -> Bool {
        zigNiriEngine?.setSelectedNodeId(
            nodeId,
            in: workspaceId,
            focusedWindowId: focusedWindowId
        ) ?? false
    }

    func zigNodeId(
        for handle: WindowHandle,
        workspaceId: WorkspaceDescriptor.ID? = nil
    ) -> NodeId? {
        if let workspaceId {
            _ = syncZigNiriWorkspace(workspaceId: workspaceId)
        }
        return zigNiriEngine?.nodeId(for: handle)
    }

    func zigWindowHandle(
        for nodeId: NodeId,
        workspaceId: WorkspaceDescriptor.ID? = nil
    ) -> WindowHandle? {
        if let workspaceId {
            _ = syncZigNiriWorkspace(workspaceId: workspaceId)
        }
        return zigNiriEngine?.windowHandle(for: nodeId)
    }

    func zigContainsNode(
        _ nodeId: NodeId,
        workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        if let workspaceView = syncZigNiriWorkspace(workspaceId: workspaceId, selectedNodeId: nodeId) {
            if workspaceView.windowsById[nodeId] != nil {
                return true
            }
            if workspaceView.columns.contains(where: { $0.nodeId == nodeId }) {
                return true
            }
        }
        return false
    }

    func moveMouseToWindow(_ handle: WindowHandle) {
        guard let entry = workspaceManager.entry(for: handle) else { return }
        guard let frame = AXWindowService.framePreferFast(entry.axRef) else { return }
        let center = frame.center
        guard NSScreen.screens.contains(where: { $0.frame.contains(center) }) else { return }
        CGWarpMouseCursorPosition(center)
    }

    func runningAppsWithWindows() -> [RunningAppInfo] {
        var appInfoMap: [String: RunningAppInfo] = [:]
        for entry in workspaceManager.allEntries() {
            guard entry.layoutReason == .standard else { continue }
            guard let info = appInfoCache.info(for: entry.handle.pid),
                  let bundleId = info.bundleId else { continue }
            if appInfoMap[bundleId] != nil { continue }
            let frame = AXWindowService.framePreferFast(entry.axRef) ?? .zero
            appInfoMap[bundleId] = RunningAppInfo(
                id: bundleId,
                bundleId: bundleId,
                appName: info.name ?? "Unknown",
                icon: info.icon,
                windowSize: frame.size
            )
        }
        return appInfoMap.values.sorted { $0.appName < $1.appName }
    }

    @discardableResult
    func moveWindowToWorkspace(handle: WindowHandle, toWorkspaceId workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard workspaceManager.entry(for: handle) != nil else { return false }
        let submitted = submitCoreCommand(
            kind: rawEnumValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX),
            workspaceId: workspaceId,
            windowHandleId: handle.id
        )
        guard submitted else { return false }
        return workspaceManager.syncRuntimeStateFromCore()
    }

    func overviewInsertWindow(
        handle _: WindowHandle,
        targetHandle _: WindowHandle,
        position _: InsertPosition,
        in _: WorkspaceDescriptor.ID
    ) {}

    func overviewInsertWindowInNewColumn(
        handle _: WindowHandle,
        insertIndex _: Int,
        in _: WorkspaceDescriptor.ID
    ) {}

    func startWorkspaceAnimation(for _: WorkspaceDescriptor.ID) {}

    func refreshLayout() {
        coreRuntime.syncControllerState()
        updateWorkspaceBar()
    }
}

extension WMController {
    func withSuppressedMonitorUpdate(_ body: () -> Void) {
        suppressActiveMonitorUpdate = true
        defer { suppressActiveMonitorUpdate = false }
        body()
    }

    func isFrontmostAppLockScreen() -> Bool {
        lockScreenObserver.isFrontmostAppLockScreen()
    }

    func isPointInQuakeTerminal(_ point: CGPoint) -> Bool {
        guard settings.quakeTerminalEnabled,
              quakeTerminalController.visible,
              let window = quakeTerminalController.window else {
            return false
        }
        return window.frame.contains(point)
    }

    func isPointInOwnWindow(_ point: CGPoint) -> Bool {
        if isPointInQuakeTerminal(point) { return true }
        if overviewController.isPointInside(point) { return true }
        if SettingsWindowController.shared.isPointInside(point) { return true }
        if AppRulesWindowController.shared.isPointInside(point) { return true }
        if SponsorsWindowController.shared.isPointInside(point) { return true }
        return false
    }

    func focusWindow(_ handle: WindowHandle) {
        guard let entry = workspaceManager.entry(for: handle) else { return }
        focusedHandle = handle
        let pid = handle.pid
        let windowId = entry.windowId
        let axRef = entry.axRef
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [])
        }
        OmniWM.focusWindow(pid: pid, windowId: UInt32(windowId), windowRef: axRef.element)
        AXUIElementPerformAction(axRef.element, kAXRaiseAction as CFString)
        if moveMouseToFocusedWindowEnabled {
            moveMouseToWindow(handle)
        }
        if let frame = AXWindowService.framePreferFast(axRef) {
            refreshBorderPresentation(focusedFrame: frame, windowId: entry.windowId)
        }
    }

    var isDiscoveryInProgress: Bool {
        false
    }

    private func navigateToWindowInternal(handle: WindowHandle, workspaceId: WorkspaceDescriptor.ID) {
        if workspaceId != activeWorkspace()?.id {
            let switched = submitCoreCommand(
                kind: rawEnumValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE),
                workspaceId: workspaceId
            )
            if switched {
                _ = workspaceManager.syncRuntimeStateFromCore()
            }
        }
        focusWindow(handle)
    }

    private func submitCoreCommand(
        kind: UInt8,
        workspaceId: WorkspaceDescriptor.ID? = nil,
        windowHandleId: UUID? = nil
    ) -> Bool {
        let command = OmniControllerCommand(
            kind: kind,
            direction: 0,
            workspace_index: 0,
            monitor_direction: 0,
            has_workspace_id: workspaceId == nil ? 0 : 1,
            workspace_id: workspaceId.map(ZigNiriStateKernel.omniUUID(from:)) ?? OmniUuid128(),
            has_window_handle_id: windowHandleId == nil ? 0 : 1,
            window_handle_id: windowHandleId.map(ZigNiriStateKernel.omniUUID(from:)) ?? OmniUuid128()
        )
        return coreRuntime.submitUIBridgeCommand(command)
    }

    private func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
        UInt8(clamping: Int(value.rawValue))
    }

    private func closeWindowFromOverview(handle: WindowHandle) {
        guard let entry = workspaceManager.entry(for: handle) else { return }
        let element = entry.axRef.element
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        var closeButton: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &closeButton) == .success {
            AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString)
        }
    }
}
