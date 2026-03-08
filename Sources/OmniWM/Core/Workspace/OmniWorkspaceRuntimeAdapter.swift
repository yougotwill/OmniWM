import AppKit
import CZigLayout
import Foundation

final class OmniWorkspaceRuntimeAdapter {
    private struct SafeStateCounts {
        let monitorCount: Int
        let workspaceCount: Int
        let windowCount: Int
    }

    struct StateExport {
        struct MonitorRecord {
            let displayId: UInt32
            let isMain: Bool
            let frame: CGRect
            let visibleFrame: CGRect
            let name: String
            let activeWorkspaceId: WorkspaceDescriptor.ID?
            let previousWorkspaceId: WorkspaceDescriptor.ID?
        }

        struct WorkspaceRecord {
            let workspaceId: WorkspaceDescriptor.ID
            let name: String
            let assignedMonitorAnchor: CGPoint?
            let assignedDisplayId: UInt32?
            let isVisible: Bool
            let isPreviousVisible: Bool
            let isPersistent: Bool
        }

        struct WindowRecord {
            let handleId: UUID
            let pid: pid_t
            let windowId: Int
            let workspaceId: WorkspaceDescriptor.ID
            let hiddenState: WindowModel.HiddenState?
            let layoutReason: LayoutReason
        }

        let monitors: [MonitorRecord]
        let workspaces: [WorkspaceRecord]
        let windows: [WindowRecord]
        let activeMonitorDisplayId: UInt32?
        let previousMonitorDisplayId: UInt32?
    }

    private let runtime: OpaquePointer
    private let ownsRuntime: Bool

    var rawRuntimeHandle: OpaquePointer {
        runtime
    }

    init?() {
        var config = OmniWorkspaceRuntimeConfig(
            abi_version: UInt32(OMNI_WORKSPACE_RUNTIME_ABI_VERSION),
            reserved: 0
        )
        guard let runtime = withUnsafePointer(to: &config, { configPtr in
            omni_workspace_runtime_create(configPtr)
        }) else {
            return nil
        }
        guard omni_workspace_runtime_start(runtime) == Int32(OMNI_OK) else {
            omni_workspace_runtime_destroy(runtime)
            return nil
        }
        self.runtime = runtime
        ownsRuntime = true
    }

    init(existingRuntimeHandle runtime: OpaquePointer, ownsRuntime: Bool = false) {
        self.runtime = runtime
        self.ownsRuntime = ownsRuntime
    }

    deinit {
        guard ownsRuntime else { return }
        _ = omni_workspace_runtime_stop(runtime)
        omni_workspace_runtime_destroy(runtime)
    }

    func importMonitors(_ monitors: [Monitor]) -> Bool {
        let snapshots = monitors.map { monitor in
            OmniWorkspaceRuntimeMonitorSnapshot(
                display_id: monitor.displayId,
                is_main: monitor.isMain ? 1 : 0,
                frame_x: monitor.frame.origin.x,
                frame_y: monitor.frame.origin.y,
                frame_width: monitor.frame.width,
                frame_height: monitor.frame.height,
                visible_x: monitor.visibleFrame.origin.x,
                visible_y: monitor.visibleFrame.origin.y,
                visible_width: monitor.visibleFrame.width,
                visible_height: monitor.visibleFrame.height,
                name: Self.rawName(from: monitor.name)
            )
        }

        let rc = snapshots.withUnsafeBufferPointer { buffer in
            omni_workspace_runtime_import_monitors(runtime, buffer.baseAddress, buffer.count)
        }
        return rc == Int32(OMNI_OK)
    }

