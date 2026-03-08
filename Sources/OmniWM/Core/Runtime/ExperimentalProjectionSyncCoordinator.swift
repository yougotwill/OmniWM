import CoreGraphics
import CZigLayout
import Foundation

@MainActor
struct WMControllerControllerSnapshot {
    struct MonitorRecord {
        let displayId: UInt32
        let isMain: Bool
        let frame: CGRect
        let visibleFrame: CGRect
        let name: String
    }

    struct WorkspaceRecord {
        let workspaceId: WorkspaceDescriptor.ID
        let assignedDisplayId: UInt32?
        let isVisible: Bool
        let isPreviousVisible: Bool
        let layoutKind: UInt8
        let name: String
        let selectedNodeId: UUID?
        let lastFocusedWindowId: UUID?
    }

    struct WindowRecord {
        let handleId: UUID
        let pid: pid_t
        let windowId: Int
        let workspaceId: WorkspaceDescriptor.ID
        let layoutKind: UInt8
        let isHidden: Bool
        let isFocused: Bool
        let isManaged: Bool
        let nodeId: UUID?
        let columnId: UUID?
        let orderIndex: Int
        let columnIndex: Int
        let rowIndex: Int

        var handle: WindowHandle {
            WindowHandle(id: handleId, pid: pid)
        }
    }

    let monitors: [MonitorRecord]
    let workspaces: [WorkspaceRecord]
    let windows: [WindowRecord]
    let focusedWindowId: UUID?
    let activeMonitorDisplayId: UInt32?
    let previousMonitorDisplayId: UInt32?
    let secureInputActive: Bool
    let lockScreenActive: Bool
    let nonManagedFocusActive: Bool
    let appFullscreenActive: Bool
    let focusFollowsWindowToMonitor: Bool
    let moveMouseToFocusedWindow: Bool
    let layoutLightSessionActive: Bool
    let layoutImmediateInProgress: Bool
    let layoutIncrementalInProgress: Bool
    let layoutFullEnumerationInProgress: Bool
    let layoutAnimationActive: Bool
    let layoutHasCompletedInitialRefresh: Bool

    func window(handleId: UUID) -> WindowRecord? {
        windows.first(where: { $0.handleId == handleId })
    }

    func focusedWindowRecord() -> WindowRecord? {
        guard let focusedWindowId else { return nil }
        return window(handleId: focusedWindowId)
    }

    func orderedWindows(in workspaceId: WorkspaceDescriptor.ID) -> [WindowRecord] {
        windows
            .filter { $0.workspaceId == workspaceId && $0.isManaged && !$0.isHidden }
            .sorted(by: Self.compareWindows)
    }

    private static func compareWindows(_ lhs: WindowRecord, _ rhs: WindowRecord) -> Bool {
        let lhsKey = sortKey(for: lhs)
        let rhsKey = sortKey(for: rhs)
        if lhsKey.group != rhsKey.group { return lhsKey.group < rhsKey.group }
        if lhsKey.primary != rhsKey.primary { return lhsKey.primary < rhsKey.primary }
        if lhsKey.secondary != rhsKey.secondary { return lhsKey.secondary < rhsKey.secondary }
        if lhsKey.tertiary != rhsKey.tertiary { return lhsKey.tertiary < rhsKey.tertiary }
        return lhs.handleId.uuidString < rhs.handleId.uuidString
    }

    private static func sortKey(for window: WindowRecord) -> (group: Int, primary: Int, secondary: Int, tertiary: Int) {
        if window.columnId != nil || window.columnIndex >= 0 {
            return (
                0,
                normalizedIndex(window.columnIndex),
                normalizedIndex(window.rowIndex),
                normalizedIndex(window.orderIndex)
            )
        }
        return (
            1,
            normalizedIndex(window.orderIndex),
            normalizedIndex(window.rowIndex),
            normalizedIndex(window.columnIndex)
        )
    }

