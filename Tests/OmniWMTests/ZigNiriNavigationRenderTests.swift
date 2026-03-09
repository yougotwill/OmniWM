import CoreGraphics
import Foundation
import XCTest

@testable import OmniWM

@MainActor
final class ZigNiriNavigationRenderTests: XCTestCase {
    private struct Fixture {
        let engine: ZigNiriEngine
        let workspaceId: WorkspaceDescriptor.ID
        let handles: [WindowHandle]
        let monitorFrame: CGRect
        let workingArea: ZigNiriWorkingAreaContext
        let gaps: ZigNiriGaps
    }

    func testNavigationToOffscreenColumnThenCalculateLayoutReturnsFramesWithoutRuntimeIssue() throws {
        let fixture = try makeFixture(windowCount: 4, maxVisibleColumns: 2)
        let initial = fixture.engine.calculateLayout(makeLayoutRequest(fixture))
        XCTAssertEqual(initial.frames.count, fixture.handles.count)

        let navigation = fixture.engine.applyNavigation(
            .focusColumn(index: 2),
            in: fixture.workspaceId
        )
        XCTAssertNotNil(navigation.selection?.selectedNodeId)

        let view = try XCTUnwrap(fixture.engine.workspaceView(for: fixture.workspaceId))
        let targetColumnIndex = try XCTUnwrap(activeColumnIndex(for: fixture, view: view))
        XCTAssertEqual(targetColumnIndex, 2)
        XCTAssertTrue(
            fixture.engine.transitionViewportToColumn(
                in: fixture.workspaceId,
                requestedIndex: targetColumnIndex,
                gap: fixture.gaps.horizontal,
                viewportSpan: fixture.workingArea.workingFrame.width,
                animate: true,
                centerMode: .never,
                alwaysCenterSingleColumn: false,
                scale: fixture.workingArea.scale,
                displayRefreshRate: 60,
                reduceMotion: false
            )
        )

        let rendered = fixture.engine.calculateLayout(makeLayoutRequest(fixture))
        XCTAssertEqual(rendered.frames.count, view.windowsById.count)
        XCTAssertNil(fixture.engine.latestRuntimeRenderIssue(in: fixture.workspaceId))
    }

    func testRuntimeRenderMismatchReseedFailureFallsBackAndRecordsIssue() throws {
        let fixture = try makeFixture(windowCount: 4, maxVisibleColumns: 2)
        let initial = fixture.engine.calculateLayout(makeLayoutRequest(fixture))
        XCTAssertEqual(initial.frames.count, fixture.handles.count)

        var malformedView = try XCTUnwrap(fixture.engine.workspaceView(for: fixture.workspaceId))
        let duplicateWindowId = try XCTUnwrap(malformedView.columns.first?.windowIds.first)
        malformedView.columns.append(
            ZigNiriColumnView(
                nodeId: NodeId(),
                windowIds: [duplicateWindowId],
                display: .normal,
                activeWindowIndex: 0
            )
        )
        _ = fixture.engine.debugStoreWorkspaceView(
            malformedView,
            workspaceId: fixture.workspaceId
        )

        let fallback = fixture.engine.calculateLayout(makeLayoutRequest(fixture))
        XCTAssertEqual(fallback.frames.count, malformedView.windowsById.count)

        let issue = try XCTUnwrap(fixture.engine.latestRuntimeRenderIssue(in: fixture.workspaceId))
        XCTAssertEqual(issue.stage, .reseedSync)
        XCTAssertNotEqual(issue.rc, 0)
        XCTAssertEqual(issue.expectedColumnCount, malformedView.columns.count)
        XCTAssertEqual(issue.expectedWindowCount, malformedView.windowsById.count)
    }

    func testTransitionViewportToColumnOutOfRangeCancelsViewportMotion() throws {
        let fixture = try makeFixture(windowCount: 4, maxVisibleColumns: 2)
        _ = fixture.engine.calculateLayout(makeLayoutRequest(fixture))

        XCTAssertTrue(
            fixture.engine.beginViewportGesture(
                in: fixture.workspaceId,
                isTrackpad: true
            )
        )
        _ = fixture.engine.updateViewportGesture(
            in: fixture.workspaceId,
            deltaPixels: 48,
            timestamp: 1,
            gap: fixture.gaps.horizontal,
            viewportSpan: fixture.workingArea.workingFrame.width
        )
        XCTAssertTrue(fixture.engine.isViewportGestureActive(in: fixture.workspaceId))

        XCTAssertFalse(
            fixture.engine.transitionViewportToColumn(
                in: fixture.workspaceId,
                requestedIndex: 999,
                gap: fixture.gaps.horizontal,
                viewportSpan: fixture.workingArea.workingFrame.width,
                animate: true,
                centerMode: .never,
                alwaysCenterSingleColumn: false,
                scale: fixture.workingArea.scale,
                displayRefreshRate: 60,
                reduceMotion: false
            )
        )
        XCTAssertFalse(fixture.engine.isViewportGestureActive(in: fixture.workspaceId))
        XCTAssertNil(fixture.engine.latestRuntimeRenderIssue(in: fixture.workspaceId))
    }

