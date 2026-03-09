import AppKit
import CZigLayout
import Foundation

private func zigCoreRuntimeSecureInputBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ isSecureInputActive: UInt8
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleSecureInputChangedCallback(isSecureInputActive)
}

private func zigCoreRuntimeTapHealthBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ tapKind: UInt8,
    _ reason: UInt8
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleTapHealthCallback(tapKind: tapKind, reason: reason)
}

private func zigCoreRuntimeWMApplyEffectsBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ effects: UnsafePointer<OmniControllerEffectExport>?
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleWMApplyEffectsCallback(effects)
}

private func zigCoreRuntimeWMReportErrorBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ code: Int32,
    _ message: OmniControllerName
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleWMReportErrorCallback(code: code, message: message)
}

private func zigCoreRuntimeLifecycleStateBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ state: UInt8
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleLifecycleStateChangedCallback(state)
}

private func zigCoreRuntimeLifecycleErrorBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ code: Int32,
    _ message: OmniControllerName
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleLifecycleErrorCallback(code: code, message: message)
}

private enum ZigCoreRuntimeHostCallbackAction: Sendable {
    case secureInputChanged(Bool)
    case tapHealthNotification(UInt8, UInt8)
    case applyEffects([UInt8])
    case reportError(Int32, String)
    case lifecycleStateChanged(UInt8)
    case lifecycleError(Int32, String)
}

@MainActor
final class ZigCoreRuntime {
    weak var controller: WMController?
    var onSecureInputStateChange: ((Bool) -> Void)?
    var onTapHealthNotification: ((UInt8, UInt8) -> Void)?
    var started: Bool = false
    var registrationFailures: Set<HotkeyCommand> = []

    private var wmControllerRuntime: OpaquePointer?
    private var serviceLifecycle: OpaquePointer?

    private var hotkeyCommandByBindingId: [String: HotkeyCommand] = [:]
    private var secureInputState: Bool = false

#if DEBUG
    var debugOnUIActionsDispatched: (([UInt8]) -> Void)?
    var debugOnControllerErrorDispatched: ((Int32, String) -> Void)?
    private(set) var debugSnapshotInvalidationCount: Int = 0
#endif

    init(workspaceRuntimeHandle: OpaquePointer) {
        createRuntimes(workspaceRuntimeHandle: workspaceRuntimeHandle)
        refreshLifecycleState()
    }

    deinit {
        MainActor.assumeIsolated {
            destroyRuntimes()
        }
    }

    func start(
        settings: SettingsStore,
        focusFollowsWindowToMonitor: Bool,
        moveMouseToFocusedWindow: Bool
    ) {
        guard serviceLifecycle != nil else {
            started = false
            return
        }

        updateBindings(settings.hotkeyBindings)
        setHotkeysEnabled(settings.hotkeysEnabled, settings: settings)
        applyControllerSettings(
            settings: settings,
            focusFollowsWindowToMonitor: focusFollowsWindowToMonitor,
            moveMouseToFocusedWindow: moveMouseToFocusedWindow
        )

        if let serviceLifecycle {
            let rc = omni_service_lifecycle_start(serviceLifecycle)
            if rc != Int32(OMNI_OK) {
                started = false
                dispatchControllerError(code: rc, message: "failed to start core service lifecycle")
                return
            }
        }

        refreshLifecycleState()
        refreshRegistrationFailures()
        syncControllerState()
    }

    func stop() {
        if let serviceLifecycle {
            _ = omni_service_lifecycle_stop(serviceLifecycle)
        }
        started = false
        registrationFailures.removeAll(keepingCapacity: false)
        secureInputState = false
        onSecureInputStateChange?(false)
        invalidateControllerSnapshot()
    }

