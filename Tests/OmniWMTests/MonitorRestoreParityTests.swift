import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class MonitorRestoreParityTests: XCTestCase {
    func testResolveAssignmentsPrefersExactDisplayIdFirst() {
        let ws1 = UUID()
        let ws2 = UUID()

        let oldA = testMonitor(displayId: 10, name: "A", origin: CGPoint(x: 0, y: 0))
        let oldB = testMonitor(displayId: 20, name: "B", origin: CGPoint(x: 1920, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: oldA), workspaceId: ws1),
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: oldB), workspaceId: ws2)
        ]

        let newA = testMonitor(displayId: 20, name: "B", origin: CGPoint(x: 0, y: 0))
        let newB = testMonitor(displayId: 10, name: "A", origin: CGPoint(x: 1920, y: 0))
        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [newA, newB],
            workspaceExists: { _ in true }
        )

        XCTAssertEqual(assignments[newB.id], ws1)
        XCTAssertEqual(assignments[newA.id], ws2)
    }

    func testResolveAssignmentsFallsBackToBestGeometryAndName() {
        let ws = UUID()
        let old = testMonitor(displayId: 999, name: "Desk-L", origin: CGPoint(x: 0, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: old), workspaceId: ws)
        ]

        let nearNameMatch = testMonitor(displayId: 1, name: "Desk-L", origin: CGPoint(x: 20, y: 0))
        let fartherNoMatch = testMonitor(displayId: 2, name: "Other", origin: CGPoint(x: 2000, y: 0))

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [fartherNoMatch, nearNameMatch],
            workspaceExists: { _ in true }
        )

        XCTAssertEqual(assignments[nearNameMatch.id], ws)
        XCTAssertNil(assignments[fartherNoMatch.id])
    }

    func testResolveAssignmentsSkipsUnknownAndDuplicateWorkspaceIds() {
        let ws = UUID()
        let monitor = testMonitor(displayId: 42, name: "Main", origin: .zero)
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: monitor), workspaceId: ws),
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: monitor), workspaceId: ws)
        ]

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [monitor],
            workspaceExists: { _ in false }
        )

        XCTAssertTrue(assignments.isEmpty)
    }

    private func testMonitor(displayId: UInt32, name: String, origin: CGPoint) -> Monitor {
        Monitor(
            id: .init(displayId: displayId),
            displayId: displayId,
            frame: CGRect(origin: origin, size: CGSize(width: 1920, height: 1080)),
            visibleFrame: CGRect(origin: origin, size: CGSize(width: 1920, height: 1040)),
            hasNotch: false,
            name: name
        )
    }
}