    @MainActor
    func importSettings(_ settings: SettingsStore, monitors: [Monitor]) -> Bool {
        let persistentNames = settings.persistentWorkspaceNames().map(Self.rawName(from:))
        let sortedMonitors = Monitor.sortedByPosition(monitors)

        var assignments: [OmniWorkspaceRuntimeMonitorAssignment] = []
        for (workspaceName, descriptions) in settings.workspaceToMonitorAssignments(sortedMonitors: sortedMonitors) {
            for description in descriptions {
                assignments.append(rawAssignment(workspaceName: workspaceName, description: description))
            }
        }

        var payload = OmniWorkspaceRuntimeSettingsImport(
            persistent_names: nil,
            persistent_name_count: persistentNames.count,
            monitor_assignments: nil,
            monitor_assignment_count: assignments.count
        )

        let rc = persistentNames.withUnsafeBufferPointer { namesBuffer in
            assignments.withUnsafeBufferPointer { assignmentsBuffer in
                payload.persistent_names = namesBuffer.baseAddress
                payload.monitor_assignments = assignmentsBuffer.baseAddress
                return withUnsafePointer(to: &payload) { payloadPtr in
                    omni_workspace_runtime_import_settings(runtime, payloadPtr)
                }
            }
        }
        return rc == Int32(OMNI_OK)
    }

    func exportState() -> StateExport? {
        guard var counts = queryStateCounts() else { return nil }

        for _ in 0 ..< 3 {
            var rawExport = OmniWorkspaceRuntimeStateExport()
            var monitorBuffer = Array(repeating: OmniWorkspaceRuntimeMonitorRecord(), count: counts.monitorCount)
            var workspaceBuffer = Array(repeating: OmniWorkspaceRuntimeWorkspaceRecord(), count: counts.workspaceCount)
            var windowBuffer = Array(repeating: OmniWorkspaceRuntimeWindowRecord(), count: counts.windowCount)

            let rc = monitorBuffer.withUnsafeMutableBufferPointer { monitorsPtr in
                workspaceBuffer.withUnsafeMutableBufferPointer { workspacesPtr in
                    windowBuffer.withUnsafeMutableBufferPointer { windowsPtr in
                        withUnsafeMutablePointer(to: &rawExport) { exportPtr in
                            omni_workspace_runtime_copy_state(
                                runtime,
                                exportPtr,
                                monitorsPtr.baseAddress,
                                monitorsPtr.count,
                                workspacesPtr.baseAddress,
                                workspacesPtr.count,
                                windowsPtr.baseAddress,
                                windowsPtr.count
                            )
                        }
                    }
                }
            }

            if rc == Int32(OMNI_OK) {
                return Self.stateExport(
                    from: rawExport,
                    monitorBuffer: monitorBuffer,
                    workspaceBuffer: workspaceBuffer,
                    windowBuffer: windowBuffer
                )
            }

            guard rc == Int32(OMNI_ERR_OUT_OF_RANGE),
                  let nextCounts = Self.validatedCounts(
                      monitorCount: rawExport.monitor_count,
                      workspaceCount: rawExport.workspace_count,
                      windowCount: rawExport.window_count
                  )
            else {
                return nil
            }
            counts = nextCounts
        }

        return nil
    }

    static func stateExport(
        from rawExport: OmniWorkspaceRuntimeStateExport,
        monitorBuffer: [OmniWorkspaceRuntimeMonitorRecord],
        workspaceBuffer: [OmniWorkspaceRuntimeWorkspaceRecord],
        windowBuffer: [OmniWorkspaceRuntimeWindowRecord]
    ) -> StateExport? {
        guard rawExport.monitor_count <= monitorBuffer.count,
              rawExport.workspace_count <= workspaceBuffer.count,
              rawExport.window_count <= windowBuffer.count
        else {
            return nil
        }

        let monitorRecords = monitorBuffer.prefix(rawExport.monitor_count).map(monitorRecord(from:))
        let workspaceRecords = workspaceBuffer.prefix(rawExport.workspace_count).map(workspaceRecord(from:))
        let windowRecords = windowBuffer.prefix(rawExport.window_count).map(windowRecord(from:))

        return StateExport(
            monitors: monitorRecords,
            workspaces: workspaceRecords,
            windows: windowRecords,
            activeMonitorDisplayId: rawExport.has_active_monitor_display_id == 0
                ? nil
                : rawExport.active_monitor_display_id,
            previousMonitorDisplayId: rawExport.has_previous_monitor_display_id == 0
                ? nil
                : rawExport.previous_monitor_display_id
        )
    }