    func setHotkeysEnabled(_ enabled: Bool, settings: SettingsStore) {
        if hotkeyCommandByBindingId.isEmpty {
            updateBindings(settings.hotkeyBindings)
        }

        guard let serviceLifecycle else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var options = OmniInputOptions(
            hotkeys_enabled: enabled ? 1 : 0,
            mouse_enabled: 1,
            gestures_enabled: settings.scrollGestureEnabled ? 1 : 0,
            secure_input_enabled: 1
        )

        withUnsafePointer(to: &options) { optionsPtr in
            _ = omni_service_lifecycle_set_input_options(serviceLifecycle, optionsPtr)
        }

        if enabled {
            refreshRegistrationFailures()
        } else {
            registrationFailures.removeAll(keepingCapacity: false)
        }
    }

    func updateBindings(_ bindings: [HotkeyBinding]) {
        hotkeyCommandByBindingId = Dictionary(
            bindings.map { ($0.id, $0.command) },
            uniquingKeysWith: { first, _ in first }
        )

        guard let serviceLifecycle else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        let rawBindings = bindings.map { binding in
            OmniInputBinding(
                binding_id: Self.rawBindingId(from: binding.id),
                key_code: binding.binding.keyCode,
                modifiers: binding.binding.modifiers,
                enabled: binding.binding.isUnassigned ? 0 : 1
            )
        }

        let rc: Int32
        if rawBindings.isEmpty {
            rc = omni_service_lifecycle_set_bindings(serviceLifecycle, nil, 0)
        } else {
            rc = rawBindings.withUnsafeBufferPointer { buffer in
                omni_service_lifecycle_set_bindings(serviceLifecycle, buffer.baseAddress, buffer.count)
            }
        }

        if rc != Int32(OMNI_OK) {
            dispatchControllerError(code: rc, message: "failed to update input bindings")
        }

        refreshRegistrationFailures()
    }

