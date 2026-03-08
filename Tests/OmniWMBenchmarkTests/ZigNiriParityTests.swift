import Foundation
import XCTest

@testable import OmniWM

@MainActor
final class ZigNiriParityTests: XCTestCase {
    func testSyncWindowsUnchangedHandlesPreservesRuntimeAndUpdatesSelection() throws {
        let fixture = try makeFixture()
        let workspaceId = fixture.primaryWorkspaceId
        let beforeSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        let beforeView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let orderedWindowIds = orderedWindowIds(in: beforeView)
        let secondWindowId = try XCTUnwrap(orderedWindowIds.dropFirst().first)
        let secondHandle = try XCTUnwrap(fixture.engine.windowHandle(for: secondWindowId))

        _ = fixture.engine.syncWindows(
            orderedWindowIds.compactMap { fixture.engine.windowHandle(for: $0) },
            in: workspaceId,
            selectedNodeId: secondWindowId,
            focusedHandle: secondHandle
        )

        let afterSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        XCTAssertEqual(beforeSnapshot, afterSnapshot)
        XCTAssertEqual(fixture.engine.selection(in: workspaceId)?.selectedNodeId, secondWindowId)
        XCTAssertEqual(fixture.engine.selection(in: workspaceId)?.focusedWindowId, secondWindowId)
    }

    func testInteractiveResizeDefersRuntimeMutationUntilCommit() throws {
        let fixture = try makeFixture()
        let workspaceId = fixture.primaryWorkspaceId
        let beforeSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        let beforeView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let trackedColumnId = try trackedColumnId(
            in: beforeView,
            windowId: fixture.trackedNodeId
        )
        let beforeColumn = try XCTUnwrap(beforeView.columns.first(where: { $0.nodeId == trackedColumnId }))

        XCTAssertTrue(
            fixture.engine.beginInteractiveResize(
                ZigNiriInteractiveResizeState(
                    windowId: fixture.trackedNodeId,
                    workspaceId: workspaceId,
                    edges: [.right],
                    startMouseLocation: CGPoint(x: 100, y: 100),
                    monitorFrame: fixture.monitorFrame,
                    orientation: .horizontal,
                    gap: fixture.gaps.horizontal,
                    initialViewportOffset: 0
                )
            )
        )

        let update = fixture.engine.updateInteractiveResize(mouseLocation: CGPoint(x: 124, y: 100))
        XCTAssertTrue(update.applied)

        let duringSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        XCTAssertEqual(beforeSnapshot, duringSnapshot)

        let duringView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let duringColumn = try XCTUnwrap(duringView.columns.first(where: { $0.nodeId == trackedColumnId }))
        XCTAssertNotEqual(duringColumn.width, beforeColumn.width)

        _ = fixture.engine.endInteractiveResize(commit: true)

        let afterSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        XCTAssertNotEqual(afterSnapshot, beforeSnapshot)

        let afterView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let afterColumn = try XCTUnwrap(afterView.columns.first(where: { $0.nodeId == trackedColumnId }))
        let runtimeColumn = try XCTUnwrap(afterSnapshot.columns.first(where: { $0.columnId == trackedColumnId }))
        XCTAssertEqual(
            ZigNiriStateKernel.decodeWidth(
                kind: runtimeColumn.widthKind,
                value: runtimeColumn.sizeValue
            ),
            afterColumn.width
        )
    }

    func testInteractiveResizeCancelRestoresPreviewWithoutMutatingRuntime() throws {
        let fixture = try makeFixture()
        let workspaceId = fixture.primaryWorkspaceId
        let beforeSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        let beforeView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let trackedColumnId = try trackedColumnId(
            in: beforeView,
            windowId: fixture.trackedNodeId
        )
        let beforeColumn = try XCTUnwrap(beforeView.columns.first(where: { $0.nodeId == trackedColumnId }))

        XCTAssertTrue(
            fixture.engine.beginInteractiveResize(
                ZigNiriInteractiveResizeState(
                    windowId: fixture.trackedNodeId,
                    workspaceId: workspaceId,
                    edges: [.right],
                    startMouseLocation: CGPoint(x: 100, y: 100),
                    monitorFrame: fixture.monitorFrame,
                    orientation: .horizontal,
                    gap: fixture.gaps.horizontal,
                    initialViewportOffset: 0
                )
            )
        )

        let update = fixture.engine.updateInteractiveResize(mouseLocation: CGPoint(x: 124, y: 100))
        XCTAssertTrue(update.applied)

        _ = fixture.engine.endInteractiveResize(commit: false)

        let afterSnapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        XCTAssertEqual(beforeSnapshot, afterSnapshot)

        let afterView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let afterColumn = try XCTUnwrap(afterView.columns.first(where: { $0.nodeId == trackedColumnId }))
        XCTAssertEqual(afterColumn.width, beforeColumn.width)
    }