    func workspaceId(forName name: String, createIfMissing: Bool) -> WorkspaceDescriptor.ID? {
        let rawName = Self.rawName(from: name)
        var hasId: UInt8 = 0
        var rawId = OmniUuid128()

        let rc = withUnsafePointer(to: rawName) { namePtr in
            withUnsafeMutablePointer(to: &hasId) { hasPtr in
                withUnsafeMutablePointer(to: &rawId) { idPtr in
                    omni_workspace_runtime_workspace_id_by_name_ptr(
                        runtime,
                        namePtr,
                        createIfMissing ? 1 : 0,
                        hasPtr,
                        idPtr
                    )
                }
            }
        }

        guard rc == Int32(OMNI_OK), hasId != 0 else { return nil }
        return Self.uuid(from: rawId)
    }

    func setActiveWorkspace(_ workspaceId: WorkspaceDescriptor.ID, monitorDisplayId: UInt32) -> Bool {
        omni_workspace_runtime_set_active_workspace(
            runtime,
            Self.rawUUID(from: workspaceId),
            monitorDisplayId
        ) == Int32(OMNI_OK)
    }

    func switchWorkspace(named name: String) -> WorkspaceDescriptor.ID? {
        let rawName = Self.rawName(from: name)
        var hasId: UInt8 = 0
        var rawId = OmniUuid128()
        let rc = withUnsafePointer(to: rawName) { namePtr in
            withUnsafeMutablePointer(to: &hasId) { hasPtr in
                withUnsafeMutablePointer(to: &rawId) { idPtr in
                    omni_workspace_runtime_switch_workspace_by_name_ptr(
                        runtime,
                        namePtr,
                        hasPtr,
                        idPtr
                    )
                }
            }
        }
        guard rc == Int32(OMNI_OK), hasId != 0 else { return nil }
        return Self.uuid(from: rawId)
    }

    func focusWorkspaceAnywhereById(_ workspaceId: WorkspaceDescriptor.ID) -> WorkspaceDescriptor.ID? {
        var hasId: UInt8 = 0
        var rawId = OmniUuid128()
        let rc = withUnsafeMutablePointer(to: &hasId) { hasPtr in
            withUnsafeMutablePointer(to: &rawId) { idPtr in
                omni_workspace_runtime_focus_workspace_anywhere(
                    runtime,
                    Self.rawUUID(from: workspaceId),
                    hasPtr,
                    idPtr
                )
            }
        }
        guard rc == Int32(OMNI_OK), hasId != 0 else { return nil }
        return Self.uuid(from: rawId)
    }

    func summonWorkspace(named name: String, to monitorDisplayId: UInt32) -> WorkspaceDescriptor.ID? {
        let rawName = Self.rawName(from: name)
        var hasId: UInt8 = 0
        var rawId = OmniUuid128()
        let rc = withUnsafePointer(to: rawName) { namePtr in
            withUnsafeMutablePointer(to: &hasId) { hasPtr in
                withUnsafeMutablePointer(to: &rawId) { idPtr in
                    omni_workspace_runtime_summon_workspace_by_name_ptr(
                        runtime,
                        namePtr,
                        monitorDisplayId,
                        hasPtr,
                        idPtr
                    )
                }
            }
        }
        guard rc == Int32(OMNI_OK), hasId != 0 else { return nil }
        return Self.uuid(from: rawId)
    }

    func moveWorkspaceToMonitor(_ workspaceId: WorkspaceDescriptor.ID, targetDisplayId: UInt32) -> Bool {
        omni_workspace_runtime_move_workspace_to_monitor(
            runtime,
            Self.rawUUID(from: workspaceId),
            targetDisplayId
        ) == Int32(OMNI_OK)
    }

    func swapWorkspaces(
        _ workspace1Id: WorkspaceDescriptor.ID,
        on monitor1DisplayId: UInt32,
        with workspace2Id: WorkspaceDescriptor.ID,
        on monitor2DisplayId: UInt32
    ) -> Bool {
        omni_workspace_runtime_swap_workspaces(
            runtime,
            Self.rawUUID(from: workspace1Id),
            monitor1DisplayId,
            Self.rawUUID(from: workspace2Id),
            monitor2DisplayId
        ) == Int32(OMNI_OK)
    }