    func applyControllerSettings(
        settings: SettingsStore,
        focusFollowsWindowToMonitor: Bool,
        moveMouseToFocusedWindow: Bool
    ) {
        guard let wmControllerRuntime else { return }
        var delta = OmniControllerSettingsDelta()
        delta.struct_size = MemoryLayout<OmniControllerSettingsDelta>.size
        delta.has_focus_follows_mouse = 1
        delta.focus_follows_mouse = settings.focusFollowsMouse ? 1 : 0
        delta.has_focus_follows_window_to_monitor = 1
        delta.focus_follows_window_to_monitor = focusFollowsWindowToMonitor ? 1 : 0
        delta.has_move_mouse_to_focused_window = 1
        delta.move_mouse_to_focused_window = moveMouseToFocusedWindow ? 1 : 0
        delta.has_layout_gap = 1
        delta.layout_gap = settings.gapSize
        delta.has_outer_gap_left = 1
        delta.outer_gap_left = settings.outerGapLeft
        delta.has_outer_gap_right = 1
        delta.outer_gap_right = settings.outerGapRight
        delta.has_outer_gap_top = 1
        delta.outer_gap_top = settings.outerGapTop
        delta.has_outer_gap_bottom = 1
        delta.outer_gap_bottom = settings.outerGapBottom
        delta.has_niri_max_visible_columns = 1
        delta.niri_max_visible_columns = Int64(settings.niriMaxVisibleColumns)
        delta.has_niri_max_windows_per_column = 1
        delta.niri_max_windows_per_column = Int64(settings.niriMaxWindowsPerColumn)
        delta.has_niri_infinite_loop = 1
        delta.niri_infinite_loop = settings.niriInfiniteLoop ? 1 : 0
        delta.has_niri_width_presets = 1
        delta.has_border_enabled = 1
        delta.border_enabled = settings.bordersEnabled ? 1 : 0
        delta.has_border_width = 1
        delta.border_width = settings.borderWidth
        delta.has_border_color = 1
        delta.border_color = OmniBorderColor(
            red: settings.borderColorRed,
            green: settings.borderColorGreen,
            blue: settings.borderColorBlue,
            alpha: settings.borderColorAlpha
        )
        delta.has_default_layout_kind = 1
        delta.default_layout_kind = Self.rawControllerLayoutKind(from: settings.defaultLayoutType)
        delta.has_dwindle_move_to_root_stable = 1
        delta.dwindle_move_to_root_stable = settings.dwindleMoveToRootStable ? 1 : 0

        let cappedPresets = Array(
            settings.niriColumnWidthPresets.prefix(Int(OMNI_CONTROLLER_NIRI_WIDTH_PRESET_CAP))
        )
        delta.niri_width_preset_count = cappedPresets.count
        withUnsafeMutableBytes(of: &delta.niri_width_presets) { rawBuffer in
            rawBuffer.initializeMemory(as: Double.self, repeating: 0)
            let buffer = rawBuffer.bindMemory(to: Double.self)
            for (index, preset) in cappedPresets.enumerated() where index < buffer.count {
                buffer[index] = preset
            }
        }

        let monitorSettings: [OmniControllerMonitorNiriSettings] = controller?.workspaceManager.monitors.map { monitor in
            let resolved = settings.resolvedNiriSettings(for: monitor)
            let aspect = Self.aspectComponents(from: resolved.singleWindowAspectRatio)
            return OmniControllerMonitorNiriSettings(
                display_id: monitor.displayId,
                orientation: Self.rawOrientation(from: settings.effectiveOrientation(for: monitor)),
                center_focused_column: Self.rawCenterMode(from: resolved.centerFocusedColumn),
                always_center_single_column: resolved.alwaysCenterSingleColumn ? 1 : 0,
                single_window_aspect_width: aspect.width,
                single_window_aspect_height: aspect.height
            )
        } ?? []
        let dwindleMonitorSettings: [OmniControllerMonitorDwindleSettings] = controller?.workspaceManager.monitors.map { monitor in
            let resolved = settings.resolvedDwindleSettings(for: monitor)
            let aspect = resolved.singleWindowAspectRatio.size
            return OmniControllerMonitorDwindleSettings(
                display_id: monitor.displayId,
                smart_split: resolved.smartSplit ? 1 : 0,
                default_split_ratio: resolved.defaultSplitRatio,
                split_width_multiplier: resolved.splitWidthMultiplier,
                inner_gap: resolved.innerGap,
                outer_gap_top: resolved.outerGapTop,
                outer_gap_bottom: resolved.outerGapBottom,
                outer_gap_left: resolved.outerGapLeft,
                outer_gap_right: resolved.outerGapRight,
                single_window_aspect_width: aspect.width,
                single_window_aspect_height: aspect.height
            )
        } ?? []

        let workspaceLayoutSettings = settings.workspaceConfigurations
            .filter { $0.layoutType != .defaultLayout }
            .sorted { $0.name.toLogicalSegments() < $1.name.toLogicalSegments() }
            .map { config in
            OmniControllerWorkspaceLayoutSetting(
                name: Self.rawControllerName(from: config.name),
                layout_kind: Self.rawControllerLayoutKind(from: config.layoutType)
            )
        }

        let rc = monitorSettings.withUnsafeBufferPointer { buffer in
            delta.monitor_niri_settings = buffer.isEmpty ? nil : buffer.baseAddress
            delta.monitor_niri_settings_count = buffer.count
            return dwindleMonitorSettings.withUnsafeBufferPointer { dwindleBuffer in
                delta.monitor_dwindle_settings = dwindleBuffer.isEmpty ? nil : dwindleBuffer.baseAddress
                delta.monitor_dwindle_settings_count = dwindleBuffer.count
                return workspaceLayoutSettings.withUnsafeBufferPointer { workspaceBuffer in
                    delta.workspace_layout_settings = workspaceBuffer.isEmpty ? nil : workspaceBuffer.baseAddress
                    delta.workspace_layout_settings_count = workspaceBuffer.count
                    return withUnsafePointer(to: &delta) { settingsPtr in
                        omni_wm_controller_apply_settings(wmControllerRuntime, settingsPtr)
                    }
                }
            }
        }

        if rc != Int32(OMNI_OK) {
            dispatchControllerError(code: rc, message: "failed to apply controller settings")
        }
    }

