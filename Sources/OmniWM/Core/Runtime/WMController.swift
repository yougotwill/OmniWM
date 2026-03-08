import AppKit
import CZigLayout
import Foundation

final class BorderRuntimeStorage {
    private var rawValue: UInt?

    var runtime: OpaquePointer? {
        guard let rawValue else { return nil }
        return OpaquePointer(bitPattern: rawValue)
    }

    func store(_ runtime: OpaquePointer) {
        rawValue = UInt(bitPattern: runtime)
    }

    func destroy() {
        guard let runtime else { return }
        omni_border_runtime_destroy(runtime)
        rawValue = nil
    }

    deinit {
        destroy()
    }
}

struct WMControllerWorkspaceLayoutOverride: Equatable {
    let name: String
    let layoutType: LayoutType
}

@MainActor @Observable
final class WMController {
    var isEnabled: Bool = true
    var hotkeysEnabled: Bool = true
    private(set) var focusFollowsMouseEnabled: Bool = false
    private(set) var moveMouseToFocusedWindowEnabled: Bool = false
    private(set) var workspaceBarVersion: Int = 0

    let settings: SettingsStore
    let workspaceManager: WorkspaceManager
    private(set) var latestControllerSnapshot: WMControllerControllerSnapshot?
    private(set) var latestWorkspaceStateExport: OmniWorkspaceRuntimeAdapter.StateExport?
    private(set) var latestWorkspaceLayoutOverrides: [WMControllerWorkspaceLayoutOverride]?
    private let hotkeys = HotkeyCenter()
    let secureInputMonitor = SecureInputMonitor()
    let lockScreenObserver = LockScreenObserver()
    var isLockScreenActive: Bool = false
    let axManager = AXManager()
    let appInfoCache = AppInfoCache()
    let focusManager = FocusManager()
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
    private var suppressActiveMonitorUpdate: Bool = false

    var zigNiriEngine: ZigNiriEngine?
    var dwindleEngine: DwindleLayoutEngine?

    let tabbedOverlayManager = TabbedColumnOverlayManager()
    @ObservationIgnored
    let borderRuntimeStorage = BorderRuntimeStorage()
    @ObservationIgnored
    var borderRuntime: OpaquePointer? {
        borderRuntimeStorage.runtime
    }
    @ObservationIgnored
    var borderRuntimeDegraded: Bool = false
    @ObservationIgnored
    var borderRuntimeFailureCount: Int = 0
    @ObservationIgnored
    var borderRuntimePlatformFailureStreak: Int = 0
    @ObservationIgnored
    var borderRuntimeRetryNotBefore: TimeInterval = 0
    @ObservationIgnored
    var borderDisplayCache: [OmniBorderDisplayInfo] = []
    @ObservationIgnored
    var borderDisplayCacheValid: Bool = false
    @ObservationIgnored
    let borderRuntimeFactory: () -> OpaquePointer?
    @ObservationIgnored
    private lazy var workspaceBarManager: WorkspaceBarManager = .init()
    @ObservationIgnored
    private lazy var hiddenBarController: HiddenBarController = .init(settings: settings)
    @ObservationIgnored
    private lazy var quakeTerminalController: QuakeTerminalController = .init(settings: settings)
    @ObservationIgnored
    private let coreRuntime: ZigCoreRuntime

    var isTransferringWindow: Bool = false
    var hiddenAppPIDs: Set<pid_t> = []

    private(set) var appRulesByBundleId: [String: AppRule] = [:]

    @ObservationIgnored
    private(set) lazy var mouseEventHandler = MouseEventHandler(controller: self)
    @ObservationIgnored
    private(set) lazy var mouseWarpHandler = MouseWarpHandler(controller: self)
    @ObservationIgnored
    private(set) lazy var axEventHandler = AXEventHandler(controller: self)
    @ObservationIgnored
    private(set) lazy var commandHandler = CommandHandler(controller: self)
    @ObservationIgnored
    private(set) lazy var layoutRefreshController = LayoutRefreshController(controller: self)
    var niriLayoutHandler: NiriLayoutHandler { layoutRefreshController.niriHandler }
    var dwindleLayoutHandler: DwindleLayoutHandler { layoutRefreshController.dwindleHandler }
    @ObservationIgnored
    private(set) lazy var serviceLifecycleManager = ServiceLifecycleManager(controller: self)
    @ObservationIgnored
    private(set) lazy var windowActionHandler = WindowActionHandler(controller: self)
    @ObservationIgnored
    private(set) lazy var focusNotificationDispatcher = FocusNotificationDispatcher(controller: self)
    var hasStartedServices = false
    var isCoreRuntimeStarted: Bool { coreRuntime.started }

