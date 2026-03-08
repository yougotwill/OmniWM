import CZigLayout
import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class WMControllerRoutingContextTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "WMControllerRoutingContextTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    @MainActor
    func testRoutedMonitorStateWinsOverStaleFocusedHandle() throws {
        let controller = makeController()
        let monitors = testMonitors()

        let ws1 = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let ws2 = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitors[0].id))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws2, on: monitors[1].id))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitors[0].id))

        let staleHandle = try XCTUnwrap(controller.workspaceManager.addWindow(
            AXWindowRef(pid: ProcessInfo.processInfo.processIdentifier, windowId: 101),
            pid: ProcessInfo.processInfo.processIdentifier,
            windowId: 101,
            to: ws1
        ))
        controller.focusManager.setFocus(staleHandle, in: ws1)

        let routed = controller.workspaceManager.switchWorkspace(named: "2")
        XCTAssertEqual(routed?.workspace.id, ws2)
        controller.syncMonitorStateFromWorkspaceRuntime()

        XCTAssertEqual(controller.focusedHandle, staleHandle)
        XCTAssertEqual(controller.monitorForInteraction()?.id, monitors[1].id)
        XCTAssertEqual(controller.activeWorkspace()?.id, ws2)
        XCTAssertEqual(controller.activeMonitorId, monitors[1].id)
        XCTAssertEqual(controller.previousMonitorId, monitors[0].id)
    }

    @MainActor
    func testToggleFullscreenTargetsRoutedWorkspaceAfterCrossMonitorSwitch() throws {
        let controller = makeController()
        controller.zigNiriEngine = ZigNiriEngine()
        let monitors = testMonitors()

        let ws1 = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let ws2 = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitors[0].id))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws2, on: monitors[1].id))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitors[0].id))

        let pid = ProcessInfo.processInfo.processIdentifier
        let handle1 = try XCTUnwrap(controller.workspaceManager.addWindow(
            AXWindowRef(pid: pid, windowId: 201),
            pid: pid,
            windowId: 201,
            to: ws1
        ))
        let handle2 = try XCTUnwrap(controller.workspaceManager.addWindow(
            AXWindowRef(pid: pid, windowId: 202),
            pid: pid,
            windowId: 202,
            to: ws2
        ))

        let node1 = try XCTUnwrap(controller.zigNodeId(for: handle1, workspaceId: ws1))
        let node2 = try XCTUnwrap(controller.zigNodeId(for: handle2, workspaceId: ws2))

        controller.workspaceManager.setSelection(node2, for: ws2)
        _ = controller.zigNiriEngine?.setSelection(
            ZigNiriSelection(
                selectedNodeId: node2,
                focusedWindowId: node2
            ),
            in: ws2
        )
        controller.focusManager.setFocus(handle1, in: ws1)

        let routed = controller.workspaceManager.switchWorkspace(named: "2")
        XCTAssertEqual(routed?.workspace.id, ws2)
        controller.syncMonitorStateFromWorkspaceRuntime()

        controller.niriLayoutHandler.toggleFullscreen()

        let view1 = try XCTUnwrap(controller.syncZigNiriWorkspace(workspaceId: ws1))
        let view2 = try XCTUnwrap(controller.syncZigNiriWorkspace(workspaceId: ws2, selectedNodeId: node2))

        XCTAssertEqual(controller.activeWorkspace()?.id, ws2)
        XCTAssertEqual(view2.windowsById[node2]?.sizingMode, .fullscreen)
        XCTAssertEqual(view1.windowsById[node1]?.sizingMode, .normal)
    }

    @MainActor
    func testExportedLayoutOverridesPersistIntoSettingsWhilePreservingWorkspaceMetadata() {
        let controller = makeController()
        controller.settings.workspaceConfigurations = [
            WorkspaceConfiguration(
                name: "1",
                displayName: "Web",
                monitorAssignment: .main,
                layoutType: .defaultLayout,
                isPersistent: true
            ),
            WorkspaceConfiguration(
                name: "2",
                displayName: "Chat",
                monitorAssignment: .secondary,
                layoutType: .dwindle,
                isPersistent: false
            )
        ]

        controller.syncExperimentalProjectionsFromCore(
            workspaceLayoutOverrides: [
                .init(name: "1", layoutType: .dwindle),
                .init(name: "3", layoutType: .niri)
            ]
        )

        let configurations = Dictionary(
            uniqueKeysWithValues: controller.settings.workspaceConfigurations.map { ($0.name, $0) }
        )

        XCTAssertEqual(configurations["1"]?.displayName, "Web")
        XCTAssertEqual(configurations["1"]?.monitorAssignment, .main)
        XCTAssertEqual(configurations["1"]?.isPersistent, true)
        XCTAssertEqual(configurations["1"]?.layoutType, .dwindle)

        XCTAssertEqual(configurations["2"]?.displayName, "Chat")
        XCTAssertEqual(configurations["2"]?.monitorAssignment, .secondary)
        XCTAssertEqual(configurations["2"]?.isPersistent, false)
        XCTAssertEqual(configurations["2"]?.layoutType, .defaultLayout)

        XCTAssertEqual(configurations["3"]?.layoutType, .niri)
        XCTAssertEqual(configurations["3"]?.monitorAssignment, .any)
        XCTAssertEqual(configurations["3"]?.isPersistent, false)
    }

    @MainActor
    func testSyncZigNiriWorkspacePrefersSnapshotManagedHandlesWhenSnapshotExists() throws {
        let controller = makeController()
        controller.zigNiriEngine = ZigNiriEngine()
        let monitor = try XCTUnwrap(controller.workspaceManager.monitors.first)
        let workspaceId = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspaceId, on: monitor.id))

        let managerHandle = try XCTUnwrap(controller.workspaceManager.addWindow(
            AXWindowRef(pid: 700, windowId: 800),
            pid: 700,
            windowId: 800,
            to: workspaceId
        ))

        let snapshotHandleId = UUID()
        controller.syncExperimentalProjectionsFromCore(
            controllerSnapshot: WMControllerControllerSnapshot(
                monitors: [],
                workspaces: [
                    .init(
                        workspaceId: workspaceId,
                        assignedDisplayId: monitor.displayId,
                        isVisible: true,
                        isPreviousVisible: false,
                        layoutKind: UInt8(truncatingIfNeeded: OMNI_CONTROLLER_LAYOUT_NIRI.rawValue),
                        name: "1",
                        selectedNodeId: nil,
                        lastFocusedWindowId: snapshotHandleId
                    )
                ],
                windows: [
                    .init(
                        handleId: snapshotHandleId,
                        pid: 701,
                        windowId: 801,
                        workspaceId: workspaceId,
                        layoutKind: UInt8(truncatingIfNeeded: OMNI_CONTROLLER_LAYOUT_NIRI.rawValue),
                        isHidden: false,
                        isFocused: true,
                        isManaged: true,
                        nodeId: nil,
                        columnId: nil,
                        orderIndex: 0,
                        columnIndex: 0,
                        rowIndex: 0
                    )
                ],
                focusedWindowId: snapshotHandleId,
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
        )

        let view = try XCTUnwrap(controller.syncZigNiriWorkspace(workspaceId: workspaceId))
        let syncedHandles = Set(view.windowsById.values.map(\.handle))

        XCTAssertFalse(syncedHandles.contains(managerHandle))
        XCTAssertEqual(syncedHandles, Set([WindowHandle(id: snapshotHandleId, pid: 701)]))
    }

    @MainActor
    func testSyncZigNiriWorkspaceFallsBackToManagerHandlesWithoutSnapshot() throws {
        let controller = makeController()
        controller.zigNiriEngine = ZigNiriEngine()
        let monitor = try XCTUnwrap(controller.workspaceManager.monitors.first)
        let workspaceId = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspaceId, on: monitor.id))

        let managerHandle = try XCTUnwrap(controller.workspaceManager.addWindow(
            AXWindowRef(pid: 710, windowId: 810),
            pid: 710,
            windowId: 810,
            to: workspaceId
        ))

        let view = try XCTUnwrap(controller.syncZigNiriWorkspace(workspaceId: workspaceId))
        let syncedHandles = Set(view.windowsById.values.map(\.handle))

        XCTAssertEqual(syncedHandles, Set([managerHandle]))
    }

    @MainActor
    private func makeController() -> WMController {
        let settings = SettingsStore(defaults: defaults)
        let controller = WMController(settings: settings)
        controller.workspaceManager.updateMonitors(testMonitors())
        return controller
    }

    private func testMonitors() -> [Monitor] {
        [
            Monitor(
                id: Monitor.ID(displayId: 1001),
                displayId: 1001,
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
                hasNotch: false,
                name: "Primary"
            ),
            Monitor(
                id: Monitor.ID(displayId: 1002),
                displayId: 1002,
                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1040),
                hasNotch: false,
                name: "Secondary"
            )
        ]
    }

    private func unwrapWorkspaceId(
        _ value: WorkspaceDescriptor.ID?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WorkspaceDescriptor.ID {
        guard let value else {
            XCTFail("Expected workspace id to exist", file: file, line: line)
            return UUID()
        }
        return value
    }
}