    func submitUIBridgeCommand(_ command: OmniControllerCommand) -> Bool {
        guard let wmControllerRuntime else { return false }
        var mutableCommand = command
        let rc = withUnsafePointer(to: &mutableCommand) { commandPtr in
            omni_ui_bridge_submit_hotkey(wmControllerRuntime, commandPtr)
        }
        guard rc == Int32(OMNI_OK) else { return false }
        syncControllerState()
        return true
    }

    func syncControllerState() {
        refreshLifecycleState()

        guard started, let wmControllerRuntime else {
            invalidateControllerSnapshot()
            return
        }
        guard let snapshotExport = WMControllerSnapshotAdapter.flushAndCapture(runtime: wmControllerRuntime) else {
            invalidateControllerSnapshot(refreshUI: false)
            controller?.syncExperimentalProjectionsFromCore(changedWorkspaceIds: nil)
            updateSecureInputStateFromRuntime()
            return
        }
        let workspaceLayoutOverrides = captureWorkspaceLayoutOverrides(runtime: wmControllerRuntime)

        controller?.syncExperimentalProjectionsFromCore(
            changedWorkspaceIds: snapshotExport.changedWorkspaceIds,
            stateExport: snapshotExport.stateExport,
            controllerSnapshot: snapshotExport.controllerSnapshot,
            workspaceLayoutOverrides: workspaceLayoutOverrides
        )
        updateSecureInputState(snapshotExport.uiState)
    }

    nonisolated fileprivate func handleSecureInputChangedCallback(_ isSecureInputActive: UInt8) -> Int32 {
        enqueueHostCallback(.secureInputChanged(isSecureInputActive != 0))
    }

    nonisolated fileprivate func handleTapHealthCallback(tapKind: UInt8, reason: UInt8) -> Int32 {
        enqueueHostCallback(.tapHealthNotification(tapKind, reason))
    }

    nonisolated fileprivate func handleWMApplyEffectsCallback(
        _ effects: UnsafePointer<OmniControllerEffectExport>?
    ) -> Int32 {
        guard let effects else { return Int32(OMNI_ERR_INVALID_ARGS) }
        let export = effects.pointee
        let uiActionKinds: [UInt8]
        if let actions = export.ui_actions, export.ui_action_count > 0 {
            uiActionKinds = Array(
                UnsafeBufferPointer(start: actions, count: export.ui_action_count).map(\.kind)
            )
        } else {
            uiActionKinds = []
        }
        return enqueueHostCallback(.applyEffects(uiActionKinds))
    }

    nonisolated fileprivate func handleWMReportErrorCallback(
        code: Int32,
        message: OmniControllerName
    ) -> Int32 {
        enqueueHostCallback(.reportError(code, Self.string(from: message)))
    }

    nonisolated fileprivate func handleLifecycleStateChangedCallback(_ state: UInt8) -> Int32 {
        enqueueHostCallback(.lifecycleStateChanged(state))
    }

    nonisolated fileprivate func handleLifecycleErrorCallback(
        code: Int32,
        message: OmniControllerName
    ) -> Int32 {
        enqueueHostCallback(.lifecycleError(code, Self.string(from: message)))
    }