    private static func normalizedIndex(_ raw: Int) -> Int {
        raw >= 0 ? raw : Int.max
    }
}

@MainActor
struct WMControllerSnapshotExport {
    let stateExport: OmniWorkspaceRuntimeAdapter.StateExport
    let controllerSnapshot: WMControllerControllerSnapshot
    let uiState: OmniControllerUiState
    let changedWorkspaceIds: Set<WorkspaceDescriptor.ID>?
}

@MainActor
enum WMControllerSnapshotAdapter {
    static func flushAndCapture(runtime: OpaquePointer) -> WMControllerSnapshotExport? {
        guard omni_wm_controller_flush(runtime) == Int32(OMNI_OK) else {
            return nil
        }
        guard let snapshot = omni_wm_controller_snapshot_create(runtime) else {
            return nil
        }
        defer { omni_wm_controller_snapshot_destroy(snapshot) }
        return capture(snapshot: snapshot)
    }

    private static func capture(snapshot: OpaquePointer) -> WMControllerSnapshotExport? {
        var counts = OmniWMControllerSnapshotCounts()
        let countsRc = withUnsafeMutablePointer(to: &counts) { countsPtr in
            omni_wm_controller_snapshot_query_counts(snapshot, countsPtr)
        }
        guard countsRc == Int32(OMNI_OK) else { return nil }

        var uiState = OmniControllerUiState()
        let uiRc = withUnsafeMutablePointer(to: &uiState) { statePtr in
            omni_wm_controller_snapshot_query_ui_state(snapshot, statePtr)
        }
        guard uiRc == Int32(OMNI_OK) else { return nil }

        guard let stateExport = captureWorkspaceRuntimeState(snapshot: snapshot, counts: counts),
              let controllerSnapshot = captureControllerSnapshot(snapshot: snapshot, counts: counts)
        else {
            return nil
        }

        let changedWorkspaceIds: Set<WorkspaceDescriptor.ID>?
        if counts.invalidate_all_workspace_projections != 0 {
            changedWorkspaceIds = nil
        } else {
            var changedIdBuffer = Array(repeating: OmniUuid128(), count: counts.changed_workspace_count)
            var written = 0
            let changedRc = changedIdBuffer.withUnsafeMutableBufferPointer { idsPtr in
                withUnsafeMutablePointer(to: &written) { writtenPtr in
                    omni_wm_controller_snapshot_copy_changed_workspaces(
                        snapshot,
                        idsPtr.baseAddress,
                        idsPtr.count,
                        writtenPtr
                    )
                }
            }
            guard changedRc == Int32(OMNI_OK), written <= changedIdBuffer.count else {
                return nil
            }
            changedWorkspaceIds = Set(changedIdBuffer.prefix(written).map(ZigNiriStateKernel.uuid(from:)))
        }

        return WMControllerSnapshotExport(
            stateExport: stateExport,
            controllerSnapshot: controllerSnapshot,
            uiState: uiState,
            changedWorkspaceIds: changedWorkspaceIds
        )
    }

