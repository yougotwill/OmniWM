import CZigLayout
import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class WorkspaceBarDataSourceTests: XCTestCase {
    @MainActor
    func testDeduplicatedWindowEntriesFiltersExactDuplicateExports() {
        let workspaceId = UUID()
        let sharedHandle = WindowHandle(id: UUID(), pid: 4242)

        let first = WindowModel.Entry(
            handle: sharedHandle,
            axRef: AXWindowRef(pid: 4242, windowId: 100),
            workspaceId: workspaceId,
            windowId: 100,
            hiddenProportionalPosition: nil
        )
        let duplicate = WindowModel.Entry(
            handle: sharedHandle,
            axRef: AXWindowRef(pid: 4242, windowId: 100),
            workspaceId: workspaceId,
            windowId: 100,
            hiddenProportionalPosition: nil
        )
        let distinctHandle = WindowModel.Entry(
            handle: WindowHandle(id: UUID(), pid: 4242),
            axRef: AXWindowRef(pid: 4242, windowId: 100),
            workspaceId: workspaceId,
            windowId: 100,
            hiddenProportionalPosition: nil
        )

        let deduped = WorkspaceBarDataSource.deduplicatedWindowEntries([first, duplicate, distinctHandle])

        XCTAssertEqual(deduped.count, 2)
        XCTAssertTrue(deduped[0] === first)
        XCTAssertTrue(deduped[1] === distinctHandle)
    }

    @MainActor
    func testWorkspaceBarItemsPreserveRawNameAndStableWorkspaceIdWhenDisplayNameChanges() {
        let suiteName = "WorkspaceBarDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", displayName: "Web")
        ]

        let manager = WorkspaceManager(settings: settings)
        let monitor = Monitor(
            id: .init(displayId: 1001),
            displayId: 1001,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Primary"
        )
        manager.updateMonitors([monitor])

        guard let workspaceId = manager.workspaceId(for: "1", createIfMissing: true) else {
            return XCTFail("Expected workspace 1 to be created")
        }
        XCTAssertTrue(manager.setActiveWorkspace(workspaceId, on: monitor.id))

        let items = WorkspaceBarDataSource.workspaceBarItems(
            for: monitor,
            deduplicate: true,
            hideEmpty: false,
            workspaceManager: manager,
            appInfoCache: AppInfoCache(),
            workspaceStateExport: nil,
            controllerSnapshot: nil,
            focusedHandle: nil,
            settings: settings
        )

        guard let item = items.first(where: { $0.workspaceId == workspaceId }) else {
            return XCTFail("Expected workspace bar item for workspace 1")
        }

        XCTAssertEqual(item.rawName, "1")
        XCTAssertEqual(item.displayName, "Web")
    }

    @MainActor
    func testWorkspaceBarItemsPreferRuntimeExportForRosterFocusAndMembership() {
        let suiteName = "WorkspaceBarDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitor = Monitor(
            id: .init(displayId: 1501),
            displayId: 1501,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Primary"
        )
        manager.updateMonitors([monitor])

        guard let workspace1Id = manager.workspaceId(for: "1", createIfMissing: true),
              let workspace2Id = manager.workspaceId(for: "2", createIfMissing: true) else {
            return XCTFail("Expected workspaces to be created")
        }
        XCTAssertTrue(manager.setActiveWorkspace(workspace1Id, on: monitor.id))
        _ = manager.addWindow(
            AXWindowRef(pid: 111, windowId: 1111),
            pid: 111,
            windowId: 1111,
            to: workspace1Id
        )

        let exportHandle = UUID()
        let stateExport = makeStateExport(
            monitors: [
                .init(
                    displayId: monitor.displayId,
                    isMain: true,
                    frame: monitor.frame,
                    visibleFrame: monitor.visibleFrame,
                    name: monitor.name,
                    activeWorkspaceId: workspace2Id,
                    previousWorkspaceId: workspace1Id
                )
            ],
            workspaces: [
                .init(
                    workspaceId: workspace1Id,
                    name: "1",
                    assignedMonitorAnchor: nil,
                    assignedDisplayId: monitor.displayId,
                    isVisible: false,
                    isPreviousVisible: true,
                    isPersistent: false
                ),
                .init(
                    workspaceId: workspace2Id,
                    name: "2",
                    assignedMonitorAnchor: nil,
                    assignedDisplayId: monitor.displayId,
                    isVisible: true,
                    isPreviousVisible: false,
                    isPersistent: false
                )
            ],
            windows: [
                .init(
                    handleId: exportHandle,
                    pid: 222,
                    windowId: 2222,
                    workspaceId: workspace2Id,
                    hiddenState: nil,
                    layoutReason: .standard
                )
            ],
            activeMonitorDisplayId: monitor.displayId,
            previousMonitorDisplayId: nil
        )

        let items = WorkspaceBarDataSource.workspaceBarItems(
            for: monitor,
            deduplicate: false,
            hideEmpty: true,
            workspaceManager: manager,
            appInfoCache: AppInfoCache(),
            workspaceStateExport: stateExport,
            controllerSnapshot: nil,
            focusedHandle: WindowHandle(id: exportHandle, pid: 222),
            settings: settings
        )

        XCTAssertEqual(items.map(\.rawName), ["2"])
        XCTAssertEqual(items.first?.workspaceId, workspace2Id)
        XCTAssertEqual(items.first?.isFocused, true)
        XCTAssertEqual(items.first?.windows.map(\.windowId), [2222])
        XCTAssertEqual(items.first?.windows.first?.id, exportHandle)
    }

    @MainActor
    func testWorkspaceBarItemsUseControllerSnapshotAsAuthoritativeMembership() {
        let suiteName = "WorkspaceBarDataSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitor = Monitor(
            id: .init(displayId: 2001),
            displayId: 2001,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Primary"
        )
        manager.updateMonitors([monitor])

        guard let workspaceId = manager.workspaceId(for: "1", createIfMissing: true) else {
            return XCTFail("Expected workspace 1 to be created")
        }
        XCTAssertTrue(manager.setActiveWorkspace(workspaceId, on: monitor.id))

        _ = manager.addWindow(AXWindowRef(pid: 101, windowId: 1001), pid: 101, windowId: 1001, to: workspaceId)
        _ = manager.addWindow(AXWindowRef(pid: 202, windowId: 2002), pid: 202, windowId: 2002, to: workspaceId)
        _ = manager.addWindow(AXWindowRef(pid: 303, windowId: 3003), pid: 303, windowId: 3003, to: workspaceId)

        let layoutKind = UInt8(truncatingIfNeeded: OMNI_CONTROLLER_LAYOUT_NIRI.rawValue)
        let focusedHandleId = UUID()
        let secondaryHandleId = UUID()
        let snapshot = WMControllerControllerSnapshot(
            monitors: [],
            workspaces: [
                .init(
                    workspaceId: workspaceId,
                    assignedDisplayId: monitor.displayId,
                    isVisible: true,
                    isPreviousVisible: false,
                    layoutKind: layoutKind,
                    name: "1",
                    selectedNodeId: nil,
                    lastFocusedWindowId: focusedHandleId
                )
            ],
            windows: [
                .init(
                    handleId: focusedHandleId,
                    pid: 101,
                    windowId: 1001,
                    workspaceId: workspaceId,
                    layoutKind: layoutKind,
                    isHidden: false,
                    isFocused: true,
                    isManaged: true,
                    nodeId: nil,
                    columnId: nil,
                    orderIndex: 0,
                    columnIndex: 0,
                    rowIndex: 0
                ),
                .init(
                    handleId: UUID(),
                    pid: 202,
                    windowId: 2002,
                    workspaceId: workspaceId,
                    layoutKind: layoutKind,
                    isHidden: false,
                    isFocused: false,
                    isManaged: false,
                    nodeId: nil,
                    columnId: nil,
                    orderIndex: 1,
                    columnIndex: 1,
                    rowIndex: 0
                ),
                .init(
                    handleId: UUID(),
                    pid: 303,
                    windowId: 3003,
                    workspaceId: workspaceId,
                    layoutKind: layoutKind,
                    isHidden: true,
                    isFocused: false,
                    isManaged: true,
                    nodeId: nil,
                    columnId: nil,
                    orderIndex: 2,
                    columnIndex: 2,
                    rowIndex: 0
                ),
                .init(
                    handleId: secondaryHandleId,
                    pid: 404,
                    windowId: 4004,
                    workspaceId: workspaceId,
                    layoutKind: layoutKind,
                    isHidden: false,
                    isFocused: false,
                    isManaged: true,
                    nodeId: nil,
                    columnId: nil,
                    orderIndex: 3,
                    columnIndex: 3,
                    rowIndex: 0
                )
            ],
            focusedWindowId: focusedHandleId,
            activeMonitorDisplayId: monitor.displayId,
            previousMonitorDisplayId: nil,
            secureInputActive: false,
            lockScreenActive: false,
            nonManagedFocusActive: false,
            appFullscreenActive: false,
            focusFollowsWindowToMonitor: false,
            moveMouseToFocusedWindow: false,
            layoutLightSessionActive: false,
            layoutImmediateInProgress: false,
            layoutIncrementalInProgress: false,
            layoutFullEnumerationInProgress: false,
            layoutAnimationActive: false,
            layoutHasCompletedInitialRefresh: true
        )

        let items = WorkspaceBarDataSource.workspaceBarItems(
            for: monitor,
            deduplicate: false,
            hideEmpty: false,
            workspaceManager: manager,
            appInfoCache: AppInfoCache(),
            workspaceStateExport: makeStateExport(
                monitors: [
                    .init(
                        displayId: monitor.displayId,
                        isMain: true,
                        frame: monitor.frame,
                        visibleFrame: monitor.visibleFrame,
                        name: monitor.name,
                        activeWorkspaceId: workspaceId,
                        previousWorkspaceId: nil
                    )
                ],
                workspaces: [
                    .init(
                        workspaceId: workspaceId,
                        name: "1",
                        assignedMonitorAnchor: nil,
                        assignedDisplayId: monitor.displayId,
                        isVisible: true,
                        isPreviousVisible: false,
                        isPersistent: false
                    )
                ],
                windows: [
                    .init(
                        handleId: focusedHandleId,
                        pid: 101,
                        windowId: 1001,
                        workspaceId: workspaceId,
                        hiddenState: nil,
                        layoutReason: .standard
                    )
                ],
                activeMonitorDisplayId: monitor.displayId,
                previousMonitorDisplayId: nil
            ),
            controllerSnapshot: snapshot,
            focusedHandle: WindowHandle(id: focusedHandleId, pid: 101),
            settings: settings
        )

        guard let item = items.first(where: { $0.workspaceId == workspaceId }) else {
            return XCTFail("Expected workspace bar item for workspace 1")
        }

        XCTAssertEqual(item.windows.map(\.windowId), [1001, 4004])
        XCTAssertEqual(item.windows.map(\.id), [focusedHandleId, secondaryHandleId])
        XCTAssertEqual(item.windows.first?.allWindows.first?.id, focusedHandleId)
    }
}

private func makeStateExport(
    monitors: [OmniWorkspaceRuntimeAdapter.StateExport.MonitorRecord],
    workspaces: [OmniWorkspaceRuntimeAdapter.StateExport.WorkspaceRecord],
    windows: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord],
    activeMonitorDisplayId: UInt32?,
    previousMonitorDisplayId: UInt32?
) -> OmniWorkspaceRuntimeAdapter.StateExport {
    OmniWorkspaceRuntimeAdapter.StateExport(
        monitors: monitors,
        workspaces: workspaces,
        windows: windows,
        activeMonitorDisplayId: activeMonitorDisplayId,
        previousMonitorDisplayId: previousMonitorDisplayId
    )
}
