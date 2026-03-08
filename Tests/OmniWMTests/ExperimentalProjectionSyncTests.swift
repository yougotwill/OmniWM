import CoreGraphics
import Foundation
import XCTest

@testable import OmniWM

final class ExperimentalProjectionSyncTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "ExperimentalProjectionSyncTests.\(UUID().uuidString)"
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
    func testChangedWorkspaceInvalidationStaysSelective() throws {
        let controller = makeController()
        let seeded = try seedControllerState(controller)
        let engine = try XCTUnwrap(controller.zigNiriEngine)

        XCTAssertFalse(engine.isWorkspaceProjectionDirty(seeded.ws1))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(seeded.ws2))

        controller.syncExperimentalProjectionsFromCore(changedWorkspaceIds: [seeded.ws1])

        XCTAssertTrue(engine.isWorkspaceProjectionDirty(seeded.ws1))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(seeded.ws2))
    }

    @MainActor
    func testRemovedWorkspaceProjectionsArePrunedFromEngine() throws {
        let controller = makeController()
        let seeded = try seedControllerState(controller)
        let engine = try XCTUnwrap(controller.zigNiriEngine)

        let ghostWorkspaceId = UUID()
        let ghostHandle = WindowHandle(
            id: UUID(),
            pid: ProcessInfo.processInfo.processIdentifier
        )
        _ = engine.syncWindows(
            [ghostHandle],
            in: ghostWorkspaceId,
            selectedNodeId: nil,
            focusedHandle: ghostHandle
        )
        XCTAssertTrue(engine.refreshWorkspaceProjection(ghostWorkspaceId))
        XCTAssertNotNil(engine.workspaceView(for: ghostWorkspaceId))

        controller.syncExperimentalProjectionsFromCore(changedWorkspaceIds: [seeded.ws1])

        XCTAssertNil(engine.workspaceView(for: ghostWorkspaceId))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(ghostWorkspaceId))
    }

    @MainActor
    func testNilChangedWorkspaceFallbackInvalidatesAllActiveWorkspaces() throws {
        let controller = makeController()
        let seeded = try seedControllerState(controller)
        let engine = try XCTUnwrap(controller.zigNiriEngine)

        XCTAssertFalse(engine.isWorkspaceProjectionDirty(seeded.ws1))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(seeded.ws2))

        controller.syncExperimentalProjectionsFromCore(changedWorkspaceIds: nil)

        XCTAssertTrue(engine.isWorkspaceProjectionDirty(seeded.ws1))
        XCTAssertTrue(engine.isWorkspaceProjectionDirty(seeded.ws2))
    }

    @MainActor
    private func makeController() -> WMController {
        let settings = SettingsStore(defaults: defaults)
        let controller = WMController(settings: settings)
        controller.workspaceManager.updateMonitors(testMonitors())
        controller.zigNiriEngine = ZigNiriEngine()
        return controller
    }

    @MainActor
    private func seedControllerState(
        _ controller: WMController
    ) throws -> (ws1: WorkspaceDescriptor.ID, ws2: WorkspaceDescriptor.ID) {
        let monitors = testMonitors()
        let ws1 = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "1", createIfMissing: true))
        let ws2 = try XCTUnwrap(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws1, on: monitors[0].id))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(ws2, on: monitors[1].id))

        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertNotNil(controller.workspaceManager.addWindow(
            AXWindowRef(pid: pid, windowId: 1101),
            pid: pid,
            windowId: 1101,
            to: ws1
        ))
        XCTAssertNotNil(controller.workspaceManager.addWindow(
            AXWindowRef(pid: pid, windowId: 1102),
            pid: pid,
            windowId: 1102,
            to: ws2
        ))

        XCTAssertNotNil(controller.syncZigNiriWorkspace(workspaceId: ws1))
        XCTAssertNotNil(controller.syncZigNiriWorkspace(workspaceId: ws2))

        let engine = try XCTUnwrap(controller.zigNiriEngine)
        XCTAssertTrue(engine.refreshWorkspaceProjection(ws1))
        XCTAssertTrue(engine.refreshWorkspaceProjection(ws2))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(ws1))
        XCTAssertFalse(engine.isWorkspaceProjectionDirty(ws2))

        return (ws1, ws2)
    }

    private func testMonitors() -> [Monitor] {
        [
            Monitor(
                id: Monitor.ID(displayId: 2101),
                displayId: 2101,
                frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
                hasNotch: false,
                name: "Primary"
            ),
            Monitor(
                id: Monitor.ID(displayId: 2102),
                displayId: 2102,
                frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1040),
                hasNotch: false,
                name: "Secondary"
            ),
        ]
    }
}