    private func createRuntimes(workspaceRuntimeHandle: OpaquePointer) {
        let userdata = Unmanaged.passUnretained(self).toOpaque()

        var wmConfig = OmniWMControllerConfig(
            abi_version: UInt32(OMNI_WM_CONTROLLER_ABI_VERSION),
            reserved: 0
        )
        var wmHost = OmniWMControllerHostVTable(
            userdata: userdata,
            apply_effects: zigCoreRuntimeWMApplyEffectsBridge,
            report_error: zigCoreRuntimeWMReportErrorBridge
        )
        wmControllerRuntime = withUnsafePointer(to: &wmConfig) { configPtr in
            withUnsafePointer(to: &wmHost) { hostPtr in
                omni_wm_controller_create(configPtr, workspaceRuntimeHandle, hostPtr)
            }
        }

        guard wmControllerRuntime != nil else {
            dispatchControllerError(code: Int32(OMNI_ERR_PLATFORM), message: "failed to create core runtimes")
            destroyRuntimes()
            return
        }

        var lifecycleConfig = OmniServiceLifecycleConfig(
            abi_version: UInt32(OMNI_SERVICE_LIFECYCLE_ABI_VERSION),
            poll_ax_permission: 1,
            request_ax_prompt: 0,
            reserved: (0, 0),
            ax_poll_timeout_millis: 0,
            ax_poll_interval_millis: 250
        )
        var lifecycleHandles = OmniServiceLifecycleHandles(
            wm_controller: wmControllerRuntime,
            input_runtime: nil,
            platform_runtime: nil,
            workspace_observer_runtime: nil,
            lock_observer_runtime: nil,
            ax_runtime: nil,
            monitor_runtime: nil
        )
        var lifecycleHost = OmniServiceLifecycleHostVTable(
            userdata: userdata,
            on_state_changed: zigCoreRuntimeLifecycleStateBridge,
            on_error: zigCoreRuntimeLifecycleErrorBridge,
            on_secure_input_state_changed: zigCoreRuntimeSecureInputBridge,
            on_tap_health_notification: zigCoreRuntimeTapHealthBridge
        )

        serviceLifecycle = withUnsafePointer(to: &lifecycleConfig) { configPtr in
            withUnsafePointer(to: &lifecycleHandles) { handlesPtr in
                withUnsafePointer(to: &lifecycleHost) { hostPtr in
                    omni_service_lifecycle_create(configPtr, handlesPtr, hostPtr)
                }
            }
        }

        if serviceLifecycle == nil {
            dispatchControllerError(code: Int32(OMNI_ERR_PLATFORM), message: "failed to create core service lifecycle")
            destroyRuntimes()
        }
    }

    private func destroyRuntimes() {
        if let serviceLifecycle {
            _ = omni_service_lifecycle_stop(serviceLifecycle)
            omni_service_lifecycle_destroy(serviceLifecycle)
            self.serviceLifecycle = nil
        }

        if let wmControllerRuntime {
            omni_wm_controller_destroy(wmControllerRuntime)
            self.wmControllerRuntime = nil
        }

        started = false
        invalidateControllerSnapshot()
    }

    private func refreshLifecycleState() {
        guard let serviceLifecycle else {
            started = false
            return
        }
        var state: UInt8 = 0
        let rc = withUnsafeMutablePointer(to: &state) { statePtr in
            omni_service_lifecycle_query_state(serviceLifecycle, statePtr)
        }
        guard rc == Int32(OMNI_OK) else {
            started = false
            return
        }
        started = state == Self.rawEnumValue(OMNI_SERVICE_LIFECYCLE_STATE_RUNNING)
    }

    private func refreshRegistrationFailures() {
        guard let serviceLifecycle else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var required = 0
        let probeRc = withUnsafeMutablePointer(to: &required) { writtenPtr in
            omni_service_lifecycle_query_registration_failures(serviceLifecycle, nil, 0, writtenPtr)
        }
        guard probeRc == Int32(OMNI_OK), required > 0 else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var failures = Array(repeating: OmniInputRegistrationFailure(), count: required)
        var written = 0
        let queryRc = failures.withUnsafeMutableBufferPointer { buffer in
            withUnsafeMutablePointer(to: &written) { writtenPtr in
                omni_service_lifecycle_query_registration_failures(
                    serviceLifecycle,
                    buffer.baseAddress,
                    buffer.count,
                    writtenPtr
                )
            }
        }
        guard queryRc == Int32(OMNI_OK) else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var commands: Set<HotkeyCommand> = []
        for failure in failures.prefix(max(0, min(written, failures.count))) {
            let id = Self.string(from: failure.binding_id)
            if let command = hotkeyCommandByBindingId[id] {
                commands.insert(command)
            }
        }
        registrationFailures = commands
    }

