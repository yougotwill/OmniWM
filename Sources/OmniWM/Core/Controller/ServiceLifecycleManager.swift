import AppKit
import Foundation

@MainActor
final class ServiceLifecycleManager {
    weak var controller: WMController?

    private var displayObserver: DisplayConfigurationObserver?
    private var appActivationObserver: NSObjectProtocol?
    private var appHideObserver: NSObjectProtocol?
    private var appUnhideObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var permissionCheckerTask: Task<Void, Never>?
    private var wasHotkeysEnabledBeforeSecureInput = true

    init(controller: WMController) {
        self.controller = controller
    }

    func start() {
        guard let controller else { return }
        permissionCheckerTask?.cancel()
        permissionCheckerTask = Task { @MainActor [weak controller] in
            for await granted in AccessibilityPermissionMonitor.shared.stream(initial: true) {
                guard let controller, !Task.isCancelled else { return }

                if granted {
                    if !controller.hasStartedServices {
                        controller.serviceLifecycleManager.startServices()
                    }
                } else {
                    _ = controller.axManager.requestPermission()
                    controller.isEnabled = false
                    controller.hotkeysEnabled = false
                    controller.setHotkeysEnabled(false)
                }
            }
        }
    }

    private func startServices() {
        guard let controller, !controller.hasStartedServices else { return }
        controller.hasStartedServices = true
        controller.resetBorderRuntimeHealth()
        controller.layoutRefreshController.setup()
        controller.axEventHandler.setup()
        if controller.hotkeysEnabled {
            controller.setHotkeysEnabled(true)
        }
        controller.axManager.onAppLaunched = { [weak controller] app in
            guard let controller else { return }
            Task { @MainActor in
                _ = await controller.axManager.windowsForApp(app)
                controller.layoutRefreshController.scheduleRefreshSession(.axWindowCreated)
            }
        }
        controller.axManager.onAppTerminated = { [weak controller] pid in
            guard let controller else { return }
            controller.workspaceManager.removeWindowsForApp(pid: pid)
            controller.appInfoCache.evict(pid: pid)
            controller.layoutRefreshController.refreshWindowsAndLayout()
        }
        controller.axManager.onWindowDestroyed = { [weak controller] pid, windowId in
            guard let controller else { return }
            controller.axEventHandler.handleRemoved(pid: pid, winId: windowId)
        }
        controller.axManager.onWindowDestroyedUnknown = { [weak controller] in
            controller?.layoutRefreshController.refreshWindowsAndLayout()
        }
        controller.axManager.onFocusedWindowChanged = { [weak controller] pid in
            controller?.axEventHandler.handleAppActivation(pid: pid)
        }
        controller.axManager.startLifecycleObservation()
        setupWorkspaceObservation()
        controller.mouseEventHandler.setup()
        if controller.settings.mouseWarpEnabled {
            controller.mouseWarpHandler.setup()
        }
        setupDisplayObserver()
        setupAppActivationObserver()
        setupAppHideObservers()
        controller.workspaceManager.onGapsChanged = { [weak controller] in
            controller?.layoutRefreshController.refreshWindowsAndLayout()
        }

        controller.layoutRefreshController.refreshWindowsAndLayout()
        startSecureInputMonitor()
        startLockScreenObserver()
    }

    private func startLockScreenObserver() {
        guard let controller else { return }
        controller.lockScreenObserver.onLockDetected = { [weak controller] in
            controller?.isLockScreenActive = true
        }
        controller.lockScreenObserver.onUnlockDetected = { [weak controller] in
            guard let controller else { return }
            controller.isLockScreenActive = false
            controller.layoutRefreshController.refreshWindowsAndLayout()
            controller.updateWorkspaceBar()
        }
        controller.lockScreenObserver.start()
    }

    private func startSecureInputMonitor() {
        guard let controller else { return }
        controller.secureInputMonitor.start { [weak self] isSecure in
            self?.handleSecureInputChange(isSecure)
        }
    }

    private func handleSecureInputChange(_ isSecure: Bool) {
        guard let controller else { return }
        if isSecure {
            wasHotkeysEnabledBeforeSecureInput = controller.hotkeysEnabled
            if controller.hotkeysEnabled {
                controller.setHotkeysEnabled(false)
                SecureInputIndicatorController.shared.show()
            }
        } else {
            SecureInputIndicatorController.shared.hide()
            if wasHotkeysEnabledBeforeSecureInput {
                controller.setHotkeysEnabled(true)
            }
        }
    }

    private func setupDisplayObserver() {
        displayObserver = DisplayConfigurationObserver()
        displayObserver?.setEventHandler { [weak self] event in
            Task { @MainActor in
                self?.handleDisplayEvent(event)
            }
        }
    }

    private func handleDisplayEvent(_ event: DisplayConfigurationObserver.DisplayEvent) {
        switch event {
        case let .disconnected(monitorId, outputId):
            handleMonitorDisconnect(monitorId: monitorId, outputId: outputId)
        case .connected, .reconfigured:
            break
        }
        handleMonitorConfigurationChanged()
    }

    private func handleMonitorDisconnect(monitorId: Monitor.ID, outputId: OutputId) {
        guard let controller else { return }
        controller.layoutRefreshController.cleanupForMonitorDisconnect(displayId: outputId.displayId, migrateAnimations: false)

        if controller.activeMonitorId == monitorId {
            controller.activeMonitorId = controller.workspaceManager.monitors.first?.id
        }
        if controller.previousMonitorId == monitorId {
            controller.previousMonitorId = nil
        }

        controller.dwindleEngine?.cleanupRemovedMonitor(monitorId)
    }