    func testWorkspaceMoveUpdatesSourceAndTargetSelections() throws {
        let fixture = try makeFixture()
        let result = fixture.engine.applyWorkspace(
            .moveWindow(
                windowId: fixture.trackedNodeId,
                targetWorkspaceId: fixture.secondaryWorkspaceId
            ),
            in: fixture.primaryWorkspaceId
        )

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.workspaceId, fixture.secondaryWorkspaceId)
        XCTAssertEqual(result.selection?.selectedNodeId, fixture.trackedNodeId)
        XCTAssertEqual(result.selection?.focusedWindowId, fixture.trackedNodeId)

        let sourceView = try XCTUnwrap(fixture.engine.workspaceView(for: fixture.primaryWorkspaceId))
        let targetView = try XCTUnwrap(fixture.engine.workspaceView(for: fixture.secondaryWorkspaceId))
        XCTAssertNil(sourceView.windowsById[fixture.trackedNodeId])
        XCTAssertNotNil(targetView.windowsById[fixture.trackedNodeId])
        if !sourceView.windowsById.isEmpty {
            try assertValidSelection(in: sourceView)
            XCTAssertNotEqual(sourceView.selection?.selectedNodeId, fixture.trackedNodeId)
        }
        XCTAssertEqual(targetView.selection?.selectedNodeId, fixture.trackedNodeId)
        XCTAssertEqual(targetView.selection?.focusedWindowId, fixture.trackedNodeId)

