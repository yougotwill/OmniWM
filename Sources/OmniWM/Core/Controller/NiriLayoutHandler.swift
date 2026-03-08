import AppKit
import Foundation
import QuartzCore

@MainActor
final class NiriLayoutHandler {
    weak var controller: WMController?
    var scrollAnimationByDisplay: [CGDirectDisplayID: WorkspaceDescriptor.ID] = [:]

    init(controller: WMController?) {
        self.controller = controller
    }

    @discardableResult
    private func submit(_ hotkeyCommand: HotkeyCommand) -> Bool {
        guard let controller,
              let controllerCommand = hotkeyCommand.controllerCommand
        else {
            return false
        }
        return controller.submitControllerCommand(controllerCommand)
    }

    func registerScrollAnimation(_ workspaceId: WorkspaceDescriptor.ID, on displayId: CGDirectDisplayID) -> Bool {
        if scrollAnimationByDisplay[displayId] == workspaceId {
            return false
        }
        scrollAnimationByDisplay[displayId] = workspaceId
        return true
    }

    func tickScrollAnimation(targetTime: CFTimeInterval, displayId: CGDirectDisplayID) {
        guard let wsId = scrollAnimationByDisplay[displayId] else { return }
        guard let controller,
              let monitor = controller.workspaceManager.monitors.first(where: { $0.displayId == displayId })
        else {
            controller?.layoutRefreshController.stopScrollAnimation(for: displayId)
            return
        }

        let isAnimating = applyFramesOnDemand(
            wsId: wsId,
            monitor: monitor,
            animationTime: targetTime
        )

        if !isAnimating {
            finalizeAnimation(for: wsId)
            var activeIds = Set<WorkspaceDescriptor.ID>()
            for mon in controller.workspaceManager.monitors {
                if let ws = controller.workspaceManager.activeWorkspaceOrFirst(on: mon.id) {
                    activeIds.insert(ws.id)
                }
            }
            controller.layoutRefreshController.hideInactiveWorkspaces(activeWorkspaceIds: activeIds)
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
        }
    }

    func applyFramesOnDemand(
        wsId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        animationTime: TimeInterval? = nil
    ) -> Bool {
        guard let controller,
              let zig = controller.zigNiriEngine
        else {
            return false
        }

        let orientation = controller.settings.effectiveOrientation(for: monitor)
        let gaps = ZigNiriGaps(
            horizontal: CGFloat(controller.workspaceManager.gaps),
            vertical: CGFloat(controller.workspaceManager.gaps)
        )
        let lrc = controller.layoutRefreshController
        let insetFrame = controller.insetWorkingFrame(for: monitor)

        let area = ZigNiriWorkingAreaContext(
            workingFrame: insetFrame,
            viewFrame: monitor.frame,
            scale: lrc.backingScale(for: monitor)
        )

        let now = animationTime ?? CACurrentMediaTime()
        let layoutResult = zig.calculateLayout(
            ZigNiriLayoutRequest(
                workspaceId: wsId,
                monitorFrame: monitor.visibleFrame,
                screenFrame: monitor.frame,
                gaps: gaps,
                scale: area.scale,
                workingArea: area,
                orientation: orientation,
                viewportOffset: zig.viewportOffset(in: wsId, at: now),
                animationTime: now
            )
        )

        let frames = layoutResult.frames
        let hiddenHandles = layoutResult.hiddenHandles

        var hiddenWindowJobs: [(pid: pid_t, windowId: Int)] = []
        var visibleWindowJobs: [(pid: pid_t, windowId: Int)] = []

        let workspaceEntries = controller.workspaceManager.entries(in: wsId)
        for entry in workspaceEntries {
            if hiddenHandles[entry.handle] != nil {
                hiddenWindowJobs.append((entry.handle.pid, entry.windowId))
            } else {
                visibleWindowJobs.append((entry.handle.pid, entry.windowId))
            }
        }

        if !hiddenWindowJobs.isEmpty {
            controller.axManager.suppressFrameWrites(hiddenWindowJobs)
            controller.axManager.cancelPendingFrameJobs(hiddenWindowJobs)
        }

        for entry in workspaceEntries {
            if let side = hiddenHandles[entry.handle] {
                let targetY = frames[entry.handle]?.origin.y
                lrc.hideWindow(entry, monitor: monitor, side: side, targetY: targetY, reason: .layoutTransient)
            } else {
                lrc.unhideWindow(entry, monitor: monitor)
            }
        }

        var frameUpdates: [(pid: pid_t, windowId: Int, frame: CGRect)] = []
        for (handle, frame) in frames {
            if hiddenHandles[handle] != nil { continue }
            if let entry = controller.workspaceManager.entry(for: handle) {
                if let nodeId = zig.nodeId(for: handle),
                   let workspaceView = zig.workspaceView(for: wsId),
                   workspaceView.windowsById[nodeId]?.sizingMode == .fullscreen
                {
                    controller.axManager.forceApplyNextFrame(for: entry.windowId)
                }
                frameUpdates.append((handle.pid, entry.windowId, frame))
            }
        }

        if !visibleWindowJobs.isEmpty {
            let activeJobs = visibleWindowJobs.filter { !controller.axManager.inactiveWorkspaceWindowIds.contains($0.windowId) }
            if !activeJobs.isEmpty {
                controller.axManager.unsuppressFrameWrites(activeJobs)
            }
        }

        controller.axManager.applyFramesParallel(frameUpdates)
        let updateMode = Self.borderUpdateMode(for: animationTime)
        updateBorderDuringLayout(frames: frames, hiddenHandles: hiddenHandles, updateMode: updateMode)
        return layoutResult.isAnimating
    }