    private func handleMonitorConfigurationChanged() {
        applyMonitorConfigurationChanged(currentMonitors: Monitor.current())
    }

    func applyMonitorConfigurationChanged(
        currentMonitors: [Monitor],
        performPostUpdateActions: Bool = true
    ) {
        guard let controller else { return }
        // Invalidate border cache so it gets fully recomputed after monitor change
        // (prevents stale geometry when display ID or coordinate space changes, e.g. KVM switch)
        controller.invalidateBorderDisplays()
        let workspaceSnapshots = captureWorkspaceSnapshotsBeforeMonitorUpdate()
        guard !currentMonitors.isEmpty else { return }
        guard currentMonitors.allSatisfy({ $0.frame.width > 1 && $0.frame.height > 1 }) else { return }

        controller.workspaceManager.updateMonitors(currentMonitors)
        controller.workspaceManager.reconcileAfterMonitorChange()
        restoreWorkspacesAfterMonitorUpdate(from: workspaceSnapshots)
        controller.syncMonitorsToNiriEngine()
        controller.syncMonitorStateFromWorkspaceRuntime()

        let focusedWsId = controller.focusedHandle.flatMap { controller.workspaceManager.workspace(for: $0) }
        controller.workspaceManager.garbageCollectUnusedWorkspaces(focusedWorkspaceId: focusedWsId)

        controller.layoutRefreshController.refreshWindowsAndLayout()
    }

    private func captureWorkspaceSnapshotsBeforeMonitorUpdate() -> [WorkspaceRestoreSnapshot] {
        guard let controller else { return [] }
        var snapshots: [WorkspaceRestoreSnapshot] = []
        snapshots.reserveCapacity(controller.workspaceManager.monitors.count)

        for monitor in controller.workspaceManager.monitors {
            guard let workspace = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id) else { continue }
            snapshots.append(WorkspaceRestoreSnapshot(
                monitor: MonitorRestoreKey(monitor: monitor),
                workspaceId: workspace.id
            ))
        }

        return snapshots
    }

    private func restoreWorkspacesAfterMonitorUpdate(from snapshots: [WorkspaceRestoreSnapshot]) {
        guard let controller else { return }
        guard !snapshots.isEmpty else { return }
        let forcedWorkspaceIds = forcedWorkspaceIdsForCurrentSettings()

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: controller.workspaceManager.monitors,
            workspaceExists: { workspaceId in
                controller.workspaceManager.descriptor(for: workspaceId) != nil
            }
        )

        if assignments.isEmpty { return }

        let sortedMonitors = Monitor.sortedByPosition(controller.workspaceManager.monitors)
        var restoredWorkspaces: Set<WorkspaceDescriptor.ID> = []

        for monitor in sortedMonitors {
            guard let workspaceId = assignments[monitor.id] else { continue }
            guard !forcedWorkspaceIds.contains(workspaceId) else { continue }
            guard restoredWorkspaces.insert(workspaceId).inserted else { continue }
            _ = controller.submitControllerCommand(
                .setActiveWorkspaceOnMonitor(
                    workspaceId: workspaceId,
                    displayId: monitor.displayId
                )
            )
        }

        // Forced workspace assignments remain authoritative after reconnect restore.
        controller.workspaceManager.reconcileAfterMonitorChange()
    }

    private func forcedWorkspaceIdsForCurrentSettings() -> Set<WorkspaceDescriptor.ID> {
        guard let controller else { return [] }
        let assignmentNames = controller.settings.workspaceToMonitorAssignments(
            sortedMonitors: controller.workspaceManager.monitors
        ).keys
        return Set(assignmentNames.compactMap { controller.workspaceManager.workspaceId(named: $0) })
    }

    private func setupWorkspaceObservation() {
        guard let controller else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak controller] _ in
            Task { @MainActor in
                controller?.refreshBorderPresentation(forceHide: true)
                controller?.layoutRefreshController.refreshWindowsAndLayout()
            }
        }
    }

    private func setupAppActivationObserver() {
        guard let controller else { return }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak controller] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let pid = app.processIdentifier
            Task { @MainActor in
                controller?.axEventHandler.handleAppActivation(pid: pid)
            }
        }
    }

    private func setupAppHideObservers() {
        guard let controller else { return }
        appHideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak controller] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                controller?.axEventHandler.handleAppHidden(pid: app.processIdentifier)
            }
        }

        appUnhideObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak controller] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                controller?.axEventHandler.handleAppUnhidden(pid: app.processIdentifier)
            }
        }
    }

    func stop() {
        guard let controller else { return }
        controller.hasStartedServices = false

        controller.axManager.onAppLaunched = nil
        controller.axManager.onAppTerminated = nil
        controller.axManager.onWindowDestroyed = nil
        controller.axManager.onWindowDestroyedUnknown = nil
        controller.axManager.onFocusedWindowChanged = nil
        controller.workspaceManager.onGapsChanged = nil

        controller.layoutRefreshController.resetState()
        controller.mouseEventHandler.cleanup()
        controller.mouseWarpHandler.cleanup()
        controller.axEventHandler.cleanup()

        controller.tabbedOverlayManager.removeAll()
        controller.cleanupBorderRuntime()
        controller.cleanupUIOnStop()

        controller.axManager.cleanup()

        displayObserver = nil

        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        if let observer = appHideObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appHideObserver = nil
        }
        if let observer = appUnhideObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appUnhideObserver = nil
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        controller.secureInputMonitor.stop()
        SecureInputIndicatorController.shared.hide()
        controller.lockScreenObserver.stop()
        controller.setHotkeysEnabled(false)
        permissionCheckerTask?.cancel()
        permissionCheckerTask = nil
    }
}