    private func dispatchUIActions(_ uiActionKinds: [UInt8]) {
#if DEBUG
        debugOnUIActionsDispatched?(uiActionKinds)
#endif
        for kind in uiActionKinds {
            switch kind {
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_OPEN_WINDOW_FINDER):
                controller?.openWindowFinder()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_RAISE_ALL_FLOATING_WINDOWS):
                controller?.raiseAllFloatingWindows()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_OPEN_MENU_ANYWHERE):
                controller?.openMenuAnywhere()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_OPEN_MENU_PALETTE):
                controller?.openMenuPalette()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_TOGGLE_HIDDEN_BAR):
                controller?.toggleHiddenBar()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_TOGGLE_QUAKE_TERMINAL):
                controller?.toggleQuakeTerminal()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_TOGGLE_OVERVIEW):
                controller?.toggleOverview()
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_SHOW_SECURE_INPUT):
                secureInputState = true
                onSecureInputStateChange?(true)
            case Self.rawEnumValue(OMNI_CONTROLLER_UI_HIDE_SECURE_INPUT):
                secureInputState = false
                onSecureInputStateChange?(false)
            default:
                continue
            }
        }
    }

    private func dispatchControllerError(code: Int32, message: String) {
#if DEBUG
        debugOnControllerErrorDispatched?(code, message)
#endif
        controller?.handleZigCoreRuntimeError(code: code, message: message)
    }

    private func invalidateControllerSnapshot(refreshUI: Bool = true) {
#if DEBUG
        debugSnapshotInvalidationCount += 1
#endif
        controller?.invalidateControllerSnapshot(refreshUI: refreshUI)
    }

    nonisolated private func enqueueHostCallback(_ action: ZigCoreRuntimeHostCallbackAction) -> Int32 {
        let runtimePtr = Unmanaged.passRetained(self).toOpaque()
        Task { @MainActor in
            let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(runtimePtr).takeRetainedValue()
            runtime.applyHostCallback(action)
        }
        return Int32(OMNI_OK)
    }

    private func applyHostCallback(_ action: ZigCoreRuntimeHostCallbackAction) {
        switch action {
        case let .secureInputChanged(isSecure):
            secureInputState = isSecure
            onSecureInputStateChange?(isSecure)
        case let .tapHealthNotification(tapKind, reason):
            onTapHealthNotification?(tapKind, reason)
        case let .applyEffects(uiActionKinds):
            dispatchUIActions(uiActionKinds)
        case let .reportError(code, message):
            dispatchControllerError(code: code, message: message)
        case let .lifecycleStateChanged(state):
            started = state == Self.rawEnumValue(OMNI_SERVICE_LIFECYCLE_STATE_RUNNING)
            if !started {
                invalidateControllerSnapshot()
            }
        case let .lifecycleError(code, message):
            started = false
            invalidateControllerSnapshot()
            dispatchControllerError(code: code, message: message)
        }
    }