    static func borderUpdateMode(for animationTime: TimeInterval?) -> BorderPresentationUpdateMode {
        _ = animationTime
        return .coalesced
    }

    private func updateBorderDuringLayout(
        frames: [WindowHandle: CGRect],
        hiddenHandles: [WindowHandle: HideSide],
        updateMode: BorderPresentationUpdateMode
    ) {
        guard let controller,
              let focusedHandle = controller.focusedHandle
        else {
            return
        }

        if hiddenHandles[focusedHandle] != nil {
            controller.refreshBorderPresentation(forceHide: true, updateMode: updateMode)
            return
        }

        guard let frame = frames[focusedHandle],
              let entry = controller.workspaceManager.entry(for: focusedHandle)
        else {
            return
        }

        controller.refreshBorderPresentation(
            focusedFrame: frame,
            windowId: entry.windowId,
            updateMode: updateMode
        )
    }

    private func finalizeAnimation(for workspaceId: WorkspaceDescriptor.ID) {
        guard let controller else { return }

        if let focusedHandle = controller.focusedHandle,
           let entry = controller.workspaceManager.entry(for: focusedHandle),
           let workspaceView = controller.syncZigNiriWorkspace(workspaceId: workspaceId),
           let nodeId = controller.zigNodeId(for: focusedHandle),
           let frame = workspaceView.windowsById[nodeId]?.frame
        {
            controller.refreshBorderPresentation(focusedFrame: frame, windowId: entry.windowId)
        }

        if controller.moveMouseToFocusedWindowEnabled,
           let focusedHandle = controller.focusedHandle
        {
            controller.moveMouseToWindow(focusedHandle)
        }
    }

    func cancelActiveAnimations(for workspaceId: WorkspaceDescriptor.ID) {
        guard let controller else { return }
        for (displayId, wsId) in scrollAnimationByDisplay where wsId == workspaceId {
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
        }
        _ = controller.zigNiriEngine?.cancelViewportMotion(in: workspaceId)
        controller.zigNiriEngine?.cancelStructuralAnimation(in: workspaceId)
    }

    func layoutWithNiriEngine(
        activeWorkspaces: Set<WorkspaceDescriptor.ID>,
        useScrollAnimationPath: Bool = false,
        removedNodeId _: NodeId? = nil
    ) async {
        guard let controller,
              let zig = controller.zigNiriEngine
        else {
            return
        }

        var processed: Set<WorkspaceDescriptor.ID> = []

        for monitor in controller.workspaceManager.monitors {
            guard let workspace = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id) else { continue }
            let wsId = workspace.id
            guard activeWorkspaces.contains(wsId) else { continue }
            guard !processed.contains(wsId) else { continue }
            processed.insert(wsId)

            let handles = controller.workspaceManager.entries(in: wsId).map(\.handle)
            controller.workspaceManager.withNiriViewportState(for: wsId) { state in
                _ = zig.syncWindows(
                    handles,
                    in: wsId,
                    selectedNodeId: state.selectedNodeId,
                    focusedHandle: controller.focusedHandle
                )

                if let selection = zig.workspaceView(for: wsId)?.selection?.selectedNodeId {
                    state.selectedNodeId = selection
                }

                let isAnimating = applyFramesOnDemand(wsId: wsId, monitor: monitor)

                if !useScrollAnimationPath, isAnimating {
                    controller.layoutRefreshController.startScrollAnimation(for: wsId)
                }
            }

            await Task.yield()
        }

