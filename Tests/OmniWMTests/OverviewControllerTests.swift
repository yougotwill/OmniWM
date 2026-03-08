import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class OverviewControllerTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "OverviewControllerTests.\(UUID().uuidString)"
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
    func testOverviewWorkspaceContextsUseRuntimeExportOrderingAndActiveState() {
        let settings = SettingsStore(defaults: defaults)
        let controller = WMController(settings: settings)
        let monitor = Monitor(
            id: .init(displayId: 3001),
            displayId: 3001,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1040),
            hasNotch: false,
            name: "Primary"
        )
        controller.workspaceManager.updateMonitors([monitor])

        let workspace10Id = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "10", createIfMissing: true))
        let workspace2Id = unwrapWorkspaceId(controller.workspaceManager.workspaceId(for: "2", createIfMissing: true))
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspace10Id, on: monitor.id))

        controller.syncExperimentalProjectionsFromCore(
            stateExport: OmniWorkspaceRuntimeAdapter.StateExport(
                monitors: [
                    .init(
                        displayId: monitor.displayId,
                        isMain: true,
                        frame: monitor.frame,
                        visibleFrame: monitor.visibleFrame,
                        name: monitor.name,
                        activeWorkspaceId: workspace2Id,
                        previousWorkspaceId: workspace10Id
                    )
                ],
                workspaces: [
                    .init(
                        workspaceId: workspace10Id,
                        name: "10",
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
                windows: [],
                activeMonitorDisplayId: monitor.displayId,
                previousMonitorDisplayId: nil
            )
        )

        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(workspace10Id, on: monitor.id))

        let overviewController = OverviewController(wmController: controller)
        let workspaces = overviewController.overviewWorkspaceContexts()

        XCTAssertEqual(workspaces.map(\.name), ["2", "10"])
        XCTAssertEqual(workspaces.first(where: { $0.id == workspace2Id })?.isActive, true)
        XCTAssertEqual(workspaces.first(where: { $0.id == workspace10Id })?.isActive, false)
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
