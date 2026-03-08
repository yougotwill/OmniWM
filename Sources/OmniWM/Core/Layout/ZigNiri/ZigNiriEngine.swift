import CZigLayout
import CoreGraphics
import Foundation
import QuartzCore
final class ZigNiriEngine {
    static let mutationAnimationDuration: TimeInterval = 0.18
    static let workspaceSwitchAnimationDuration: TimeInterval = 0.20
    private struct RuntimeSelectionAnchor {
        let windowId: NodeId?
        let columnId: NodeId?
        let rowIndex: Int?
    }
    private struct RuntimeStateMutationOutcome {
        let rc: Int32
        let applied: Bool
    }
    private struct RuntimeDecodeWindowIndexCache {
        let windowIds: [NodeId]
        let handles: [WindowHandle]
    }
    private struct ActiveInteractiveResize {
        let windowId: NodeId
        let workspaceId: WorkspaceDescriptor.ID
        let edges: ZigNiriResizeEdge
        let startMouseLocation: CGPoint
        let columnId: NodeId?
        let originalColumnSize: ProportionalSize?
        let originalColumnIsFullWidth: Bool
        let originalColumnWidth: CGFloat
        let minColumnWidth: CGFloat
        let maxColumnWidth: CGFloat
        let originalWindowHeight: WeightedSize?
        let originalWindowWeight: CGFloat
        let minWindowWeight: CGFloat
        let maxWindowWeight: CGFloat
        let pixelsPerWeight: CGFloat
        let originalViewOffset: CGFloat?
        let orientation: Monitor.Orientation
    }
    private var maxVisibleColumns: Int
    private var maxWindowsPerColumn: Int
    private var infiniteLoop: Bool
    private var workspaceViews: [WorkspaceDescriptor.ID: ZigNiriWorkspaceView] = [:]
    private var windowNodeIdsByHandle: [WindowHandle: NodeId] = [:]
    private var windowHandlesByNodeId: [NodeId: WindowHandle] = [:]
    private var windowHandlesByUUID: [UUID: WindowHandle] = [:]
    private var runtimeDecodeWindowIndexCacheByWorkspace: [WorkspaceDescriptor.ID: RuntimeDecodeWindowIndexCache] = [:]
    private var dirtyWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
    private var workspaceNodeIds: [WorkspaceDescriptor.ID: Set<NodeId>] = [:]
    private var nodeReferenceCounts: [NodeId: Int] = [:]
    private var layoutContexts: [WorkspaceDescriptor.ID: ZigNiriLayoutKernel.LayoutContext] = [:]
    private var windowSizingModesByNodeId: [NodeId: SizingMode] = [:]
    private var savedWindowHeightsByNodeId: [NodeId: WeightedSize] = [:]
    private var runtimeRenderFailureCountByWorkspace: [WorkspaceDescriptor.ID: Int] = [:]
    private var runtimeRenderMismatchCountByWorkspace: [WorkspaceDescriptor.ID: Int] = [:]
    private var interactiveMoveState: ZigNiriInteractiveMoveState?
    private var interactiveResizeState: ActiveInteractiveResize?
    private let timeProvider: () -> TimeInterval
    init(
        maxWindowsPerColumn: Int = 3,
        maxVisibleColumns: Int = 3,
        infiniteLoop: Bool = false,
        timeProvider: @escaping () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        self.maxWindowsPerColumn = max(1, min(10, maxWindowsPerColumn))
        self.maxVisibleColumns = max(1, min(5, maxVisibleColumns))
        self.infiniteLoop = infiniteLoop
        self.timeProvider = timeProvider
    }
    private func currentTime() -> TimeInterval {
        timeProvider()
    }
    func updateConfiguration(
        maxWindowsPerColumn: Int? = nil,
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil
    ) {
        if let maxWindowsPerColumn {
            self.maxWindowsPerColumn = max(1, min(10, maxWindowsPerColumn))
        }
        if let maxVisibleColumns {
            self.maxVisibleColumns = max(1, min(5, maxVisibleColumns))
        }
        if let infiniteLoop {
            self.infiniteLoop = infiniteLoop
        }
    }
    func nodeId(for handle: WindowHandle) -> NodeId? {
        windowNodeIdsByHandle[handle]
    }
    func windowHandle(for nodeId: NodeId) -> WindowHandle? {
        windowHandlesByNodeId[nodeId]
    }
    func workspaceView(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriWorkspaceView? {
        workspaceViews[workspaceId]
    }
    func benchmarkRuntimeSnapshot(
        workspaceId: WorkspaceDescriptor.ID
    ) -> ZigNiriStateKernel.RuntimeStateExport? {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return nil
        }
        switch ZigNiriStateKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(export):
            return export
        case .failure:
            return nil
        }
    }
    func selection(in workspaceId: WorkspaceDescriptor.ID) -> ZigNiriSelection? {
        workspaceViews[workspaceId]?.selection
    }
    func selectedNodeId(in workspaceId: WorkspaceDescriptor.ID) -> NodeId? {
        selection(in: workspaceId)?.selectedNodeId
    }

    func resolvedColumnSpans(
        for view: ZigNiriWorkspaceView,
        primarySpan: CGFloat,
        primaryGap _: CGFloat
    ) -> [CGFloat] {
        Array(repeating: primarySpan, count: view.columns.count)
    }
    @discardableResult
    func setSelection(_ selection: ZigNiriSelection?, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard ensureRuntimeContext(for: workspaceId) != nil else {
            return false
        }
        _ = applyWorkspace(.setSelection(selection), in: workspaceId)
        return true
    }
    @discardableResult
    func setSelectedNodeId(
        _ nodeId: NodeId?,
        in workspaceId: WorkspaceDescriptor.ID,
        focusedWindowId: NodeId? = nil
    ) -> Bool {
        let currentFocused = workspaceViews[workspaceId]?.selection?.focusedWindowId
        let resolvedFocused = focusedWindowId ?? (nodeId ?? currentFocused)
        if nodeId == nil, resolvedFocused == nil {
            return setSelection(nil, in: workspaceId)
        }
        return setSelection(
            ZigNiriSelection(
                selectedNodeId: nodeId,
                focusedWindowId: resolvedFocused
            ),
            in: workspaceId
        )
    }
    func hasActiveStructuralAnimation(
        in workspaceId: WorkspaceDescriptor.ID,
        at time: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        return ZigNiriStateKernel.isAnimationActive(
            context: context,
            sampleTime: time ?? currentTime()
        )
    }
    func pruneExpiredStructuralAnimations(
        at time: TimeInterval? = nil,
        workspaceId: WorkspaceDescriptor.ID? = nil
    ) {
        if let workspaceId {
            if let context = ensureRuntimeContext(for: workspaceId) {
                _ = ZigNiriStateKernel.isAnimationActive(
                    context: context,
                    sampleTime: time ?? currentTime()
                )
            }
            return
        }
        for context in layoutContexts.values {
            _ = ZigNiriStateKernel.isAnimationActive(
                context: context,
                sampleTime: time ?? currentTime()
            )
        }
    }
    func cancelStructuralAnimation(in workspaceId: WorkspaceDescriptor.ID) {
        guard let context = ensureRuntimeContext(for: workspaceId) else { return }
        _ = ZigNiriStateKernel.cancelAnimation(context: context)
    }
    func hasActiveAnimation(
        in workspaceId: WorkspaceDescriptor.ID,
        at time: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        let sampleTime = time ?? currentTime()
        let structural = ZigNiriStateKernel.isAnimationActive(
            context: context,
            sampleTime: sampleTime
        )
        let viewport = ZigNiriStateKernel.viewportStatus(
            context: context,
            sampleTime: sampleTime
        ).status?.isAnimating ?? false
        return structural || viewport
    }
    func viewportOffset(
        in workspaceId: WorkspaceDescriptor.ID,
        at time: TimeInterval? = nil
    ) -> CGFloat {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return 0
        }
        let sampleTime = time ?? currentTime()
        return ZigNiriStateKernel.viewportStatus(
            context: context,
            sampleTime: sampleTime
        ).status?.currentOffset ?? 0
    }
    func isViewportGestureActive(
        in workspaceId: WorkspaceDescriptor.ID,
        at time: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        let sampleTime = time ?? currentTime()
        return ZigNiriStateKernel.viewportStatus(
            context: context,
            sampleTime: sampleTime
        ).status?.isGesture ?? false
    }
    @discardableResult
    func beginViewportGesture(
        in workspaceId: WorkspaceDescriptor.ID,
        isTrackpad: Bool,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        return ZigNiriStateKernel.beginViewportGesture(
            context: context,
            sampleTime: sampleTime ?? currentTime(),
            isTrackpad: isTrackpad
        ) == 0
    }
    func updateViewportGesture(
        in workspaceId: WorkspaceDescriptor.ID,
        deltaPixels: CGFloat,
        timestamp: TimeInterval,
        gap: CGFloat,
        viewportSpan: CGFloat
    ) -> Int? {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return nil
        }
        let result = ZigNiriStateKernel.updateViewportGesture(
            context: context,
            deltaPixels: deltaPixels,
            timestamp: timestamp,
            gap: gap,
            viewportSpan: viewportSpan
        )
        guard result.rc == 0 else { return nil }
        return result.result?.selectionSteps
    }

    func updateViewportGesture(
        in workspaceId: WorkspaceDescriptor.ID,
        deltaPixels: CGFloat,
        timestamp: TimeInterval,
        spans _: [CGFloat],
        gap: CGFloat,
        viewportSpan: CGFloat
    ) -> Int? {
        updateViewportGesture(
            in: workspaceId,
            deltaPixels: deltaPixels,
            timestamp: timestamp,
            gap: gap,
            viewportSpan: viewportSpan
        )
    }
    @discardableResult
    func endViewportGesture(
        in workspaceId: WorkspaceDescriptor.ID,
        gap: CGFloat,
        viewportSpan: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        displayRefreshRate: Double,
        reduceMotion: Bool,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        let result = ZigNiriStateKernel.endViewportGesture(
            context: context,
            request: ZigNiriStateKernel.RuntimeViewportGestureEndRequest(
                gap: gap,
                viewportSpan: viewportSpan,
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                sampleTime: sampleTime ?? currentTime(),
                displayRefreshRate: displayRefreshRate,
                reduceMotion: reduceMotion
            )
        )
        return result.rc == 0
    }

    @discardableResult
    func endViewportGesture(
        in workspaceId: WorkspaceDescriptor.ID,
        spans _: [CGFloat],
        gap: CGFloat,
        viewportSpan: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        displayRefreshRate: Double,
        reduceMotion: Bool,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        endViewportGesture(
            in: workspaceId,
            gap: gap,
            viewportSpan: viewportSpan,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            displayRefreshRate: displayRefreshRate,
            reduceMotion: reduceMotion,
            sampleTime: sampleTime
        )
    }
    @discardableResult
    func transitionViewportToColumn(
        in workspaceId: WorkspaceDescriptor.ID,
        requestedIndex: Int,
        gap: CGFloat,
        viewportSpan: CGFloat,
        animate: Bool,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        scale: CGFloat,
        displayRefreshRate: Double,
        reduceMotion: Bool,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        let result = ZigNiriStateKernel.transitionViewportToColumn(
            context: context,
            request: ZigNiriStateKernel.RuntimeViewportTransitionRequest(
                requestedIndex: requestedIndex,
                gap: gap,
                viewportSpan: viewportSpan,
                centerMode: centerMode,
                alwaysCenterSingleColumn: alwaysCenterSingleColumn,
                animate: animate,
                scale: scale,
                sampleTime: sampleTime ?? currentTime(),
                displayRefreshRate: displayRefreshRate,
                reduceMotion: reduceMotion
            )
        )
        return result.rc == 0
    }

    @discardableResult
    func transitionViewportToColumn(
        in workspaceId: WorkspaceDescriptor.ID,
        requestedIndex: Int,
        spans _: [CGFloat],
        gap: CGFloat,
        viewportSpan: CGFloat,
        animate: Bool,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool,
        scale: CGFloat,
        displayRefreshRate: Double,
        reduceMotion: Bool,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        transitionViewportToColumn(
            in: workspaceId,
            requestedIndex: requestedIndex,
            gap: gap,
            viewportSpan: viewportSpan,
            animate: animate,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            scale: scale,
            displayRefreshRate: displayRefreshRate,
            reduceMotion: reduceMotion,
            sampleTime: sampleTime
        )
    }
    @discardableResult
    func setViewportOffset(
        in workspaceId: WorkspaceDescriptor.ID,
        offset: CGFloat
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        return ZigNiriStateKernel.setViewportOffset(
            context: context,
            offset: offset
        ) == 0
    }
    @discardableResult
    func cancelViewportMotion(
        in workspaceId: WorkspaceDescriptor.ID,
        sampleTime: TimeInterval? = nil
    ) -> Bool {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        return ZigNiriStateKernel.cancelViewportMotion(
            context: context,
            sampleTime: sampleTime ?? currentTime()
        ) == 0
    }
    @discardableResult
    func startWorkspaceSwitchAnimation(
        in workspaceId: WorkspaceDescriptor.ID,
        duration: TimeInterval = ZigNiriEngine.workspaceSwitchAnimationDuration
    ) -> Bool {
        _ = duration
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return false
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return false
        }
        return ZigNiriStateKernel.startWorkspaceSwitchAnimation(
            context: context,
            sampleTime: currentTime()
        ) == 0
    }
    @discardableResult
    func applyNavigation(
        _ request: ZigNiriNavigationRequest,
        in workspaceId: WorkspaceDescriptor.ID,
        orientation: Monitor.Orientation = .horizontal,
        selection: ZigNiriSelection? = nil
    ) -> ZigNiriNavigationResult {
        let latencyToken = ZigNiriLatencyProbe.begin(.navigationStep)
        defer { ZigNiriLatencyProbe.end(latencyToken) }

        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: nil,
                selection: workspaceViews[workspaceId]?.selection
            )
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: nil,
                selection: workspaceViews[workspaceId]?.selection
            )
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        guard let runtimeRequest = runtimeNavigationRequest(
            for: request,
            orientation: orientation,
            in: view
        )
        else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: view.selection?.selectedNodeId,
                selection: view.selection
            )
        }
        let outcome = ZigNiriStateKernel.applyNavigation(
            context: context,
            request: .init(request: runtimeRequest),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: view.selection?.selectedNodeId,
                selection: view.selection
            )
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(
                workspaceId: workspaceId,
                targetNodeId: view.selection?.selectedNodeId,
                selection: view.selection
            )
        }
        var projected = ensureWorkspaceView(for: workspaceId)
        let targetNodeId = outcome.targetWindowId
            ?? navigationFallbackTarget(for: request, in: projected)
            ?? projected.selection?.selectedNodeId
        projected.selection = ZigNiriSelection(
            selectedNodeId: targetNodeId,
            focusedWindowId: outcome.targetWindowId ?? projected.selection?.focusedWindowId
        )
        projected = storeWorkspaceView(projected, workspaceId: workspaceId)
        return ZigNiriNavigationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            targetNodeId: targetNodeId,
            selection: projected.selection,
            wrapped: false
        )
    }
    @discardableResult
    func applyMutation(
        _ request: ZigNiriMutationRequest,
        in workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection? = nil
    ) -> ZigNiriMutationResult {
        let latencyToken: (hotPath: ZigNiriLatencyHotPath, startedAt: UInt64)?
        switch request {
        case .moveWindow:
            latencyToken = ZigNiriLatencyProbe.begin(.windowMove)
        default:
            latencyToken = nil
        }
        defer { ZigNiriLatencyProbe.end(latencyToken) }

        guard ensureRuntimeContext(for: workspaceId) != nil else {
            return .noChange(
                workspaceId: workspaceId,
                selection: workspaceViews[workspaceId]?.selection
            )
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(
                workspaceId: workspaceId,
                selection: workspaceViews[workspaceId]?.selection
            )
        }
        switch request {
        case let .setColumnDisplay(columnId, display):
            return applyColumnDisplayMutation(
                columnId: columnId,
                display: display,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .setColumnActiveWindow(columnId, windowIndex):
            return applyColumnActiveWindowMutation(
                columnId: columnId,
                windowIndex: windowIndex,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .setColumnWidth(columnId, width):
            return applyColumnWidthMutation(
                columnId: columnId,
                width: width,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .toggleColumnFullWidth(columnId):
            return applyColumnFullWidthToggleMutation(
                columnId: columnId,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .setWindowSizing(windowId, mode):
            return applyWindowSizingMutation(
                windowId: windowId,
                mode: mode,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .setWindowHeight(windowId, height):
            return applyWindowHeightMutation(
                windowId: windowId,
                height: height,
                workspaceId: workspaceId,
                selection: selection
            )
        case let .moveWindow(windowId, direction, orientation):
            guard let op = mutationOpForWindowMove(
                direction: direction,
                orientation: orientation,
                swap: false
            )
            else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: op,
                    sourceWindowId: windowId,
                    direction: direction
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .swapWindow(windowId, direction, orientation):
            guard let op = mutationOpForWindowMove(
                direction: direction,
                orientation: orientation,
                swap: true
            )
            else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: op,
                    sourceWindowId: windowId,
                    direction: direction
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .moveColumn(columnId, direction):
            guard direction == .left || direction == .right else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .moveColumn,
                    sourceColumnId: columnId,
                    direction: direction
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .consumeWindow(windowId, direction):
            guard direction == .left || direction == .right else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .consumeWindow,
                    sourceWindowId: windowId,
                    direction: direction,
                    placeholderColumnId: UUID()
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .expelWindow(windowId, direction):
            guard direction == .left || direction == .right else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .expelWindow,
                    sourceWindowId: windowId,
                    direction: direction,
                    createdColumnId: UUID(),
                    placeholderColumnId: UUID()
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .insertWindowByMove(sourceWindowId, targetWindowId, position):
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .insertWindowByMove,
                    sourceWindowId: sourceWindowId,
                    targetWindowId: targetWindowId,
                    insertPosition: position
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .insertWindowInNewColumn(windowId, insertIndex):
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .insertWindowInNewColumn,
                    sourceWindowId: windowId,
                    insertColumnIndex: insertIndex,
                    maxVisibleColumnsOverride: maxVisibleColumns,
                    createdColumnId: UUID(),
                    placeholderColumnId: UUID()
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case .balanceSizes:
            return applyRuntimeMutation(
                RuntimeMutationSpec(
                    op: .balanceSizes,
                    maxVisibleColumnsOverride: maxVisibleColumns
                ),
                workspaceId: workspaceId,
                selection: selection
            )
        case let .removeWindow(windowId):
            return applyRemoveWindowMutation(
                windowId: windowId,
                workspaceId: workspaceId,
                selection: selection
            )
        case .custom:
            var view = ensureWorkspaceView(for: workspaceId)
            if let selection {
                view.selection = selection
                view = storeWorkspaceView(view, workspaceId: workspaceId)
            }
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }
    }
    @discardableResult
    func applyWorkspace(
        _ request: ZigNiriWorkspaceRequest,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> ZigNiriMutationResult {
        let latencyToken: (hotPath: ZigNiriLatencyHotPath, startedAt: UInt64)?
        switch request {
        case .moveWindow:
            latencyToken = ZigNiriLatencyProbe.begin(.workspaceMove)
        default:
            latencyToken = nil
        }
        defer { ZigNiriLatencyProbe.end(latencyToken) }

        switch request {
        case .ensureWorkspace:
            let existed = layoutContexts[workspaceId] != nil
            guard ensureRuntimeContext(for: workspaceId) != nil else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let view = ensureWorkspaceView(for: workspaceId)
            return ZigNiriMutationResult(
                applied: !existed,
                workspaceId: workspaceId,
                selection: view.selection,
                affectedNodeIds: [],
                removedNodeIds: []
            )
        case .clearWorkspace:
            guard let context = ensureRuntimeContext(for: workspaceId) else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let removedIds: [NodeId] = {
                switch ZigNiriStateKernel.snapshotRuntimeStateResult(context: context) {
                case let .success(export):
                    return export.windows.map(\.windowId)
                case .failure:
                    return []
                }
            }()
            let resetColumnId = workspaceViews[workspaceId]?.columns.first?.nodeId
            let outcome = ZigNiriStateKernel.applyMutation(
                context: context,
                request: .init(
                    request: ZigNiriStateKernel.MutationRequest(
                        op: .clearWorkspace
                    ),
                    placeholderColumnId: resetColumnId?.uuid
                ),
                sampleTime: currentTime()
            )
            guard outcome.rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            if outcome.applied {
                markWorkspaceDirty(workspaceId)
            }
            guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            var view = ensureWorkspaceView(for: workspaceId)
            view.selection = nil
            view = storeWorkspaceView(view, workspaceId: workspaceId, allowNilWhenRequested: true)
            return ZigNiriMutationResult(
                applied: outcome.applied,
                workspaceId: workspaceId,
                selection: nil,
                affectedNodeIds: [],
                removedNodeIds: outcome.applied ? removedIds : []
            )
        case let .setSelection(selection):
            guard ensureRuntimeContext(for: workspaceId) != nil else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            var view = ensureWorkspaceView(for: workspaceId)
            view.selection = selection
            view = storeWorkspaceView(view, workspaceId: workspaceId, allowNilWhenRequested: true)
            return ZigNiriMutationResult(
                applied: true,
                workspaceId: workspaceId,
                selection: view.selection,
                affectedNodeIds: [],
                removedNodeIds: []
            )
        case let .moveWindow(windowId, targetWorkspaceId):
            guard let sourceContext = ensureRuntimeContext(for: workspaceId),
                  let targetContext = ensureRuntimeContext(for: targetWorkspaceId)
            else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let sourcePreFrames = captureNodeFrames(in: workspaceId)
            let targetPreFrames = captureNodeFrames(in: targetWorkspaceId)
            let outcome = ZigNiriStateKernel.applyWorkspace(
                sourceContext: sourceContext,
                targetContext: targetContext,
                request: .init(
                    request: ZigNiriStateKernel.WorkspaceRequest(
                        op: .moveWindowToWorkspace,
                        sourceWindowId: windowId,
                        maxVisibleColumns: maxVisibleColumns
                    ),
                    targetCreatedColumnId: UUID(),
                    sourcePlaceholderColumnId: UUID()
                ),
                sampleTime: currentTime()
            )
            guard outcome.rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
            if structuralAnimationActive {
                scheduleStructuralAnimation(
                    in: workspaceId,
                    from: sourcePreFrames
                )
                scheduleStructuralAnimation(
                    in: targetWorkspaceId,
                    from: targetPreFrames
                )
            }
            let targetSynced: Bool
            if outcome.applied,
               let targetDelta = outcome.targetDelta,
               syncWorkspaceView(
                   workspaceId: targetWorkspaceId,
                   export: runtimeStateExport(from: targetDelta)
               )
            {
                targetSynced = true
            } else if outcome.applied {
                markWorkspaceDirty(targetWorkspaceId)
                targetSynced = ensureSyncedViewIfNeeded(workspaceId: targetWorkspaceId)
            } else {
                targetSynced = true
            }
            let sourceSynced: Bool
            if outcome.applied,
               let sourceDelta = outcome.sourceDelta,
               syncWorkspaceView(
                   workspaceId: workspaceId,
                   export: runtimeStateExport(from: sourceDelta)
               )
            {
                sourceSynced = true
            } else if outcome.applied {
                markWorkspaceDirty(workspaceId)
                sourceSynced = ensureSyncedViewIfNeeded(workspaceId: workspaceId)
            } else {
                sourceSynced = true
            }
            guard sourceSynced, targetSynced else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            var sourceView = ensureWorkspaceView(for: workspaceId)
            if let sourceSelectionWindowId = outcome.sourceSelectionWindowId {
                sourceView.selection = ZigNiriSelection(
                    selectedNodeId: sourceSelectionWindowId,
                    focusedWindowId: sourceSelectionWindowId
                )
            } else if sourceView.windowsById.isEmpty {
                sourceView.selection = nil
            }
            _ = storeWorkspaceView(
                sourceView,
                workspaceId: workspaceId,
                allowNilWhenRequested: true
            )
            var targetView = ensureWorkspaceView(for: targetWorkspaceId)
            if let targetSelectionWindowId = outcome.targetSelectionWindowId ?? outcome.movedWindowId {
                targetView.selection = ZigNiriSelection(
                    selectedNodeId: targetSelectionWindowId,
                    focusedWindowId: targetSelectionWindowId
                )
            }
            targetView = storeWorkspaceView(
                targetView,
                workspaceId: targetWorkspaceId,
                allowNilWhenRequested: true
            )
            return ZigNiriMutationResult(
                applied: outcome.applied,
                workspaceId: targetWorkspaceId,
                selection: targetView.selection,
                affectedNodeIds: [windowId],
                removedNodeIds: [],
                structuralAnimationActive: structuralAnimationActive
            )
        case let .moveColumn(columnId, targetWorkspaceId):
            guard let sourceContext = ensureRuntimeContext(for: workspaceId),
                  let targetContext = ensureRuntimeContext(for: targetWorkspaceId)
            else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let sourcePreFrames = captureNodeFrames(in: workspaceId)
            let targetPreFrames = captureNodeFrames(in: targetWorkspaceId)
            let outcome = ZigNiriStateKernel.applyWorkspace(
                sourceContext: sourceContext,
                targetContext: targetContext,
                request: .init(
                    request: ZigNiriStateKernel.WorkspaceRequest(
                        op: .moveColumnToWorkspace,
                        sourceColumnId: columnId
                    ),
                    sourcePlaceholderColumnId: UUID()
                ),
                sampleTime: currentTime()
            )
            guard outcome.rc == 0 else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
            if structuralAnimationActive {
                scheduleStructuralAnimation(
                    in: workspaceId,
                    from: sourcePreFrames
                )
                scheduleStructuralAnimation(
                    in: targetWorkspaceId,
                    from: targetPreFrames
                )
            }
            let targetSynced: Bool
            if outcome.applied,
               let targetDelta = outcome.targetDelta,
               syncWorkspaceView(
                   workspaceId: targetWorkspaceId,
                   export: runtimeStateExport(from: targetDelta)
               )
            {
                targetSynced = true
            } else if outcome.applied {
                markWorkspaceDirty(targetWorkspaceId)
                targetSynced = ensureSyncedViewIfNeeded(workspaceId: targetWorkspaceId)
            } else {
                targetSynced = true
            }
            let sourceSynced: Bool
            if outcome.applied,
               let sourceDelta = outcome.sourceDelta,
               syncWorkspaceView(
                   workspaceId: workspaceId,
                   export: runtimeStateExport(from: sourceDelta)
               )
            {
                sourceSynced = true
            } else if outcome.applied {
                markWorkspaceDirty(workspaceId)
                sourceSynced = ensureSyncedViewIfNeeded(workspaceId: workspaceId)
            } else {
                sourceSynced = true
            }
            guard sourceSynced, targetSynced else {
                return .noChange(
                    workspaceId: workspaceId,
                    selection: workspaceViews[workspaceId]?.selection
                )
            }
            var sourceView = ensureWorkspaceView(for: workspaceId)
            if let sourceSelectionWindowId = outcome.sourceSelectionWindowId {
                sourceView.selection = ZigNiriSelection(
                    selectedNodeId: sourceSelectionWindowId,
                    focusedWindowId: sourceSelectionWindowId
                )
            } else if sourceView.windowsById.isEmpty {
                sourceView.selection = nil
            }
            _ = storeWorkspaceView(
                sourceView,
                workspaceId: workspaceId,
                allowNilWhenRequested: true
            )
            var targetView = ensureWorkspaceView(for: targetWorkspaceId)
            if let targetSelectionWindowId = outcome.targetSelectionWindowId {
                targetView.selection = ZigNiriSelection(
                    selectedNodeId: targetSelectionWindowId,
                    focusedWindowId: targetSelectionWindowId
                )
            }
            targetView = storeWorkspaceView(
                targetView,
                workspaceId: targetWorkspaceId,
                allowNilWhenRequested: true
            )
            return ZigNiriMutationResult(
                applied: outcome.applied,
                workspaceId: targetWorkspaceId,
                selection: targetView.selection,
                affectedNodeIds: [columnId],
                removedNodeIds: [],
                structuralAnimationActive: structuralAnimationActive
            )
        }
    }
    @discardableResult
    func syncWindows(
        _ handles: [WindowHandle],
        in workspaceId: WorkspaceDescriptor.ID,
        selectedNodeId: NodeId?,
        focusedHandle: WindowHandle? = nil
    ) -> Set<WindowHandle> {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return []
        }
        if let view = workspaceViews[workspaceId],
           !dirtyWorkspaceIds.contains(workspaceId),
           Set(view.windowsById.values.map(\.handle)) == Set(handles)
        {
            var updatedView = view
            let focusedNodeId = focusedHandle.flatMap { windowNodeIdsByHandle[$0] }
            let selectedForView = selectedNodeId ?? focusedNodeId ?? updatedView.selection?.selectedNodeId
            updatedView.selection = ZigNiriSelection(
                selectedNodeId: selectedForView,
                focusedWindowId: focusedNodeId ?? updatedView.selection?.focusedWindowId
            )
            _ = storeWorkspaceView(updatedView, workspaceId: workspaceId)
            return []
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        let incomingHandles = Set(handles)
        var incomingByUUID: [UUID: WindowHandle] = [:]
        incomingByUUID.reserveCapacity(handles.count)
        var nextWindowNodeIdsByHandle = windowNodeIdsByHandle
        var nextWindowHandlesByNodeId = windowHandlesByNodeId
        var nextWindowHandlesByUUID = windowHandlesByUUID
        for handle in handles {
            incomingByUUID[handle.id] = handle
            nextWindowHandlesByUUID[handle.id] = handle
        }
        var export: ZigNiriStateKernel.RuntimeStateExport
        switch ZigNiriStateKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case .failure:
            export = runtimeBootstrapExport(for: workspaceId)
        }
        var removedNodeIds = Set<NodeId>()
        var keptWindows: [ZigNiriStateKernel.RuntimeWindowState] = []
        keptWindows.reserveCapacity(export.windows.count)
        for runtimeWindow in export.windows {
            let mappedHandle = nextWindowHandlesByNodeId[runtimeWindow.windowId]
                ?? incomingByUUID[runtimeWindow.windowId.uuid]
            guard let handle = mappedHandle else {
                removedNodeIds.insert(runtimeWindow.windowId)
                continue
            }
            nextWindowHandlesByNodeId[runtimeWindow.windowId] = handle
            nextWindowNodeIdsByHandle[handle] = runtimeWindow.windowId
            if incomingHandles.contains(handle) {
                keptWindows.append(runtimeWindow)
            } else {
                removedNodeIds.insert(runtimeWindow.windowId)
            }
        }
        export.windows = keptWindows
        if export.columns.isEmpty {
            export.columns = [defaultRuntimeColumnState(columnId: NodeId())]
        }
        normalizeRuntimeExport(&export)
        let selectedAnchorId = selectedNodeId ?? workspaceViews[workspaceId]?.selection?.selectedNodeId
        let preferredColumnId: NodeId = {
            let view = workspaceViews[workspaceId]
            let anchor = runtimeSelectionAnchor(
                selectedNodeId: selectedAnchorId,
                in: view
            )
            return anchor?.columnId ?? export.columns.first!.columnId
        }()
        var existingWindowIds = Set(export.windows.map(\.windowId))
        var addedWindowIds: [NodeId] = []
        for handle in handles {
            let nodeId: NodeId
            if let existingNodeId = nextWindowNodeIdsByHandle[handle] {
                nodeId = existingNodeId
            } else {
                nodeId = NodeId(uuid: handle.id)
                nextWindowNodeIdsByHandle[handle] = nodeId
            }
            nextWindowHandlesByNodeId[nodeId] = handle
            nextWindowHandlesByUUID[handle.id] = handle
            if existingWindowIds.contains(nodeId) {
                continue
            }
            let targetColumnId: NodeId
            if export.windows.isEmpty,
               let emptyColumnIndex = export.columns.firstIndex(where: { $0.windowCount == 0 })
            {
                targetColumnId = export.columns[emptyColumnIndex].columnId
            } else {
                let preferredIndex = export.columns.firstIndex(where: { $0.columnId == preferredColumnId })
                    ?? max(0, export.columns.count - 1)
                let insertedColumnId = NodeId()
                export.columns.insert(
                    defaultRuntimeColumnState(columnId: insertedColumnId),
                    at: min(preferredIndex + 1, export.columns.count)
                )
                targetColumnId = insertedColumnId
            }
            export.windows.append(
                ZigNiriStateKernel.RuntimeWindowState(
                    windowId: nodeId,
                    columnId: targetColumnId,
                    columnIndex: 0,
                    sizeValue: 1.0,
                    heightKind: ZigNiriStateKernel.heightKindAuto,
                    heightValue: 1.0
                )
            )
            existingWindowIds.insert(nodeId)
            addedWindowIds.append(nodeId)
        }
        normalizeRuntimeExport(&export)
        let seedRC = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: export
        )
        guard seedRC == 0 else {
            return []
        }
        let removedHandles = Set(
            removedNodeIds.compactMap { windowHandlesByNodeId[$0] ?? nextWindowHandlesByNodeId[$0] }
        )
        windowNodeIdsByHandle = nextWindowNodeIdsByHandle
        windowHandlesByNodeId = nextWindowHandlesByNodeId
        windowHandlesByUUID = nextWindowHandlesByUUID
        let synced = syncWorkspaceView(workspaceId: workspaceId, export: export)
            || {
                markWorkspaceDirty(workspaceId)
                return ensureSyncedViewIfNeeded(workspaceId: workspaceId)
            }()
        guard synced else {
            return removedHandles
        }
        var view = ensureWorkspaceView(for: workspaceId)
        let focusedNodeId = focusedHandle.flatMap { windowNodeIdsByHandle[$0] }
        let selectedForView = selectedNodeId ?? focusedNodeId ?? view.selection?.selectedNodeId
        view.selection = ZigNiriSelection(
            selectedNodeId: selectedForView,
            focusedWindowId: focusedNodeId ?? view.selection?.focusedWindowId
        )
        _ = storeWorkspaceView(view, workspaceId: workspaceId)
        if !addedWindowIds.isEmpty || !removedNodeIds.isEmpty {
            scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        }
        return removedHandles
    }
    private struct LayoutProjectionSnapshot {
        let frames: [WindowHandle: CGRect]
        let hiddenHandles: [WindowHandle: HideSide]
    }
    private struct RuntimeRenderDecodedOutput {
        let snapshot: LayoutProjectionSnapshot
        let mappedWindowCount: Int
        let missingWindowIds: [NodeId]
        let unmappedOutputWindowIds: [NodeId]
    }
    private struct RuntimeRenderAttempt {
        let rc: Int32
        let decoded: RuntimeRenderDecodedOutput?
        let animationActive: Bool
    }
    func calculateLayout(_ request: ZigNiriLayoutRequest) -> ZigNiriLayoutResult {
        let latencyToken = ZigNiriLatencyProbe.begin(.layoutPass)
        defer { ZigNiriLatencyProbe.end(latencyToken) }
        let persistFrames = !ZigNiriLatencyProbe.isEnabled

        guard let context = ensureRuntimeContext(for: request.workspaceId),
              ensureSyncedViewIfNeeded(workspaceId: request.workspaceId),
              let view = workspaceViews[request.workspaceId]
        else {
            return fallbackLayoutResult(for: request.workspaceId)
        }
        guard !view.columns.isEmpty else {
            return ZigNiriLayoutResult(frames: [:], hiddenHandles: [:], isAnimating: false)
        }
        let firstAttempt = attemptRuntimeRenderFromState(
            context: context,
            request: request,
            view: view
        )
        if let decoded = firstAttempt.decoded,
           firstAttempt.rc == 0,
           !isRuntimeRenderMismatch(decoded, view: view)
        {
            var persistedView = view
            if persistFrames {
                persistCompositedFrames(decoded.snapshot.frames, in: &persistedView)
                workspaceViews[request.workspaceId] = persistedView
            }
            return ZigNiriLayoutResult(
                frames: decoded.snapshot.frames,
                hiddenHandles: decoded.snapshot.hiddenHandles,
                isAnimating: firstAttempt.animationActive
            )
        }
        if firstAttempt.rc == 0 {
            runtimeRenderMismatchCountByWorkspace[request.workspaceId, default: 0] += 1
        } else {
            runtimeRenderFailureCountByWorkspace[request.workspaceId, default: 0] += 1
        }
        guard reseedRuntimeFromWorkspaceView(
            workspaceId: request.workspaceId,
            context: context
        ),
            ensureSyncedViewIfNeeded(workspaceId: request.workspaceId),
            let retryView = workspaceViews[request.workspaceId]
        else {
            assertionFailure("Runtime render reseed failed for workspace \(request.workspaceId)")
            return fallbackLayoutResult(for: request.workspaceId)
        }
        let retryAttempt = attemptRuntimeRenderFromState(
            context: context,
            request: request,
            view: retryView
        )
        if let decoded = retryAttempt.decoded,
           retryAttempt.rc == 0,
           !isRuntimeRenderMismatch(decoded, view: retryView)
        {
            var persistedView = retryView
            if persistFrames {
                persistCompositedFrames(decoded.snapshot.frames, in: &persistedView)
                workspaceViews[request.workspaceId] = persistedView
            }
            return ZigNiriLayoutResult(
                frames: decoded.snapshot.frames,
                hiddenHandles: decoded.snapshot.hiddenHandles,
                isAnimating: retryAttempt.animationActive
            )
        }
        if retryAttempt.rc == 0 {
            runtimeRenderMismatchCountByWorkspace[request.workspaceId, default: 0] += 1
        } else {
            runtimeRenderFailureCountByWorkspace[request.workspaceId, default: 0] += 1
        }
        assertionFailure("Runtime render from state failed after reseed retry in workspace \(request.workspaceId)")
        return fallbackLayoutResult(for: request.workspaceId)
    }
    private func attemptRuntimeRenderFromState(
        context: ZigNiriLayoutKernel.LayoutContext,
        request: ZigNiriLayoutRequest,
        view: ZigNiriWorkspaceView
    ) -> RuntimeRenderAttempt {
        let runtimeRequest = runtimeRenderRequestFromState(
            for: request,
            view: view
        )
        let render = ZigNiriStateKernel.renderRuntimeFromState(
            context: context,
            request: runtimeRequest
        )
        guard render.rc == 0 else {
            return RuntimeRenderAttempt(
                rc: render.rc,
                decoded: nil,
                animationActive: false
            )
        }
        return RuntimeRenderAttempt(
            rc: render.rc,
            decoded: decodeRuntimeRenderOutput(
                render.output,
                workspaceId: request.workspaceId,
                view: view
            ),
            animationActive: render.output.animationActive
        )
    }
    private func runtimeRenderRequestFromState(
        for request: ZigNiriLayoutRequest,
        view: ZigNiriWorkspaceView
    ) -> ZigNiriStateKernel.RuntimeRenderFromStateRequest {
        let workingFrame = request.workingArea?.workingFrame ?? request.monitorFrame
        let screenFrame = request.screenFrame ?? request.monitorFrame
        let primaryGap = request.orientation == .horizontal ? request.gaps.horizontal : request.gaps.vertical
        let secondaryGap = request.orientation == .horizontal ? request.gaps.vertical : request.gaps.horizontal
        let primarySpan = request.orientation == .horizontal ? workingFrame.width : workingFrame.height
        let viewportSpan = max(0, primarySpan)
        let fullscreenWindowId = view.windowsById.values
            .first(where: { $0.sizingMode == .fullscreen })?
            .nodeId
        let fullscreenFrame = request.workingArea?.workingFrame ?? screenFrame
        return ZigNiriStateKernel.RuntimeRenderFromStateRequest(
            expectedColumnCount: view.columns.count,
            expectedWindowCount: view.windowsById.count,
            workingFrame: workingFrame,
            viewFrame: screenFrame,
            fullscreenFrame: fullscreenFrame,
            primaryGap: primaryGap,
            secondaryGap: secondaryGap,
            viewportSpan: viewportSpan,
            workspaceOffset: 0,
            fullscreenWindowId: fullscreenWindowId,
            scale: request.scale,
            orientation: request.orientation,
            sampleTime: request.animationTime ?? currentTime()
        )
    }
    private func reseedRuntimeFromWorkspaceView(
        workspaceId: WorkspaceDescriptor.ID,
        context: ZigNiriLayoutKernel.LayoutContext
    ) -> Bool {
        let export = runtimeBootstrapExport(for: workspaceId)
        let rc = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: export
        )
        if rc == 0 {
            if !syncWorkspaceView(workspaceId: workspaceId, export: export) {
                markWorkspaceDirty(workspaceId)
            }
            return true
        }
        return false
    }
    private func decodeRuntimeRenderOutput(
        _ output: ZigNiriStateKernel.RuntimeRenderOutput,
        workspaceId: WorkspaceDescriptor.ID,
        view: ZigNiriWorkspaceView
    ) -> RuntimeRenderDecodedOutput {
        if let decoded = decodeRuntimeRenderOutputFromIndexCache(
            output,
            workspaceId: workspaceId,
            view: view
        ) {
            return decoded
        }
        return decodeRuntimeRenderOutputByNodeLookup(output, view: view)
    }
    private func decodeRuntimeRenderOutputFromIndexCache(
        _ output: ZigNiriStateKernel.RuntimeRenderOutput,
        workspaceId: WorkspaceDescriptor.ID,
        view: ZigNiriWorkspaceView
    ) -> RuntimeRenderDecodedOutput? {
        guard let cache = runtimeDecodeWindowIndexCacheByWorkspace[workspaceId],
              cache.windowIds.count == output.windows.count,
              cache.handles.count == output.windows.count
        else {
            return nil
        }
        var frames: [WindowHandle: CGRect] = [:]
        var hiddenHandles: [WindowHandle: HideSide] = [:]
        frames.reserveCapacity(output.windows.count)
        for (index, raw) in output.windows.enumerated() {
            let windowId = ZigNiriStateKernel.nodeId(from: raw.window_id)
            guard windowId == cache.windowIds[index] else {
                return nil
            }
            let handle = cache.handles[index]
            frames[handle] = CGRect(
                x: raw.animated_x,
                y: raw.animated_y,
                width: raw.animated_width,
                height: raw.animated_height
            )
            switch Int(raw.hide_side) {
            case Int(OMNI_NIRI_HIDE_LEFT.rawValue):
                hiddenHandles[handle] = .left
            case Int(OMNI_NIRI_HIDE_RIGHT.rawValue):
                hiddenHandles[handle] = .right
            default:
                break
            }
        }
        let mappedWindowIds = Set(cache.windowIds)
        let missingWindowIds = view.windowsById.keys.filter { !mappedWindowIds.contains($0) }
        return RuntimeRenderDecodedOutput(
            snapshot: LayoutProjectionSnapshot(frames: frames, hiddenHandles: hiddenHandles),
            mappedWindowCount: mappedWindowIds.count,
            missingWindowIds: missingWindowIds,
            unmappedOutputWindowIds: []
        )
    }
    private func decodeRuntimeRenderOutputByNodeLookup(
        _ output: ZigNiriStateKernel.RuntimeRenderOutput,
        view: ZigNiriWorkspaceView
    ) -> RuntimeRenderDecodedOutput {
        var frames: [WindowHandle: CGRect] = [:]
        var hiddenHandles: [WindowHandle: HideSide] = [:]
        frames.reserveCapacity(output.windows.count)
        var mappedWindowIds = Set<NodeId>()
        mappedWindowIds.reserveCapacity(output.windows.count)
        var unmappedOutputWindowIds: [NodeId] = []
        for raw in output.windows {
            let windowId = ZigNiriStateKernel.nodeId(from: raw.window_id)
            guard mappedWindowIds.insert(windowId).inserted else {
                unmappedOutputWindowIds.append(windowId)
                continue
            }
            guard let window = view.windowsById[windowId] else {
                unmappedOutputWindowIds.append(windowId)
                continue
            }
            frames[window.handle] = CGRect(
                x: raw.animated_x,
                y: raw.animated_y,
                width: raw.animated_width,
                height: raw.animated_height
            )
            switch Int(raw.hide_side) {
            case Int(OMNI_NIRI_HIDE_LEFT.rawValue):
                hiddenHandles[window.handle] = .left
            case Int(OMNI_NIRI_HIDE_RIGHT.rawValue):
                hiddenHandles[window.handle] = .right
            default:
                break
            }
        }
        let missingWindowIds = view.windowsById.keys.filter { !mappedWindowIds.contains($0) }
        return RuntimeRenderDecodedOutput(
            snapshot: LayoutProjectionSnapshot(frames: frames, hiddenHandles: hiddenHandles),
            mappedWindowCount: mappedWindowIds.count,
            missingWindowIds: missingWindowIds,
            unmappedOutputWindowIds: unmappedOutputWindowIds
        )
    }
    private func isRuntimeRenderMismatch(
        _ decoded: RuntimeRenderDecodedOutput,
        view: ZigNiriWorkspaceView
    ) -> Bool {
        decoded.mappedWindowCount != view.windowsById.count
            || !decoded.missingWindowIds.isEmpty
            || !decoded.unmappedOutputWindowIds.isEmpty
    }
    private func fallbackLayoutResult(
        for workspaceId: WorkspaceDescriptor.ID,
        isAnimating: Bool = false
    ) -> ZigNiriLayoutResult {
        guard let view = workspaceViews[workspaceId] else {
            return ZigNiriLayoutResult(frames: [:], hiddenHandles: [:], isAnimating: isAnimating)
        }
        var frames: [WindowHandle: CGRect] = [:]
        frames.reserveCapacity(view.windowsById.count)
        for window in view.windowsById.values {
            if let frame = window.frame {
                frames[window.handle] = frame
            }
        }
        return ZigNiriLayoutResult(frames: frames, hiddenHandles: [:], isAnimating: isAnimating)
    }
    private func persistCompositedFrames(
        _ frames: [WindowHandle: CGRect],
        in view: inout ZigNiriWorkspaceView
    ) {
        for (windowId, existingWindow) in view.windowsById {
            var window = existingWindow
            window.frame = frames[window.handle]
            view.windowsById[windowId] = window
        }
    }
    func hitTestResize(
        at point: CGPoint,
        _ request: ZigNiriHitTestRequest
    ) -> ZigNiriResizeHitResult? {
        guard let tiled = hitTestTiled(at: point, request) else {
            return nil
        }
        let threshold = max(2.0, 8.0 / max(request.scale, 0.5))
        var edges: ZigNiriResizeEdge = []
        if abs(point.x - tiled.windowFrame.minX) <= threshold {
            edges.insert(.left)
        }
        if abs(point.x - tiled.windowFrame.maxX) <= threshold {
            edges.insert(.right)
        }
        if abs(point.y - tiled.windowFrame.minY) <= threshold {
            edges.insert(.top)
        }
        if abs(point.y - tiled.windowFrame.maxY) <= threshold {
            edges.insert(.bottom)
        }
        guard !edges.isEmpty else {
            return nil
        }
        return ZigNiriResizeHitResult(
            windowHandle: tiled.windowHandle,
            windowId: tiled.windowId,
            columnIndex: tiled.columnIndex,
            edges: edges,
            windowFrame: tiled.windowFrame
        )
    }
    func hitTestTiled(
        at point: CGPoint,
        _ request: ZigNiriHitTestRequest
    ) -> ZigNiriTiledHitResult? {
        guard let view = workspaceViews[request.workspaceId] else {
            return nil
        }
        for (windowId, window) in view.windowsById {
            guard let frame = window.frame else {
                continue
            }
            guard frame.contains(point) else {
                continue
            }
            return ZigNiriTiledHitResult(
                windowHandle: window.handle,
                windowId: windowId,
                columnId: window.columnId,
                columnIndex: columnIndex(for: windowId, in: view),
                windowFrame: frame
            )
        }
        return nil
    }
    @discardableResult
    func beginInteractiveMove(_ state: ZigNiriInteractiveMoveState) -> Bool {
        guard interactiveMoveState == nil else { return false }
        interactiveMoveState = state
        return true
    }
    func updateInteractiveMove(mouseLocation: CGPoint) -> ZigNiriMoveHoverTarget? {
        guard var move = interactiveMoveState else { return nil }
        let hoverTarget: ZigNiriMoveHoverTarget?
        if mouseLocation.x <= move.monitorFrame.minX {
            hoverTarget = .workspaceEdge(side: .left)
        } else if mouseLocation.x >= move.monitorFrame.maxX {
            hoverTarget = .workspaceEdge(side: .right)
        } else {
            hoverTarget = nil
        }
        move.currentHoverTarget = hoverTarget
        interactiveMoveState = move
        return hoverTarget
    }
    func endInteractiveMove(commit: Bool = true) -> ZigNiriMutationResult {
        guard let move = interactiveMoveState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        defer { interactiveMoveState = nil }
        guard commit else {
            return .noChange(
                workspaceId: move.workspaceId,
                selection: workspaceViews[move.workspaceId]?.selection
            )
        }
        return ZigNiriMutationResult(
            applied: move.currentHoverTarget != nil,
            workspaceId: move.workspaceId,
            selection: workspaceViews[move.workspaceId]?.selection,
            affectedNodeIds: [move.windowId],
            removedNodeIds: []
        )
    }
    @discardableResult
    func beginInteractiveResize(_ state: ZigNiriInteractiveResizeState) -> Bool {
        guard interactiveResizeState == nil else { return false }
        guard ensureSyncedViewIfNeeded(workspaceId: state.workspaceId),
              let view = workspaceViews[state.workspaceId],
              let window = view.windowsById[state.windowId]
        else {
            return false
        }
        let fallbackWidth = max(1, state.orientation == .horizontal
            ? state.monitorFrame.width / 2
            : state.monitorFrame.width)
        let fallbackHeight = max(1, state.orientation == .horizontal
            ? state.monitorFrame.height
            : state.monitorFrame.height / 2)
        let windowFrame = window.frame ?? CGRect(
            x: state.monitorFrame.minX,
            y: state.monitorFrame.minY,
            width: fallbackWidth,
            height: fallbackHeight
        )
        let columnId = window.columnId
        let originalColumn = columnId.flatMap { targetColumnId in
            view.columns.first(where: { $0.nodeId == targetColumnId })
        }
        let hasHorizontal = state.edges.hasHorizontal
        let hasVertical = state.edges.hasVertical
        let originalColumnWidth: CGFloat
        let minColumnWidth: CGFloat
        let maxColumnWidth: CGFloat
        if hasHorizontal {
            let measured = state.orientation == .horizontal ? windowFrame.width : windowFrame.height
            originalColumnWidth = max(1, measured)
            minColumnWidth = 80
            let monitorPrimary = state.orientation == .horizontal
                ? state.monitorFrame.width
                : state.monitorFrame.height
            maxColumnWidth = max(minColumnWidth, monitorPrimary - state.gap)
        } else {
            originalColumnWidth = 0
            minColumnWidth = 0
            maxColumnWidth = 0
        }
        let originalWindowWeight: CGFloat
        let pixelsPerWeight: CGFloat
        if hasVertical {
            switch window.height {
            case let .auto(weight):
                originalWindowWeight = max(0.1, weight)
            case let .fixed(value):
                originalWindowWeight = max(0.1, value / max(windowFrame.height, 1))
            }
            pixelsPerWeight = max(1, windowFrame.height / max(0.1, originalWindowWeight))
        } else {
            originalWindowWeight = 0
            pixelsPerWeight = 0
        }
        interactiveResizeState = ActiveInteractiveResize(
            windowId: state.windowId,
            workspaceId: state.workspaceId,
            edges: state.edges,
            startMouseLocation: state.startMouseLocation,
            columnId: columnId,
            originalColumnSize: hasHorizontal ? originalColumn?.width : nil,
            originalColumnIsFullWidth: originalColumn?.isFullWidth ?? false,
            originalColumnWidth: originalColumnWidth,
            minColumnWidth: minColumnWidth,
            maxColumnWidth: maxColumnWidth,
            originalWindowHeight: hasVertical ? window.height : nil,
            originalWindowWeight: originalWindowWeight,
            minWindowWeight: ResizeConfiguration.default.minWindowWeight,
            maxWindowWeight: ResizeConfiguration.default.maxWindowWeight,
            pixelsPerWeight: pixelsPerWeight,
            originalViewOffset: state.edges.contains(.left) ? state.initialViewportOffset : nil,
            orientation: state.orientation
        )
        return true
    }
    func updateInteractiveResize(mouseLocation: CGPoint) -> ZigNiriMutationResult {
        let latencyToken = ZigNiriLatencyProbe.begin(.resizeDragUpdate)
        defer { ZigNiriLatencyProbe.end(latencyToken) }

        guard let resize = interactiveResizeState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        let hasMovement = mouseLocation != resize.startMouseLocation
        guard hasMovement else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        var input = OmniNiriResizeInput(
            edges: UInt8(resize.edges.rawValue & 0xFF),
            start_x: Double(resize.startMouseLocation.x),
            start_y: Double(resize.startMouseLocation.y),
            current_x: Double(mouseLocation.x),
            current_y: Double(mouseLocation.y),
            original_column_width: Double(resize.originalColumnWidth),
            min_column_width: Double(resize.minColumnWidth),
            max_column_width: Double(resize.maxColumnWidth),
            original_window_weight: Double(resize.originalWindowWeight),
            min_window_weight: Double(resize.minWindowWeight),
            max_window_weight: Double(resize.maxWindowWeight),
            pixels_per_weight: Double(resize.pixelsPerWeight),
            has_original_view_offset: resize.originalViewOffset == nil ? 0 : 1,
            original_view_offset: Double(resize.originalViewOffset ?? 0)
        )
        var output = OmniNiriResizeResult(
            changed_width: 0,
            new_column_width: Double(resize.originalColumnWidth),
            changed_weight: 0,
            new_window_weight: Double(resize.originalWindowWeight),
            adjust_view_offset: 0,
            new_view_offset: Double(resize.originalViewOffset ?? 0)
        )
        let rc = withUnsafePointer(to: &input) { inputPtr in
            withUnsafeMutablePointer(to: &output) { outputPtr in
                omni_niri_resize_compute(inputPtr, outputPtr)
            }
        }
        guard rc == 0 else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        let nextColumnWidth: CGFloat? = output.changed_width != 0 ? CGFloat(output.new_column_width) : nil
        let nextWindowWeight: CGFloat? = output.changed_weight != 0 ? CGFloat(output.new_window_weight) : nil
        let nextViewportOffset: CGFloat? = output.adjust_view_offset != 0 ? CGFloat(output.new_view_offset) : nil
        guard nextColumnWidth != nil || nextWindowWeight != nil || nextViewportOffset != nil else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        guard ensureSyncedViewIfNeeded(workspaceId: resize.workspaceId) else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        let previewApplied = applyInteractiveResizePreview(
            resize,
            columnWidth: nextColumnWidth,
            windowWeight: nextWindowWeight
        )
        var affectedNodeIds: [NodeId] = []
        if previewApplied {
            affectedNodeIds.append(resize.windowId)
            if let columnId = resize.columnId {
                affectedNodeIds.append(columnId)
            }
        }
        return ZigNiriMutationResult(
            applied: previewApplied || nextViewportOffset != nil,
            workspaceId: resize.workspaceId,
            selection: workspaceViews[resize.workspaceId]?.selection,
            affectedNodeIds: affectedNodeIds,
            removedNodeIds: [],
            resizeOutput: ZigNiriResizeMutationOutput(
                columnWidth: nextColumnWidth,
                windowWeight: nextWindowWeight,
                viewportOffset: nextViewportOffset
            )
        )
    }
    func endInteractiveResize(commit: Bool = true) -> ZigNiriMutationResult {
        guard let resize = interactiveResizeState else {
            return .noChange(workspaceId: nil, selection: nil)
        }
        defer { interactiveResizeState = nil }
        guard ensureSyncedViewIfNeeded(workspaceId: resize.workspaceId) else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        guard commit else {
            _ = restoreInteractiveResizePreview(resize)
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        guard let context = ensureRuntimeContext(for: resize.workspaceId) else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        let export = runtimeBootstrapExport(for: resize.workspaceId)
        let rc = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: export
        )
        guard rc == 0 else {
            return .noChange(
                workspaceId: resize.workspaceId,
                selection: workspaceViews[resize.workspaceId]?.selection
            )
        }
        if !syncWorkspaceView(workspaceId: resize.workspaceId, export: export) {
            markWorkspaceDirty(resize.workspaceId)
            _ = ensureSyncedViewIfNeeded(workspaceId: resize.workspaceId)
        }
        var affectedNodeIds = [resize.windowId]
        if let columnId = resize.columnId {
            affectedNodeIds.append(columnId)
        }
        return ZigNiriMutationResult(
            applied: true,
            workspaceId: resize.workspaceId,
            selection: workspaceViews[resize.workspaceId]?.selection,
            affectedNodeIds: affectedNodeIds,
            removedNodeIds: []
        )
    }

    func invalidateWorkspaceProjection(_ workspaceId: WorkspaceDescriptor.ID) {
        dirtyWorkspaceIds.insert(workspaceId)
    }

    @discardableResult
    func refreshWorkspaceProjection(_ workspaceId: WorkspaceDescriptor.ID) -> Bool {
        invalidateWorkspaceProjection(workspaceId)
        return ensureSyncedViewIfNeeded(workspaceId: workspaceId)
    }

    func pruneWorkspaceProjections(to activeWorkspaceIds: Set<WorkspaceDescriptor.ID>) {
        let candidateWorkspaceIds = Set(workspaceViews.keys)
            .union(runtimeDecodeWindowIndexCacheByWorkspace.keys)
            .union(dirtyWorkspaceIds)
            .union(layoutContexts.keys)
            .union(runtimeRenderFailureCountByWorkspace.keys)
            .union(runtimeRenderMismatchCountByWorkspace.keys)
            .union(workspaceNodeIds.keys)
        let removedWorkspaceIds = candidateWorkspaceIds.subtracting(activeWorkspaceIds)
        guard !removedWorkspaceIds.isEmpty else { return }

        for workspaceId in removedWorkspaceIds {
            let removedNodeIds = updateNodeReferences(for: workspaceId, currentNodeIds: [])
            workspaceNodeIds.removeValue(forKey: workspaceId)
            for nodeId in removedNodeIds {
                cleanupWindowMappings(for: nodeId)
            }
            workspaceViews.removeValue(forKey: workspaceId)
            runtimeDecodeWindowIndexCacheByWorkspace.removeValue(forKey: workspaceId)
            dirtyWorkspaceIds.remove(workspaceId)
            layoutContexts.removeValue(forKey: workspaceId)
            runtimeRenderFailureCountByWorkspace.removeValue(forKey: workspaceId)
            runtimeRenderMismatchCountByWorkspace.removeValue(forKey: workspaceId)
        }

        if let interactiveMoveState, removedWorkspaceIds.contains(interactiveMoveState.workspaceId) {
            self.interactiveMoveState = nil
        }
        if let interactiveResizeState, removedWorkspaceIds.contains(interactiveResizeState.workspaceId) {
            self.interactiveResizeState = nil
        }
    }

    func isWorkspaceProjectionDirty(_ workspaceId: WorkspaceDescriptor.ID) -> Bool {
        dirtyWorkspaceIds.contains(workspaceId)
    }
}
private extension ZigNiriEngine {
    struct RuntimeMutationSpec {
        let op: ZigNiriStateKernel.MutationOp
        var sourceWindowId: NodeId?
        var sourceColumnId: NodeId?
        var targetWindowId: NodeId?
        var direction: Direction?
        var insertPosition: InsertPosition?
        var insertColumnIndex: Int
        var maxVisibleColumnsOverride: Int?
        var incomingWindowId: UUID?
        var incomingSpawnMode: ZigNiriStateKernel.IncomingSpawnMode
        var createdColumnId: UUID?
        var placeholderColumnId: UUID?
        init(
            op: ZigNiriStateKernel.MutationOp,
            sourceWindowId: NodeId? = nil,
            sourceColumnId: NodeId? = nil,
            targetWindowId: NodeId? = nil,
            direction: Direction? = nil,
            insertPosition: InsertPosition? = nil,
            insertColumnIndex: Int = -1,
            maxVisibleColumnsOverride: Int? = nil,
            incomingWindowId: UUID? = nil,
            incomingSpawnMode: ZigNiriStateKernel.IncomingSpawnMode = .newColumn,
            createdColumnId: UUID? = nil,
            placeholderColumnId: UUID? = nil
        ) {
            self.op = op
            self.sourceWindowId = sourceWindowId
            self.sourceColumnId = sourceColumnId
            self.targetWindowId = targetWindowId
            self.direction = direction
            self.insertPosition = insertPosition
            self.insertColumnIndex = insertColumnIndex
            self.maxVisibleColumnsOverride = maxVisibleColumnsOverride
            self.incomingWindowId = incomingWindowId
            self.incomingSpawnMode = incomingSpawnMode
            self.createdColumnId = createdColumnId
            self.placeholderColumnId = placeholderColumnId
        }
    }
    func mutationOpForWindowMove(
        direction: Direction,
        orientation: Monitor.Orientation,
        swap: Bool
    ) -> ZigNiriStateKernel.MutationOp? {
        if direction.primaryStep(for: orientation) != nil {
            return swap ? .swapWindowHorizontal : .moveWindowHorizontal
        }
        if direction.secondaryStep(for: orientation) != nil {
            return swap ? .swapWindowVertical : .moveWindowVertical
        }
        return nil
    }
    func applyRuntimeMutation(
        _ mutation: RuntimeMutationSpec,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection? = nil
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        let request = ZigNiriStateKernel.MutationRequest(
            op: mutation.op,
            sourceWindowId: mutation.sourceWindowId,
            targetWindowId: mutation.targetWindowId,
            direction: mutation.direction,
            infiniteLoop: infiniteLoop,
            insertPosition: mutation.insertPosition,
            maxWindowsPerColumn: maxWindowsPerColumn,
            sourceColumnId: mutation.sourceColumnId,
            targetColumnId: nil,
            insertColumnIndex: mutation.insertColumnIndex,
            maxVisibleColumns: mutation.maxVisibleColumnsOverride ?? maxVisibleColumns,
            selectedNodeId: selection?.selectedNodeId ?? workspaceViews[workspaceId]?.selection?.selectedNodeId,
            focusedWindowId: selection?.focusedWindowId ?? workspaceViews[workspaceId]?.selection?.focusedWindowId,
            incomingSpawnMode: mutation.incomingSpawnMode
        )
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: request,
                incomingWindowId: mutation.incomingWindowId,
                createdColumnId: mutation.createdColumnId,
                placeholderColumnId: mutation.placeholderColumnId
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let removedIds = outcome.delta?.removedWindowIds ?? []
        let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
        if outcome.applied {
            if structuralAnimationActive {
                scheduleStructuralAnimation(in: workspaceId, from: preFrames)
            }
        }
        var affected: [NodeId] = []
        if let sourceWindowId = mutation.sourceWindowId {
            affected.append(sourceWindowId)
        }
        if let sourceColumnId = mutation.sourceColumnId {
            affected.append(sourceColumnId)
        }
        if let targetWindowId = mutation.targetWindowId {
            affected.append(targetWindowId)
        }
        if let targetWindowId = outcome.targetWindowId,
           !affected.contains(targetWindowId)
        {
            affected.append(targetWindowId)
        }
        if let targetNode = outcome.targetNode,
           !affected.contains(targetNode.nodeId)
        {
            affected.append(targetNode.nodeId)
        }
        let synced: Bool
        if outcome.applied,
           let delta = outcome.delta,
           syncWorkspaceView(
               workspaceId: workspaceId,
               export: runtimeStateExport(from: delta)
           )
        {
            synced = true
        } else if outcome.applied {
            markWorkspaceDirty(workspaceId)
            synced = ensureSyncedViewIfNeeded(workspaceId: workspaceId)
        } else {
            synced = true
        }
        guard synced else {
            if outcome.applied {
                return ZigNiriMutationResult(
                    applied: true,
                    workspaceId: workspaceId,
                    selection: selection ?? workspaceViews[workspaceId]?.selection,
                    affectedNodeIds: affected,
                    removedNodeIds: removedIds,
                    structuralAnimationActive: structuralAnimationActive
                )
            }
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        var nextSelection = selection ?? view.selection
        if let targetWindowId = outcome.delta?.targetSelectionWindowId ?? outcome.targetWindowId {
            nextSelection = ZigNiriSelection(
                selectedNodeId: targetWindowId,
                focusedWindowId: targetWindowId
            )
        } else if let targetNode = outcome.targetNode {
            switch targetNode.kind {
            case .window:
                nextSelection = ZigNiriSelection(
                    selectedNodeId: targetNode.nodeId,
                    focusedWindowId: targetNode.nodeId
                )
            case .column:
                let focusedWindowId = nextSelection?.focusedWindowId ?? view.selection?.focusedWindowId
                if let resolvedWindowId = ZigNiriSelectionResolver.actionableWindowId(
                    for: targetNode.nodeId,
                    in: view
                ) {
                    nextSelection = ZigNiriSelection(
                        selectedNodeId: resolvedWindowId,
                        focusedWindowId: resolvedWindowId
                    )
                } else {
                    nextSelection = ZigNiriSelection(
                        selectedNodeId: targetNode.nodeId,
                        focusedWindowId: focusedWindowId
                    )
                }
            case .none:
                break
            }
        }
        view.selection = nextSelection
        view = storeWorkspaceView(view, workspaceId: workspaceId, allowNilWhenRequested: true)
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: affected,
            removedNodeIds: removedIds,
            structuralAnimationActive: structuralAnimationActive
        )
    }
    func applyColumnDisplayMutation(
        columnId: NodeId,
        display: ColumnDisplay,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .setColumnDisplay,
                    sourceColumnId: columnId,
                    customU8A: display == .tabbed ? 1 : 0
                )
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
        if structuralAnimationActive {
            scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        }
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: outcome.applied ? [columnId] : [],
            removedNodeIds: [],
            structuralAnimationActive: structuralAnimationActive
        )
    }
    func applyColumnActiveWindowMutation(
        columnId: NodeId,
        windowIndex: Int,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .setColumnActiveTile,
                    sourceColumnId: columnId,
                    customI64A: windowIndex
                )
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        } else if let column = view.columns.first(where: { $0.nodeId == columnId }),
                  column.windowIds.indices.contains(min(max(windowIndex, 0), max(0, column.windowIds.count - 1)))
        {
            let activeWindowId = column.windowIds[min(max(windowIndex, 0), column.windowIds.count - 1)]
            view.selection = ZigNiriSelection(selectedNodeId: activeWindowId, focusedWindowId: activeWindowId)
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: outcome.applied ? [columnId] : [],
            removedNodeIds: []
        )
    }
    func applyColumnWidthMutation(
        columnId: NodeId,
        width: ProportionalSize,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        let encodedWidth = ZigNiriStateKernel.encodeWidth(width)
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .setColumnWidth,
                    sourceColumnId: columnId,
                    customU8A: encodedWidth.kind,
                    customF64A: encodedWidth.value
                )
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = normalizedSelection(selection, in: view)
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
        if structuralAnimationActive {
            scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        }
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: outcome.applied ? [columnId] : [],
            removedNodeIds: [],
            structuralAnimationActive: structuralAnimationActive
        )
    }
    func applyColumnFullWidthToggleMutation(
        columnId: NodeId,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .toggleColumnFullWidth,
                    sourceColumnId: columnId
                )
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        let structuralAnimationActive = outcome.applied && outcome.structuralAnimationActive
        if structuralAnimationActive {
            scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        }
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: outcome.applied ? [columnId] : [],
            removedNodeIds: [],
            structuralAnimationActive: structuralAnimationActive
        )
    }
    func applyWindowSizingMutation(
        windowId: NodeId,
        mode: SizingMode,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        guard ensureRuntimeContext(for: workspaceId) != nil else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let preFrames = captureNodeFrames(in: workspaceId)
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        guard var window = view.windowsById[windowId] else {
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }
        let previousMode = windowSizingModesByNodeId[windowId] ?? window.sizingMode
        guard previousMode != mode else {
            return .noChange(workspaceId: workspaceId, selection: view.selection)
        }
        var affectedNodeIds: [NodeId] = [windowId]
        var needsRuntimeRefresh = false
        if mode == .fullscreen {
            for candidateId in view.windowsById.keys where candidateId != windowId {
                guard var candidateWindow = view.windowsById[candidateId] else { continue }
                let candidateMode = windowSizingModesByNodeId[candidateId] ?? candidateWindow.sizingMode
                guard candidateMode == .fullscreen else { continue }
                affectedNodeIds.append(candidateId)
                windowSizingModesByNodeId[candidateId] = .normal
                candidateWindow.sizingMode = .normal
                if let restoredHeight = savedWindowHeightsByNodeId.removeValue(forKey: candidateId) {
                    let restoreOutcome = setWindowHeightInRuntime(
                        windowId: candidateId,
                        height: restoredHeight,
                        workspaceId: workspaceId
                    )
                    if restoreOutcome.applied {
                        needsRuntimeRefresh = true
                    } else if restoreOutcome.rc != 0 {
                        candidateWindow.height = restoredHeight
                    }
                }
                view.windowsById[candidateId] = candidateWindow
            }
        }
        if previousMode == .normal, mode == .fullscreen {
            savedWindowHeightsByNodeId[windowId] = window.height
        } else if previousMode == .fullscreen,
                  mode == .normal,
                  let savedHeight = savedWindowHeightsByNodeId.removeValue(forKey: windowId)
        {
            let restoreOutcome = setWindowHeightInRuntime(
                windowId: windowId,
                height: savedHeight,
                workspaceId: workspaceId
            )
            if restoreOutcome.applied {
                needsRuntimeRefresh = true
            } else if restoreOutcome.rc != 0 {
                window.height = savedHeight
            }
        }
        if needsRuntimeRefresh {
            guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
                return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
            }
            view = ensureWorkspaceView(for: workspaceId)
            guard let refreshedWindow = view.windowsById[windowId] else {
                return .noChange(workspaceId: workspaceId, selection: view.selection)
            }
            window = refreshedWindow
        }
        windowSizingModesByNodeId[windowId] = mode
        window.sizingMode = mode
        view.windowsById[windowId] = window
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        return ZigNiriMutationResult(
            applied: true,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: affectedNodeIds,
            removedNodeIds: [],
            structuralAnimationActive: true
        )
    }
    func applyWindowHeightMutation(
        windowId: NodeId,
        height: WeightedSize,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        let mutation = setWindowHeightInRuntime(
            windowId: windowId,
            height: height,
            workspaceId: workspaceId
        )
        guard mutation.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        return ZigNiriMutationResult(
            applied: mutation.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: mutation.applied ? [windowId] : [],
            removedNodeIds: []
        )
    }
    func applyRemoveWindowMutation(
        windowId: NodeId,
        workspaceId: WorkspaceDescriptor.ID,
        selection: ZigNiriSelection?
    ) -> ZigNiriMutationResult {
        let preFrames: [NodeId: CGRect] = if ensureSyncedViewIfNeeded(workspaceId: workspaceId) {
            captureNodeFrames(in: workspaceId)
        } else {
            [:]
        }
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        let request = ZigNiriStateKernel.MutationRequest(
            op: .removeWindow,
            sourceWindowId: windowId
        )
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: request,
                placeholderColumnId: UUID()
            ),
            sampleTime: currentTime()
        )
        guard outcome.rc == 0 else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        guard ensureSyncedViewIfNeeded(workspaceId: workspaceId) else {
            return .noChange(workspaceId: workspaceId, selection: workspaceViews[workspaceId]?.selection)
        }
        var view = ensureWorkspaceView(for: workspaceId)
        if let selection {
            view.selection = selection
        }
        view = storeWorkspaceView(view, workspaceId: workspaceId)
        if outcome.applied, outcome.structuralAnimationActive {
            scheduleStructuralAnimation(in: workspaceId, from: preFrames)
        }
        return ZigNiriMutationResult(
            applied: outcome.applied,
            workspaceId: workspaceId,
            selection: view.selection,
            affectedNodeIds: [],
            removedNodeIds: outcome.applied ? [windowId] : [],
            structuralAnimationActive: outcome.structuralAnimationActive
        )
    }
    private func setWindowHeightInRuntime(
        windowId: NodeId,
        height: WeightedSize,
        workspaceId: WorkspaceDescriptor.ID
    ) -> RuntimeStateMutationOutcome {
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return RuntimeStateMutationOutcome(rc: -1, applied: false)
        }
        let encodedHeight = ZigNiriStateKernel.encodeHeight(height)
        let outcome = ZigNiriStateKernel.applyMutation(
            context: context,
            request: .init(
                request: ZigNiriStateKernel.MutationRequest(
                    op: .setWindowHeight,
                    sourceWindowId: windowId,
                    customU8A: encodedHeight.kind,
                    customF64A: encodedHeight.value
                )
            ),
            sampleTime: currentTime()
        )
        if outcome.applied {
            markWorkspaceDirty(workspaceId)
        }
        return RuntimeStateMutationOutcome(rc: outcome.rc, applied: outcome.applied)
    }
    private func mutateRuntimeState(
        context: ZigNiriLayoutKernel.LayoutContext,
        workspaceId: WorkspaceDescriptor.ID,
        mutate: (inout ZigNiriStateKernel.RuntimeStateExport) -> Bool
    ) -> RuntimeStateMutationOutcome {
        var export: ZigNiriStateKernel.RuntimeStateExport
        switch ZigNiriStateKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            export = snapshot
        case let .failure(error):
            return RuntimeStateMutationOutcome(rc: error.rc, applied: false)
        }
        let applied = mutate(&export)
        guard applied else {
            return RuntimeStateMutationOutcome(rc: 0, applied: false)
        }
        normalizeRuntimeExport(&export)
        let rc = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: export
        )
        if rc == 0 {
            markWorkspaceDirty(workspaceId)
        }
        return RuntimeStateMutationOutcome(rc: rc, applied: rc == 0)
    }
    func ensureWorkspaceView(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriWorkspaceView {
        if let existing = workspaceViews[workspaceId] {
            return existing
        }
        let view = ZigNiriWorkspaceView(
            workspaceId: workspaceId,
            columns: [],
            windowsById: [:],
            selection: nil
        )
        workspaceViews[workspaceId] = view
        return view
    }
    func markWorkspaceDirty(_ workspaceId: WorkspaceDescriptor.ID) {
        dirtyWorkspaceIds.insert(workspaceId)
    }
    @discardableResult
    func ensureSyncedViewIfNeeded(workspaceId: WorkspaceDescriptor.ID) -> Bool {
        if workspaceViews[workspaceId] == nil || dirtyWorkspaceIds.contains(workspaceId) {
            return syncWorkspaceViewFromRuntime(workspaceId: workspaceId)
        }
        return true
    }
    @discardableResult
    func storeWorkspaceView(
        _ view: ZigNiriWorkspaceView,
        workspaceId: WorkspaceDescriptor.ID,
        allowNilWhenRequested: Bool = false
    ) -> ZigNiriWorkspaceView {
        var normalizedView = view
        normalizedView.selection = normalizedSelection(
            normalizedView.selection,
            in: normalizedView,
            allowNilWhenRequested: allowNilWhenRequested
        )
        applyFocusState(to: &normalizedView)
        workspaceViews[workspaceId] = normalizedView
        return normalizedView
    }
    func ensureRuntimeContext(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriLayoutKernel.LayoutContext? {
        if let context = layoutContexts[workspaceId] {
            return context
        }
        guard let context = ZigNiriLayoutKernel.LayoutContext() else {
            return nil
        }
        let bootstrapExport = runtimeBootstrapExport(for: workspaceId)
        let seedRC = ZigNiriStateKernel.seedRuntimeState(
            context: context,
            export: bootstrapExport
        )
        guard seedRC == 0 else {
            return nil
        }
        layoutContexts[workspaceId] = context
        markWorkspaceDirty(workspaceId)
        return context
    }
    func runtimeBootstrapExport(for workspaceId: WorkspaceDescriptor.ID) -> ZigNiriStateKernel.RuntimeStateExport {
        guard let view = workspaceViews[workspaceId], !view.columns.isEmpty else {
            return ZigNiriStateKernel.RuntimeStateExport(
                columns: [
                    .init(
                        columnId: NodeId(),
                        windowStart: 0,
                        windowCount: 0,
                        activeTileIdx: 0,
                        isTabbed: false,
                        sizeValue: 1.0
                    ),
                ],
                windows: []
            )
        }
        var runtimeColumns: [ZigNiriStateKernel.RuntimeColumnState] = []
        runtimeColumns.reserveCapacity(max(1, view.columns.count))
        var runtimeWindows: [ZigNiriStateKernel.RuntimeWindowState] = []
        for (columnIndex, column) in view.columns.enumerated() {
            let encodedWidth = ZigNiriStateKernel.encodeWidth(column.width)
            let start = runtimeWindows.count
            for windowId in column.windowIds {
                guard let window = view.windowsById[windowId] else { continue }
                let encodedHeight = ZigNiriStateKernel.encodeHeight(window.height)
                let sizeValue: Double
                switch window.height {
                case let .auto(weight):
                    sizeValue = Double(weight)
                case .fixed:
                    sizeValue = 1.0
                }
                runtimeWindows.append(
                    ZigNiriStateKernel.RuntimeWindowState(
                        windowId: window.nodeId,
                        columnId: column.nodeId,
                        columnIndex: columnIndex,
                        sizeValue: sizeValue,
                        heightKind: encodedHeight.kind,
                        heightValue: encodedHeight.value
                    )
                )
            }
            runtimeColumns.append(
                ZigNiriStateKernel.RuntimeColumnState(
                    columnId: column.nodeId,
                    windowStart: start,
                    windowCount: runtimeWindows.count - start,
                    activeTileIdx: column.activeWindowIndex ?? 0,
                    isTabbed: column.display == .tabbed,
                    sizeValue: encodedWidth.value,
                    widthKind: encodedWidth.kind,
                    isFullWidth: column.isFullWidth,
                    hasSavedWidth: false,
                    savedWidthKind: encodedWidth.kind,
                    savedWidthValue: encodedWidth.value
                )
            )
        }
        if runtimeColumns.isEmpty {
            runtimeColumns.append(
                .init(
                    columnId: NodeId(),
                    windowStart: 0,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: false,
                    sizeValue: 1.0
                )
            )
        }
        return ZigNiriStateKernel.RuntimeStateExport(
            columns: runtimeColumns,
            windows: runtimeWindows
        )
    }
    @discardableResult
    func syncWorkspaceViewFromRuntime(workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let context = layoutContexts[workspaceId] else {
            return false
        }
        switch ZigNiriStateKernel.snapshotRuntimeStateResult(context: context) {
        case let .success(snapshot):
            return syncWorkspaceView(workspaceId: workspaceId, export: snapshot)
        case .failure:
            return false
        }
    }
    @discardableResult
    func syncWorkspaceView(
        workspaceId: WorkspaceDescriptor.ID,
        export: ZigNiriStateKernel.RuntimeStateExport
    ) -> Bool {
        let previousView = workspaceViews[workspaceId]
        var previousColumnsById: [NodeId: ZigNiriColumnView] = [:]
        if let previousView {
            previousColumnsById.reserveCapacity(previousView.columns.count)
            for column in previousView.columns {
                previousColumnsById[column.nodeId] = column
            }
        }
        var columns: [ZigNiriColumnView] = []
        columns.reserveCapacity(export.columns.count)
        var windowsById: [NodeId: ZigNiriWindowView] = [:]
        windowsById.reserveCapacity(export.windows.count)
        var currentNodeIds = Set<NodeId>()
        currentNodeIds.reserveCapacity(export.windows.count)
        for runtimeColumn in export.columns {
            let start = runtimeColumn.windowStart
            let count = runtimeColumn.windowCount
            let hasValidRange = start >= 0
                && count >= 0
                && start <= export.windows.count
                && count <= export.windows.count - start
            let end = hasValidRange ? start + count : start
            var columnWindowIds: [NodeId] = []
            columnWindowIds.reserveCapacity(max(0, count))
            if hasValidRange {
                for index in start ..< end {
                    let runtimeWindow = export.windows[index]
                    let handle = windowHandlesByNodeId[runtimeWindow.windowId]
                        ?? windowHandlesByUUID[runtimeWindow.windowId.uuid]
                    guard let handle else {
                        continue
                    }
                    windowHandlesByNodeId[runtimeWindow.windowId] = handle
                    windowNodeIdsByHandle[handle] = runtimeWindow.windowId
                    windowHandlesByUUID[handle.id] = handle
                    currentNodeIds.insert(runtimeWindow.windowId)
                    let priorWindow = previousView?.windowsById[runtimeWindow.windowId]
                    let height = ZigNiriStateKernel.decodeHeight(
                        kind: runtimeWindow.heightKind,
                        value: runtimeWindow.heightValue
                    ) ?? priorWindow?.height ?? .default
                    let sizingMode = windowSizingModesByNodeId[runtimeWindow.windowId]
                        ?? priorWindow?.sizingMode
                        ?? .normal
                    windowsById[runtimeWindow.windowId] = ZigNiriWindowView(
                        nodeId: runtimeWindow.windowId,
                        handle: handle,
                        columnId: runtimeColumn.columnId,
                        frame: priorWindow?.frame,
                        sizingMode: sizingMode,
                        height: height,
                        isFocused: false
                    )
                    columnWindowIds.append(runtimeWindow.windowId)
                }
            }
            let activeWindowIndex: Int?
            if columnWindowIds.isEmpty {
                activeWindowIndex = nil
            } else {
                activeWindowIndex = min(max(runtimeColumn.activeTileIdx, 0), columnWindowIds.count - 1)
            }
            let priorColumn = previousColumnsById[runtimeColumn.columnId]
            let width = ZigNiriStateKernel.decodeWidth(
                kind: runtimeColumn.widthKind,
                value: runtimeColumn.sizeValue
            ) ?? priorColumn?.width ?? .default
            columns.append(
                ZigNiriColumnView(
                    nodeId: runtimeColumn.columnId,
                    windowIds: columnWindowIds,
                    display: runtimeColumn.isTabbed ? .tabbed : .normal,
                    activeWindowIndex: activeWindowIndex,
                    width: width,
                    isFullWidth: runtimeColumn.isFullWidth
                )
            )
        }
        var nextView = ZigNiriWorkspaceView(
            workspaceId: workspaceId,
            columns: columns,
            windowsById: windowsById,
            selection: previousView?.selection
        )
        nextView = storeWorkspaceView(nextView, workspaceId: workspaceId)
        let removedNodeIds = updateNodeReferences(for: workspaceId, currentNodeIds: currentNodeIds)
        for removedNodeId in removedNodeIds {
            cleanupWindowMappings(for: removedNodeId)
        }
        rebuildRuntimeDecodeWindowIndexCache(
            workspaceId: workspaceId,
            export: export
        )
        dirtyWorkspaceIds.remove(workspaceId)
        return true
    }
    func runtimeStateExport(
        from delta: ZigNiriStateKernel.DeltaExport
    ) -> ZigNiriStateKernel.RuntimeStateExport {
        let columns = delta.columns
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.column.columnId.uuid.uuidString < rhs.column.columnId.uuid.uuidString
            }
            .map(\.column)
        let windows = delta.windows
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.columnOrderIndex != rhs.element.columnOrderIndex {
                    return lhs.element.columnOrderIndex < rhs.element.columnOrderIndex
                }
                if lhs.element.rowIndex != rhs.element.rowIndex {
                    return lhs.element.rowIndex < rhs.element.rowIndex
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element.window)
        return ZigNiriStateKernel.RuntimeStateExport(
            columns: columns,
            windows: windows
        )
    }
    @discardableResult
    private func applyInteractiveResizePreview(
        _ resize: ActiveInteractiveResize,
        columnWidth: CGFloat?,
        windowWeight: CGFloat?
    ) -> Bool {
        guard var view = workspaceViews[resize.workspaceId] else {
            return false
        }
        var changed = false
        if let columnId = resize.columnId,
           let columnWidth,
           let columnIndex = view.columns.firstIndex(where: { $0.nodeId == columnId })
        {
            let nextWidth = ProportionalSize.fixed(columnWidth)
            if view.columns[columnIndex].width != nextWidth || view.columns[columnIndex].isFullWidth {
                view.columns[columnIndex].width = nextWidth
                view.columns[columnIndex].isFullWidth = false
                changed = true
            }
        }
        if let windowWeight,
           var window = view.windowsById[resize.windowId]
        {
            let nextHeight = WeightedSize.auto(weight: windowWeight)
            if window.height != nextHeight {
                window.height = nextHeight
                view.windowsById[resize.windowId] = window
                changed = true
            }
        }
        if changed {
            _ = storeWorkspaceView(view, workspaceId: resize.workspaceId)
        }
        return changed
    }
    @discardableResult
    private func restoreInteractiveResizePreview(_ resize: ActiveInteractiveResize) -> Bool {
        guard var view = workspaceViews[resize.workspaceId] else {
            return false
        }
        var changed = false
        if let columnId = resize.columnId,
           let originalColumnSize = resize.originalColumnSize,
           let columnIndex = view.columns.firstIndex(where: { $0.nodeId == columnId })
        {
            if view.columns[columnIndex].width != originalColumnSize
                || view.columns[columnIndex].isFullWidth != resize.originalColumnIsFullWidth
            {
                view.columns[columnIndex].width = originalColumnSize
                view.columns[columnIndex].isFullWidth = resize.originalColumnIsFullWidth
                changed = true
            }
        }
        if let originalWindowHeight = resize.originalWindowHeight,
           var window = view.windowsById[resize.windowId]
        {
            if window.height != originalWindowHeight {
                window.height = originalWindowHeight
                view.windowsById[resize.windowId] = window
                changed = true
            }
        }
        if changed {
            _ = storeWorkspaceView(view, workspaceId: resize.workspaceId)
        }
        return changed
    }
    private func rebuildRuntimeDecodeWindowIndexCache(
        workspaceId: WorkspaceDescriptor.ID,
        export: ZigNiriStateKernel.RuntimeStateExport
    ) {
        var orderedWindowIds: [NodeId] = []
        orderedWindowIds.reserveCapacity(export.windows.count)
        var orderedHandles: [WindowHandle] = []
        orderedHandles.reserveCapacity(export.windows.count)
        var seenWindowIds = Set<NodeId>()
        seenWindowIds.reserveCapacity(export.windows.count)
        for runtimeWindow in export.windows {
            let windowId = runtimeWindow.windowId
            guard seenWindowIds.insert(windowId).inserted,
                  let handle = windowHandlesByNodeId[windowId]
                    ?? windowHandlesByUUID[windowId.uuid]
            else {
                runtimeDecodeWindowIndexCacheByWorkspace.removeValue(forKey: workspaceId)
                return
            }
            orderedWindowIds.append(windowId)
            orderedHandles.append(handle)
        }
        runtimeDecodeWindowIndexCacheByWorkspace[workspaceId] = RuntimeDecodeWindowIndexCache(
            windowIds: orderedWindowIds,
            handles: orderedHandles
        )
    }
    func updateNodeReferences(
        for workspaceId: WorkspaceDescriptor.ID,
        currentNodeIds: Set<NodeId>
    ) -> [NodeId] {
        let previousNodeIds = workspaceNodeIds[workspaceId] ?? []
        let addedNodeIds = currentNodeIds.subtracting(previousNodeIds)
        let removedNodeIds = previousNodeIds.subtracting(currentNodeIds)
        workspaceNodeIds[workspaceId] = currentNodeIds
        for nodeId in addedNodeIds {
            nodeReferenceCounts[nodeId, default: 0] += 1
        }
        var cleanupCandidates: [NodeId] = []
        cleanupCandidates.reserveCapacity(removedNodeIds.count)
        for nodeId in removedNodeIds {
            let nextCount = (nodeReferenceCounts[nodeId] ?? 1) - 1
            if nextCount <= 0 {
                nodeReferenceCounts.removeValue(forKey: nodeId)
                cleanupCandidates.append(nodeId)
            } else {
                nodeReferenceCounts[nodeId] = nextCount
            }
        }
        return cleanupCandidates
    }
    func normalizeRuntimeExport(_ export: inout ZigNiriStateKernel.RuntimeStateExport) {
        let maxPerColumn = max(1, maxWindowsPerColumn)
        guard runtimeExportNeedsNormalization(export, maxPerColumn: maxPerColumn) else {
            return
        }
        var windowsByColumn = groupedRuntimeWindowsByColumn(export)
        let normalized = rebuildNormalizedRuntimeExport(
            sourceColumns: export.columns,
            windowsByColumn: &windowsByColumn,
            sourceWindows: export.windows,
            maxPerColumn: maxPerColumn
        )
        export.columns = normalized.columns
        export.windows = normalized.windows
    }
    func runtimeExportNeedsNormalization(
        _ export: ZigNiriStateKernel.RuntimeStateExport,
        maxPerColumn: Int
    ) -> Bool {
        guard !export.columns.isEmpty else {
            return true
        }
        var seenWindowIds = Set<NodeId>()
        seenWindowIds.reserveCapacity(export.windows.count)
        for (columnIndex, column) in export.columns.enumerated() {
            let start = column.windowStart
            let count = column.windowCount
            guard start >= 0,
                  count >= 0,
                  start <= export.windows.count,
                  count <= export.windows.count - start
            else {
                return true
            }
            if count > maxPerColumn {
                return true
            }
            if count == 0 {
                if column.activeTileIdx != 0 {
                    return true
                }
                continue
            }
            if column.activeTileIdx < 0 || column.activeTileIdx >= count {
                return true
            }
            for index in start ..< start + count {
                let runtimeWindow = export.windows[index]
                if runtimeWindow.columnId != column.columnId || runtimeWindow.columnIndex != columnIndex {
                    return true
                }
                if !seenWindowIds.insert(runtimeWindow.windowId).inserted {
                    return true
                }
            }
        }
        return seenWindowIds.count != export.windows.count
    }
    func groupedRuntimeWindowsByColumn(
        _ export: ZigNiriStateKernel.RuntimeStateExport
    ) -> [NodeId: [ZigNiriStateKernel.RuntimeWindowState]] {
        var windowsByColumn: [NodeId: [ZigNiriStateKernel.RuntimeWindowState]] = [:]
        windowsByColumn.reserveCapacity(export.columns.count + 1)
        var orderedWindowIds = Set<NodeId>()
        orderedWindowIds.reserveCapacity(export.windows.count)
        for sourceColumn in export.columns {
            let start = sourceColumn.windowStart
            let count = sourceColumn.windowCount
            guard start >= 0,
                  count >= 0,
                  start <= export.windows.count,
                  count <= export.windows.count - start
            else {
                windowsByColumn[sourceColumn.columnId, default: []] = []
                continue
            }
            for runtimeWindow in export.windows[start ..< start + count] {
                windowsByColumn[sourceColumn.columnId, default: []].append(runtimeWindow)
                orderedWindowIds.insert(runtimeWindow.windowId)
            }
        }
        for runtimeWindow in export.windows where !orderedWindowIds.contains(runtimeWindow.windowId) {
            windowsByColumn[runtimeWindow.columnId, default: []].append(runtimeWindow)
        }
        return windowsByColumn
    }
    func rebuildNormalizedRuntimeExport(
        sourceColumns: [ZigNiriStateKernel.RuntimeColumnState],
        windowsByColumn: inout [NodeId: [ZigNiriStateKernel.RuntimeWindowState]],
        sourceWindows: [ZigNiriStateKernel.RuntimeWindowState],
        maxPerColumn: Int
    ) -> (columns: [ZigNiriStateKernel.RuntimeColumnState], windows: [ZigNiriStateKernel.RuntimeWindowState]) {
        var normalizedColumns: [ZigNiriStateKernel.RuntimeColumnState] = []
        normalizedColumns.reserveCapacity(max(1, sourceColumns.count))
        var normalizedWindows: [ZigNiriStateKernel.RuntimeWindowState] = []
        normalizedWindows.reserveCapacity(sourceWindows.count)
        var occupiedNodeIds = Set<NodeId>()
        occupiedNodeIds.reserveCapacity(sourceColumns.count + sourceWindows.count)
        occupiedNodeIds.formUnion(sourceColumns.map(\.columnId))
        occupiedNodeIds.formUnion(sourceWindows.map(\.windowId))
        for sourceColumn in sourceColumns {
            appendColumnWithSplits(
                sourceColumn: sourceColumn,
                windowsByColumn: &windowsByColumn,
                maxPerColumn: maxPerColumn,
                normalizedColumns: &normalizedColumns,
                normalizedWindows: &normalizedWindows,
                occupiedNodeIds: &occupiedNodeIds
            )
        }
        if !windowsByColumn.isEmpty {
            let orphanColumnIds = windowsByColumn.keys.sorted { lhs, rhs in
                lhs.uuid.uuidString < rhs.uuid.uuidString
            }
            for orphanColumnId in orphanColumnIds {
                appendColumnWithSplits(
                    sourceColumn: defaultRuntimeColumnState(columnId: orphanColumnId),
                    windowsByColumn: &windowsByColumn,
                    maxPerColumn: maxPerColumn,
                    normalizedColumns: &normalizedColumns,
                    normalizedWindows: &normalizedWindows,
                    occupiedNodeIds: &occupiedNodeIds
                )
            }
        }
        if normalizedColumns.isEmpty {
            normalizedColumns = [defaultRuntimeColumnState(columnId: NodeId())]
        }
        return (columns: normalizedColumns, windows: normalizedWindows)
    }
    func appendColumnWithSplits(
        sourceColumn: ZigNiriStateKernel.RuntimeColumnState,
        windowsByColumn: inout [NodeId: [ZigNiriStateKernel.RuntimeWindowState]],
        maxPerColumn: Int,
        normalizedColumns: inout [ZigNiriStateKernel.RuntimeColumnState],
        normalizedWindows: inout [ZigNiriStateKernel.RuntimeWindowState],
        occupiedNodeIds: inout Set<NodeId>
    ) {
        let columnWindows = windowsByColumn[sourceColumn.columnId] ?? []
        windowsByColumn.removeValue(forKey: sourceColumn.columnId)
        if columnWindows.isEmpty {
            let start = normalizedWindows.count
            normalizedColumns.append(
                ZigNiriStateKernel.RuntimeColumnState(
                    columnId: sourceColumn.columnId,
                    windowStart: start,
                    windowCount: 0,
                    activeTileIdx: 0,
                    isTabbed: sourceColumn.isTabbed,
                    sizeValue: sourceColumn.sizeValue,
                    widthKind: sourceColumn.widthKind,
                    isFullWidth: sourceColumn.isFullWidth,
                    hasSavedWidth: sourceColumn.hasSavedWidth,
                    savedWidthKind: sourceColumn.savedWidthKind,
                    savedWidthValue: sourceColumn.savedWidthValue
                )
            )
            return
        }
        let sourceActiveIndex = min(max(sourceColumn.activeTileIdx, 0), columnWindows.count - 1)
        var chunkStart = 0
        var chunkIndex = 0
        while chunkStart < columnWindows.count {
            let chunkEnd = min(columnWindows.count, chunkStart + maxPerColumn)
            let chunk = columnWindows[chunkStart ..< chunkEnd]
            let activeTileIdx: Int
            if sourceActiveIndex >= chunkStart, sourceActiveIndex < chunkEnd {
                activeTileIdx = sourceActiveIndex - chunkStart
            } else {
                activeTileIdx = 0
            }
            appendColumnChunk(
                sourceColumn: sourceColumn,
                chunk: chunk,
                chunkIndex: chunkIndex,
                activeTileIdx: activeTileIdx,
                normalizedColumns: &normalizedColumns,
                normalizedWindows: &normalizedWindows,
                occupiedNodeIds: &occupiedNodeIds
            )
            chunkStart = chunkEnd
            chunkIndex += 1
        }
    }
    func appendColumnChunk(
        sourceColumn: ZigNiriStateKernel.RuntimeColumnState,
        chunk: ArraySlice<ZigNiriStateKernel.RuntimeWindowState>,
        chunkIndex: Int,
        activeTileIdx: Int,
        normalizedColumns: inout [ZigNiriStateKernel.RuntimeColumnState],
        normalizedWindows: inout [ZigNiriStateKernel.RuntimeWindowState],
        occupiedNodeIds: inout Set<NodeId>
    ) {
        let isFirstChunk = chunkIndex == 0
        let columnId: NodeId
        if isFirstChunk {
            columnId = sourceColumn.columnId
        } else {
            columnId = splitColumnId(
                from: sourceColumn.columnId,
                splitIndex: chunkIndex,
                occupied: &occupiedNodeIds
            )
        }
        let start = normalizedWindows.count
        let columnIndex = normalizedColumns.count
        for runtimeWindow in chunk {
            normalizedWindows.append(
                ZigNiriStateKernel.RuntimeWindowState(
                    windowId: runtimeWindow.windowId,
                    columnId: columnId,
                    columnIndex: columnIndex,
                    sizeValue: runtimeWindow.sizeValue,
                    heightKind: runtimeWindow.heightKind,
                    heightValue: runtimeWindow.heightValue
                )
            )
        }
        if isFirstChunk {
            normalizedColumns.append(
                ZigNiriStateKernel.RuntimeColumnState(
                    columnId: columnId,
                    windowStart: start,
                    windowCount: chunk.count,
                    activeTileIdx: activeTileIdx,
                    isTabbed: sourceColumn.isTabbed,
                    sizeValue: sourceColumn.sizeValue,
                    widthKind: sourceColumn.widthKind,
                    isFullWidth: sourceColumn.isFullWidth,
                    hasSavedWidth: sourceColumn.hasSavedWidth,
                    savedWidthKind: sourceColumn.savedWidthKind,
                    savedWidthValue: sourceColumn.savedWidthValue
                )
            )
        } else {
            let spillColumn = defaultRuntimeColumnState(columnId: columnId)
            normalizedColumns.append(
                ZigNiriStateKernel.RuntimeColumnState(
                    columnId: columnId,
                    windowStart: start,
                    windowCount: chunk.count,
                    activeTileIdx: activeTileIdx,
                    isTabbed: sourceColumn.isTabbed,
                    sizeValue: spillColumn.sizeValue,
                    widthKind: spillColumn.widthKind,
                    isFullWidth: false,
                    hasSavedWidth: false,
                    savedWidthKind: spillColumn.savedWidthKind,
                    savedWidthValue: spillColumn.savedWidthValue
                )
            )
        }
    }
    func defaultRuntimeColumnState(columnId: NodeId) -> ZigNiriStateKernel.RuntimeColumnState {
        ZigNiriStateKernel.RuntimeColumnState(
            columnId: columnId,
            windowStart: 0,
            windowCount: 0,
            activeTileIdx: 0,
            isTabbed: false,
            sizeValue: 1.0,
            widthKind: ZigNiriStateKernel.sizeKindProportion,
            isFullWidth: false,
            hasSavedWidth: false,
            savedWidthKind: ZigNiriStateKernel.sizeKindProportion,
            savedWidthValue: 1.0
        )
    }
    func splitColumnId(
        from baseColumnId: NodeId,
        splitIndex: Int,
        occupied: inout Set<NodeId>
    ) -> NodeId {
        var salt = UInt32(max(1, splitIndex))
        while true {
            var raw = baseColumnId.uuid.uuid
            var encodedSalt = salt.littleEndian
            withUnsafeMutableBytes(of: &raw) { bytes in
                withUnsafeBytes(of: &encodedSalt) { saltBytes in
                    for idx in 0 ..< 4 {
                        bytes[12 + idx] ^= saltBytes[idx]
                    }
                    bytes[8] ^= saltBytes[0]
                    bytes[9] ^= saltBytes[1]
                }
            }
            let candidate = NodeId(uuid: UUID(uuid: raw))
            if candidate != baseColumnId, !occupied.contains(candidate) {
                occupied.insert(candidate)
                return candidate
            }
            salt &+= 1
        }
    }
    func nearestNonFullColumnIndex(
        columns: [ZigNiriStateKernel.RuntimeColumnState],
        windowsByColumn: [NodeId: [NodeId]],
        anchorIndex: Int,
        maxPerColumn: Int
    ) -> Int? {
        guard !columns.isEmpty else { return nil }
        let clampedAnchorIndex = min(max(anchorIndex, 0), columns.count - 1)
        var bestIndex: Int?
        var bestDistance = Int.max
        for (index, column) in columns.enumerated() {
            let count = windowsByColumn[column.columnId, default: []].count
            guard count < maxPerColumn else { continue }
            let distance = abs(index - clampedAnchorIndex)
            if distance < bestDistance || (distance == bestDistance && index < (bestIndex ?? Int.max)) {
                bestIndex = index
                bestDistance = distance
            }
        }
        return bestIndex
    }
    func preferredWindowId(
        in column: ZigNiriColumnView,
        focusedWindowId: NodeId?
    ) -> NodeId? {
        ZigNiriSelectionResolver.preferredWindowId(
            in: column,
            focusedWindowId: focusedWindowId
        )
    }
    func activeColumnIndex(
        in view: ZigNiriWorkspaceView,
        selectedNodeId: NodeId?,
        focusedWindowId: NodeId?
    ) -> Int? {
        if let selectedNodeId {
            if let selectedColumnIndex = view.columns.firstIndex(where: { $0.nodeId == selectedNodeId }) {
                return selectedColumnIndex
            }
            if let selectedWindowColumnIndex = view.columns.firstIndex(where: { $0.windowIds.contains(selectedNodeId) }) {
                return selectedWindowColumnIndex
            }
        }
        if let focusedWindowId,
           let focusedColumnIndex = view.columns.firstIndex(where: { $0.windowIds.contains(focusedWindowId) })
        {
            return focusedColumnIndex
        }
        if let firstPopulated = view.columns.firstIndex(where: { !$0.windowIds.isEmpty }) {
            return firstPopulated
        }
        return view.columns.isEmpty ? nil : 0
    }
    func cleanupWindowMappings(for nodeId: NodeId) {
        if let handle = windowHandlesByNodeId.removeValue(forKey: nodeId) {
            windowNodeIdsByHandle.removeValue(forKey: handle)
        }
        windowSizingModesByNodeId.removeValue(forKey: nodeId)
        savedWindowHeightsByNodeId.removeValue(forKey: nodeId)
        if !windowHandlesByNodeId.keys.contains(where: { $0.uuid == nodeId.uuid }) {
            windowHandlesByUUID.removeValue(forKey: nodeId.uuid)
        }
    }
    func normalizedSelection(
        _ selection: ZigNiriSelection?,
        in view: ZigNiriWorkspaceView,
        allowNilWhenRequested: Bool = false
    ) -> ZigNiriSelection? {
        if allowNilWhenRequested, selection == nil {
            return nil
        }
        guard !view.columns.isEmpty || !view.windowsById.isEmpty else {
            return nil
        }
        func containsNode(_ nodeId: NodeId) -> Bool {
            if view.windowsById[nodeId] != nil {
                return true
            }
            return view.columns.contains(where: { $0.nodeId == nodeId })
        }
        let firstWindowId = view.columns.lazy
            .compactMap { $0.windowIds.first }
            .first
            ?? view.windowsById.keys.first
        var selectedNodeId = selection?.selectedNodeId
        if let currentSelectedNodeId = selectedNodeId, !containsNode(currentSelectedNodeId) {
            selectedNodeId = nil
        }
        if selectedNodeId == nil {
            selectedNodeId = firstWindowId ?? view.columns.first?.nodeId
        }
        var focusedWindowId = selection?.focusedWindowId
        if let currentFocusedWindowId = focusedWindowId, view.windowsById[currentFocusedWindowId] == nil {
            focusedWindowId = nil
        }
        if focusedWindowId == nil,
           let selectedNodeId,
           view.windowsById[selectedNodeId] != nil
        {
            focusedWindowId = selectedNodeId
        }
        if focusedWindowId == nil {
            focusedWindowId = firstWindowId
        }
        return ZigNiriSelection(
            selectedNodeId: selectedNodeId,
            focusedWindowId: focusedWindowId
        )
    }
    func applyFocusState(to view: inout ZigNiriWorkspaceView) {
        let focusedWindowId = view.selection?.focusedWindowId
        let currentFocusedWindowId = view.windowsById.first(where: { $0.value.isFocused })?.key
        guard currentFocusedWindowId != focusedWindowId else {
            return
        }
        if let currentFocusedWindowId,
           var window = view.windowsById[currentFocusedWindowId]
        {
            window.isFocused = false
            view.windowsById[currentFocusedWindowId] = window
        }
        if let focusedWindowId,
           var window = view.windowsById[focusedWindowId]
        {
            window.isFocused = true
            view.windowsById[focusedWindowId] = window
        }
    }
    private func runtimeSelectionAnchor(
        selectedNodeId: NodeId?,
        in view: ZigNiriWorkspaceView?
    ) -> RuntimeSelectionAnchor? {
        guard let view else { return nil }
        guard let selectedNodeId = selectedNodeId ?? view.selection?.selectedNodeId else {
            if let firstColumn = view.columns.first {
                let firstWindow = preferredWindowId(
                    in: firstColumn,
                    focusedWindowId: view.selection?.focusedWindowId
                )
                return RuntimeSelectionAnchor(
                    windowId: firstWindow,
                    columnId: firstColumn.nodeId,
                    rowIndex: firstWindow.flatMap { rowIndex(for: $0, in: firstColumn.windowIds) }
                )
            }
            return nil
        }
        if let window = view.windowsById[selectedNodeId] {
            let row: Int?
            if let columnId = window.columnId,
               let column = view.columns.first(where: { $0.nodeId == columnId })
            {
                row = rowIndex(for: selectedNodeId, in: column.windowIds)
            } else {
                row = nil
            }
            return RuntimeSelectionAnchor(
                windowId: selectedNodeId,
                columnId: window.columnId,
                rowIndex: row
            )
        }
        guard let column = view.columns.first(where: { $0.nodeId == selectedNodeId }) else {
            return nil
        }
        let windowId = preferredWindowId(
            in: column,
            focusedWindowId: view.selection?.focusedWindowId
        )
        return RuntimeSelectionAnchor(
            windowId: windowId,
            columnId: column.nodeId,
            rowIndex: windowId.flatMap { rowIndex(for: $0, in: column.windowIds) }
        )
    }
    func runtimeNavigationRequest(
        for request: ZigNiriNavigationRequest,
        orientation: Monitor.Orientation,
        in view: ZigNiriWorkspaceView
    ) -> ZigNiriStateKernel.NavigationRequest? {
        let anchor = runtimeSelectionAnchor(
            selectedNodeId: view.selection?.selectedNodeId,
            in: view
        )
        switch request {
        case let .focus(direction):
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusTarget,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId,
                direction: direction,
                orientation: orientation,
                infiniteLoop: infiniteLoop
            )
        case let .move(direction):
            guard let anchor else { return nil }
            if let step = direction.primaryStep(for: orientation) {
                return ZigNiriStateKernel.NavigationRequest(
                    op: .moveByColumns,
                    sourceWindowId: anchor.windowId,
                    sourceColumnId: anchor.columnId,
                    direction: direction,
                    orientation: orientation,
                    infiniteLoop: infiniteLoop,
                    step: step,
                    targetRowIndex: anchor.rowIndex ?? -1
                )
            }
            if direction.secondaryStep(for: orientation) != nil {
                return ZigNiriStateKernel.NavigationRequest(
                    op: .moveVertical,
                    sourceWindowId: anchor.windowId,
                    sourceColumnId: anchor.columnId,
                    direction: direction,
                    orientation: orientation,
                    infiniteLoop: infiniteLoop
                )
            }
            return nil
        case .focusDownOrLeft:
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusDownOrLeft,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId
            )
        case .focusUpOrRight:
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusUpOrRight,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId
            )
        case .focusColumnFirst:
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusColumnFirst,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId
            )
        case .focusColumnLast:
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusColumnLast,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId
            )
        case let .focusColumn(index):
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusColumnIndex,
                sourceWindowId: anchor?.windowId,
                sourceColumnId: anchor?.columnId,
                focusColumnIndex: index
            )
        case let .focusWindow(index):
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusWindowIndex,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId,
                focusWindowIndex: index
            )
        case .focusWindowTop:
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusWindowTop,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId
            )
        case .focusWindowBottom:
            guard let anchor else { return nil }
            return ZigNiriStateKernel.NavigationRequest(
                op: .focusWindowBottom,
                sourceWindowId: anchor.windowId,
                sourceColumnId: anchor.columnId
            )
        }
    }
    func navigationFallbackTarget(
        for request: ZigNiriNavigationRequest,
        in view: ZigNiriWorkspaceView
    ) -> NodeId? {
        switch request {
        case .focusColumnFirst:
            guard let column = view.columns.first else { return nil }
            return column.windowIds.first ?? column.nodeId
        case .focusColumnLast:
            guard let column = view.columns.last else { return nil }
            return column.windowIds.last ?? column.nodeId
        case let .focusColumn(index):
            guard view.columns.indices.contains(index) else { return nil }
            let column = view.columns[index]
            return column.windowIds.first ?? column.nodeId
        case let .focusWindow(index):
            let orderedWindowIds = view.columns.flatMap(\.windowIds)
            guard orderedWindowIds.indices.contains(index) else { return nil }
            return orderedWindowIds[index]
        case .focusDownOrLeft:
            return view.columns.first?.windowIds.first ?? view.selection?.selectedNodeId
        case .focusUpOrRight:
            return view.columns.last?.windowIds.last ?? view.selection?.selectedNodeId
        case .focusWindowTop:
            guard let selected = view.selection?.selectedNodeId else { return nil }
            guard let window = view.windowsById[selected],
                  let columnId = window.columnId,
                  let column = view.columns.first(where: { $0.nodeId == columnId })
            else {
                return view.columns.first?.windowIds.first
            }
            return column.windowIds.first
        case .focusWindowBottom:
            guard let selected = view.selection?.selectedNodeId else { return nil }
            guard let window = view.windowsById[selected],
                  let columnId = window.columnId,
                  let column = view.columns.first(where: { $0.nodeId == columnId })
            else {
                return view.columns.first?.windowIds.last
            }
            return column.windowIds.last
        case .focus, .move:
            return view.selection?.selectedNodeId
        }
    }
    func captureNodeFrames(in workspaceId: WorkspaceDescriptor.ID) -> [NodeId: CGRect] {
        guard let view = workspaceViews[workspaceId] else {
            return [:]
        }
        var framesByNodeId: [NodeId: CGRect] = [:]
        framesByNodeId.reserveCapacity(view.windowsById.count)
        for (windowId, window) in view.windowsById {
            if let frame = window.frame {
                framesByNodeId[windowId] = frame
            }
        }
        return framesByNodeId
    }
    func scheduleStructuralAnimation(
        in workspaceId: WorkspaceDescriptor.ID,
        from fromFramesByNodeId: [NodeId: CGRect],
        duration: TimeInterval = ZigNiriEngine.mutationAnimationDuration
    ) {
        _ = fromFramesByNodeId
        _ = duration
        guard let context = ensureRuntimeContext(for: workspaceId) else {
            return
        }
        _ = ZigNiriStateKernel.cancelAnimation(context: context)
        _ = ZigNiriStateKernel.startMutationAnimation(
            context: context,
            sampleTime: currentTime()
        )
    }
    func shiftedFrame(
        _ frame: CGRect,
        orientation: Monitor.Orientation,
        offset: CGFloat
    ) -> CGRect {
        if orientation == .horizontal {
            return frame.offsetBy(dx: offset, dy: 0)
        }
        return frame.offsetBy(dx: 0, dy: offset)
    }
    func interpolatedFrame(from: CGRect, to: CGRect, progress: TimeInterval) -> CGRect {
        let t = CGFloat(max(0, min(1, progress)))
        return CGRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * t,
            y: from.origin.y + (to.origin.y - from.origin.y) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        )
    }
    func rowIndex(for windowId: NodeId, in windowIds: [NodeId]) -> Int? {
        windowIds.firstIndex(of: windowId)
    }
    func columnIndex(for windowId: NodeId, in view: ZigNiriWorkspaceView) -> Int? {
        view.columns.firstIndex { $0.windowIds.contains(windowId) }
    }
}
