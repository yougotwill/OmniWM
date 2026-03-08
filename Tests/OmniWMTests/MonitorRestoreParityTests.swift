import CoreGraphics
import Foundation
import XCTest
@testable import OmniWM

final class MonitorRestoreParityTests: XCTestCase {
    func testResolveAssignmentsPrefersPhysicalMatchOverReusedDisplayId() {
        let ws = UUID()

        let oldMonitor = testMonitor(displayId: 10, name: "Main", origin: CGPoint(x: 0, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: oldMonitor), workspaceId: ws)
        ]

        let reusedDisplayId = testMonitor(displayId: 10, name: "Side", origin: CGPoint(x: 1920, y: 0))
        let physicalMatch = testMonitor(displayId: 20, name: "Main", origin: CGPoint(x: 0, y: 0))
        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [reusedDisplayId, physicalMatch],
            workspaceExists: { _ in true }
        )

        XCTAssertEqual(assignments[physicalMatch.id], ws)
        XCTAssertNil(assignments[reusedDisplayId.id])
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

    func testResolveAssignmentsReservesConfidentDisplayIdMatchesBeforeApproximateMatches() {
        let wsA = UUID()
        let wsB = UUID()

        let oldA = testMonitor(displayId: 10, name: "Desk", origin: CGPoint(x: 0, y: 0))
        let oldB = testMonitor(displayId: 20, name: "Desk", origin: CGPoint(x: 48, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: oldB), workspaceId: wsB),
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: oldA), workspaceId: wsA)
        ]

        let preservedDisplayId = testMonitor(displayId: 10, name: "Desk", origin: CGPoint(x: 48, y: 0))
        let approximateFallback = testMonitor(displayId: 30, name: "Desk", origin: CGPoint(x: 0, y: 0))

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [preservedDisplayId, approximateFallback],
            workspaceExists: { _ in true }
        )

        XCTAssertEqual(assignments[preservedDisplayId.id], wsA)
        XCTAssertEqual(assignments[approximateFallback.id], wsB)
    }

    func testResolveAssignmentsRejectsNameOnlyMatchesAcrossDuplicateDisplayNames() {
        let ws = UUID()
        let old = testMonitor(displayId: 42, name: "Studio", origin: CGPoint(x: 0, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: old), workspaceId: ws)
        ]

        let farLeft = testMonitor(displayId: 1, name: "Studio", origin: CGPoint(x: 1920, y: 0))
        let farRight = testMonitor(displayId: 2, name: "Studio", origin: CGPoint(x: 3840, y: 0))

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [farLeft, farRight],
            workspaceExists: { _ in true }
        )

        XCTAssertTrue(assignments.isEmpty)
    }

    func testResolveAssignmentsLeavesUnmatchedExactMonitorUnassigned() {
        let ws = UUID()
        let old = testMonitor(displayId: 42, name: "Studio", origin: CGPoint(x: 0, y: 0))
        let snapshots = [
            WorkspaceRestoreSnapshot(monitor: MonitorRestoreKey(monitor: old), workspaceId: ws)
        ]

        let unrelated = testMonitor(displayId: 42, name: "Laptop", origin: CGPoint(x: 2400, y: 0))

        let assignments = resolveWorkspaceRestoreAssignments(
            snapshots: snapshots,
            monitors: [unrelated],
            workspaceExists: { _ in true }
        )

        XCTAssertTrue(assignments.isEmpty)
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

    func testExactMonitorAssignmentDoesNotDegradeToSameNameFallback() {
        let original = testMonitor(displayId: 42, name: "Studio", origin: CGPoint(x: 0, y: 0))
        let sameNameWrongGeometry = testMonitor(displayId: 77, name: "Studio", origin: CGPoint(x: 2400, y: 0))

        let assignment = MonitorAssignment.exact(MonitorRestoreKey(monitor: original))

        XCTAssertNil(assignment.toMonitorDescription(sortedMonitors: [sameNameWrongGeometry]))
    }

    func testExactMonitorAssignmentRequiresOriginalDisplayIdEvenWhenNameAndGeometryStillMatch() {
        let original = testMonitor(displayId: 42, name: "Studio", origin: CGPoint(x: 1920, y: 0))
        let assignment = MonitorAssignment.exact(MonitorRestoreKey(monitor: original))
        let monitors = [
            testMonitor(displayId: 11, name: "Main", origin: CGPoint(x: 0, y: 0)),
            testMonitor(displayId: 99, name: "Studio", origin: CGPoint(x: 1920, y: 0))
        ]

        XCTAssertNil(assignment.toMonitorDescription(sortedMonitors: monitors))
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
