import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class WorkspaceManagerPhase3ParityTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "WorkspaceManagerPhase3ParityTests.\(UUID().uuidString)"
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
    func testWorkspaceMoveSwapAndSummonParityFlow() {
        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitors = testMonitors()
        manager.updateMonitors(monitors)

        let ws1 = unwrapWorkspaceId(manager.workspaceId(for: "1", createIfMissing: true))
        let ws2 = unwrapWorkspaceId(manager.workspaceId(for: "2", createIfMissing: true))
        let ws3 = unwrapWorkspaceId(manager.workspaceId(for: "3", createIfMissing: true))

        XCTAssertTrue(manager.setActiveWorkspace(ws1, on: monitors[0].id))
        XCTAssertTrue(manager.setActiveWorkspace(ws2, on: monitors[1].id))
        XCTAssertEqual(manager.activeWorkspace(on: monitors[0].id)?.id, ws1)
        XCTAssertEqual(manager.activeWorkspace(on: monitors[1].id)?.id, ws2)

        XCTAssertTrue(manager.moveWorkspaceToMonitor(ws1, to: monitors[1].id))
        XCTAssertEqual(manager.activeWorkspace(on: monitors[1].id)?.id, ws1)
        XCTAssertNotNil(manager.activeWorkspace(on: monitors[0].id))

        let monitor0WorkspaceBeforeSwap = manager.activeWorkspace(on: monitors[0].id)?.id
        XCTAssertNotNil(monitor0WorkspaceBeforeSwap)

        XCTAssertTrue(
            manager.swapWorkspaces(
                ws1,
                on: monitors[1].id,
                with: monitor0WorkspaceBeforeSwap!,
                on: monitors[0].id
            )
        )
        XCTAssertEqual(manager.activeWorkspace(on: monitors[0].id)?.id, ws1)
        XCTAssertEqual(manager.activeWorkspace(on: monitors[1].id)?.id, monitor0WorkspaceBeforeSwap)

        let summonTarget = manager.activeWorkspace(on: monitors[1].id)?.id == ws3 ? monitors[0] : monitors[1]
        let previousOnTarget = manager.activeWorkspace(on: summonTarget.id)?.id

        let summoned = manager.summonWorkspace(named: "3", to: summonTarget.id)
        if previousOnTarget == ws3 {
            XCTAssertNil(summoned)
        } else {
            if let summoned {
                XCTAssertEqual(summoned.id, ws3)
                XCTAssertEqual(manager.activeWorkspace(on: summonTarget.id)?.id, ws3)
                XCTAssertEqual(manager.previousWorkspace(on: summonTarget.id)?.id, previousOnTarget)
            } else {
                XCTAssertEqual(manager.activeWorkspace(on: summonTarget.id)?.id, previousOnTarget)
            }
        }
    }

    @MainActor
    func testForcedAssignmentTakesPrecedenceOverManualMove() {
        let settings = SettingsStore(defaults: defaults)
        settings.workspaceAssignmentsRaw = "2:1"
        let manager = WorkspaceManager(settings: settings)
        let monitors = testMonitors()
        manager.updateMonitors(monitors)
        manager.applySettings()

        let ws2 = unwrapWorkspaceId(manager.workspaceId(for: "2", createIfMissing: true))
        let currentMonitorId = manager.monitorId(for: ws2)
        XCTAssertEqual(currentMonitorId, monitors[0].id)

        let moved = manager.moveWorkspaceToMonitor(ws2, to: monitors[1].id)
        XCTAssertFalse(moved)
        XCTAssertEqual(manager.monitorId(for: ws2), monitors[0].id)
    }

    @MainActor
    func testEachMonitorGetsVisibleWorkspaceStubWhenNeeded() {
        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitors = testMonitors()
        manager.updateMonitors(monitors)

        let active0 = manager.activeWorkspaceOrFirst(on: monitors[0].id)
        let active1 = manager.activeWorkspaceOrFirst(on: monitors[1].id)

        XCTAssertNotNil(active0)
        XCTAssertNotNil(active1)
        XCTAssertNotEqual(active0?.id, active1?.id)
    }

    @MainActor
    func testHiddenStateRetentionRoundTrip() {
        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitors = testMonitors()
        manager.updateMonitors(monitors)

        let ws1 = unwrapWorkspaceId(manager.workspaceId(for: "1", createIfMissing: true))
        let handle = manager.addWindow(
            AXWindowRef(pid: 111, windowId: 222),
            pid: 111,
            windowId: 222,
            to: ws1
        )

        let expected = WindowModel.HiddenState(
            proportionalPosition: CGPoint(x: 0.8, y: 0.2),
            referenceMonitorId: monitors[1].id,
            workspaceInactive: true
        )

        manager.setHiddenState(expected, for: handle)
        let actual = manager.hiddenState(for: handle)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual!.proportionalPosition.x, expected.proportionalPosition.x, accuracy: 0.0001)
        XCTAssertEqual(actual!.proportionalPosition.y, expected.proportionalPosition.y, accuracy: 0.0001)
        XCTAssertEqual(actual!.referenceMonitorId, expected.referenceMonitorId)
        XCTAssertEqual(actual!.workspaceInactive, expected.workspaceInactive)

        manager.setHiddenState(nil, for: handle)
        XCTAssertNil(manager.hiddenState(for: handle))
    }

    @MainActor
    func testRemoveMissingHonorsConsecutiveMissThreshold() {
        let settings = SettingsStore(defaults: defaults)
        let manager = WorkspaceManager(settings: settings)
        let monitors = testMonitors()
        manager.updateMonitors(monitors)

        let ws1 = unwrapWorkspaceId(manager.workspaceId(for: "1", createIfMissing: true))
        _ = manager.addWindow(
            AXWindowRef(pid: 321, windowId: 654),
            pid: 321,
            windowId: 654,
            to: ws1
        )

        manager.removeMissing(keys: [], requiredConsecutiveMisses: 2)
        XCTAssertNotNil(manager.entry(forPid: 321, windowId: 654))

        manager.removeMissing(keys: [], requiredConsecutiveMisses: 2)
        XCTAssertNil(manager.entry(forPid: 321, windowId: 654))
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
            XCTFail("Expected workspace id to be created", file: file, line: line)
            return UUID()
        }
        return value
    }
}