    let animationClock = AnimationClock()

    init(
        settings: SettingsStore,
        createBorderRuntime: @escaping () -> OpaquePointer? = { omni_border_runtime_create() }
    ) {
        self.settings = settings
        borderRuntimeFactory = createBorderRuntime
        workspaceManager = WorkspaceManager(settings: settings)
        coreRuntime = ZigCoreRuntime(workspaceRuntimeHandle: workspaceManager.runtimeHandle)
        workspaceManager.updateAnimationClock(animationClock)
        hotkeys.onCommand = { [weak self] command in
            self?.commandHandler.handleCommand(command)
        }
        tabbedOverlayManager.onSelect = { [weak self] workspaceId, columnId, index in
            self?.layoutRefreshController.selectTabInNiri(workspaceId: workspaceId, columnId: columnId, index: index)
        }
        focusManager.onFocusedHandleChanged = { [weak self] handle in
            self?.focusedHandle = handle
        }
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
        applyExperimentalControllerSettings(syncAfterApply: true)
    }

    func setOuterGaps(left: Double, right: Double, top: Double, bottom: Double) {
        workspaceManager.setOuterGaps(left: left, right: right, top: top, bottom: bottom)
        applyExperimentalControllerSettings(syncAfterApply: true)
    }

    func setBordersEnabled(_ enabled: Bool) {
        settings.bordersEnabled = enabled
        if enabled {
            resetBorderRuntimeHealth()
        }
        applyExperimentalControllerSettings(syncAfterApply: true)
        refreshBorderPresentation(forceHide: !enabled)
    }

    func updateBorderConfig() {
        applyExperimentalControllerSettings(syncAfterApply: true)
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
        applyExperimentalControllerSettings(syncAfterApply: true)
    }

    func updateMonitorNiriSettings() {
        applyExperimentalControllerSettings(syncAfterApply: true)
    }

    func updateMonitorDwindleSettings() {
        guard let engine = dwindleEngine else { return }
        for monitor in workspaceManager.monitors {
            let resolved = settings.resolvedDwindleSettings(for: monitor)
            engine.updateMonitorSettings(resolved, for: monitor.id)
        }
        layoutRefreshController.refreshWindowsAndLayout()
    }

    func workspaceBarItems(for monitor: Monitor, deduplicate: Bool, hideEmpty: Bool) -> [WorkspaceBarItem] {
        WorkspaceBarDataSource.workspaceBarItems(
            for: monitor,
            deduplicate: deduplicate,
            hideEmpty: hideEmpty,
            workspaceManager: workspaceManager,
            appInfoCache: appInfoCache,
            workspaceStateExport: latestWorkspaceStateExport,
            controllerSnapshot: latestControllerSnapshot,
            focusedHandle: focusedHandle,
            settings: settings
        )
    }

    func focusWorkspaceFromBar(workspaceId: WorkspaceDescriptor.ID) {
        windowActionHandler.focusWorkspaceFromBar(workspaceId: workspaceId)
    }

    func focusWindowFromBar(handleId: UUID) {
        windowActionHandler.focusWindowFromBar(handleId: handleId)
    }

    func setFocusFollowsMouse(_ enabled: Bool) {
        focusFollowsMouseEnabled = enabled
        coreRuntime.applyControllerSettings(
            settings: settings,
            focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: moveMouseToFocusedWindowEnabled
        )
    }

    func setMoveMouseToFocusedWindow(_ enabled: Bool) {
        moveMouseToFocusedWindowEnabled = enabled
        coreRuntime.applyControllerSettings(
            settings: settings,
            focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: enabled
        )
    }

