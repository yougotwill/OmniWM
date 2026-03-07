import AppKit
import CZigLayout
import Foundation

private func zigCoreRuntimeInputHotkeyBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ command: OmniControllerCommand
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleInputHotkeyCallback(command)
}

private func zigCoreRuntimeSecureInputBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ isSecureInputActive: UInt8
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleSecureInputChangedCallback(isSecureInputActive)
}

private func zigCoreRuntimeMouseEffectBridge(
    _ userdata: UnsafeMutableRawPointer?,
    _ effects: UnsafePointer<OmniInputEffectExport>?
) -> Int32 {
    guard let userdata else { return Int32(OMNI_ERR_INVALID_ARGS) }
    let runtime = Unmanaged<ZigCoreRuntime>.fromOpaque(userdata).takeUnretainedValue()
    return runtime.handleMouseEffectBatchCallback(effects)
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

@MainActor
final class ZigCoreRuntime {
    weak var controller: WMController?
    var onSecureInputStateChange: ((Bool) -> Void)?
    var onTapHealthNotification: ((UInt8, UInt8) -> Void)?
    var started: Bool = false
    var registrationFailures: Set<HotkeyCommand> = []

    private var wmControllerRuntime: OpaquePointer?
    private var inputRuntime: OpaquePointer?
    private var serviceLifecycle: OpaquePointer?

    private var hotkeyCommandByBindingId: [String: HotkeyCommand] = [:]
    private var secureInputState: Bool = false

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
    }

    func setHotkeysEnabled(_ enabled: Bool, settings: SettingsStore) {
        if hotkeyCommandByBindingId.isEmpty {
            updateBindings(settings.hotkeyBindings)
        }

        guard let inputRuntime else {
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
            _ = omni_input_runtime_set_options(inputRuntime, optionsPtr)
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

        guard let inputRuntime else {
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
            rc = omni_input_runtime_set_bindings(inputRuntime, nil, 0)
        } else {
            rc = rawBindings.withUnsafeBufferPointer { buffer in
                omni_input_runtime_set_bindings(inputRuntime, buffer.baseAddress, buffer.count)
            }
        }

        if rc != Int32(OMNI_OK) {
            dispatchControllerError(code: rc, message: "failed to update input runtime bindings")
        }

        refreshRegistrationFailures()
    }

    func applyControllerSettings(
        focusFollowsWindowToMonitor: Bool,
        moveMouseToFocusedWindow: Bool
    ) {
        guard let wmControllerRuntime else { return }
        var settings = OmniControllerSettingsDelta(
            has_focus_follows_window_to_monitor: 1,
            focus_follows_window_to_monitor: focusFollowsWindowToMonitor ? 1 : 0,
            has_move_mouse_to_focused_window: 1,
            move_mouse_to_focused_window: moveMouseToFocusedWindow ? 1 : 0
        )
        withUnsafePointer(to: &settings) { settingsPtr in
            _ = omni_ui_bridge_apply_settings(wmControllerRuntime, settingsPtr)
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

        guard let wmControllerRuntime else { return }
        _ = omni_wm_controller_tick(wmControllerRuntime, Date().timeIntervalSinceReferenceDate)
        var uiState = OmniControllerUiState()
        let rc = withUnsafeMutablePointer(to: &uiState) { statePtr in
            omni_ui_bridge_query_ui_state(wmControllerRuntime, statePtr)
        }
        guard rc == Int32(OMNI_OK) else { return }

        let isSecure = uiState.secure_input_active != 0
        if isSecure != secureInputState {
            secureInputState = isSecure
            onSecureInputStateChange?(isSecure)
        }
    }

    nonisolated fileprivate func handleInputHotkeyCallback(_ command: OmniControllerCommand) -> Int32 {
        MainActor.assumeIsolated {
            guard let wmControllerRuntime else { return Int32(OMNI_ERR_INVALID_ARGS) }
            var mutableCommand = command
            return withUnsafePointer(to: &mutableCommand) { commandPtr in
                omni_wm_controller_submit_hotkey(wmControllerRuntime, commandPtr)
            }
        }
    }

    nonisolated fileprivate func handleSecureInputChangedCallback(_ isSecureInputActive: UInt8) -> Int32 {
        MainActor.assumeIsolated {
            let isSecure = isSecureInputActive != 0
            let rc = submitSecureInputChangedEvent(isSecure)
            secureInputState = isSecure
            onSecureInputStateChange?(isSecure)
            return rc
        }
    }

    nonisolated fileprivate func handleMouseEffectBatchCallback(
        _ effects: UnsafePointer<OmniInputEffectExport>?
    ) -> Int32 {
        guard let effects else { return Int32(OMNI_ERR_INVALID_ARGS) }
        Self.releaseUnconsumedMouseEffects(effects.pointee)
        return Int32(OMNI_OK)
    }

    nonisolated fileprivate func handleTapHealthCallback(tapKind: UInt8, reason: UInt8) -> Int32 {
        MainActor.assumeIsolated {
            onTapHealthNotification?(tapKind, reason)
        }
        return Int32(OMNI_OK)
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
        MainActor.assumeIsolated {
            dispatchUIActions(uiActionKinds)
        }
        return Int32(OMNI_OK)
    }

    nonisolated fileprivate func handleWMReportErrorCallback(
        code: Int32,
        message: OmniControllerName
    ) -> Int32 {
        MainActor.assumeIsolated {
            dispatchControllerError(code: code, message: Self.string(from: message))
        }
        return Int32(OMNI_OK)
    }

    nonisolated fileprivate func handleLifecycleStateChangedCallback(_ state: UInt8) -> Int32 {
        MainActor.assumeIsolated {
            started = state == Self.rawEnumValue(OMNI_SERVICE_LIFECYCLE_STATE_RUNNING)
        }
        return Int32(OMNI_OK)
    }

    nonisolated fileprivate func handleLifecycleErrorCallback(
        code: Int32,
        message: OmniControllerName
    ) -> Int32 {
        MainActor.assumeIsolated {
            started = false
            dispatchControllerError(code: code, message: Self.string(from: message))
        }
        return Int32(OMNI_OK)
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

        var inputConfig = OmniInputRuntimeConfig(
            abi_version: UInt32(OMNI_INPUT_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        var inputHost = OmniInputHostVTable(
            userdata: userdata,
            on_hotkey_command: zigCoreRuntimeInputHotkeyBridge,
            on_secure_input_state_changed: zigCoreRuntimeSecureInputBridge,
            on_mouse_effect_batch: zigCoreRuntimeMouseEffectBridge,
            on_tap_health_notification: zigCoreRuntimeTapHealthBridge
        )
        inputRuntime = withUnsafePointer(to: &inputConfig) { configPtr in
            withUnsafePointer(to: &inputHost) { hostPtr in
                omni_input_runtime_create(configPtr, hostPtr)
            }
        }

        guard wmControllerRuntime != nil, inputRuntime != nil else {
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
            input_runtime: inputRuntime,
            platform_runtime: nil,
            workspace_observer_runtime: nil,
            lock_observer_runtime: nil,
            ax_runtime: nil,
            monitor_runtime: nil
        )
        var lifecycleHost = OmniServiceLifecycleHostVTable(
            userdata: userdata,
            on_state_changed: zigCoreRuntimeLifecycleStateBridge,
            on_error: zigCoreRuntimeLifecycleErrorBridge
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

        if let inputRuntime {
            omni_input_runtime_destroy(inputRuntime)
            self.inputRuntime = nil
        }

        if let wmControllerRuntime {
            omni_wm_controller_destroy(wmControllerRuntime)
            self.wmControllerRuntime = nil
        }

        started = false
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
        guard let inputRuntime else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var required = 0
        let probeRc = withUnsafeMutablePointer(to: &required) { writtenPtr in
            omni_input_runtime_query_registration_failures(inputRuntime, nil, 0, writtenPtr)
        }
        guard probeRc == Int32(OMNI_OK), required > 0 else {
            registrationFailures.removeAll(keepingCapacity: false)
            return
        }

        var failures = Array(repeating: OmniInputRegistrationFailure(), count: required)
        var written = 0
        let queryRc = failures.withUnsafeMutableBufferPointer { buffer in
            withUnsafeMutablePointer(to: &written) { writtenPtr in
                omni_input_runtime_query_registration_failures(
                    inputRuntime,
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

    private func submitSecureInputChangedEvent(_ isSecure: Bool) -> Int32 {
        guard let wmControllerRuntime else { return Int32(OMNI_ERR_INVALID_ARGS) }

        var event = OmniControllerEvent(
            kind: Self.rawEnumValue(OMNI_CONTROLLER_EVENT_SECURE_INPUT_CHANGED),
            enabled: isSecure ? 1 : 0,
            refresh_reason: 0,
            has_display_id: 0,
            display_id: 0,
            pid: 0,
            has_window_handle_id: 0,
            window_handle_id: OmniUuid128(),
            has_workspace_id: 0,
            workspace_id: OmniUuid128()
        )

        return withUnsafePointer(to: &event) { eventPtr in
            omni_wm_controller_submit_os_event(wmControllerRuntime, eventPtr)
        }
    }

    private func dispatchUIActions(_ uiActionKinds: [UInt8]) {
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

    nonisolated private static func releaseUnconsumedMouseEffects(_ effectExport: OmniInputEffectExport) {
        guard let effects = effectExport.effects,
              effectExport.effect_count > 0
        else {
            return
        }

        for effect in UnsafeBufferPointer(start: effects, count: effectExport.effect_count) {
            let consumed = false
            if !consumed, let eventRef = effect.event.event_ref {
                Unmanaged<CGEvent>.fromOpaque(eventRef).release()
            }
        }
    }

    private func dispatchControllerError(code: Int32, message: String) {
        controller?.handleZigCoreRuntimeError(code: code, message: message)
    }

    private static func rawBindingId(from string: String) -> OmniInputBindingId {
        var result = OmniInputBindingId()
        let utf8 = Array(string.utf8.prefix(Int(OMNI_INPUT_BINDING_ID_CAP)))
        result.length = UInt8(utf8.count)
        withUnsafeMutableBytes(of: &result.bytes) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: utf8)
        }
        return result
    }

    private static func string(from rawBindingId: OmniInputBindingId) -> String {
        let length = min(Int(rawBindingId.length), Int(OMNI_INPUT_BINDING_ID_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: rawBindingId.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func string(from rawName: OmniControllerName) -> String {
        let length = min(Int(rawName.length), Int(OMNI_CONTROLLER_NAME_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: rawName.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
        UInt8(clamping: Int(value.rawValue))
    }
}

private extension WMController {
    func handleZigCoreRuntimeError(code: Int32, message: String) {
        NSLog("Zig core runtime error code=%d message=%@", code, message)
    }
}