    func adjacentMonitor(from displayId: UInt32, direction: Direction, wrapAround: Bool) -> UInt32? {
        var hasMonitor: UInt8 = 0
        var monitor = OmniWorkspaceRuntimeMonitorRecord()
        let rc = withUnsafeMutablePointer(to: &hasMonitor) { hasPtr in
            withUnsafeMutablePointer(to: &monitor) { monitorPtr in
                omni_workspace_runtime_adjacent_monitor(
                    runtime,
                    displayId,
                    Self.rawDirection(direction),
                    wrapAround ? 1 : 0,
                    hasPtr,
                    monitorPtr
                )
            }
        }
        guard rc == Int32(OMNI_OK), hasMonitor != 0 else { return nil }
        return monitor.display_id
    }

    func windowUpsert(
        pid: pid_t,
        windowId: Int,
        workspaceId: WorkspaceDescriptor.ID,
        preferredHandleId: UUID?
    ) -> UUID? {
        var request = OmniWorkspaceRuntimeWindowUpsert(
            pid: Int32(pid),
            window_id: Int64(windowId),
            workspace_id: Self.rawUUID(from: workspaceId),
            has_handle_id: preferredHandleId == nil ? 0 : 1,
            handle_id: preferredHandleId.map(Self.rawUUID(from:)) ?? OmniUuid128()
        )
        var outHandle = OmniUuid128()
        let rc = withUnsafePointer(to: &request) { requestPtr in
            withUnsafeMutablePointer(to: &outHandle) { handlePtr in
                omni_workspace_runtime_window_upsert(runtime, requestPtr, handlePtr)
            }
        }
        guard rc == Int32(OMNI_OK) else { return nil }
        return Self.uuid(from: outHandle)
    }

    func windowRemove(key: WindowModel.WindowKey) {
        let rawKey = OmniWorkspaceRuntimeWindowKey(
            pid: Int32(key.pid),
            window_id: Int64(key.windowId)
        )
        _ = omni_workspace_runtime_window_remove(runtime, rawKey)
    }

    func windowSetWorkspace(handleId: UUID, workspaceId: WorkspaceDescriptor.ID) -> Bool {
        omni_workspace_runtime_window_set_workspace(
            runtime,
            Self.rawUUID(from: handleId),
            Self.rawUUID(from: workspaceId)
        ) == Int32(OMNI_OK)
    }

    func windowSetHiddenState(handleId: UUID, state: WindowModel.HiddenState?) -> Bool {
        var rawState = OmniWorkspaceRuntimeWindowHiddenState(
            proportional_x: 0,
            proportional_y: 0,
            has_reference_display_id: 0,
            reference_display_id: 0,
            workspace_inactive: 0
        )
        let hasState: UInt8
        if let state {
            hasState = 1
            rawState.proportional_x = state.proportionalPosition.x
            rawState.proportional_y = state.proportionalPosition.y
            rawState.has_reference_display_id = state.referenceMonitorId == nil ? 0 : 1
            rawState.reference_display_id = state.referenceMonitorId?.displayId ?? 0
            rawState.workspace_inactive = state.workspaceInactive ? 1 : 0
        } else {
            hasState = 0
        }

        return omni_workspace_runtime_window_set_hidden_state(
            runtime,
            Self.rawUUID(from: handleId),
            hasState,
            rawState
        ) == Int32(OMNI_OK)
    }

    func windowSetLayoutReason(handleId: UUID, reason: LayoutReason) -> Bool {
        omni_workspace_runtime_window_set_layout_reason(
            runtime,
            Self.rawUUID(from: handleId),
            Self.rawLayoutReason(reason)
        ) == Int32(OMNI_OK)
    }

    func windowRemoveMissing(keys: Set<WindowModel.WindowKey>, requiredConsecutiveMisses: Int) {
        let rawKeys = keys.map { key in
            OmniWorkspaceRuntimeWindowKey(
                pid: Int32(key.pid),
                window_id: Int64(key.windowId)
            )
        }

        _ = rawKeys.withUnsafeBufferPointer { keyBuffer in
            omni_workspace_runtime_window_remove_missing(
                runtime,
                keyBuffer.baseAddress,
                keyBuffer.count,
                UInt32(max(1, requiredConsecutiveMisses))
            )
        }
    }