    func setMouseWarpEnabled(_ enabled: Bool) {
        if enabled {
            mouseWarpHandler.setup()
        } else {
            mouseWarpHandler.cleanup()
        }
    }

    func applyExperimentalControllerSettings(syncAfterApply: Bool = false) {
        coreRuntime.applyControllerSettings(
            settings: settings,
            focusFollowsWindowToMonitor: settings.focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: moveMouseToFocusedWindowEnabled
        )
        if syncAfterApply {
            coreRuntime.syncControllerState()
        }
    }

    @discardableResult
    func submitControllerCommand(_ command: OmniControllerCommand) -> Bool {
        coreRuntime.submitUIBridgeCommand(command)
    }

    func insetWorkingFrame(for monitor: Monitor) -> CGRect {
        let scale = NSScreen.screens.first(where: { $0.displayId == monitor.displayId })?.backingScaleFactor ?? 2.0
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
        return computeWorkingArea(
            parentArea: frame,
            scale: scale,
            struts: struts
        )
    }

    func updateHotkeyBindings(_ bindings: [HotkeyBinding]) {
        coreRuntime.updateBindings(bindings)
    }

    func updateWorkspaceConfig() {
        workspaceManager.applySettings()
        syncMonitorsToNiriEngine()
        applyExperimentalControllerSettings(syncAfterApply: true)
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
        syncExperimentalProjectionsFromCore()
    }

    var hotkeyRegistrationFailures: Set<HotkeyCommand> {
        coreRuntime.registrationFailures
    }

    func enableNiriLayout(
        maxWindowsPerColumn: Int = 3,
        centerFocusedColumn: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn: Bool = false
    ) {
        niriLayoutHandler.enableNiriLayout(
            maxWindowsPerColumn: maxWindowsPerColumn,
            centerFocusedColumn: centerFocusedColumn,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn
        )
    }

    func syncMonitorsToNiriEngine() {
        niriLayoutHandler.syncMonitorsToNiriEngine()
    }

    func updateNiriConfig(
        maxWindowsPerColumn: Int? = nil,
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil,
        centerFocusedColumn: CenterFocusedColumn? = nil,
        alwaysCenterSingleColumn: Bool? = nil,
        singleWindowAspectRatio: SingleWindowAspectRatio? = nil,
        columnWidthPresets: [Double]? = nil
    ) {
        niriLayoutHandler.updateNiriConfig(
            maxWindowsPerColumn: maxWindowsPerColumn,
            maxVisibleColumns: maxVisibleColumns,
            infiniteLoop: infiniteLoop,
            centerFocusedColumn: centerFocusedColumn,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            singleWindowAspectRatio: singleWindowAspectRatio,
            columnWidthPresets: columnWidthPresets
        )
    }

    func enableDwindleLayout() {
        dwindleLayoutHandler.enableDwindleLayout()
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
        dwindleLayoutHandler.updateDwindleConfig(
            smartSplit: smartSplit,
            defaultSplitRatio: defaultSplitRatio,
            splitWidthMultiplier: splitWidthMultiplier,
            singleWindowAspectRatio: singleWindowAspectRatio,
            innerGap: innerGap,
            outerGapTop: outerGapTop,
            outerGapBottom: outerGapBottom,
            outerGapLeft: outerGapLeft,
            outerGapRight: outerGapRight
        )
    }

    func monitorForInteraction() -> Monitor? {
        if let activeMonitorId,
           let monitor = workspaceManager.monitor(byId: activeMonitorId)
        {
            return monitor
        }
        if let routedMonitor = workspaceManager.routedMonitor() {
            return routedMonitor
        }
        if let focused = focusedHandle,
           let workspaceId = workspaceManager.workspace(for: focused),
           let monitor = workspaceManager.monitor(for: workspaceId)
        {
            return monitor
        }
        return workspaceManager.monitors.first(where: { $0.isMain }) ?? workspaceManager.monitors.first
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
        if let activeWorkspaceId = activeWorkspaceId(on: monitor) {
            return workspaceDescriptor(for: activeWorkspaceId)
        }
        return workspaceManager.activeWorkspaceOrFirst(on: monitor.id)
    }