    func testViewportTransitionAfterNavigationToLaterColumnKeepsRenderConsistent() throws {
        let fixture = try makeFixture(windowCount: 5, maxVisibleColumns: 2)
        _ = fixture.engine.calculateLayout(makeLayoutRequest(fixture))

        let navigation = fixture.engine.applyNavigation(
            .focusColumn(index: 3),
            in: fixture.workspaceId
        )
        XCTAssertNotNil(navigation.selection?.selectedNodeId)

        let view = try XCTUnwrap(fixture.engine.workspaceView(for: fixture.workspaceId))
        let targetColumnIndex = try XCTUnwrap(activeColumnIndex(for: fixture, view: view))
        XCTAssertEqual(targetColumnIndex, 3)

        let beforeOffset = fixture.engine.viewportOffset(in: fixture.workspaceId)
        XCTAssertTrue(
            fixture.engine.transitionViewportToColumn(
                in: fixture.workspaceId,
                requestedIndex: targetColumnIndex,
                gap: fixture.gaps.horizontal,
                viewportSpan: fixture.workingArea.workingFrame.width,
                animate: false,
                centerMode: .never,
                alwaysCenterSingleColumn: false,
                scale: fixture.workingArea.scale,
                displayRefreshRate: 60,
                reduceMotion: false
            )
        )
        XCTAssertNotEqual(beforeOffset, fixture.engine.viewportOffset(in: fixture.workspaceId))

        let rendered = fixture.engine.calculateLayout(makeLayoutRequest(fixture))
        XCTAssertEqual(rendered.frames.count, view.windowsById.count)
        XCTAssertNil(fixture.engine.latestRuntimeRenderIssue(in: fixture.workspaceId))
    }

    private func makeFixture(
        windowCount: Int,
        maxVisibleColumns: Int
    ) throws -> Fixture {
        let monitorFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let workingArea = ZigNiriWorkingAreaContext(
            workingFrame: monitorFrame,
            viewFrame: monitorFrame,
            scale: 2
        )
        let workspace = WorkspaceDescriptor(name: "zig-niri-nav-\(UUID().uuidString)")
        let handles = makeWindowHandles(count: windowCount)
        let engine = ZigNiriEngine(
            maxWindowsPerColumn: 3,
            maxVisibleColumns: maxVisibleColumns,
            infiniteLoop: false
        )

        _ = engine.syncWindows(
            handles,
            in: workspace.id,
            selectedNodeId: nil,
            focusedHandle: handles.first
        )

        guard let focusedHandle = handles.first,
              let focusedNodeId = engine.nodeId(for: focusedHandle)
        else {
            throw XCTSkip("fixture workspace missing focused node")
        }

        let nodeIds = try handles.map { handle in
            try XCTUnwrap(engine.nodeId(for: handle))
        }
        let columns = nodeIds.map { nodeId in
            ZigNiriColumnView(
                nodeId: NodeId(),
                windowIds: [nodeId],
                display: .normal,
                activeWindowIndex: 0
            )
        }
        let windowsById = Dictionary(
            uniqueKeysWithValues: zip(zip(handles, nodeIds), columns).map { entry in
                let ((handle, nodeId), column) = entry
                return (
                    nodeId,
                    ZigNiriWindowView(
                        nodeId: nodeId,
                        handle: handle,
                        columnId: column.nodeId,
                        frame: nil,
                        sizingMode: .normal,
                        height: .default,
                        isFocused: nodeId == focusedNodeId
                    )
                )
            }
        )
        _ = engine.debugStoreWorkspaceView(
            ZigNiriWorkspaceView(
                workspaceId: workspace.id,
                columns: columns,
                windowsById: windowsById,
                selection: ZigNiriSelection(
                    selectedNodeId: focusedNodeId,
                    focusedWindowId: focusedNodeId
                )
            ),
            workspaceId: workspace.id
        )
        XCTAssertTrue(engine.debugReseedRuntimeFromWorkspaceView(workspaceId: workspace.id))

        return Fixture(
            engine: engine,
            workspaceId: workspace.id,
            handles: handles,
            monitorFrame: monitorFrame,
            workingArea: workingArea,
            gaps: ZigNiriGaps(horizontal: 8, vertical: 8)
        )
    }

    private func makeLayoutRequest(_ fixture: Fixture) -> ZigNiriLayoutRequest {
        ZigNiriLayoutRequest(
            workspaceId: fixture.workspaceId,
            monitorFrame: fixture.monitorFrame,
            screenFrame: nil,
            gaps: fixture.gaps,
            scale: fixture.workingArea.scale,
            workingArea: fixture.workingArea,
            orientation: .horizontal,
            viewportOffset: 0
        )
    }

    private func activeColumnIndex(
        for fixture: Fixture,
        view: ZigNiriWorkspaceView
    ) -> Int? {
        if let selectedNodeId = view.selection?.selectedNodeId {
            if let selectedColumnIndex = view.columns.firstIndex(where: { $0.nodeId == selectedNodeId }) {
                return selectedColumnIndex
            }
            if let selectedWindowColumnIndex = view.columns.firstIndex(where: { $0.windowIds.contains(selectedNodeId) }) {
                return selectedWindowColumnIndex
            }
        }
        if let focusedWindowId = view.selection?.focusedWindowId,
           let focusedColumnIndex = view.columns.firstIndex(where: { $0.windowIds.contains(focusedWindowId) })
        {
            return focusedColumnIndex
        }
        if let firstPopulated = view.columns.firstIndex(where: { !$0.windowIds.isEmpty }) {
            return firstPopulated
        }
        return view.columns.isEmpty ? nil : 0
    }

    private func makeWindowHandles(count: Int) -> [WindowHandle] {
        let pid = pid_t(ProcessInfo.processInfo.processIdentifier)
        return (0 ..< count).map { _ in
            WindowHandle(id: UUID(), pid: pid)
        }
    }
}
