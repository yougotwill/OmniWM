import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private func dwindleMutationUUID(_ marker: UInt8) -> UUID {
    var bytes = [UInt8](repeating: 0, count: 16)
    bytes[0] = marker
    let tuple: uuid_t = (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
    return UUID(uuid: tuple)
}

private func dwindleDedupOrder(_ ids: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    var ordered: [UUID] = []
    ordered.reserveCapacity(ids.count)
    for id in ids where !seen.contains(id) {
        seen.insert(id)
        ordered.append(id)
    }
    return ordered
}

private func applyReferenceMutationOp(
    _ op: DwindleZigKernel.Op,
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID,
    handlePool: inout [UUID: WindowHandle],
    nextPid: inout pid_t
) -> [UUID] {
    let currentHandles = engine.root(for: workspaceId)?.collectAllWindows() ?? []

    switch op {
    case let .addWindow(windowId):
        if currentHandles.contains(where: { $0.id == windowId }) {
            return []
        }
        let handle: WindowHandle
        if let existing = handlePool[windowId] {
            handle = existing
        } else {
            nextPid += 1
            handle = dwindleMutationMakeHandle(id: windowId, pid: nextPid)
            handlePool[windowId] = handle
        }
        _ = engine.addWindow(handle: handle, to: workspaceId, activeWindowFrame: nil)
        return []

    case let .removeWindow(windowId):
        guard let existingHandle = currentHandles.first(where: { $0.id == windowId }) else {
            return []
        }
        engine.removeWindow(handle: existingHandle, from: workspaceId)
        return [windowId]

    case let .syncWindows(windowIds):
        let deduped = dwindleDedupOrder(windowIds)
        var seenCurrent: Set<UUID> = []
        let currentOrder = currentHandles.compactMap { handle in
            if seenCurrent.insert(handle.id).inserted {
                return handle.id
            }
            return nil
        }
        let incomingSet = Set(deduped)
        let expectedRemoved = currentOrder.filter { !incomingSet.contains($0) }

        var handles: [WindowHandle] = []
        handles.reserveCapacity(deduped.count)
        for windowId in deduped {
            if let existing = handlePool[windowId] {
                handles.append(existing)
                continue
            }
            nextPid += 1
            let created = dwindleMutationMakeHandle(id: windowId, pid: nextPid)
            handlePool[windowId] = created
            handles.append(created)
        }

        _ = engine.syncWindows(handles, in: workspaceId, focusedHandle: nil)
        return expectedRemoved

    case let .moveFocus(direction):
        _ = engine.moveFocus(direction: direction, in: workspaceId)
        return []

    case let .swapWindows(direction):
        _ = engine.swapWindows(direction: direction, in: workspaceId)
        return []

    case .toggleFullscreen:
        _ = engine.toggleFullscreen(in: workspaceId)
        return []

    case .toggleOrientation:
        engine.toggleOrientation(in: workspaceId)
        return []

    case let .resizeSelected(delta, direction):
        engine.resizeSelected(by: delta, direction: direction, in: workspaceId)
        return []

    case .balanceSizes:
        engine.balanceSizes(in: workspaceId)
        return []

    case let .cycleSplitRatio(forward):
        engine.cycleSplitRatio(forward: forward, in: workspaceId)
        return []

    case let .moveSelectionToRoot(stable):
        engine.moveSelectionToRoot(stable: stable, in: workspaceId)
        return []

    case .swapSplit:
        engine.swapSplit(in: workspaceId)
        return []

    case let .setPreselection(direction):
        engine.setPreselection(direction, in: workspaceId)
        return []

    case .clearPreselection:
        engine.setPreselection(nil, in: workspaceId)
        return []

    case .validateSelection:
        _ = dwindleMutationNormalizeSelectionReference(engine: engine, workspaceId: workspaceId)
        return []
    }
}

@Suite struct DwindleZigMutationParityTests {
    @MainActor
    @Test func scenarioCoversAllV1Ops() {
        let engine = DwindleLayoutEngine()
        engine.settings.defaultSplitRatio = 1.0
        engine.settings.smartSplit = true
        engine.settings.splitWidthMultiplier = 1.0

        let workspaceId = WorkspaceDescriptor.ID()
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

        var nextPid: pid_t = 200_000
        var handlePool: [UUID: WindowHandle] = [:]

        let w1 = dwindleMutationUUID(11)
        let w2 = dwindleMutationUUID(22)
        let w3 = dwindleMutationUUID(33)
        let w4 = dwindleMutationUUID(44)
        let w5 = dwindleMutationUUID(55)

        for id in [w1, w2, w3] {
            nextPid += 1
            let handle = dwindleMutationMakeHandle(id: id, pid: nextPid)
            handlePool[id] = handle
            _ = engine.addWindow(handle: handle, to: workspaceId, activeWindowFrame: nil)
            engine.updateWindowConstraints(
                for: handle,
                constraints: WindowSizeConstraints(
                    minSize: CGSize(width: 80, height: 60),
                    maxSize: CGSize(width: 0, height: 0),
                    isFixed: false
                )
            )
        }

        guard let context = DwindleZigKernel.LayoutContext() else {
            #expect(Bool(false))
            return
        }
        let seedRC = dwindleMutationSeedContext(engine: engine, workspaceId: workspaceId, context: context)
        #expect(seedRC == 0)
        guard seedRC == 0 else { return }

        dwindleMutationAssertLayoutAndNeighborParity(
            engine: engine,
            context: context,
            workspaceId: workspaceId,
            screen: screen
        )

        let ops: [DwindleZigKernel.Op] = [
            .setPreselection(direction: .left),
            .addWindow(windowId: w4),
            .clearPreselection,
            .moveFocus(direction: .left),
            .swapWindows(direction: .right),
            .toggleFullscreen,
            .toggleOrientation,
            .resizeSelected(delta: 0.12, direction: .left),
            .balanceSizes,
            .cycleSplitRatio(forward: true),
            .moveSelectionToRoot(stable: true),
            .swapSplit,
            .validateSelection,
            .removeWindow(windowId: w2),
            .syncWindows(windowIds: [w3, w5, w4]),
        ]

        for op in ops {
            let expectedRemoved = applyReferenceMutationOp(
                op,
                engine: engine,
                workspaceId: workspaceId,
                handlePool: &handlePool,
                nextPid: &nextPid
            )

            let zigResult = DwindleZigKernel.applyOp(context: context, op: op)
            #expect(zigResult.rc == 0)
            guard zigResult.rc == 0 else { continue }

            let expectedSelected = dwindleMutationSelectedWindowId(engine: engine, workspaceId: workspaceId)
            #expect(zigResult.selectedWindowId == expectedSelected)
            #expect(zigResult.focusedWindowId == expectedSelected)
            #expect(zigResult.preselection == engine.getPreselection(in: workspaceId))

            if case .removeWindow = op {
                #expect(zigResult.removedWindowIds == expectedRemoved)
            }
            if case .syncWindows = op {
                #expect(zigResult.removedWindowIds == expectedRemoved)
            }

            dwindleMutationAssertLayoutAndNeighborParity(
                engine: engine,
                context: context,
                workspaceId: workspaceId,
                screen: screen
            )
        }
    }
}