    func syncExperimentalProjectionsFromCore(
        changedWorkspaceIds: Set<WorkspaceDescriptor.ID>? = nil,
        stateExport: OmniWorkspaceRuntimeAdapter.StateExport? = nil,
        controllerSnapshot: WMControllerControllerSnapshot? = nil,
        workspaceLayoutOverrides: [WMControllerWorkspaceLayoutOverride]? = nil
    ) {
        let resolvedStateExport = stateExport
        if let resolvedStateExport {
            guard ExperimentalProjectionSyncCoordinator.sync(
                workspaceManager: workspaceManager,
                zigNiriEngine: zigNiriEngine,
                stateExport: resolvedStateExport,
                changedWorkspaceIds: changedWorkspaceIds
            ) != nil else {
                return
            }
            latestWorkspaceStateExport = resolvedStateExport
        } else {
            latestWorkspaceStateExport = nil
            latestWorkspaceLayoutOverrides = nil
            guard workspaceManager.syncRuntimeStateFromCore() else { return }
            let activeWorkspaceIds = Set(workspaceManager.workspaces.map(\.id))
            zigNiriEngine?.pruneWorkspaceProjections(to: activeWorkspaceIds)
            let refreshWorkspaceIds = changedWorkspaceIds?.intersection(activeWorkspaceIds) ?? activeWorkspaceIds
            for workspaceId in refreshWorkspaceIds {
                zigNiriEngine?.invalidateWorkspaceProjection(workspaceId)
            }
        }
        if let workspaceLayoutOverrides {
            applyWorkspaceLayoutOverrides(workspaceLayoutOverrides)
        }
        if let controllerSnapshot {
            applyControllerSnapshot(controllerSnapshot)
        } else {
            syncMonitorStateFromWorkspaceRuntime()
        }
        updateWorkspaceBar()
    }

    func invalidateControllerSnapshot(refreshUI: Bool = true) {
        latestControllerSnapshot = nil
        latestWorkspaceStateExport = nil
        latestWorkspaceLayoutOverrides = nil
        guard refreshUI else { return }
        syncMonitorStateFromWorkspaceRuntime()
        updateWorkspaceBar()
    }

    func syncMonitorStateFromWorkspaceRuntime() {
        let resolvedActiveMonitorId =
            workspaceManager.runtimeActiveMonitorId.flatMap { monitorId in
                workspaceManager.monitor(byId: monitorId) == nil ? nil : monitorId
            }
            ?? focusedHandle.flatMap { focused in
                workspaceManager.workspace(for: focused).flatMap { workspaceId in
                    workspaceManager.monitor(for: workspaceId)?.id
                }
            }
            ?? workspaceManager.monitors.first(where: { $0.isMain })?.id
            ?? workspaceManager.monitors.first?.id

        let resolvedPreviousMonitorId: Monitor.ID? = {
            guard let monitorId = workspaceManager.runtimePreviousMonitorId else { return nil }
            guard workspaceManager.monitor(byId: monitorId) != nil else { return nil }
            guard monitorId != resolvedActiveMonitorId else { return nil }
            return monitorId
        }()

        if activeMonitorId != resolvedActiveMonitorId {
            activeMonitorId = resolvedActiveMonitorId
        }
        if previousMonitorId != resolvedPreviousMonitorId {
            previousMonitorId = resolvedPreviousMonitorId
        }
    }