    private static func captureWorkspaceRuntimeState(
        snapshot: OpaquePointer,
        counts: OmniWMControllerSnapshotCounts
    ) -> OmniWorkspaceRuntimeAdapter.StateExport? {
        var rawExport = OmniWorkspaceRuntimeStateExport()
        var monitorBuffer = Array(repeating: OmniWorkspaceRuntimeMonitorRecord(), count: counts.monitor_count)
        var workspaceBuffer = Array(repeating: OmniWorkspaceRuntimeWorkspaceRecord(), count: counts.workspace_count)
        var windowBuffer = Array(repeating: OmniWorkspaceRuntimeWindowRecord(), count: counts.window_count)

        let stateRc = monitorBuffer.withUnsafeMutableBufferPointer { monitorsPtr in
            workspaceBuffer.withUnsafeMutableBufferPointer { workspacesPtr in
                windowBuffer.withUnsafeMutableBufferPointer { windowsPtr in
                    withUnsafeMutablePointer(to: &rawExport) { exportPtr in
                        omni_wm_controller_snapshot_copy_workspace_state(
                            snapshot,
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

        guard stateRc == Int32(OMNI_OK) else { return nil }
        return OmniWorkspaceRuntimeAdapter.stateExport(
            from: rawExport,
            monitorBuffer: monitorBuffer,
            workspaceBuffer: workspaceBuffer,
            windowBuffer: windowBuffer
        )
    }

    private static func captureControllerSnapshot(
        snapshot: OpaquePointer,
        counts: OmniWMControllerSnapshotCounts
    ) -> WMControllerControllerSnapshot? {
        var rawSnapshot = OmniControllerSnapshot()
        var monitorBuffer = Array(repeating: OmniControllerMonitorSnapshot(), count: counts.monitor_count)
        var workspaceBuffer = Array(repeating: OmniControllerWorkspaceSnapshot(), count: counts.workspace_count)
        var windowBuffer = Array(repeating: OmniControllerWindowSnapshot(), count: counts.window_count)

        let rc = monitorBuffer.withUnsafeMutableBufferPointer { monitorsPtr in
            workspaceBuffer.withUnsafeMutableBufferPointer { workspacesPtr in
                windowBuffer.withUnsafeMutableBufferPointer { windowsPtr in
                    withUnsafeMutablePointer(to: &rawSnapshot) { snapshotPtr in
                        omni_wm_controller_snapshot_copy_controller_state(
                            snapshot,
                            snapshotPtr,
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

        guard rc == Int32(OMNI_OK),
              rawSnapshot.monitor_count <= monitorBuffer.count,
              rawSnapshot.workspace_count <= workspaceBuffer.count,
              rawSnapshot.window_count <= windowBuffer.count
        else {
            return nil
        }

        return WMControllerControllerSnapshot(
            monitors: monitorBuffer.prefix(rawSnapshot.monitor_count).map(monitorRecord(from:)),
            workspaces: workspaceBuffer.prefix(rawSnapshot.workspace_count).map(workspaceRecord(from:)),
            windows: windowBuffer.prefix(rawSnapshot.window_count).map(windowRecord(from:)),
            focusedWindowId: rawSnapshot.has_focused_window_id == 0
                ? nil
                : ZigNiriStateKernel.uuid(from: rawSnapshot.focused_window_id),
            activeMonitorDisplayId: rawSnapshot.has_active_monitor_display_id == 0
                ? nil
                : rawSnapshot.active_monitor_display_id,
            previousMonitorDisplayId: rawSnapshot.has_previous_monitor_display_id == 0
                ? nil
                : rawSnapshot.previous_monitor_display_id,
            secureInputActive: rawSnapshot.secure_input_active != 0,
            lockScreenActive: rawSnapshot.lock_screen_active != 0,
            nonManagedFocusActive: rawSnapshot.non_managed_focus_active != 0,
            appFullscreenActive: rawSnapshot.app_fullscreen_active != 0,
            focusFollowsWindowToMonitor: rawSnapshot.focus_follows_window_to_monitor != 0,
            moveMouseToFocusedWindow: rawSnapshot.move_mouse_to_focused_window != 0,
            layoutLightSessionActive: rawSnapshot.layout_light_session_active != 0,
            layoutImmediateInProgress: rawSnapshot.layout_immediate_in_progress != 0,
            layoutIncrementalInProgress: rawSnapshot.layout_incremental_in_progress != 0,
            layoutFullEnumerationInProgress: rawSnapshot.layout_full_enumeration_in_progress != 0,
            layoutAnimationActive: rawSnapshot.layout_animation_active != 0,
            layoutHasCompletedInitialRefresh: rawSnapshot.layout_has_completed_initial_refresh != 0
        )
    }

    private static func monitorRecord(from raw: OmniControllerMonitorSnapshot) -> WMControllerControllerSnapshot.MonitorRecord {
        WMControllerControllerSnapshot.MonitorRecord(
            displayId: raw.display_id,
            isMain: raw.is_main != 0,
            frame: CGRect(
                x: raw.frame_x,
                y: raw.frame_y,
                width: raw.frame_width,
                height: raw.frame_height
            ),
            visibleFrame: CGRect(
                x: raw.visible_x,
                y: raw.visible_y,
                width: raw.visible_width,
                height: raw.visible_height
            ),
            name: string(from: raw.name)
        )
    }

    private static func workspaceRecord(from raw: OmniControllerWorkspaceSnapshot) -> WMControllerControllerSnapshot.WorkspaceRecord {
        WMControllerControllerSnapshot.WorkspaceRecord(
            workspaceId: ZigNiriStateKernel.uuid(from: raw.workspace_id),
            assignedDisplayId: raw.has_assigned_display_id == 0 ? nil : raw.assigned_display_id,
            isVisible: raw.is_visible != 0,
            isPreviousVisible: raw.is_previous_visible != 0,
            layoutKind: raw.layout_kind,
            name: string(from: raw.name),
            selectedNodeId: raw.has_selected_node_id == 0 ? nil : ZigNiriStateKernel.uuid(from: raw.selected_node_id),
            lastFocusedWindowId: raw.has_last_focused_window_id == 0
                ? nil
                : ZigNiriStateKernel.uuid(from: raw.last_focused_window_id)
        )
    }

    private static func windowRecord(from raw: OmniControllerWindowSnapshot) -> WMControllerControllerSnapshot.WindowRecord {
        WMControllerControllerSnapshot.WindowRecord(
            handleId: ZigNiriStateKernel.uuid(from: raw.handle_id),
            pid: raw.pid,
            windowId: Int(raw.window_id),
            workspaceId: ZigNiriStateKernel.uuid(from: raw.workspace_id),
            layoutKind: raw.layout_kind,
            isHidden: raw.is_hidden != 0,
            isFocused: raw.is_focused != 0,
            isManaged: raw.is_managed != 0,
            nodeId: raw.has_node_id == 0 ? nil : ZigNiriStateKernel.uuid(from: raw.node_id),
            columnId: raw.has_column_id == 0 ? nil : ZigNiriStateKernel.uuid(from: raw.column_id),
            orderIndex: Int(raw.order_index),
            columnIndex: Int(raw.column_index),
            rowIndex: Int(raw.row_index)
        )
    }

    private static func string(from rawName: OmniControllerName) -> String {
        let length = min(Int(rawName.length), Int(OMNI_CONTROLLER_NAME_CAP))
        let bytes: [UInt8] = withUnsafeBytes(of: rawName.bytes) { rawBuffer in
            Array(rawBuffer.prefix(length))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

@MainActor
enum ExperimentalProjectionSyncCoordinator {
    @discardableResult
    static func sync(
        workspaceManager: WorkspaceManager,
        zigNiriEngine: ZigNiriEngine?,
        stateExport: OmniWorkspaceRuntimeAdapter.StateExport,
        changedWorkspaceIds: Set<WorkspaceDescriptor.ID>?,
        onSynchronized: (() -> Void)? = nil
    ) -> Set<WorkspaceDescriptor.ID>? {
        guard workspaceManager.syncRuntimeStateFromCore(stateExport: stateExport) else {
            return nil
        }

        let activeWorkspaceIds = Set(workspaceManager.workspaces.map(\.id))
        zigNiriEngine?.pruneWorkspaceProjections(to: activeWorkspaceIds)

        let refreshWorkspaceIds = changedWorkspaceIds?.intersection(activeWorkspaceIds) ?? activeWorkspaceIds
        for workspaceId in refreshWorkspaceIds {
            zigNiriEngine?.invalidateWorkspaceProjection(workspaceId)
        }

        onSynchronized?()
        return refreshWorkspaceIds
    }
}