        updateTabbedColumnOverlays()
        controller.updateWorkspaceBar()
    }

    func updateTabbedColumnOverlays() {
        guard let controller,
              let zig = controller.zigNiriEngine
        else {
            controller?.tabbedOverlayManager.removeAll()
            return
        }

        var infos: [TabbedColumnOverlayInfo] = []
        for monitor in controller.workspaceManager.monitors {
            guard let workspace = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id) else { continue }
            guard let view = controller.syncZigNiriWorkspace(workspaceId: workspace.id) else { continue }

            for column in view.columns where column.display == .tabbed {
                let visibleWindows = column.windowIds.compactMap { view.windowsById[$0] }
                guard !visibleWindows.isEmpty else { continue }

                let frames = visibleWindows.compactMap(\.frame)
                guard !frames.isEmpty else { continue }

                let unionFrame = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                guard TabbedColumnOverlayManager.shouldShowOverlay(
                    columnFrame: unionFrame,
                    visibleFrame: monitor.visibleFrame
                ) else { continue }

                let clampedIndex = min(max(0, column.activeWindowIndex ?? 0), visibleWindows.count - 1)
                let activeHandle = visibleWindows[clampedIndex].handle
                let activeWindowId = controller.workspaceManager.entry(for: activeHandle)?.windowId

                infos.append(
                    TabbedColumnOverlayInfo(
                        workspaceId: workspace.id,
                        columnId: column.nodeId,
                        columnFrame: unionFrame,
                        tabCount: visibleWindows.count,
                        activeIndex: clampedIndex,
                        activeWindowId: activeWindowId
                    )
                )
            }
        }

        _ = zig
        controller.tabbedOverlayManager.updateOverlays(infos)
    }

    func selectTabInNiri(workspaceId: WorkspaceDescriptor.ID, columnId: NodeId, index: Int) {
        guard let controller else {
            return
        }

        guard let view = controller.syncZigNiriWorkspace(workspaceId: workspaceId),
              let column = view.columns.first(where: { $0.nodeId == columnId }),
              column.windowIds.indices.contains(index)
        else {
            return
        }

        let selectedWindowId = column.windowIds[index]
        guard let handle = controller.zigWindowHandle(for: selectedWindowId, workspaceId: workspaceId) else {
            return
        }

        _ = controller.submitControllerCommand(.focusWindow(handleId: handle.id))
        updateTabbedColumnOverlays()
    }

    func focusPrevious() {
        _ = submit(.focusPrevious)
    }

    func focusDownOrLeft() {
        _ = submit(.focusDownOrLeft)
    }

    func focusUpOrRight() {
        _ = submit(.focusUpOrRight)
    }

    func focusColumnFirst() {
        _ = submit(.focusColumnFirst)
    }

    func focusColumnLast() {
        _ = submit(.focusColumnLast)
    }

    func focusColumn(index: Int) {
        _ = submit(.focusColumn(index))
    }

    func focusWindowTop() {
        _ = submit(.focusWindowTop)
    }

    func focusWindowBottom() {
        _ = submit(.focusWindowBottom)
    }

    func moveWindow(direction: Direction) {
        _ = submit(.move(direction))
    }

    func swapWindow(direction: Direction) {
        _ = submit(.swap(direction))
    }

    func moveColumn(direction: Direction) {
        _ = submit(.moveColumn(direction))
    }

    func consumeWindow(direction: Direction) {
        _ = submit(.consumeWindow(direction))
    }

    func expelWindow(direction: Direction) {
        _ = submit(.expelWindow(direction))
    }

    func toggleColumnTabbed() {
        _ = submit(.toggleColumnTabbed)
    }

    func toggleColumnFullWidth() {
        _ = submit(.toggleColumnFullWidth)
    }

    func toggleFullscreen() {
        if submit(.toggleFullscreen) {
            return
        }
        guard let controller else { return }

        withActiveWorkspaceFallback { wsId, monitor, state, zig in
            guard let selectedWindowId = selectedWindowId(
                in: wsId,
                state: state,
                controller: controller
            ),
                  let view = controller.syncZigNiriWorkspace(workspaceId: wsId, selectedNodeId: selectedWindowId),
                  let currentMode = view.windowsById[selectedWindowId]?.sizingMode
            else {
                return
            }

            let nextMode: SizingMode = currentMode == .fullscreen ? .normal : .fullscreen
            let result = zig.applyMutation(
                .setWindowSizing(windowId: selectedWindowId, mode: nextMode),
                in: wsId,
                selection: currentSelection(workspaceId: wsId, state: state, controller: controller)
            )
            applyFallbackMutationSelection(
                result,
                workspaceId: wsId,
                monitor: monitor,
                state: &state,
                controller: controller,
                animateViewport: false
            )
        }
    }

    func cycleSize(forward: Bool) {
        _ = submit(forward ? .cycleColumnWidthForward : .cycleColumnWidthBackward)
    }

    func balanceSizes() {
        _ = submit(.balanceSizes)
    }

    func overviewInsertWindow(
        handle: WindowHandle,
        targetHandle: WindowHandle,
        position: InsertPosition,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        controller?.overviewInsertWindow(
            handle: handle,
            targetHandle: targetHandle,
            position: position,
            in: workspaceId
        )
    }

    func overviewInsertWindowInNewColumn(
        handle: WindowHandle,
        insertIndex: Int,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
        controller?.overviewInsertWindowInNewColumn(
            handle: handle,
            insertIndex: insertIndex,
            in: workspaceId
        )
    }

    func enableNiriLayout(
        maxWindowsPerColumn: Int = 3,
        centerFocusedColumn _: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn _: Bool = false
    ) {
        guard let controller else { return }

        if controller.zigNiriEngine == nil {
            controller.zigNiriEngine = ZigNiriEngine(
                maxWindowsPerColumn: maxWindowsPerColumn,
                maxVisibleColumns: controller.settings.niriMaxVisibleColumns,
                infiniteLoop: controller.settings.niriInfiniteLoop
            )
        } else {
            controller.zigNiriEngine?.updateConfiguration(maxWindowsPerColumn: maxWindowsPerColumn)
        }

        syncMonitorsToNiriEngine()
        controller.applyExperimentalControllerSettings(syncAfterApply: true)
    }

    func syncMonitorsToNiriEngine() {
        // Zig runtime stores workspace state keyed by workspace id and does not require
        // monitor registration. Keep this method as an explicit no-op for call-site parity.
    }

    func updateNiriConfig(
        maxWindowsPerColumn: Int? = nil,
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil,
        centerFocusedColumn _: CenterFocusedColumn? = nil,
        alwaysCenterSingleColumn _: Bool? = nil,
        singleWindowAspectRatio _: SingleWindowAspectRatio? = nil,
        columnWidthPresets _: [Double]? = nil
    ) {
        guard let controller else { return }
        controller.zigNiriEngine?.updateConfiguration(
            maxWindowsPerColumn: maxWindowsPerColumn,
            maxVisibleColumns: maxVisibleColumns,
            infiniteLoop: infiniteLoop
        )
        controller.applyExperimentalControllerSettings(syncAfterApply: true)
    }

    private func applyFallbackMutationSelection(
        _ result: ZigNiriMutationResult,
        workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        state: inout ViewportState,
        controller: WMController,
        animateViewport: Bool
    ) {
        guard result.applied else { return }

        applyFallbackSelection(
            result.selection,
            workspaceId: workspaceId,
            monitor: monitor,
            state: &state,
            controller: controller,
            focusWindow: true,
            animateViewport: animateViewport
        )
        controller.layoutRefreshController.executeLayoutRefreshImmediate()
        if result.structuralAnimationActive
            || (controller.zigNiriEngine?.hasActiveAnimation(in: workspaceId) ?? false)
        {
            controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
        }
    }

    private func withActiveWorkspaceFallback(
        _ perform: (WorkspaceDescriptor.ID, Monitor, inout ViewportState, ZigNiriEngine) -> Void
    ) {
        guard let controller,
              let zig = controller.zigNiriEngine
        else {
            return
        }

        controller.layoutRefreshController.runLightSession {
            guard let workspace = controller.activeWorkspace(),
                  let monitor = controller.workspaceManager.monitor(for: workspace.id)
            else {
                return
            }

            controller.workspaceManager.withNiriViewportState(for: workspace.id) { state in
                perform(workspace.id, monitor, &state, zig)
            }
        }
    }

    private func currentSelection(
        workspaceId: WorkspaceDescriptor.ID,
        state: ViewportState,
        controller: WMController
    ) -> ZigNiriSelection? {
        let focusedWindowId: NodeId? = {
            guard let handle = controller.focusedHandle else { return nil }
            guard controller.workspaceManager.workspace(for: handle) == workspaceId else { return nil }
            return controller.zigNodeId(for: handle, workspaceId: workspaceId)
        }()
        return ZigNiriSelection(
            selectedNodeId: state.selectedNodeId,
            focusedWindowId: focusedWindowId
        )
    }

    private func selectedWindowId(
        in workspaceId: WorkspaceDescriptor.ID,
        state: ViewportState,
        controller: WMController
    ) -> NodeId? {
        guard let view = controller.syncZigNiriWorkspace(workspaceId: workspaceId, selectedNodeId: state.selectedNodeId) else {
            return nil
        }
        return resolveActionableWindowId(
            for: state.selectedNodeId,
            in: view
        )
    }

    private func resolveActionableWindowId(
        for selectedNodeId: NodeId?,
        in view: ZigNiriWorkspaceView
    ) -> NodeId? {
        ZigNiriSelectionResolver.actionableWindowId(
            for: selectedNodeId,
            in: view
        )
    }

    private func applyFallbackSelection(
        _ selection: ZigNiriSelection?,
        workspaceId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        state: inout ViewportState,
        controller: WMController,
        focusWindow: Bool,
        animateViewport: Bool
    ) {
        guard let zig = controller.zigNiriEngine else { return }
        state.selectedNodeId = selection?.selectedNodeId

        let workspaceView = controller.syncZigNiriWorkspace(
            workspaceId: workspaceId,
            selectedNodeId: selection?.selectedNodeId
        )
        let actionableNodeId = workspaceView.flatMap { view in
            resolveActionableWindowId(
                for: selection?.selectedNodeId,
                in: view
            )
        }

        if let handle = actionableNodeId.flatMap({ controller.zigWindowHandle(for: $0, workspaceId: workspaceId) }) {
            controller.focusManager.setFocus(handle, in: workspaceId)
            if focusWindow {
                controller.focusWindow(handle)
            }
        }

        guard animateViewport,
              let view = workspaceView,
              let selectedNodeId = selection?.selectedNodeId ?? actionableNodeId,
              let selectedColumnIndex = view.columns.firstIndex(where: { column in
                  column.nodeId == selectedNodeId || column.windowIds.contains(selectedNodeId)
              })
        else {
            return
        }

        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let orientation = controller.settings.effectiveOrientation(for: monitor)
        let resolved = controller.settings.resolvedNiriSettings(for: monitor)
        let viewportSpan = orientation == .horizontal ? workingFrame.width : workingFrame.height
        let columnSpans = zig.resolvedColumnSpans(
            for: view,
            primarySpan: viewportSpan,
            primaryGap: CGFloat(controller.workspaceManager.gaps)
        )
        guard !columnSpans.isEmpty else { return }

        let didStartViewportAnimation = zig.transitionViewportToColumn(
            in: workspaceId,
            requestedIndex: selectedColumnIndex,
            spans: columnSpans,
            gap: CGFloat(controller.workspaceManager.gaps),
            viewportSpan: viewportSpan,
            animate: true,
            centerMode: resolved.centerFocusedColumn,
            alwaysCenterSingleColumn: resolved.alwaysCenterSingleColumn,
            scale: controller.layoutRefreshController.backingScale(for: monitor),
            displayRefreshRate: controller.layoutRefreshController.layoutState.refreshRateByDisplay[monitor.displayId] ?? 60.0,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        if didStartViewportAnimation,
           zig.hasActiveAnimation(in: workspaceId)
        {
            controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
        }
    }

}

extension NiriLayoutHandler: LayoutFocusable, LayoutSwappable, LayoutSizable {
    func focusNeighbor(direction: Direction) {
        _ = submit(.focus(direction))
    }
}