#if DEBUG
    nonisolated func debugInvokeSecureInputChangedOffMain(_ isSecure: Bool) async {
        await debugInvokeOffMain { runtime in
            _ = runtime.handleSecureInputChangedCallback(isSecure ? 1 : 0)
        }
    }

    nonisolated func debugInvokeTapHealthOffMain(tapKind: UInt8, reason: UInt8) async {
        await debugInvokeOffMain { runtime in
            _ = runtime.handleTapHealthCallback(tapKind: tapKind, reason: reason)
        }
    }

    nonisolated func debugInvokeWMApplyEffectsOffMain(_ uiActionKinds: [UInt8]) async {
        await debugInvokeOffMain { runtime in
            var rawActions = uiActionKinds.map { OmniControllerUiAction(kind: $0) }
            var export = OmniControllerEffectExport(
                focus_exports: nil,
                focus_export_count: 0,
                route_plans: nil,
                route_plan_count: 0,
                transfer_plans: nil,
                transfer_plan_count: 0,
                refresh_plans: nil,
                refresh_plan_count: 0,
                ui_actions: nil,
                ui_action_count: rawActions.count,
                layout_actions: nil,
                layout_action_count: 0
            )
            rawActions.withUnsafeMutableBufferPointer { buffer in
                export.ui_actions = buffer.baseAddress.map { UnsafePointer($0) }
                withUnsafePointer(to: &export) { exportPtr in
                    _ = runtime.handleWMApplyEffectsCallback(exportPtr)
                }
            }
        }
    }

    nonisolated func debugInvokeWMReportErrorOffMain(code: Int32, message: String) async {
        await debugInvokeOffMain { runtime in
            _ = runtime.handleWMReportErrorCallback(code: code, message: Self.rawControllerName(from: message))
        }
    }

    nonisolated func debugInvokeLifecycleStateChangedOffMain(_ state: UInt8) async {
        await debugInvokeOffMain { runtime in
            _ = runtime.handleLifecycleStateChangedCallback(state)
        }
    }

    nonisolated func debugInvokeLifecycleErrorOffMain(code: Int32, message: String) async {
        await debugInvokeOffMain { runtime in
            _ = runtime.handleLifecycleErrorCallback(code: code, message: Self.rawControllerName(from: message))
        }
    }

    nonisolated private func debugInvokeOffMain(
        _ body: @escaping @Sendable (ZigCoreRuntime) -> Void
    ) async {
        let runtimePtr = Unmanaged.passRetained(self).toOpaque()
        await Task.detached {
            let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(runtimePtr).takeRetainedValue()
            body(runtime)
        }.value
        _ = await Task { @MainActor in () }.value
    }