    private func rawAssignment(
        workspaceName: String,
        description: MonitorDescription
    ) -> OmniWorkspaceRuntimeMonitorAssignment {
        switch description {
        case let .sequenceNumber(number):
            return OmniWorkspaceRuntimeMonitorAssignment(
                workspace_name: Self.rawName(from: workspaceName),
                assignment_kind: Self.rawEnumValue(OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SEQUENCE_NUMBER),
                sequence_number: Int32(number),
                monitor_pattern: Self.rawName(from: "")
            )
        case .main:
            return OmniWorkspaceRuntimeMonitorAssignment(
                workspace_name: Self.rawName(from: workspaceName),
                assignment_kind: Self.rawEnumValue(OMNI_WORKSPACE_MONITOR_ASSIGNMENT_MAIN),
                sequence_number: 0,
                monitor_pattern: Self.rawName(from: "")
            )
        case .secondary:
            return OmniWorkspaceRuntimeMonitorAssignment(
                workspace_name: Self.rawName(from: workspaceName),
                assignment_kind: Self.rawEnumValue(OMNI_WORKSPACE_MONITOR_ASSIGNMENT_SECONDARY),
                sequence_number: 0,
                monitor_pattern: Self.rawName(from: "")
            )
        case let .pattern(pattern):
            return OmniWorkspaceRuntimeMonitorAssignment(
                workspace_name: Self.rawName(from: workspaceName),
                assignment_kind: Self.rawEnumValue(OMNI_WORKSPACE_MONITOR_ASSIGNMENT_NAME_PATTERN),
                sequence_number: 0,
                monitor_pattern: Self.rawName(from: pattern)
            )
        }
    }

    private static func rawDirection(_ direction: Direction) -> UInt8 {
        switch direction {
        case .left:
            return rawEnumValue(OMNI_NIRI_DIRECTION_LEFT)
        case .right:
            return rawEnumValue(OMNI_NIRI_DIRECTION_RIGHT)
        case .up:
            return rawEnumValue(OMNI_NIRI_DIRECTION_UP)
        case .down:
            return rawEnumValue(OMNI_NIRI_DIRECTION_DOWN)
        }
    }

    private static func layoutReason(from raw: UInt8) -> LayoutReason {
        if raw == rawEnumValue(OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP) {
            return .macosHiddenApp
        }
        return .standard
    }

    private static func rawLayoutReason(_ reason: LayoutReason) -> UInt8 {
        switch reason {
        case .standard:
            return rawEnumValue(OMNI_WORKSPACE_LAYOUT_REASON_STANDARD)
        case .macosHiddenApp:
            return rawEnumValue(OMNI_WORKSPACE_LAYOUT_REASON_MACOS_HIDDEN_APP)
        }
    }