    private func applyControllerSnapshot(_ snapshot: WMControllerControllerSnapshot) {
        latestControllerSnapshot = snapshot

        let resolvedFocusedHandle = snapshot.focusedWindowRecord()?.handle
        let resolvedActiveMonitorId =
            monitorId(forDisplayId: snapshot.activeMonitorDisplayId)
            ?? workspaceManager.runtimeActiveMonitorId.flatMap { monitorId in
                workspaceManager.monitor(byId: monitorId) == nil ? nil : monitorId
            }
            ?? resolvedFocusedHandle.flatMap { handle in
                workspaceManager.workspace(for: handle).flatMap { workspaceId in
                    workspaceManager.monitor(for: workspaceId)?.id
                }
            }
            ?? workspaceManager.monitors.first(where: { $0.isMain })?.id
            ?? workspaceManager.monitors.first?.id

        let resolvedPreviousMonitorId: Monitor.ID? = {
            guard let monitorId = monitorId(forDisplayId: snapshot.previousMonitorDisplayId) else { return nil }
            guard monitorId != resolvedActiveMonitorId else { return nil }
            return monitorId
        }()

        if focusedHandle != resolvedFocusedHandle {
            withSuppressedMonitorUpdate {
                focusedHandle = resolvedFocusedHandle
            }
        }
        if activeMonitorId != resolvedActiveMonitorId {
            activeMonitorId = resolvedActiveMonitorId
        }
        if previousMonitorId != resolvedPreviousMonitorId {
            previousMonitorId = resolvedPreviousMonitorId
        }
    }

    private func layoutType(fromControllerLayoutKind rawKind: UInt8) -> LayoutType? {
        switch rawKind {
        case UInt8(truncatingIfNeeded: OMNI_CONTROLLER_LAYOUT_NIRI.rawValue):
            return .niri
        case UInt8(truncatingIfNeeded: OMNI_CONTROLLER_LAYOUT_DWINDLE.rawValue):
            return .dwindle
        default:
            return nil
        }
    }

    private func applyWorkspaceLayoutOverrides(_ overrides: [WMControllerWorkspaceLayoutOverride]) {
        latestWorkspaceLayoutOverrides = overrides
        persistWorkspaceLayoutOverridesToSettings(overrides)
    }

    private func persistWorkspaceLayoutOverridesToSettings(_ overrides: [WMControllerWorkspaceLayoutOverride]) {
        let overrideByName = Dictionary(
            overrides.map { ($0.name, $0.layoutType) },
            uniquingKeysWith: { first, _ in first }
        )
        var updatedConfigurations = settings.workspaceConfigurations.map { configuration in
            var updated = configuration
            updated.layoutType = overrideByName[configuration.name] ?? .defaultLayout
            return updated
        }
        let existingNames = Set(updatedConfigurations.map(\.name))
        for override in overrides where !existingNames.contains(override.name) {
            updatedConfigurations.append(
                WorkspaceConfiguration(
                    name: override.name,
                    monitorAssignment: .any,
                    layoutType: override.layoutType,
                    isPersistent: false
                )
            )
        }
        guard settings.workspaceConfigurations != updatedConfigurations else { return }
        settings.workspaceConfigurations = updatedConfigurations
    }

    func workspaceName(for workspaceId: WorkspaceDescriptor.ID) -> String? {
        if let workspace = latestWorkspaceStateExport?.workspaces.first(where: { $0.workspaceId == workspaceId }) {
            return workspace.name
        }
        if let workspace = latestControllerSnapshot?.workspaces.first(where: { $0.workspaceId == workspaceId }) {
            return workspace.name
        }
        return workspaceManager.descriptor(for: workspaceId)?.name
    }

    func workspaceDescriptor(for workspaceId: WorkspaceDescriptor.ID) -> WorkspaceDescriptor? {
        if let descriptor = workspaceManager.descriptor(for: workspaceId) {
            return descriptor
        }
        guard let name = workspaceName(for: workspaceId) else { return nil }
        return WorkspaceDescriptor(id: workspaceId, name: name)
    }

    func activeWorkspaceId(on monitor: Monitor) -> WorkspaceDescriptor.ID? {
        if let stateExport = latestWorkspaceStateExport,
           let activeWorkspaceId = stateExport.monitors.first(where: { $0.displayId == monitor.displayId })?.activeWorkspaceId
        {
            return activeWorkspaceId
        }
        return workspaceManager.activeWorkspace(on: monitor.id)?.id
    }

