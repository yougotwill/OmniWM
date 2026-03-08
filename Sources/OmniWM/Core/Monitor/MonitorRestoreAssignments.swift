import CoreGraphics
import Foundation
struct MonitorRestoreKey: Hashable, Codable {
    let displayId: CGDirectDisplayID
    let name: String
    let anchorPoint: CGPoint
    let frameSize: CGSize
    init(monitor: Monitor) {
        displayId = monitor.displayId
        name = monitor.name
        anchorPoint = monitor.workspaceAnchorPoint
        frameSize = monitor.frame.size
    }
}
extension MonitorRestoreKey {
    func resolveMonitor(in monitors: [Monitor]) -> Monitor? {
        guard !monitors.isEmpty else { return nil }
        let sortedMonitors = Monitor.sortedByPosition(monitors)
        let candidates = sortedMonitors.filter {
            isConfidentRestoreMatch(snapshot: self, monitor: $0)
        }
        guard let bestMonitor = candidates.min(by: {
            restoreMatchScore(snapshot: self, monitor: $0)
                < restoreMatchScore(snapshot: self, monitor: $1)
        }) else {
            return nil
        }
        return bestMonitor
    }

    func resolveExactMonitor(in monitors: [Monitor]) -> Monitor? {
        guard !monitors.isEmpty else { return nil }
        if displayId != 0 {
            return Monitor.sortedByPosition(monitors).first(where: { $0.displayId == displayId })
        }

        let sortedMonitors = Monitor.sortedByPosition(monitors)
        let candidates = sortedMonitors.filter {
            sameName(snapshot: self, monitor: $0) && geometryMatchesExactly(snapshot: self, monitor: $0)
        }
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }
}
struct WorkspaceRestoreSnapshot: Hashable {
    let monitor: MonitorRestoreKey
    let workspaceId: WorkspaceDescriptor.ID
}
func resolveWorkspaceRestoreAssignments(
    snapshots: [WorkspaceRestoreSnapshot],
    monitors: [Monitor],
    workspaceExists: (WorkspaceDescriptor.ID) -> Bool
) -> [Monitor.ID: WorkspaceDescriptor.ID] {
    guard !snapshots.isEmpty, !monitors.isEmpty else { return [:] }
    var filteredSnapshots: [WorkspaceRestoreSnapshot] = []
    var seenWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
    filteredSnapshots.reserveCapacity(snapshots.count)
    for snapshot in snapshots {
        guard workspaceExists(snapshot.workspaceId) else { continue }
        guard seenWorkspaceIds.insert(snapshot.workspaceId).inserted else { continue }
        filteredSnapshots.append(snapshot)
    }
    let sortedMonitors = Monitor.sortedByPosition(monitors)
    var assignments: [Monitor.ID: WorkspaceDescriptor.ID] = [:]
    var remainingMonitors = sortedMonitors
    var pendingSnapshots: [WorkspaceRestoreSnapshot] = []

    for snapshot in filteredSnapshots {
        guard let displayMatch = remainingMonitors.first(where: {
            isReservedDisplayIdRestoreMatch(
                snapshot: snapshot.monitor,
                monitor: $0
            )
        }) else {
            pendingSnapshots.append(snapshot)
            continue
        }
        assignments[displayMatch.id] = snapshot.workspaceId
        remainingMonitors.removeAll { $0.id == displayMatch.id }
    }

    for snapshot in pendingSnapshots {
        guard let best = snapshot.monitor.resolveMonitor(in: remainingMonitors) else {
            continue
        }
        assignments[best.id] = snapshot.workspaceId
        remainingMonitors.removeAll { $0.id == best.id }
    }
    return assignments
}
private func restoreMatchScore(snapshot: MonitorRestoreKey, monitor: Monitor) -> (Int, CGFloat, Int) {
    let exactGeometryPenalty = geometryMatchesExactly(snapshot: snapshot, monitor: monitor) ? 0 : 1
    let geometryDelta = restoreGeometryDelta(snapshot: snapshot, monitor: monitor)
    let displayPenalty = snapshot.displayId == monitor.displayId ? 0 : 1
    return (exactGeometryPenalty, geometryDelta, displayPenalty)
}
private func isConfidentRestoreMatch(
    snapshot: MonitorRestoreKey,
    monitor: Monitor
) -> Bool {
    geometryMatchesExactly(snapshot: snapshot, monitor: monitor)
        || (sameName(snapshot: snapshot, monitor: monitor)
            && geometryMatchesTightly(snapshot: snapshot, monitor: monitor))
}

private func isReservedDisplayIdRestoreMatch(
    snapshot: MonitorRestoreKey,
    monitor: Monitor
) -> Bool {
    guard snapshot.displayId == monitor.displayId else { return false }
    return geometryMatchesExactly(snapshot: snapshot, monitor: monitor)
        || (sameName(snapshot: snapshot, monitor: monitor)
            && geometryMatchesTightly(snapshot: snapshot, monitor: monitor))
}

private func sameName(snapshot: MonitorRestoreKey, monitor: Monitor) -> Bool {
    snapshot.name.localizedCaseInsensitiveCompare(monitor.name) == .orderedSame
}

private func restoreGeometryDelta(snapshot: MonitorRestoreKey, monitor: Monitor) -> CGFloat {
    let anchorDistance = snapshot.anchorPoint.distanceSquared(to: monitor.workspaceAnchorPoint)
    let widthDelta = abs(snapshot.frameSize.width - monitor.frame.width)
    let heightDelta = abs(snapshot.frameSize.height - monitor.frame.height)
    return anchorDistance + widthDelta + heightDelta
}

private func geometryMatchesExactly(snapshot: MonitorRestoreKey, monitor: Monitor) -> Bool {
    let anchorDistance = snapshot.anchorPoint.distanceSquared(to: monitor.workspaceAnchorPoint)
    let widthDelta = abs(snapshot.frameSize.width - monitor.frame.width)
    let heightDelta = abs(snapshot.frameSize.height - monitor.frame.height)
    return anchorDistance <= 1 && widthDelta <= 1 && heightDelta <= 1
}

private func geometryMatchesTightly(snapshot: MonitorRestoreKey, monitor: Monitor) -> Bool {
    let anchorDistance = snapshot.anchorPoint.distanceSquared(to: monitor.workspaceAnchorPoint)
    let widthDelta = abs(snapshot.frameSize.width - monitor.frame.width)
    let heightDelta = abs(snapshot.frameSize.height - monitor.frame.height)
    return anchorDistance <= 64 * 64 && widthDelta <= 64 && heightDelta <= 64
}

private extension CGPoint {
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return dx * dx + dy * dy
    }
}