    private static func rawName(from string: String) -> OmniWorkspaceRuntimeName {
        var result = OmniWorkspaceRuntimeName()
        let utf8 = Array(string.utf8.prefix(Int(OMNI_WORKSPACE_RUNTIME_NAME_CAP)))
        result.length = UInt8(utf8.count)
        withUnsafeMutableBytes(of: &result.bytes) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: utf8)
        }
        return result
    }

    private static func string(from rawName: OmniWorkspaceRuntimeName) -> String {
        let bytes: [UInt8] = withUnsafeBytes(of: rawName.bytes) { rawBuffer in
            let prefix = rawBuffer.prefix(Int(rawName.length))
            let trimmed = prefix.prefix { $0 != 0 }
            return Array(trimmed)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func rawUUID(from uuid: UUID) -> OmniUuid128 {
        ZigNiriStateKernel.omniUUID(from: uuid)
    }

    private static func uuid(from raw: OmniUuid128) -> UUID {
        ZigNiriStateKernel.uuid(from: raw)
    }

    private func queryStateCounts() -> SafeStateCounts? {
        var rawCounts = OmniWorkspaceRuntimeStateCounts()
        let rc = withUnsafeMutablePointer(to: &rawCounts) { countsPtr in
            omni_workspace_runtime_query_state_counts(runtime, countsPtr)
        }
        guard rc == Int32(OMNI_OK) else { return nil }
        return Self.validatedCounts(
            monitorCount: rawCounts.monitor_count,
            workspaceCount: rawCounts.workspace_count,
            windowCount: rawCounts.window_count
        )
    }

    private static func validatedCounts(
        monitorCount: Int,
        workspaceCount: Int,
        windowCount: Int
    ) -> SafeStateCounts? {
        guard validatedCount(monitorCount, for: OmniWorkspaceRuntimeMonitorRecord.self),
              validatedCount(workspaceCount, for: OmniWorkspaceRuntimeWorkspaceRecord.self),
              validatedCount(windowCount, for: OmniWorkspaceRuntimeWindowRecord.self)
        else {
            return nil
        }
        return SafeStateCounts(
            monitorCount: monitorCount,
            workspaceCount: workspaceCount,
            windowCount: windowCount
        )
    }

    private static func validatedCount<T>(_ count: Int, for _: T.Type) -> Bool {
        count >= 0 && count <= (Int.max / max(MemoryLayout<T>.stride, 1))
    }

    private static func monitorRecord(from raw: OmniWorkspaceRuntimeMonitorRecord) -> StateExport.MonitorRecord {
        StateExport.MonitorRecord(
            displayId: raw.display_id,
            isMain: raw.is_main != 0,
            frame: CGRect(x: raw.frame_x, y: raw.frame_y, width: raw.frame_width, height: raw.frame_height),
            visibleFrame: CGRect(
                x: raw.visible_x,
                y: raw.visible_y,
                width: raw.visible_width,
                height: raw.visible_height
            ),
            name: string(from: raw.name),
            activeWorkspaceId: raw.has_active_workspace_id == 0 ? nil : uuid(from: raw.active_workspace_id),
            previousWorkspaceId: raw.has_previous_workspace_id == 0 ? nil : uuid(from: raw.previous_workspace_id)
        )
    }

    private static func workspaceRecord(from raw: OmniWorkspaceRuntimeWorkspaceRecord) -> StateExport.WorkspaceRecord {
        StateExport.WorkspaceRecord(
            workspaceId: uuid(from: raw.workspace_id),
            name: string(from: raw.name),
            assignedMonitorAnchor: raw.has_assigned_monitor_anchor == 0
                ? nil
                : CGPoint(x: raw.assigned_monitor_anchor_x, y: raw.assigned_monitor_anchor_y),
            assignedDisplayId: raw.has_assigned_display_id == 0 ? nil : raw.assigned_display_id,
            isVisible: raw.is_visible != 0,
            isPreviousVisible: raw.is_previous_visible != 0,
            isPersistent: raw.is_persistent != 0
        )
    }

    private static func windowRecord(from raw: OmniWorkspaceRuntimeWindowRecord) -> StateExport.WindowRecord {
        let hiddenState: WindowModel.HiddenState? = if raw.has_hidden_state != 0 {
            WindowModel.HiddenState(
                proportionalPosition: CGPoint(
                    x: raw.hidden_state.proportional_x,
                    y: raw.hidden_state.proportional_y
                ),
                referenceMonitorId: raw.hidden_state.has_reference_display_id != 0
                    ? Monitor.ID(displayId: raw.hidden_state.reference_display_id)
                    : nil,
                workspaceInactive: raw.hidden_state.workspace_inactive != 0
            )
        } else {
            nil
        }

        return StateExport.WindowRecord(
            handleId: uuid(from: raw.handle_id),
            pid: pid_t(raw.pid),
            windowId: Int(raw.window_id),
            workspaceId: uuid(from: raw.workspace_id),
            hiddenState: hiddenState,
            layoutReason: layoutReason(from: raw.layout_reason)
        )
    }

    private static func rawEnumValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
        UInt8(clamping: Int(value.rawValue))
    }
}