    func runtimeWorkspaceRecords(on monitor: Monitor) -> [OmniWorkspaceRuntimeAdapter.StateExport.WorkspaceRecord]? {
        guard let stateExport = latestWorkspaceStateExport else { return nil }
        let monitorRecord = stateExport.monitors.first(where: { $0.displayId == monitor.displayId })
        let workspaceById = Dictionary(
            stateExport.workspaces.map { ($0.workspaceId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seenWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        var workspaceIds: [WorkspaceDescriptor.ID] = []

        func appendWorkspaceId(_ workspaceId: WorkspaceDescriptor.ID?) {
            guard let workspaceId,
                  workspaceById[workspaceId] != nil,
                  seenWorkspaceIds.insert(workspaceId).inserted else {
                return
            }
            workspaceIds.append(workspaceId)
        }

        for workspace in stateExport.workspaces where workspace.assignedDisplayId == monitor.displayId {
            appendWorkspaceId(workspace.workspaceId)
        }
        appendWorkspaceId(monitorRecord?.activeWorkspaceId)
        appendWorkspaceId(monitorRecord?.previousWorkspaceId)

        return workspaceIds
            .compactMap { workspaceById[$0] }
            .sorted { lhs, rhs in
                lhs.name.toLogicalSegments() < rhs.name.toLogicalSegments()
            }
    }

    func runtimeWorkspaceId(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
        if let workspaceId = latestWorkspaceStateExport?.windows.first(where: { $0.handleId == handle.id })?.workspaceId {
            return workspaceId
        }
        return workspaceManager.workspace(for: handle)
    }

    func effectiveLayoutType(forWorkspaceId workspaceId: WorkspaceDescriptor.ID) -> LayoutType {
        if let snapshot = latestControllerSnapshot,
           let workspace = snapshot.workspaces.first(where: { $0.workspaceId == workspaceId })
        {
            return layoutType(fromControllerLayoutKind: workspace.layoutKind) ?? settings.defaultLayoutType
        }

        if let overrides = latestWorkspaceLayoutOverrides,
           let name = workspaceName(for: workspaceId)
        {
            return overrides.first(where: { $0.name == name })?.layoutType ?? settings.defaultLayoutType
        }

        guard let name = workspaceName(for: workspaceId) else {
            return settings.defaultLayoutType
        }
        return settings.layoutType(for: name)
    }

    private func monitorId(forDisplayId displayId: UInt32?) -> Monitor.ID? {
        guard let displayId else { return nil }
        return workspaceManager.monitors.first(where: { $0.displayId == displayId })?.id
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
        fatalError("resolveWorkspaceForNewWindow: no workspaces exist")
    }

    func workspaceAssignment(pid: pid_t, windowId: Int) -> WorkspaceDescriptor.ID? {
        workspaceManager.entry(forPid: pid, windowId: windowId)?.workspaceId
    }

    func openWindowFinder() { windowActionHandler.openWindowFinder() }
    func openMenuAnywhere() { windowActionHandler.openMenuAnywhere() }
    func openMenuPalette() { windowActionHandler.openMenuPalette() }
    func toggleOverview() { windowActionHandler.toggleOverview() }
    func raiseAllFloatingWindows() { windowActionHandler.raiseAllFloatingWindows() }
    func isOverviewOpen() -> Bool { windowActionHandler.isOverviewOpen() }

    @discardableResult
    func resolveAndSetWorkspaceFocus(for workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
        focusManager.resolveAndSetWorkspaceFocus(
            for: workspaceId,
            entries: workspaceManager.entries(in: workspaceId)
        )
    }

    func recoverSourceFocusAfterMove(
        in workspaceId: WorkspaceDescriptor.ID,
        preferredNodeId: NodeId?
    ) {
        _ = syncZigNiriWorkspace(workspaceId: workspaceId, selectedNodeId: preferredNodeId)
        focusManager.recoverSourceFocusAfterMove(
            in: workspaceId,
            preferredNodeId: preferredNodeId,
            zigEngine: zigNiriEngine,
            entries: workspaceManager.entries(in: workspaceId)
        )
    }

    @discardableResult
    func syncZigNiriWorkspace(
        workspaceId: WorkspaceDescriptor.ID,
        selectedNodeId: NodeId? = nil
    ) -> ZigNiriWorkspaceView? {
        guard let zigNiriEngine else { return nil }
        let handles = latestControllerSnapshot.map { snapshot in
            snapshot.orderedWindows(in: workspaceId).map(\.handle)
        } ?? workspaceManager.entries(in: workspaceId).map(\.handle)
        _ = zigNiriEngine.syncWindows(
            handles,
            in: workspaceId,
            selectedNodeId: selectedNodeId ?? workspaceManager.niriViewportState(for: workspaceId).selectedNodeId,
            focusedHandle: focusedHandle
        )
        return zigNiriEngine.workspaceView(for: workspaceId)
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
        windowActionHandler.runningAppsWithWindows()
    }

    @discardableResult
    func moveWindowToWorkspace(handle: WindowHandle, toWorkspaceId workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard workspaceManager.entry(for: handle) != nil else { return false }
        guard submitControllerCommand(.moveWindowToWorkspace(handleId: handle.id, workspaceId: workspaceId)) else {
            return false
        }
        return workspaceManager.workspace(for: handle) == workspaceId
    }

    func overviewInsertWindow(
        handle: WindowHandle,
        targetHandle: WindowHandle,
        position: InsertPosition,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        _ = submitControllerCommand(
            .overviewInsertWindow(
                handleId: handle.id,
                targetHandleId: targetHandle.id,
                position: position,
                workspaceId: workspaceId
            )
        )
    }

    func overviewInsertWindowInNewColumn(
        handle: WindowHandle,
        insertIndex: Int,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        _ = submitControllerCommand(
            .overviewInsertWindowInNewColumn(
                handleId: handle.id,
                insertIndex: insertIndex,
                workspaceId: workspaceId
            )
        )
    }

    func startWorkspaceAnimation(for workspaceId: WorkspaceDescriptor.ID) {
        layoutRefreshController.startScrollAnimation(for: workspaceId)
    }

    func refreshLayout() {
        coreRuntime.syncControllerState()
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
        if windowActionHandler.isPointInOverview(point) { return true }
        if SettingsWindowController.shared.isPointInside(point) { return true }
        if AppRulesWindowController.shared.isPointInside(point) { return true }
        if SponsorsWindowController.shared.isPointInside(point) { return true }
        return false
    }

    func focusWindow(_ handle: WindowHandle) {
        guard let entry = workspaceManager.entry(for: handle) else { return }
        focusManager.setNonManagedFocus(active: false)

        let axRef = entry.axRef
        let pid = handle.pid
        let windowId = entry.windowId
        let moveMouseEnabled = moveMouseToFocusedWindowEnabled
        focusManager.focusWindow(
            handle,
            workspaceId: entry.workspaceId,
            performFocus: {
                // 1. Activate app first (brings process to front, may pick wrong key window)
                if let runningApp = NSRunningApplication(processIdentifier: pid) {
                    runningApp.activate(options: [])
                }

                // 2. Private API sets the SPECIFIC window as key (overrides activate's choice)
                OmniWM.focusWindow(pid: pid, windowId: UInt32(windowId), windowRef: axRef.element)

                // 3. AX raise ensures the window is visually on top and receives keyboard focus
                AXUIElementPerformAction(axRef.element, kAXRaiseAction as CFString)

                if moveMouseEnabled {
                    self.moveMouseToWindow(handle)
                }

                if let entry = self.workspaceManager.entry(for: handle) {
                    if let workspaceView = self.syncZigNiriWorkspace(workspaceId: entry.workspaceId),
                       let nodeId = self.zigNiriEngine?.nodeId(for: handle),
                       let frame = workspaceView.windowsById[nodeId]?.frame
                    {
                        self.refreshBorderPresentation(focusedFrame: frame, windowId: entry.windowId)
                    } else if let frame = try? AXWindowService.frame(entry.axRef) {
                        self.refreshBorderPresentation(focusedFrame: frame, windowId: entry.windowId)
                    }
                }
            },
            onDeferredFocus: { [weak self] deferred in
                guard let self, self.workspaceManager.entry(for: deferred) != nil else { return }
                self.focusWindow(deferred)
            }
        )
    }

    var isDiscoveryInProgress: Bool {
        layoutRefreshController.isDiscoveryInProgress
    }
}