        try assertRenderMatchesViewAndRuntime(
            fixture: fixture,
            workspaceId: fixture.primaryWorkspaceId
        )
        try assertRenderMatchesViewAndRuntime(
            fixture: fixture,
            workspaceId: fixture.secondaryWorkspaceId
        )
    }

    func testWindowMoveKeepsMovedWindowSelectedAndRenderMatchesRuntime() throws {
        let fixture = try makeFixture()
        let result = fixture.engine.applyMutation(
            .moveWindow(
                windowId: fixture.trackedNodeId,
                direction: .right,
                orientation: .horizontal
            ),
            in: fixture.primaryWorkspaceId
        )

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.selection?.selectedNodeId, fixture.trackedNodeId)
        XCTAssertEqual(result.selection?.focusedWindowId, fixture.trackedNodeId)

        try assertRenderMatchesViewAndRuntime(
            fixture: fixture,
            workspaceId: fixture.primaryWorkspaceId
        )
    }

    func testLifecycleSyncWindowsKeepsSelectionValidAndRuntimeConsistent() throws {
        let fixture = try makeFixture()
        let workspaceId = fixture.primaryWorkspaceId
        let beforeView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        let orderedIds = orderedWindowIds(in: beforeView)
        let existingHandles = orderedIds.compactMap { fixture.engine.windowHandle(for: $0) }
        let removableWindowId = try XCTUnwrap(orderedIds.last)
        let removableHandle = try XCTUnwrap(fixture.engine.windowHandle(for: removableWindowId))
        let pendingHandle = makeWindowHandle()

        _ = fixture.engine.syncWindows(
            existingHandles + [pendingHandle],
            in: workspaceId,
            selectedNodeId: fixture.trackedNodeId,
            focusedHandle: fixture.trackedHandle
        )

        let addedNodeId = try XCTUnwrap(fixture.engine.nodeId(for: pendingHandle))
        let afterAddView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        XCTAssertNotNil(afterAddView.windowsById[addedNodeId])
        try assertValidSelection(in: afterAddView)
        try assertRenderMatchesViewAndRuntime(
            fixture: fixture,
            workspaceId: workspaceId
        )

        _ = fixture.engine.syncWindows(
            (existingHandles + [pendingHandle]).filter { $0 != removableHandle },
            in: workspaceId,
            selectedNodeId: fixture.trackedNodeId,
            focusedHandle: fixture.trackedHandle
        )

        let afterRemoveView = try XCTUnwrap(fixture.engine.workspaceView(for: workspaceId))
        XCTAssertNil(afterRemoveView.windowsById[removableWindowId])
        try assertValidSelection(in: afterRemoveView)
        try assertRenderMatchesViewAndRuntime(
            fixture: fixture,
            workspaceId: workspaceId
        )
    }

    private func makeFixture() throws -> ZigNiriPhase0ReplayHarness.Fixture {
        try ZigNiriPhase0ReplayHarness.makeFixture(seed: defaultSeed())
    }

    private func defaultSeed() -> ZigNiriPhase0Scenario.Seed {
        ZigNiriPhase0Scenario.Seed(
            maxWindowsPerColumn: 2,
            maxVisibleColumns: 3,
            gap: 8,
            scale: 2,
            monitor: .init(
                displayId: 424242,
                width: 1440,
                height: 900,
                visibleInsets: .init(left: 0, right: 0, top: 0, bottom: 0)
            ),
            workspaces: [
                .init(name: "parity-primary", windowCount: 4),
                .init(name: "parity-secondary", windowCount: 2),
            ]
        )
    }

    private func runtimeSnapshot(
        for engine: ZigNiriEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) throws -> ZigNiriStateKernel.RuntimeStateExport {
        try XCTUnwrap(engine.benchmarkRuntimeSnapshot(workspaceId: workspaceId))
    }

    private func trackedColumnId(
        in view: ZigNiriWorkspaceView,
        windowId: NodeId
    ) throws -> NodeId {
        try XCTUnwrap(view.windowsById[windowId]?.columnId)
    }

    private func orderedWindowIds(in view: ZigNiriWorkspaceView) -> [NodeId] {
        var ordered: [NodeId] = []
        ordered.reserveCapacity(view.windowsById.count)
        var seen = Set<NodeId>()
        for column in view.columns {
            for windowId in column.windowIds where seen.insert(windowId).inserted {
                ordered.append(windowId)
            }
        }
        for windowId in view.windowsById.keys where seen.insert(windowId).inserted {
            ordered.append(windowId)
        }
        return ordered
    }

    private func assertValidSelection(
        in view: ZigNiriWorkspaceView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if view.windowsById.isEmpty {
            XCTAssertNil(view.selection, file: file, line: line)
            return
        }

        let selection = try XCTUnwrap(view.selection, file: file, line: line)
        if let selectedNodeId = selection.selectedNodeId {
            XCTAssertTrue(
                view.windowsById[selectedNodeId] != nil
                    || view.columns.contains(where: { $0.nodeId == selectedNodeId }),
                file: file,
                line: line
            )
        }
        if let focusedWindowId = selection.focusedWindowId {
            XCTAssertNotNil(view.windowsById[focusedWindowId], file: file, line: line)
        }
    }

    private func assertRenderMatchesViewAndRuntime(
        fixture: ZigNiriPhase0ReplayHarness.Fixture,
        workspaceId: WorkspaceDescriptor.ID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let view = try XCTUnwrap(
            fixture.engine.workspaceView(for: workspaceId),
            file: file,
            line: line
        )
        let rendered = fixture.engine.calculateLayout(
            ZigNiriLayoutRequest(
                workspaceId: workspaceId,
                monitorFrame: fixture.monitorFrame,
                screenFrame: nil,
                gaps: fixture.gaps,
                scale: fixture.workingArea.scale,
                workingArea: fixture.workingArea,
                orientation: .horizontal,
                viewportOffset: 0
            )
        )
        let snapshot = try runtimeSnapshot(
            for: fixture.engine,
            workspaceId: workspaceId
        )
        XCTAssertEqual(snapshot.windows.count, view.windowsById.count, file: file, line: line)
        XCTAssertEqual(
            Set(rendered.frames.keys),
            Set(view.windowsById.values.map(\.handle)),
            file: file,
            line: line
        )
    }

    private func makeWindowHandle() -> WindowHandle {
        WindowHandle(
            id: UUID(),
            pid: pid_t(ProcessInfo.processInfo.processIdentifier)
        )
    }
}