#endif

    private func updateSecureInputStateFromRuntime() {
        guard let wmControllerRuntime else { return }
        var uiState = OmniControllerUiState()
        let rc = withUnsafeMutablePointer(to: &uiState) { statePtr in
            omni_wm_controller_query_ui_state(wmControllerRuntime, statePtr)
        }
        guard rc == Int32(OMNI_OK) else { return }
        updateSecureInputState(uiState)
    }

    private func updateSecureInputState(_ uiState: OmniControllerUiState) {
        let isSecure = uiState.secure_input_active != 0
        if isSecure != secureInputState {
            secureInputState = isSecure
            onSecureInputStateChange?(isSecure)
        }
    }

    private func captureWorkspaceLayoutOverrides(runtime: OpaquePointer) -> [WMControllerWorkspaceLayoutOverride]? {
        var requiredCount: Int = 0
        let countRc = withUnsafeMutablePointer(to: &requiredCount) { countPtr in
            omni_wm_controller_query_workspace_layout_settings_count(runtime, countPtr)
        }
        guard countRc == Int32(OMNI_OK), requiredCount >= 0 else { return nil }

        for _ in 0 ..< 3 {
            var buffer = Array(repeating: OmniControllerWorkspaceLayoutSetting(), count: requiredCount)
            var writtenCount = 0
            let copyRc = buffer.withUnsafeMutableBufferPointer { settingsPtr in
                withUnsafeMutablePointer(to: &writtenCount) { writtenPtr in
                    omni_wm_controller_copy_workspace_layout_settings(
                        runtime,
                        settingsPtr.baseAddress,
                        settingsPtr.count,
                        writtenPtr
                    )
                }
            }

            if copyRc == Int32(OMNI_OK) {
                let safeCount = max(0, min(writtenCount, buffer.count))
                return buffer.prefix(safeCount).compactMap { rawSetting in
                    guard let layoutType = Self.layoutType(fromControllerLayoutKind: rawSetting.layout_kind) else {
                        return nil
                    }
                    return WMControllerWorkspaceLayoutOverride(
                        name: Self.string(from: rawSetting.name),
                        layoutType: layoutType
                    )
                }
            }

            guard copyRc == Int32(OMNI_ERR_OUT_OF_RANGE) else { return nil }

            let nextCountRc = withUnsafeMutablePointer(to: &requiredCount) { countPtr in
                omni_wm_controller_query_workspace_layout_settings_count(runtime, countPtr)
            }
            guard nextCountRc == Int32(OMNI_OK), requiredCount >= 0 else { return nil }
        }

        return nil
    }

    nonisolated private static func rawBindingId(from string: String) -> OmniInputBindingId {
        var result = OmniInputBindingId()
        let utf8 = Array(string.utf8.prefix(Int(OMNI_INPUT_BINDING_ID_CAP)))
        result.length = UInt8(utf8.count)
        withUnsafeMutableBytes(of: &result.bytes) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: utf8)
        }
        return result
    }

    nonisolated private static func string(from rawBindingId: OmniInputBindingId) -> String {
        let length = min(Int(rawBindingId.length), Int(OMNI_INPUT_BINDING_ID_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: rawBindingId.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated private static func string(from rawName: OmniControllerName) -> String {
        let length = min(Int(rawName.length), Int(OMNI_CONTROLLER_NAME_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: rawName.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated private static func rawControllerName(from string: String) -> OmniControllerName {
        var result = OmniControllerName()
        let utf8 = Array(string.utf8.prefix(Int(OMNI_CONTROLLER_NAME_CAP)))
        result.length = UInt8(utf8.count)
        withUnsafeMutableBytes(of: &result.bytes) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: utf8)
        }
        return result
    }

    nonisolated private static func rawOrientation(from orientation: Monitor.Orientation) -> UInt8 {
        switch orientation {
        case .horizontal:
            return rawEnumValue(OMNI_NIRI_ORIENTATION_HORIZONTAL)
        case .vertical:
            return rawEnumValue(OMNI_NIRI_ORIENTATION_VERTICAL)
        }
    }

    nonisolated private static func rawCenterMode(from centerMode: CenterFocusedColumn) -> UInt8 {
        switch centerMode {
        case .never:
            return rawEnumValue(OMNI_CENTER_NEVER)
        case .always:
            return rawEnumValue(OMNI_CENTER_ALWAYS)
        case .onOverflow:
            return rawEnumValue(OMNI_CENTER_ON_OVERFLOW)
        }
    }

    nonisolated private static func aspectComponents(from ratio: SingleWindowAspectRatio) -> (width: Double, height: Double) {
        switch ratio {
        case .none:
            return (0, 0)
        case .ratio16x9:
            return (16, 9)
        case .ratio4x3:
            return (4, 3)
        case .ratio21x9:
            return (21, 9)
        case .square:
            return (1, 1)
        }
    }

    nonisolated private static func rawControllerLayoutKind(from layoutType: LayoutType) -> UInt8 {
        switch layoutType {
        case .defaultLayout:
            return rawEnumValue(OMNI_CONTROLLER_LAYOUT_DEFAULT)
        case .niri:
            return rawEnumValue(OMNI_CONTROLLER_LAYOUT_NIRI)
        case .dwindle:
            return rawEnumValue(OMNI_CONTROLLER_LAYOUT_DWINDLE)
        }
    }

    nonisolated private static func layoutType(fromControllerLayoutKind rawKind: UInt8) -> LayoutType? {
        switch rawKind {
        case rawEnumValue(OMNI_CONTROLLER_LAYOUT_NIRI):
            return .niri
        case rawEnumValue(OMNI_CONTROLLER_LAYOUT_DWINDLE):
            return .dwindle
        default:
            return nil
        }
    }

    nonisolated private static func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
        UInt8(clamping: Int(value.rawValue))
    }
}

private extension WMController {
    func handleZigCoreRuntimeError(code: Int32, message: String) {
        NSLog("Zig core runtime error code=%d message=%@", code, message)
    }
}
