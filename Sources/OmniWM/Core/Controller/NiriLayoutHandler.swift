// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import Foundation
import QuartzCore


private func hasPendingNiriAnimationWork(
    state: ViewportState,
    engine: NiriLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> Bool {
    state.viewOffsetPixels.isAnimating
        || engine.hasAnyWindowAnimationsRunning(in: workspaceId)
        || engine.hasAnyColumnAnimationsRunning(in: workspaceId)
}

@MainActor final class NiriLayoutHandler {
    weak var controller: WMController?

    struct NiriLayoutPass {
        let wsId: WorkspaceDescriptor.ID
        let engine: NiriLayoutEngine
        let monitor: Monitor
        let insetFrame: CGRect
        let gap: CGFloat
    }

    var scrollAnimationByDisplay: [CGDirectDisplayID: WorkspaceDescriptor.ID] = [:]
    private var removalDiagnosticByWorkspace: [WorkspaceDescriptor.ID: NiriRemovalAnimationDiagnostic] = [:]

    init(controller: WMController?) {
        self.controller = controller
    }

    private func requiredRuntime(_ context: String) -> WMRuntime {
        guard let runtime = controller?.runtime else {
            preconditionFailure("\(context) requires WMRuntime to be attached")
        }
        return runtime
    }

    private func hiddenPlacementMonitorContexts() -> [HiddenPlacementMonitorContext] {
        guard let controller else { return [] }
        let topology = LayoutProjectionContext.project(controller: controller).topology
        return topology.order.compactMap { monitorId in
            topology.node(monitorId).map(HiddenPlacementMonitorContext.init)
        }
    }

    private func fallbackNodeFromGraph(
        in workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        graph: WorkspaceGraph
    ) -> NiriWindow? {
        guard let workspaceNode = graph.node(for: workspaceId) else { return nil }
        let tiledEntries = graph.tiledMembership(in: workspaceId)
        let entriesByLogicalId = Dictionary(
            tiledEntries.map { ($0.logicalId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        if let lastFocused = workspaceNode.lastTiledFocusedLogicalId,
           let entry = entriesByLogicalId[lastFocused],
           let node = graphResolvedNode(entry, in: workspaceId, engine: engine)
        {
            return node
        }

        for entry in tiledEntries {
            if let node = graphResolvedNode(entry, in: workspaceId, engine: engine) {
                return node
            }
        }
        return nil
    }

    private func graphResolvedNode(
        _ entry: WorkspaceGraph.WindowEntry,
        in workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine
    ) -> NiriWindow? {
        guard let node = engine.findNode(forLogicalId: entry.logicalId) ?? engine.findNode(for: entry.token),
              engine.findColumn(containing: node, in: workspaceId) != nil
        else {
            return nil
        }
        return node
    }

    @discardableResult
    func startScrollAnimationIfNeeded(
        for workspaceId: WorkspaceDescriptor.ID,
        state: ViewportState,
        engine: NiriLayoutEngine
    ) -> Bool {
        guard let controller else { return false }
        guard controller.motionPolicy.animationsEnabled else { return false }
        guard hasPendingNiriAnimationWork(state: state, engine: engine, workspaceId: workspaceId) else {
            return false
        }
        controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
        return true
    }

    func registerScrollAnimation(_ workspaceId: WorkspaceDescriptor.ID, on displayId: CGDirectDisplayID) -> Bool {
        if scrollAnimationByDisplay[displayId] == workspaceId {
            return false
        }
        scrollAnimationByDisplay[displayId] = workspaceId
        return true
    }

    @discardableResult
    func unregisterScrollAnimation(on displayId: CGDirectDisplayID) -> WorkspaceDescriptor.ID? {
        guard let workspaceId = scrollAnimationByDisplay.removeValue(forKey: displayId) else {
            return nil
        }
        removalDiagnosticByWorkspace.removeValue(forKey: workspaceId)
        return workspaceId
    }

    func clearScrollAnimations() -> [CGDirectDisplayID] {
        let displayIds = Array(scrollAnimationByDisplay.keys)
        scrollAnimationByDisplay.removeAll()
        removalDiagnosticByWorkspace.removeAll()
        return displayIds
    }

    func hasScrollAnimationRunning(in workspaceId: WorkspaceDescriptor.ID) -> Bool {
        scrollAnimationByDisplay.values.contains(workspaceId)
    }

    private func emitNiriRemovalAnimationDiagnostic(
        _ diagnostic: NiriRemovalAnimationDiagnostic
    ) {
        controller?.layoutRefreshController.emitNiriRemovalAnimationDiagnostic(diagnostic)
    }

    private func hasNiriScrollDirective(
        _ directives: [AnimationDirective],
        workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        directives.contains { directive in
            if case let .startNiriScroll(candidate) = directive {
                return candidate == workspaceId
            }
            return false
        }
    }

    func tickScrollAnimation(targetTime: CFTimeInterval, displayId: CGDirectDisplayID) {
        guard let wsId = scrollAnimationByDisplay[displayId] else { return }
        guard let controller, let engine = controller.niriEngine else {
            controller?.layoutRefreshController.stopScrollAnimation(for: displayId)
            return
        }

        let projectionContext = LayoutProjectionContext.project(controller: controller)
        let topology = projectionContext.topology

        guard let monitorNode = topology.node(forDisplay: displayId) else {
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
            return
        }
        let monitor = monitorNode.monitor

        guard monitorNode.activeWorkspaceId == wsId else {
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
            return
        }

        let windowAnimationsRunning = engine.tickAllWindowAnimations(in: wsId, at: targetTime)
        let columnAnimationsRunning = engine.tickAllColumnAnimations(in: wsId, at: targetTime)

        let runtime = requiredRuntime("NiriLayoutHandler.tickScrollAnimation")
        let tick = runtime.withNiriViewportState(for: wsId, source: .animation) { state in
            let viewportAnimationRunning = state.advanceAnimations(at: targetTime)
            return (
                state: state,
                viewportAnimationRunning: viewportAnimationRunning,
                animationsOngoing: viewportAnimationRunning
                    || windowAnimationsRunning
                    || columnAnimationsRunning
            )
        }

        applyFramesOnDemand(
            wsId: wsId,
            state: tick.state,
            engine: engine,
            monitor: monitor,
            animationTime: targetTime,
            projectionContext: projectionContext
        )

        if let diagnostic = removalDiagnosticByWorkspace[wsId] {
            emitNiriRemovalAnimationDiagnostic(
                diagnostic.withPhase(
                    .displayLinkTick,
                    survivorMoveAnimation: windowAnimationsRunning,
                    columnAnimation: columnAnimationsRunning,
                    viewportAnimation: tick.viewportAnimationRunning,
                    startNiriScroll: true
                )
            )
        }

        if !tick.animationsOngoing {
            finalizeAnimation()
            var activeIds = Set<WorkspaceDescriptor.ID>()
            for monitorId in topology.order {
                guard let node = topology.node(monitorId),
                      let activeWorkspaceId = node.activeWorkspaceId
                else {
                    continue
                }
                activeIds.insert(activeWorkspaceId)
            }
            controller.layoutRefreshController.hideInactiveWorkspaces(activeWorkspaceIds: activeIds)
            removalDiagnosticByWorkspace.removeValue(forKey: wsId)
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
        }
    }

    func applyFramesOnDemand(
        wsId: WorkspaceDescriptor.ID,
        state: ViewportState,
        engine: NiriLayoutEngine,
        monitor: Monitor,
        animationTime: TimeInterval? = nil,
        projectionContext: LayoutProjectionContext? = nil
    ) {
        guard let controller else { return }
        let context = projectionContext ?? LayoutProjectionContext.project(controller: controller)
        let activeWorkspaceId = context.topology.node(monitor.id)?.activeWorkspaceId
        guard let snapshot = makeWorkspaceSnapshot(
            workspaceId: wsId,
            monitor: monitor,
            viewportState: state,
            useScrollAnimationPath: true,
            removalSeed: nil,
            isActiveWorkspace: activeWorkspaceId == wsId
        )
        else {
            return
        }

        let plan = buildOnDemandLayoutPlan(
            snapshot: snapshot,
            engine: engine,
            monitor: monitor,
            animationTime: animationTime
        )
        controller.layoutRefreshController.executeLayoutPlan(plan)
    }

    private func finalizeAnimation() {
        guard let controller else { return }

        let focusedTarget: KeyboardFocusTarget?
        if controller.workspaceManager.pendingFocusedToken != nil,
           let confirmedToken = controller.workspaceManager.focusedToken
        {
            focusedTarget = controller.managedKeyboardFocusTarget(for: confirmedToken)
                ?? controller.currentKeyboardFocusTargetForRendering()
        } else {
            focusedTarget = controller.currentKeyboardFocusTargetForRendering()
        }
        let preferredFrame = focusedTarget
            .flatMap { $0.isManaged ? controller.preferredKeyboardFocusFrame(for: $0.token) : nil }
        if let token = focusedTarget?.token {
            if token == controller.workspaceManager.focusedToken {
                _ = controller.renderKeyboardFocusBorder(
                    for: focusedTarget,
                    preferredFrame: preferredFrame,
                    policy: controller.workspaceManager.pendingFocusedToken != nil ? .direct : .coordinated,
                    source: .borderReapplyAnimationSettled
                )
            } else {
                _ = controller.reapplyKeyboardFocusBorderIfMatching(
                    token: token,
                    preferredFrame: preferredFrame,
                    phase: .animationSettled,
                    policy: .coordinated
                )
            }
        } else {
            _ = controller.renderKeyboardFocusBorder(
                policy: .coordinated,
                source: .borderReapplyAnimationSettled
            )
        }

        if controller.moveMouseToFocusedWindowEnabled,
           let token = controller.workspaceManager.focusedToken
        {
            controller.moveMouseToWindow(token)
        }
    }

    func cancelActiveAnimations(for workspaceId: WorkspaceDescriptor.ID) {
        guard let controller else { return }

        let runtime = requiredRuntime("NiriLayoutHandler.cancelActiveAnimations")
        runtime.withNiriViewportState(for: workspaceId, source: .animation) { state in
            state.cancelAnimation()
        }

        for (displayId, wsId) in scrollAnimationByDisplay where wsId == workspaceId {
            controller.layoutRefreshController.stopScrollAnimation(for: displayId)
        }
    }

    func layoutWithNiriEngine(
        activeWorkspaces: Set<WorkspaceDescriptor.ID>,
        useScrollAnimationPath: Bool = false,
        removalSeeds: [WorkspaceDescriptor.ID: NiriWindowRemovalSeed] = [:]
    ) async throws -> [WorkspaceLayoutPlan] {
        guard let controller, let engine = controller.niriEngine else { return [] }
        let projectionContext = LayoutProjectionContext.project(controller: controller)
        var plans: [WorkspaceLayoutPlan] = []
        for wsId in activeWorkspaces.sorted(by: { $0.uuidString < $1.uuidString }) {
            try Task.checkCancellation()
            guard let workspaceNode = projectionContext.graph.node(for: wsId),
                  let monitorNode = projectionContext.monitorNode(for: wsId)
            else { continue }

            if workspaceNode.layoutType == .dwindle { continue }
            let monitor = monitorNode.monitor
            let isActiveWorkspace = monitorNode.activeWorkspaceId == wsId

            guard let snapshot = makeWorkspaceSnapshot(
                workspaceId: wsId,
                monitor: monitor,
                viewportState: nil,
                useScrollAnimationPath: useScrollAnimationPath,
                removalSeed: removalSeeds[wsId],
                isActiveWorkspace: isActiveWorkspace,
                projectionContext: projectionContext
            ) else { continue }

            let plan = buildRelayoutPlan(
                snapshot: snapshot,
                engine: engine,
                monitor: monitor
            )
            plans.append(plan)

            try Task.checkCancellation()
            await controller.layoutRefreshController.debugHooks.onWorkspaceLayoutPlanBuilt?(.niri, wsId)
            try Task.checkCancellation()
            await Task.yield()
        }

        try Task.checkCancellation()
        return plans
    }

    private func makeWorkspaceSnapshot(
        workspaceId wsId: WorkspaceDescriptor.ID,
        monitor: Monitor,
        viewportState: ViewportState?,
        useScrollAnimationPath: Bool,
        removalSeed: NiriWindowRemovalSeed?,
        isActiveWorkspace: Bool,
        projectionContext: LayoutProjectionContext? = nil
    ) -> NiriWorkspaceSnapshot? {
        guard let controller else { return nil }
        let context = projectionContext ?? LayoutProjectionContext.project(controller: controller)

        let shouldResolveConstraints = viewportState == nil
        guard controller.layoutRefreshController.warmWindowConstraints(
            for: context.graph.tiledMembership(in: wsId),
            resolveConstraints: shouldResolveConstraints
        ) else {
            return nil
        }

        let effectiveViewportState = viewportState ?? controller.workspaceManager.niriViewportState(for: wsId)
        let interactionWorkspaceId = context.activeWorkspaceIdForInteraction

        return makeProjectionSnapshot(
            workspaceId: wsId,
            monitor: monitor,
            viewportState: effectiveViewportState,
            useScrollAnimationPath: useScrollAnimationPath,
            removalSeed: removalSeed,
            isActiveWorkspace: isActiveWorkspace,
            isInteractionWorkspace: interactionWorkspaceId == wsId,
            projectionContext: context
        )
    }

    @MainActor
    private func makeProjectionSnapshot(
        workspaceId wsId: WorkspaceDescriptor.ID,
        monitor _: Monitor,
        viewportState: ViewportState,
        useScrollAnimationPath: Bool,
        removalSeed: NiriWindowRemovalSeed?,
        isActiveWorkspace: Bool,
        isInteractionWorkspace: Bool,
        projectionContext: LayoutProjectionContext? = nil
    ) -> NiriWorkspaceSnapshot? {
        guard let controller else { return nil }
        let manager = controller.workspaceManager
        let context = projectionContext ?? LayoutProjectionContext.project(controller: controller)
        guard let monitorNode = context.monitorNode(for: wsId) else { return nil }
        let topologyMonitor = monitorNode.monitor
        let orientationOverride = controller.niriEngine?.monitor(for: monitorNode.monitorId)?.orientation
            ?? controller.settings.effectiveOrientation(for: topologyMonitor)

        return NiriProjectionBuilder(
            graph: context.graph,
            topology: context.topology,
            lifecycle: manager
        ).buildSnapshot(
            for: wsId,
            monitorId: monitorNode.monitorId,
            viewportState: viewportState,
            preferredFocusToken: manager.preferredFocusToken(in: wsId),
            confirmedFocusedToken: manager.focusedToken,
            pendingFocusedToken: manager.pendingFocusedToken,
            pendingFocusedWorkspaceId: manager.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: manager.isNonManagedFocusActive,
            hasCompletedInitialRefresh: controller.layoutRefreshController.layoutState.hasCompletedInitialRefresh,
            useScrollAnimationPath: useScrollAnimationPath,
            removalSeed: removalSeed,
            gap: CGFloat(manager.gaps),
            outerGaps: manager.outerGaps,
            displayRefreshRate: controller.layoutRefreshController.layoutState.refreshRateByDisplay[monitorNode.displayId] ?? 60.0,
            isActiveWorkspace: isActiveWorkspace,
            isInteractionWorkspace: isInteractionWorkspace,
            orientationOverride: orientationOverride
        )
    }

    func syncAnimationRefreshRate(
        for monitor: Monitor,
        engine: NiriLayoutEngine,
        state: inout ViewportState
    ) {
        let refreshRate = controller?.layoutRefreshController.layoutState.refreshRateByDisplay[monitor.displayId] ?? 60.0
        syncAnimationRefreshRate(refreshRate, engine: engine, state: &state)
    }

    private func syncAnimationRefreshRate(
        _ refreshRate: Double,
        engine: NiriLayoutEngine,
        state: inout ViewportState
    ) {
        engine.displayRefreshRate = refreshRate
        state.displayRefreshRate = refreshRate
    }

    private func buildOnDemandLayoutPlan(
        snapshot: NiriWorkspaceSnapshot,
        engine: NiriLayoutEngine,
        monitor: Monitor,
        animationTime: TimeInterval?
    ) -> WorkspaceLayoutPlan {
        let gaps = LayoutGaps(
            horizontal: snapshot.gap,
            vertical: snapshot.gap,
            outer: snapshot.outerGaps
        )

        let area = WorkingAreaContext(
            workingFrame: snapshot.monitor.workingFrame,
            viewFrame: snapshot.monitor.frame,
            scale: snapshot.monitor.scale
        )

        let (frames, hiddenHandles) = engine.calculateCombinedLayoutUsingPools(
            in: snapshot.workspaceId,
            monitor: monitor,
            gaps: gaps,
            state: snapshot.viewportState,
            workingArea: area,
            animationTime: animationTime,
            hiddenPlacementMonitors: hiddenPlacementMonitorContexts()
        )

        let diff = layoutDiff(
            windows: snapshot.windows,
            frames: frames,
            hiddenHandles: hiddenHandles,
            confirmedFocusedToken: snapshot.confirmedFocusedToken,
            pendingFocusedToken: snapshot.pendingFocusedToken,
            pendingFocusedWorkspaceId: snapshot.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: snapshot.isNonManagedFocusActive,
            workspaceId: snapshot.workspaceId,
            engine: engine,
            directBorderUpdate: true,
            isInteractionWorkspace: snapshot.isInteractionWorkspace,
            canRestoreHiddenWorkspaceWindows: snapshot.isActiveWorkspace
        )

        var plan = WorkspaceLayoutPlan(
            workspaceId: snapshot.workspaceId,
            monitor: snapshot.monitor,
            sessionPatch: WorkspaceSessionPatch(workspaceId: snapshot.workspaceId),
            diff: diff
        )
        plan.persistManagedRestoreSnapshots = false
        return plan
    }

    private func buildRelayoutPlan(
        snapshot: NiriWorkspaceSnapshot,
        engine: NiriLayoutEngine,
        monitor: Monitor
    ) -> WorkspaceLayoutPlan {
        let hasNativeFullscreenRestoreCycle = snapshot.windows.contains {
            $0.isRestoringNativeFullscreen
        }
        let motion = hasNativeFullscreenRestoreCycle
            ? .disabled
            : (controller?.motionPolicy.snapshot() ?? .enabled)
        var state = snapshot.viewportState
        let pass = NiriLayoutPass(
            wsId: snapshot.workspaceId,
            engine: engine,
            monitor: monitor,
            insetFrame: snapshot.monitor.workingFrame,
            gap: snapshot.gap
        )
        if hasNativeFullscreenRestoreCycle {
            suppressAnimationsForNativeFullscreenRestore(pass: pass, state: &state)
        }
        let restoreContexts = resolvedNativeFullscreenRestoreContexts(
            for: snapshot.windows,
            workspaceId: snapshot.workspaceId
        )
        let topologySync = syncTopology(
            pass: pass,
            motion: motion,
            state: &state,
            snapshot: snapshot
        )

        for window in snapshot.windows {
            engine.updateWindowConstraints(for: window.token, constraints: window.constraints)
        }

        applyNativeFullscreenNiriState(
            restoreContexts,
            in: engine,
            workspaceId: snapshot.workspaceId
        )

        return computeLayoutPlan(
            pass: pass,
            motion: motion,
            state: state,
            rememberedFocusToken: topologySync.rememberedFocusToken,
            newWindowToken: topologySync.newWindowToken,
            viewportNeedsRecalc: topologySync.viewportNeedsRecalc,
            topologyDidApply: topologySync.topologyDidApply,
            snapshot: snapshot,
            restoreContexts: restoreContexts,
            suppressAnimationDirectives: hasNativeFullscreenRestoreCycle
        )
    }

    private struct TopologySyncResult {
        var viewportNeedsRecalc: Bool
        var rememberedFocusToken: WindowToken?
        var newWindowToken: WindowToken?
        var topologyDidApply: Bool
    }

    private func syncTopology(
        pass: NiriLayoutPass,
        motion: MotionSnapshot,
        state: inout ViewportState,
        snapshot: NiriWorkspaceSnapshot
    ) -> TopologySyncResult {
        syncAnimationRefreshRate(snapshot.displayRefreshRate, engine: pass.engine, state: &state)
        pass.engine.reconcileLogicalMembership(
            for: snapshot.windows,
            in: pass.wsId
        )
        let windowTokens = snapshot.windows.map(\.token)
        let existingHandleIds = pass.engine.root(for: pass.wsId)?.windowIdSet ?? []
        let newTokens = windowTokens.filter { !existingHandleIds.contains($0) }

        pass.engine.prepareColumnWidths(
            in: pass.wsId,
            workingAreaWidth: pass.insetFrame.width,
            gaps: pass.gap
        )

        let preSyncState = state
        let preSyncColumns = pass.engine.columns(in: pass.wsId)
        let preSyncViewPos = preSyncColumns.isEmpty
            ? CGFloat(0)
            : state.viewPosPixels(columns: preSyncColumns, gap: pass.gap)

        let resetForSingleWindow = windowTokens.count == 1
            && pass.engine.effectiveSingleWindowAspectRatio(in: pass.wsId).ratio != nil
        guard let plan = pass.engine.callTopologyKernel(
            operation: .syncWindows,
            workspaceId: pass.wsId,
            state: state,
            workingFrame: pass.insetFrame,
            gaps: pass.gap,
            focusedToken: snapshot.preferredFocusToken,
            desiredTokens: windowTokens,
            removedNodeIds: snapshot.removalSeed?.removedNodeIds ?? [],
            resetForSingleWindow: resetForSingleWindow,
            motion: motion,
            isActiveWorkspace: snapshot.isActiveWorkspace,
            hasCompletedInitialRefresh: snapshot.hasCompletedInitialRefresh
        ) else {
            return TopologySyncResult(
                viewportNeedsRecalc: false,
                rememberedFocusToken: nil,
                newWindowToken: nil,
                topologyDidApply: false
            )
        }

        if plan.effectKind == .removeColumn,
           plan.result.source_column_index >= 0
        {
            var animationState = state
            _ = pass.engine.animateColumnsForRemoval(
                columnIndex: Int(plan.result.source_column_index),
                in: pass.wsId,
                motion: motion,
                state: &animationState,
                gaps: pass.gap
            )
        }

        _ = pass.engine.applyTopologyPlan(
            plan,
            in: pass.wsId,
            state: &state,
            motion: motion
        )
        pass.engine.bindLogicalMembership(for: snapshot.windows)

        pass.engine.prepareColumnWidths(
            in: pass.wsId,
            workingAreaWidth: pass.insetFrame.width,
            gaps: pass.gap
        )

        if !existingHandleIds.isEmpty,
           plan.effectKind == .addColumn,
           plan.result.target_column_index >= 0
        {
            pass.engine.animateColumnsForAddition(
                columnIndex: Int(plan.result.target_column_index),
                in: pass.wsId,
                motion: motion,
                state: state,
                gaps: pass.gap,
                workingAreaWidth: pass.insetFrame.width
            )
        }

        let selectedToken = state.selectedNodeId
            .flatMap { pass.engine.findNode(by: $0) as? NiriWindow }?
            .token
        let plannedRememberedFocusToken: WindowToken? = if plan.result.remembered_focus_window_id != 0 {
            pass.engine.findWindow(in: plan, id: plan.result.remembered_focus_window_id)?.token
        } else {
            nil
        }
        let rememberedFocusToken = plannedRememberedFocusToken ?? selectedToken
        let newWindowToken: WindowToken? = if snapshot.hasCompletedInitialRefresh,
                                              snapshot.isActiveWorkspace,
                                              plan.result.new_window_id != 0
        {
            pass.engine.findWindow(in: plan, id: plan.result.new_window_id)?.token
        } else {
            nil
        }
        if let selectedId = state.selectedNodeId {
            pass.engine.updateFocusTimestamp(for: selectedId)
        }
        if let removalSeed = snapshot.removalSeed,
           let removedNodeId = removalSeed.diagnosticRemovedNodeId ?? removalSeed.removedNodeIds.first
        {
            let viewportAction: NiriRemovalViewportAction = if state.viewOffsetPixels.isAnimating {
                .animated
            } else {
                .none
            }
            emitNiriRemovalAnimationDiagnostic(
                NiriRemovalAnimationDiagnostic(
                    phase: .topologyPlanning,
                    workspaceId: pass.wsId,
                    removedNodeId: removedNodeId,
                    removedWindow: removalSeed.removedWindow,
                    activeColumnBefore: preSyncState.activeColumnIndex,
                    activeColumnAfter: state.activeColumnIndex,
                    currentOffset: state.viewOffsetPixels.current(),
                    targetOffset: state.viewOffsetPixels.target(),
                    stationaryOffset: state.stationary(),
                    viewportAction: viewportAction,
                    closeAnimation: false,
                    survivorMoveAnimation: false,
                    columnAnimation: pass.engine.hasAnyColumnAnimationsRunning(in: pass.wsId),
                    viewportAnimation: state.viewOffsetPixels.isAnimating,
                    startNiriScroll: false,
                    skipFrameApplicationForAnimation: false
                )
            )
        }

        if snapshot.hasCompletedInitialRefresh,
           snapshot.isActiveWorkspace,
           !newTokens.isEmpty
        {
            let reduceMotionScale: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.25 : 1.0
            let appearOffset = 16.0 * reduceMotionScale

            for token in newTokens {
                guard let window = pass.engine.findNode(for: token),
                      !window.isHiddenInTabbedMode else { continue }

                if abs(appearOffset) > 0.1 {
                    window.animateMoveFrom(
                        displacement: CGPoint(x: 0, y: -appearOffset),
                        clock: pass.engine.animationClock,
                        config: pass.engine.windowMovementAnimationConfig,
                        displayRefreshRate: state.displayRefreshRate,
                        animated: motion.animationsEnabled
                    )
                }
            }
        }

        let postSyncColumns = pass.engine.columns(in: pass.wsId)
        let postSyncViewPos = postSyncColumns.isEmpty
            ? preSyncViewPos
            : state.viewPosPixels(columns: postSyncColumns, gap: pass.gap)

        return TopologySyncResult(
            viewportNeedsRecalc: abs(postSyncViewPos - preSyncViewPos) > 1,
            rememberedFocusToken: rememberedFocusToken,
            newWindowToken: newWindowToken,
            topologyDidApply: plan.didApply
        )
    }

    private func computeLayoutPlan(
        pass: NiriLayoutPass,
        motion: MotionSnapshot,
        state: ViewportState,
        rememberedFocusToken: WindowToken?,
        newWindowToken: WindowToken?,
        viewportNeedsRecalc: Bool,
        topologyDidApply: Bool,
        snapshot: NiriWorkspaceSnapshot,
        restoreContexts: [WindowToken: NativeFullscreenRestoreContext] = [:],
        suppressAnimationDirectives: Bool = false
    ) -> WorkspaceLayoutPlan {
        let gaps = LayoutGaps(
            horizontal: pass.gap,
            vertical: pass.gap,
            outer: snapshot.outerGaps
        )

        let area = WorkingAreaContext(
            workingFrame: pass.insetFrame,
            viewFrame: snapshot.monitor.frame,
            scale: snapshot.monitor.scale
        )

        let (frames, hiddenHandles) = pass.engine.calculateCombinedLayoutUsingPools(
            in: pass.wsId,
            monitor: pass.monitor,
            gaps: gaps,
            state: state,
            workingArea: area,
            animationTime: nil,
            hiddenPlacementMonitors: hiddenPlacementMonitorContexts()
        )

        let restoreFrameOverrides = restoreContexts.compactMapValues(\.restoreFrame)
        let resolvedFrames = frames.merging(restoreFrameOverrides) { _, restoreFrame in restoreFrame }

        let hasColumnAnimations = suppressAnimationDirectives
            ? false
            : pass.engine.hasAnyColumnAnimationsRunning(in: pass.wsId)
        var directives: [AnimationDirective] = []

        if !snapshot.useScrollAnimationPath && !suppressAnimationDirectives {
            if viewportNeedsRecalc, newWindowToken == nil {
                directives.append(.startNiriScroll(workspaceId: pass.wsId))
            } else if hasColumnAnimations {
                directives.append(.startNiriScroll(workspaceId: pass.wsId))
            }
        }

        if let newWindowToken, !suppressAnimationDirectives {
            directives.append(.startNiriScroll(workspaceId: pass.wsId))
            directives.append(.activateWindow(token: newWindowToken))
        }

        var removalTriggeredSurvivorMoveAnimation = false
        var removalHasWindowAnimations = false
        var removalHasColumnAnimations = false
        if let removalSeed = snapshot.removalSeed,
           !removalSeed.oldFrames.isEmpty,
           !suppressAnimationDirectives
        {
            let newFrames = pass.engine.captureWindowFrames(in: pass.wsId)
            if motion.animationsEnabled {
                removalTriggeredSurvivorMoveAnimation = pass.engine.triggerMoveAnimations(
                    in: pass.wsId,
                    oldFrames: removalSeed.oldFrames,
                    newFrames: newFrames,
                    motion: motion
                )
            }
            removalHasWindowAnimations = pass.engine.hasAnyWindowAnimationsRunning(in: pass.wsId)
            removalHasColumnAnimations = pass.engine.hasAnyColumnAnimationsRunning(in: pass.wsId)
            if motion.animationsEnabled,
               (
                   removalTriggeredSurvivorMoveAnimation
                       || removalHasWindowAnimations
                       || removalHasColumnAnimations
               )
            {
                directives.append(.startNiriScroll(workspaceId: pass.wsId))
            }
        }

        let diff = layoutDiff(
            windows: snapshot.windows,
            frames: resolvedFrames,
            hiddenHandles: hiddenHandles,
            confirmedFocusedToken: snapshot.confirmedFocusedToken,
            pendingFocusedToken: snapshot.pendingFocusedToken,
            pendingFocusedWorkspaceId: snapshot.pendingFocusedWorkspaceId,
            isNonManagedFocusActive: snapshot.isNonManagedFocusActive,
            workspaceId: pass.wsId,
            engine: pass.engine,
            directBorderUpdate: snapshot.useScrollAnimationPath,
            isInteractionWorkspace: snapshot.isInteractionWorkspace,
            canRestoreHiddenWorkspaceWindows: snapshot.isActiveWorkspace
        )

        var plan = WorkspaceLayoutPlan(
            workspaceId: pass.wsId,
            monitor: snapshot.monitor,
            sessionPatch: WorkspaceSessionPatch(
                workspaceId: pass.wsId,
                viewportState: state,
                rememberedFocusToken: rememberedFocusToken
            ),
            diff: diff,
            animationDirectives: directives
        )
        let willStartNiriScrollAnimation = motion.animationsEnabled
            && hasNiriScrollDirective(directives, workspaceId: pass.wsId)
        if let removalSeed = snapshot.removalSeed,
           let removedNodeId = removalSeed.diagnosticRemovedNodeId ?? removalSeed.removedNodeIds.first
        {
            let diagnostic = NiriRemovalAnimationDiagnostic(
                phase: .animationDirectives,
                workspaceId: pass.wsId,
                removedNodeId: removedNodeId,
                removedWindow: removalSeed.removedWindow,
                activeColumnBefore: nil,
                activeColumnAfter: state.activeColumnIndex,
                currentOffset: state.viewOffsetPixels.current(),
                targetOffset: state.viewOffsetPixels.target(),
                stationaryOffset: state.stationary(),
                viewportAction: state.viewOffsetPixels.isAnimating
                    ? .animated
                    : .none,
                closeAnimation: false,
                survivorMoveAnimation: removalTriggeredSurvivorMoveAnimation || removalHasWindowAnimations,
                columnAnimation: removalHasColumnAnimations,
                viewportAnimation: state.viewOffsetPixels.isAnimating,
                startNiriScroll: willStartNiriScrollAnimation,
                skipFrameApplicationForAnimation: false
            )
            plan.niriRemovalAnimationDiagnostic = diagnostic
        }
        plan.nativeFullscreenRestoreFinalizeTokens = nativeFullscreenRestoreFinalizeTokens(
            windows: snapshot.windows,
            frames: resolvedFrames
        )
        plan.managedRestoreMaterialStateChanges = managedRestoreMaterialStateChanges(
            snapshot: snapshot,
            rememberedFocusToken: rememberedFocusToken,
            viewportNeedsRecalc: viewportNeedsRecalc,
            topologyDidApply: topologyDidApply
        )
        plan.persistManagedRestoreSnapshots = false
        plan.skipFrameApplicationForAnimation = !suppressAnimationDirectives
            && snapshot.useScrollAnimationPath
            && (
                hasScrollAnimationRunning(in: snapshot.workspaceId)
                    || willStartNiriScrollAnimation
            )
        if var diagnostic = plan.niriRemovalAnimationDiagnostic {
            diagnostic.skipFrameApplicationForAnimation = plan.skipFrameApplicationForAnimation
            plan.niriRemovalAnimationDiagnostic = diagnostic
            emitNiriRemovalAnimationDiagnostic(diagnostic)
            if willStartNiriScrollAnimation {
                removalDiagnosticByWorkspace[pass.wsId] = diagnostic
            } else {
                removalDiagnosticByWorkspace.removeValue(forKey: pass.wsId)
            }
        }
        return plan
    }

    private func managedRestoreMaterialStateChanges(
        snapshot: NiriWorkspaceSnapshot,
        rememberedFocusToken: WindowToken?,
        viewportNeedsRecalc: Bool,
        topologyDidApply: Bool
    ) -> [ManagedRestoreMaterialStateChange] {
        var changes: [ManagedRestoreMaterialStateChange] = []
        var seenTokens: Set<WindowToken> = []

        if topologyDidApply {
            for window in snapshot.windows where !window.isNativeFullscreenSuspended {
                guard seenTokens.insert(window.token).inserted else { continue }
                changes.append(
                    ManagedRestoreMaterialStateChange(
                        token: window.token,
                        reason: .topologyChanged
                    )
                )
            }
        }

        if snapshot.useScrollAnimationPath,
           viewportNeedsRecalc,
           let candidateToken = rememberedFocusToken
           ?? snapshot.pendingFocusedToken
           ?? snapshot.confirmedFocusedToken
           ?? snapshot.preferredFocusToken,
           snapshot.windows.contains(where: {
               $0.token == candidateToken && !$0.isNativeFullscreenSuspended
           }),
           seenTokens.insert(candidateToken).inserted
        {
            changes.append(
                ManagedRestoreMaterialStateChange(
                    token: candidateToken,
                    reason: .niriStateChanged
                )
            )
        }

        return changes
    }

    private func layoutDiff(
        windows: [LayoutWindowSnapshot],
        frames: [WindowToken: CGRect],
        hiddenHandles: [WindowToken: HideSide],
        confirmedFocusedToken: WindowToken?,
        pendingFocusedToken: WindowToken?,
        pendingFocusedWorkspaceId: WorkspaceDescriptor.ID?,
        isNonManagedFocusActive: Bool,
        workspaceId: WorkspaceDescriptor.ID,
        engine: NiriLayoutEngine,
        directBorderUpdate: Bool,
        isInteractionWorkspace: Bool,
        canRestoreHiddenWorkspaceWindows: Bool
    ) -> WorkspaceLayoutDiff {
        var diff = WorkspaceLayoutDiff()
        let suspendedTokens = Set(
            windows.lazy
                .filter(\.isNativeFullscreenSuspended)
                .map(\.token)
        )
        let effectiveBorderToken: WindowToken? = if directBorderUpdate && isInteractionWorkspace {
            if !isNonManagedFocusActive,
               pendingFocusedWorkspaceId == workspaceId,
               let pendingFocusedToken
            {
                pendingFocusedToken
            } else if let confirmedFocusedToken {
                confirmedFocusedToken
            } else {
                nil
            }
        } else {
            confirmedFocusedToken
        }

        if let effectiveBorderToken {
            let ownsFocusedToken = windows.contains {
                $0.token == effectiveBorderToken && !$0.isNativeFullscreenSuspended
            }
            diff.borderMode = ownsFocusedToken ? (directBorderUpdate ? .direct : .coordinated) : .none
        } else {
            diff.borderMode = directBorderUpdate ? .direct : .coordinated
        }

        for window in windows {
            let token = window.token
            if window.isNativeFullscreenSuspended {
                continue
            }
            let previousOffscreenSide = window.hiddenState?.offscreenSide
            if let side = hiddenHandles[token], !window.isRestoringNativeFullscreen {
                guard let hiddenFrame = frames[token] else { continue }
                let request = LayoutHideRequest(
                    token: token,
                    side: side,
                    hiddenFrame: hiddenFrame
                )
                let roundedOrigin = controller?
                    .layoutRefreshController
                    .hiddenOriginForComparison(request.hiddenFrame.origin, token: token)
                    ?? request.hiddenFrame.origin
                let lastAppliedOrigin = controller?.layoutRefreshController.lastAppliedHideOrigin(for: token)
                let shouldEmitHide = if let lastAppliedOrigin {
                    lastAppliedOrigin != roundedOrigin
                } else {
                    previousOffscreenSide != side
                }
                if shouldEmitHide {
                    diff.visibilityChanges.append(.hide(request))
                }
                continue
            }

            if previousOffscreenSide != nil {
                diff.visibilityChanges.append(.show(token))
            }

            if canRestoreHiddenWorkspaceWindows,
               let hiddenState = window.hiddenState,
               hiddenState.workspaceInactive
            {
                diff.restoreChanges.append(
                    .init(token: token, hiddenState: hiddenState)
                )
            }

            guard let frame = frames[token] else { continue }
            let forceApply = if let node = engine.findNode(for: token) {
                window.isRestoringNativeFullscreen || node.sizingMode == .fullscreen
            } else {
                window.isRestoringNativeFullscreen
            }
            diff.frameChanges.append(
                LayoutFrameChange(
                    token: token,
                    frame: frame,
                    forceApply: forceApply
                )
            )
        }

        if let effectiveBorderToken,
           !suspendedTokens.contains(effectiveBorderToken),
           hiddenHandles[effectiveBorderToken] == nil,
           let frame = frames[effectiveBorderToken]
        {
            diff.focusedFrame = LayoutFocusedFrame(
                token: effectiveBorderToken,
                frame: frame
            )
        } else {
            diff.focusedFrame = nil
        }

        return diff
    }

    func updateTabbedColumnOverlays() {
        guard let controller else { return }
        guard let engine = controller.niriEngine else {
            controller.tabbedOverlayManager.removeAll()
            return
        }

        let topology = LayoutProjectionContext.project(controller: controller).topology

        var infos: [TabbedColumnOverlayInfo] = []
        for monitorId in topology.order {
            guard let monitorNode = topology.node(monitorId),
                  let workspaceId = monitorNode.activeWorkspaceId
            else { continue }
            let monitor = monitorNode.monitor

            for column in engine.columns(in: workspaceId) where column.isTabbed {
                guard let frame = column.renderedFrame ?? column.frame else { continue }
                guard TabbedColumnOverlayManager.shouldShowOverlay(
                    columnFrame: frame,
                    visibleFrame: monitor.visibleFrame
                ) else { continue }

                let windows = column.windowNodes
                guard !windows.isEmpty else { continue }

                guard let activeWindow = column.activeWindow else { continue }
                let activeWindowId = controller.workspaceManager.entry(for: activeWindow.handle)?.windowId

                infos.append(
                    TabbedColumnOverlayInfo(
                        workspaceId: workspaceId,
                        columnId: column.id,
                        columnFrame: frame,
                        tabCount: windows.count,
                        activeVisualIndex: column.activeVisualTileIdx,
                        activeWindowId: activeWindowId
                    )
                )
            }
        }

        controller.tabbedOverlayManager.updateOverlays(infos)
    }

    func selectTabInNiri(workspaceId: WorkspaceDescriptor.ID, columnId: NodeId, visualIndex: Int) {
        guard let controller, let engine = controller.niriEngine else { return }
        guard let column = engine.columns(in: workspaceId).first(where: { $0.id == columnId }) else { return }

        let windows = column.windowNodes
        guard let storageIndex = column.storageTileIndex(forVisualTileIndex: visualIndex),
              windows.indices.contains(storageIndex)
        else {
            return
        }

        column.setActiveTileIdx(storageIndex)
        engine.updateTabbedColumnVisibility(column: column)

        let target = windows[storageIndex]
        var state = controller.workspaceManager.niriViewportState(for: workspaceId)
        if let monitor = LayoutProjectionContext.project(controller: controller).monitor(for: workspaceId) {
            syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
            let gap = CGFloat(controller.workspaceManager.gaps)
            engine.ensureSelectionVisible(
                node: target,
                in: workspaceId,
                motion: controller.motionPolicy.snapshot(),
                state: &state,
                workingFrame: monitor.visibleFrame,
                gaps: gap
            )
        }
        activateNode(
            target, in: workspaceId, state: &state,
            options: .init(activateWindow: false, ensureVisible: false, startAnimation: false)
        )
        let patch = WorkspaceSessionPatch(
            workspaceId: workspaceId,
            viewportState: state,
            rememberedFocusToken: nil
        )
        guard let runtime = controller.runtime else {
            preconditionFailure("NiriLayoutHandler.applyTabbedColumn requires WMRuntime to be attached")
        }
        _ = runtime.applySessionPatch(patch, source: .command)
        let updatedState = controller.workspaceManager.niriViewportState(for: workspaceId)
        if updatedState.viewOffsetPixels.isAnimating || engine.hasAnyWindowAnimationsRunning(in: workspaceId) {
            controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
        }
        updateTabbedColumnOverlays()
    }



    func focusNeighbor(
        direction: Direction,
        source: WMEventSource = .command
    ) {
        guard let controller else { return }
        guard let engine = controller.niriEngine else { return }
        let projectionContext = LayoutProjectionContext.project(controller: controller)
        guard let wsId = projectionContext.activeWorkspaceIdForInteraction
        else { return }

        var state = controller.workspaceManager.niriViewportState(for: wsId)
        guard let currentId = state.selectedNodeId,
              let currentNode = engine.findNode(by: currentId)
        else {
            if let firstNode = fallbackNodeFromGraph(
                in: wsId,
                engine: engine,
                graph: projectionContext.graph
            ) {
                activateNode(
                    firstNode, in: wsId, state: &state,
                    source: source,
                    options: .init(activateWindow: false, ensureVisible: false, layoutRefresh: false, startAnimation: false)
                )
            }
            let patch = WorkspaceSessionPatch(
                workspaceId: wsId,
                viewportState: state,
                rememberedFocusToken: nil
            )
            guard let runtime = controller.runtime else {
                preconditionFailure("NiriLayoutHandler.focusNeighbor requires WMRuntime to be attached")
            }
            _ = runtime.applySessionPatch(patch, source: source)
            return
        }

        guard let monitor = projectionContext.monitor(for: wsId) else { return }
        syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
        let gap = CGFloat(controller.workspaceManager.gaps)
        let workingFrame = controller.insetWorkingFrame(for: monitor)

        engine.prepareColumnWidths(
            in: wsId,
            workingAreaWidth: workingFrame.width,
            gaps: gap
        )

        if let newNode = engine.focusTarget(
            direction: direction,
            currentSelection: currentNode,
            in: wsId,
            motion: controller.motionPolicy.snapshot(),
            state: &state,
            workingFrame: workingFrame,
            gaps: gap
        ) {
            activateNode(
                newNode, in: wsId, state: &state,
                source: source,
                options: .init(activateWindow: false, ensureVisible: false)
            )
        }
        let patch = WorkspaceSessionPatch(
            workspaceId: wsId,
            viewportState: state,
            rememberedFocusToken: nil
        )
        guard let runtime = controller.runtime else {
            preconditionFailure("NiriLayoutHandler.focusNeighbor requires WMRuntime to be attached")
        }
        _ = runtime.applySessionPatch(patch, source: source)
    }

    func toggleFullscreen(source: WMEventSource = .command) {
        guard let controller else { return }
        let result = withNiriWorkspaceContext(source: source) {
            engine, wsId, motion, state, _, _, _ -> (NiriLayoutEngine, WorkspaceDescriptor.ID, ViewportState)? in
            guard let currentId = state.selectedNodeId,
                  let currentNode = engine.findNode(by: currentId),
                  let windowNode = currentNode as? NiriWindow
            else { return nil }

            engine.toggleFullscreen(windowNode, motion: motion, state: &state)
            return (engine, wsId, state)
        } ?? nil

        guard let (engine, wsId, state) = result else { return }
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .layoutCommand,
            affectedWorkspaceIds: [wsId]
        )
        startScrollAnimationIfNeeded(for: wsId, state: state, engine: engine)
    }

    func cycleSize(
        forward: Bool,
        source: WMEventSource = .command
    ) {
        guard let controller else { return }
        let result = withNiriWorkspaceContext(source: source) {
            engine, wsId, motion, state, _, workingFrame, gaps -> (NiriLayoutEngine, WorkspaceDescriptor.ID, ViewportState)? in
            guard let currentId = state.selectedNodeId,
                  let windowNode = engine.findNode(by: currentId) as? NiriWindow,
                  let column = engine.findColumn(containing: windowNode, in: wsId)
            else { return nil }

            engine.toggleColumnWidth(
                column,
                forwards: forward,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
            return (engine, wsId, state)
        } ?? nil

        guard let (engine, wsId, state) = result else { return }
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .layoutCommand,
            affectedWorkspaceIds: [wsId]
        )
        startScrollAnimationIfNeeded(for: wsId, state: state, engine: engine)
    }

    func toggleColumnFullWidth(source: WMEventSource = .command) {
        guard let controller else { return }
        let result = withNiriWorkspaceContext(source: source) {
            engine, wsId, motion, state, _, workingFrame, gaps -> (NiriLayoutEngine, WorkspaceDescriptor.ID, ViewportState)? in
            guard let currentId = state.selectedNodeId,
                  let windowNode = engine.findNode(by: currentId) as? NiriWindow,
                  let column = engine.findColumn(containing: windowNode, in: wsId)
            else { return nil }

            engine.toggleFullWidth(
                column,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
            return (engine, wsId, state)
        } ?? nil

        guard let (engine, wsId, state) = result else { return }
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .layoutCommand,
            affectedWorkspaceIds: [wsId]
        )
        startScrollAnimationIfNeeded(for: wsId, state: state, engine: engine)
    }

    func balanceSizes(source: WMEventSource = .command) {
        guard let controller else { return }
        let result = withNiriWorkspaceContext(source: source) {
            engine, wsId, motion, _, _, workingFrame, gaps -> (NiriLayoutEngine, WorkspaceDescriptor.ID, Bool) in
            engine.balanceSizes(
                in: wsId,
                motion: motion,
                workingAreaWidth: workingFrame.width,
                gaps: gaps
            )
            return (engine, wsId, engine.hasAnyColumnAnimationsRunning(in: wsId))
        }

        guard let (_, wsId, shouldStartAnimation) = result else { return }
        controller.layoutRefreshController.requestImmediateRelayout(
            reason: .layoutCommand,
            affectedWorkspaceIds: [wsId]
        )
        if shouldStartAnimation {
            controller.layoutRefreshController.startScrollAnimation(for: wsId)
        }
    }



    func enableNiriLayout(
        maxWindowsPerColumn: Int = 3,
        centerFocusedColumn: CenterFocusedColumn = .never,
        alwaysCenterSingleColumn: Bool = false
    ) {
        guard let controller else { return }
        let engine = NiriLayoutEngine(maxWindowsPerColumn: maxWindowsPerColumn)
        engine.centerFocusedColumn = centerFocusedColumn
        engine.alwaysCenterSingleColumn = alwaysCenterSingleColumn
        engine.renderStyle.tabIndicatorWidth = TabbedColumnOverlayManager.tabIndicatorWidth
        engine.animationClock = controller.animationClock
        controller.niriEngine = engine

        syncMonitorsToNiriEngine()

        controller.layoutRefreshController.requestRelayout(reason: .layoutConfigChanged)
    }

    func syncMonitorsToNiriEngine() {
        guard let controller, let engine = controller.niriEngine else { return }

        let projectionContext = LayoutProjectionContext.project(controller: controller)
        let currentMonitors = projectionContext.topology.order.compactMap {
            projectionContext.topology.node($0)?.monitor
        }
        engine.updateMonitors(currentMonitors)

        let workspaceAssignments: [(workspaceId: WorkspaceDescriptor.ID, monitor: Monitor)] =
            projectionContext.graph.workspaceOrder.compactMap { workspaceId in
                guard let monitor = projectionContext.monitor(for: workspaceId) else { return nil }
                return (workspaceId: workspaceId, monitor: monitor)
        }
        engine.syncWorkspaceAssignments(workspaceAssignments)

        refreshResolvedMonitorSettings()
    }

    func refreshResolvedMonitorSettings() {
        guard let controller, let engine = controller.niriEngine else { return }

        let topology = LayoutProjectionContext.project(controller: controller).topology
        let global = engine.globalResolvedSettings()
        for monitorId in topology.order {
            guard let monitor = topology.node(monitorId)?.monitor else { continue }
            let override = controller.settings.niriSettings(for: monitor)
            let resolved = ResolvedNiriSettings(
                maxVisibleColumns: override?.maxVisibleColumns ?? global.maxVisibleColumns,
                maxWindowsPerColumn: override?.maxWindowsPerColumn ?? global.maxWindowsPerColumn,
                centerFocusedColumn: override?.centerFocusedColumn ?? global.centerFocusedColumn,
                alwaysCenterSingleColumn: override?.alwaysCenterSingleColumn ?? global.alwaysCenterSingleColumn,
                singleWindowAspectRatio: override?.singleWindowAspectRatio ?? global.singleWindowAspectRatio,
                infiniteLoop: override?.infiniteLoop ?? global.infiniteLoop
            )
            engine.updateMonitorSettings(resolved, for: monitor.id)
        }
    }

    func updateNiriConfig(
        maxWindowsPerColumn: Int? = nil,
        maxVisibleColumns: Int? = nil,
        infiniteLoop: Bool? = nil,
        centerFocusedColumn: CenterFocusedColumn? = nil,
        alwaysCenterSingleColumn: Bool? = nil,
        singleWindowAspectRatio: SingleWindowAspectRatio? = nil,
        columnWidthPresets: [Double]? = nil,
        defaultColumnWidth: Double?? = nil
    ) {
        guard let controller else { return }
        controller.niriEngine?.updateConfiguration(
            maxWindowsPerColumn: maxWindowsPerColumn,
            maxVisibleColumns: maxVisibleColumns,
            infiniteLoop: infiniteLoop,
            centerFocusedColumn: centerFocusedColumn,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            singleWindowAspectRatio: singleWindowAspectRatio,
            presetColumnWidths: columnWidthPresets?.map { .proportion($0) },
            defaultColumnWidth: defaultColumnWidth.map { $0.map { CGFloat($0) } }
        )
        refreshResolvedMonitorSettings()
        controller.layoutRefreshController.requestRelayout(reason: .layoutConfigChanged)
    }



    func activateNode(
        _ node: NiriNode,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState,
        source: WMEventSource = .command,
        options: NodeActivationOptions = NodeActivationOptions()
    ) {
        guard let controller, let engine = controller.niriEngine else { return }

        state.selectedNodeId = node.id

        if options.activateWindow {
            engine.activateWindow(node.id)
        }

        if options.ensureVisible,
           let monitor = LayoutProjectionContext.project(controller: controller).monitor(for: workspaceId)
        {
            syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
            let gap = CGFloat(controller.workspaceManager.gaps)
            let workingFrame = controller.insetWorkingFrame(for: monitor)
            engine.ensureSelectionVisible(
                node: node,
                in: workspaceId,
                motion: controller.motionPolicy.snapshot(),
                state: &state,
                workingFrame: workingFrame,
                gaps: gap
            )
        }

        let focusedToken = (node as? NiriWindow)?.token
        guard let runtime = controller.runtime else {
            preconditionFailure("NiriLayoutHandler.activateNode requires WMRuntime to be attached")
        }
        _ = runtime.commitWorkspaceSelection(
            nodeId: node.id,
            focusedToken: focusedToken,
            in: workspaceId,
            onMonitor: controller.workspaceManager.monitorId(for: workspaceId),
            source: source
        )

        if let windowNode = node as? NiriWindow {
            if options.updateTimestamp {
                engine.updateFocusTimestamp(for: windowNode.id)
            }
            if !options.layoutRefresh {
                controller.recordManagedRestoreGeometryIfMaterialStateChanged(
                    for: CGWindowID(windowNode.token.windowId),
                    reason: .niriStateChanged
                )
            }
        }

        if options.layoutRefresh {
            let focusToken = options.axFocus ? (node as? NiriWindow)?.token : nil
            let materialStateWindowId = (node as? NiriWindow)?.token.windowId
            if let focusToken {
                _ = runtime.beginManagedFocusRequest(
                    focusToken,
                    in: workspaceId,
                    onMonitor: controller.workspaceManager.monitorId(for: workspaceId),
                    source: source
                )
            }
            controller.layoutRefreshController.requestImmediateRelayout(
                reason: .layoutCommand,
                affectedWorkspaceIds: [workspaceId]
            ) { [weak controller] in
                if let materialStateWindowId {
                    controller?.recordManagedRestoreGeometryIfMaterialStateChanged(
                        for: CGWindowID(materialStateWindowId),
                        reason: .niriStateChanged
                    )
                }
                if let focusToken {
                    controller?.focusWindow(focusToken, source: source)
                }
            }
            if options.startAnimation, state.viewOffsetPixels.isAnimating {
                controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
            }
        } else {
            if options.axFocus, let windowNode = node as? NiriWindow {
                controller.focusWindow(windowNode.token, source: source)
            }
            if options.startAnimation, state.viewOffsetPixels.isAnimating {
                controller.layoutRefreshController.startScrollAnimation(for: workspaceId)
            }
        }
    }

    func withNiriOperationContext(
        source: WMEventSource = .command,
        perform operation: (NiriOperationContext, inout ViewportState) -> NiriOperationPostCommit?
    ) {
        guard let controller else { return }

        guard let engine = controller.niriEngine else { return }
        let projectionContext = LayoutProjectionContext.project(controller: controller)
        guard let wsId = projectionContext.activeWorkspaceIdForInteraction
        else { return }

        let runtime = requiredRuntime("NiriLayoutHandler.withNiriOperationContext")
        let postCommit: (
            context: NiriOperationContext,
            action: NiriOperationPostCommit,
            state: ViewportState
        )? = runtime.withNiriViewportState(for: wsId, source: source) { state in
            guard let currentId = state.selectedNodeId,
                  let currentNode = engine.findNode(by: currentId),
                  let windowNode = currentNode as? NiriWindow
            else { return nil }

            guard let monitor = projectionContext.monitor(for: wsId) else {
                return nil
            }
            syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
            let workingFrame = controller.insetWorkingFrame(for: monitor)
            let gaps = CGFloat(controller.workspaceManager.gaps)

            let ctx = NiriOperationContext(
                controller: controller,
                engine: engine,
                motion: controller.motionPolicy.snapshot(),
                wsId: wsId,
                windowNode: windowNode,
                monitor: monitor,
                workingFrame: workingFrame,
                gaps: gaps
            )

            guard let postCommit = operation(ctx, &state) else {
                return nil
            }
            return (context: ctx, action: postCommit, state: state)
        }

        if let postCommit,
           postCommit.action.apply(context: postCommit.context, state: postCommit.state)
        {
            controller.layoutRefreshController.startScrollAnimation(for: postCommit.context.wsId)
        }
    }

    @discardableResult
    func withNiriWorkspaceContext<Result>(
        source: WMEventSource = .command,
        perform: (NiriLayoutEngine, WorkspaceDescriptor.ID, MotionSnapshot, inout ViewportState, Monitor, CGRect, CGFloat) -> Result
    ) -> Result? {
        guard let controller else { return nil }
        guard let engine = controller.niriEngine else { return nil }
        let projectionContext = LayoutProjectionContext.project(controller: controller)
        guard let wsId = projectionContext.activeWorkspaceIdForInteraction
        else { return nil }
        guard let monitor = projectionContext.monitor(for: wsId) else { return nil }
        let motion = controller.motionPolicy.snapshot()
        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let gaps = CGFloat(controller.workspaceManager.gaps)
        let runtime = requiredRuntime("NiriLayoutHandler.withNiriWorkspaceContext")
        return runtime.withNiriViewportState(for: wsId, source: source) { state in
            syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
            return perform(engine, wsId, motion, &state, monitor, workingFrame, gaps)
        }
    }

    @discardableResult
    func withNiriWorkspaceContext<Result>(
        for workspaceId: WorkspaceDescriptor.ID,
        source: WMEventSource = .command,
        perform: (NiriLayoutEngine, WorkspaceDescriptor.ID, MotionSnapshot, inout ViewportState, Monitor, CGRect, CGFloat) -> Result
    ) -> Result? {
        guard let controller else { return nil }
        guard let engine = controller.niriEngine else { return nil }
        guard let monitor = LayoutProjectionContext.project(controller: controller).monitor(for: workspaceId)
        else { return nil }
        let motion = controller.motionPolicy.snapshot()
        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let gaps = CGFloat(controller.workspaceManager.gaps)
        let runtime = requiredRuntime("NiriLayoutHandler.withNiriWorkspaceContextForWorkspace")
        return runtime.withNiriViewportState(for: workspaceId, source: source) { state in
            syncAnimationRefreshRate(for: monitor, engine: engine, state: &state)
            return perform(engine, workspaceId, motion, &state, monitor, workingFrame, gaps)
        }
    }

    @discardableResult
    func insertWindow(
        handle: WindowHandle,
        targetHandle: WindowHandle,
        position: InsertPosition,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        var didMove = false
        withNiriWorkspaceContext(for: workspaceId) { engine, wsId, motion, state, monitor, workingFrame, gaps in
            guard let source = engine.findNode(for: handle) else { return }
            guard let target = engine.findNode(for: targetHandle) else { return }
            didMove = engine.insertWindowByMove(
                sourceWindowId: source.id,
                targetWindowId: target.id,
                position: position,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
        return didMove
    }

    @discardableResult
    func insertWindowInNewColumn(
        handle: WindowHandle,
        insertIndex: Int,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> Bool {
        var didMove = false
        withNiriWorkspaceContext(for: workspaceId) { engine, wsId, motion, state, monitor, workingFrame, gaps in
            guard let window = engine.findNode(for: handle) else { return }
            didMove = engine.insertWindowInNewColumn(
                window,
                insertIndex: insertIndex,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
        return didMove
    }
}

private extension NiriLayoutHandler {
    func suppressAnimationsForNativeFullscreenRestore(
        pass: NiriLayoutPass,
        state: inout ViewportState
    ) {
        if let controller {
            let displayIds = scrollAnimationByDisplay.compactMap { displayId, workspaceId in
                workspaceId == pass.wsId ? displayId : nil
            }
            for displayId in displayIds {
                controller.layoutRefreshController.stopScrollAnimation(for: displayId)
            }
        }

        state.cancelAnimation()
        pass.engine.cancelAllMotionAnimations(in: pass.wsId)
    }

    func resolvedNativeFullscreenRestoreContexts(
        for windows: [LayoutWindowSnapshot],
        workspaceId: WorkspaceDescriptor.ID
    ) -> [WindowToken: NativeFullscreenRestoreContext] {
        guard let topologyProfile = controller?.workspaceManager.topologyProfile else { return [:] }

        var restoreContexts: [WindowToken: NativeFullscreenRestoreContext] = [:]
        for window in windows {
            guard let restoreContext = window.nativeFullscreenRestore,
                  restoreContext.currentToken == window.token,
                  restoreContext.workspaceId == workspaceId,
                  restoreContext.capturedTopologyProfile == topologyProfile,
                  restoreContext.restoreFrame != nil
            else {
                continue
            }
            restoreContexts[window.token] = restoreContext
        }
        return restoreContexts
    }

    func applyNativeFullscreenNiriState(
        _ restoreContexts: [WindowToken: NativeFullscreenRestoreContext],
        in engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) {
        for (token, restoreContext) in restoreContexts {
            applyNativeFullscreenNiriState(
                restoreContext.niriState,
                for: token,
                in: engine,
                workspaceId: workspaceId
            )
        }
    }

    func applyNativeFullscreenNiriState(
        _ niriState: ManagedWindowRestoreSnapshot.NiriState?,
        for token: WindowToken,
        in engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) {
        guard let niriState else {
            return
        }
        guard let window = engine.findNode(for: token) else {
            return
        }

        reconcileNativeFullscreenColumn(
            restoringWindow: window,
            niriState: niriState,
            in: engine,
            workspaceId: workspaceId
        )

        let currentColumn = engine.column(of: window)
        if let column = currentColumn {
            let sizing = niriState.columnSizing
            column.widthAnimation = nil
            column.targetWidth = nil
            column.width = sizing.width
            column.cachedWidth = sizing.cachedWidth
            column.presetWidthIdx = sizing.presetWidthIdx
            column.isFullWidth = sizing.isFullWidth
            column.savedWidth = sizing.savedWidth
            column.hasManualSingleWindowWidthOverride = sizing.hasManualSingleWindowWidthOverride
            column.height = sizing.height
            column.cachedHeight = sizing.cachedHeight
            column.isFullHeight = sizing.isFullHeight
            column.savedHeight = sizing.savedHeight
        }

        let sizing = niriState.windowSizing
        window.height = sizing.height
        window.savedHeight = sizing.savedHeight
        window.windowWidth = sizing.windowWidth
        window.sizingMode = sizing.sizingMode
        window.resolvedHeight = nil
        window.resolvedWidth = nil
        window.stopMoveAnimations()
    }

    private func reconcileNativeFullscreenColumn(
        restoringWindow window: NiriWindow,
        niriState: ManagedWindowRestoreSnapshot.NiriState,
        in engine: NiriLayoutEngine,
        workspaceId: WorkspaceDescriptor.ID
    ) {
        guard let controller else { return }
        let registry = controller.workspaceManager.logicalWindowRegistry
        let restoringLogicalId = registry.resolveForRead(token: window.token)
        let storedLogicalMembers = niriState.columnWindowMembers
        guard storedLogicalMembers.count > 1 else { return }
        guard let currentColumn = engine.column(of: window) else { return }
        guard let currentRoot = currentColumn.findRoot(),
              currentRoot.workspaceId == workspaceId
        else { return }

        let siblingLogicalIds = storedLogicalMembers.filter { $0 != restoringLogicalId }
        var sameWorkspaceColumns: [ObjectIdentifier: NiriContainer] = [:]
        var hasForeignSibling = false
        for siblingLogicalId in siblingLogicalIds {
            guard let record = registry.record(for: siblingLogicalId),
                  record.primaryPhase != .retired,
                  let siblingToken = record.currentToken,
                  let siblingNode = engine.findNode(for: siblingToken),
                  let siblingColumn = engine.column(of: siblingNode)
            else {
                continue
            }
            guard siblingColumn.findRoot()?.workspaceId == workspaceId else {
                hasForeignSibling = true
                continue
            }
            sameWorkspaceColumns[ObjectIdentifier(siblingColumn)] = siblingColumn
        }

        guard !hasForeignSibling else { return }
        guard !sameWorkspaceColumns.isEmpty else { return }

        guard sameWorkspaceColumns.count == 1,
              let targetColumn = sameWorkspaceColumns.values.first
        else { return }

        guard targetColumn !== currentColumn else {
            return
        }

        let storedIndex = niriState.tileIndex
            ?? restoringLogicalId.flatMap { storedLogicalMembers.firstIndex(of: $0) }
            ?? targetColumn.children.count
        let insertIndex = max(0, min(storedIndex, targetColumn.children.count))

        window.detach()
        targetColumn.insertChild(window, at: insertIndex)

        if currentColumn.children.isEmpty, currentColumn !== targetColumn {
            currentColumn.remove()
            if let root = engine.root(for: currentRoot.workspaceId), root.columns.isEmpty {
                root.appendChild(NiriContainer())
            }
        }
    }

    func nativeFullscreenRestoreFinalizeTokens(
        windows: [LayoutWindowSnapshot],
        frames _: [WindowToken: CGRect]
    ) -> [WindowToken] {
        return windows.compactMap { window in
            guard window.isRestoringNativeFullscreen,
                  window.restoreFrame != nil
            else {
                return nil
            }
            return window.token
        }
    }
}

struct NodeActivationOptions {
    var activateWindow: Bool = true
    var ensureVisible: Bool = true
    var updateTimestamp: Bool = true
    var layoutRefresh: Bool = true
    var axFocus: Bool = true
    var startAnimation: Bool = true
}

@MainActor struct NiriOperationPostCommit {
    enum Kind {
        case simple
        case predictedAnimation(oldFrames: [WindowToken: CGRect])
        case capturedAnimation(oldFrames: [WindowToken: CGRect])
    }

    let kind: Kind

    func apply(context: NiriOperationContext, state: ViewportState) -> Bool {
        switch kind {
        case .simple:
            context.controller.layoutRefreshController.requestImmediateRelayout(
                reason: .layoutCommand,
                affectedWorkspaceIds: [context.wsId]
            )
        case let .predictedAnimation(oldFrames):
            let scale = context.controller.layoutRefreshController.backingScale(for: context.monitor)
            let workingArea = WorkingAreaContext(
                workingFrame: context.workingFrame,
                viewFrame: context.monitor.frame,
                scale: scale
            )
            let layoutGaps = LayoutGaps(
                horizontal: context.gaps,
                vertical: context.gaps,
                outer: context.controller.workspaceManager.outerGaps
            )
            let animationTime = (context.engine.animationClock?.now() ?? CACurrentMediaTime()) + 2.0
            let topology = LayoutProjectionContext.project(controller: context.controller).topology
            let hiddenPlacementMonitors = topology.order.compactMap { monitorId in
                topology.node(monitorId).map(HiddenPlacementMonitorContext.init)
            }
            let newFrames = context.engine.calculateCombinedLayoutUsingPools(
                in: context.wsId,
                monitor: context.monitor,
                gaps: layoutGaps,
                state: state,
                workingArea: workingArea,
                animationTime: animationTime,
                hiddenPlacementMonitors: hiddenPlacementMonitors
            ).frames
            _ = context.engine.triggerMoveAnimations(
                in: context.wsId,
                oldFrames: oldFrames,
                newFrames: newFrames,
                motion: context.motion
            )
            context.controller.layoutRefreshController.requestImmediateRelayout(
                reason: .layoutCommand,
                affectedWorkspaceIds: [context.wsId]
            )
        case let .capturedAnimation(oldFrames):
            context.controller.layoutRefreshController.requestImmediateRelayout(
                reason: .layoutCommand,
                affectedWorkspaceIds: [context.wsId]
            )
            let newFrames = context.engine.captureWindowFrames(in: context.wsId)
            _ = context.engine.triggerMoveAnimations(
                in: context.wsId,
                oldFrames: oldFrames,
                newFrames: newFrames,
                motion: context.motion
            )
        }

        return hasPendingNiriAnimationWork(
            state: state,
            engine: context.engine,
            workspaceId: context.wsId
        )
    }
}

@MainActor struct NiriOperationContext {
    let controller: WMController
    let engine: NiriLayoutEngine
    let motion: MotionSnapshot
    let wsId: WorkspaceDescriptor.ID
    let windowNode: NiriWindow
    let monitor: Monitor
    let workingFrame: CGRect
    let gaps: CGFloat

    func commitWithPredictedAnimation(
        oldFrames: [WindowToken: CGRect]
    ) -> NiriOperationPostCommit {
        NiriOperationPostCommit(kind: .predictedAnimation(oldFrames: oldFrames))
    }

    func commitWithCapturedAnimation(
        oldFrames: [WindowToken: CGRect]
    ) -> NiriOperationPostCommit {
        NiriOperationPostCommit(kind: .capturedAnimation(oldFrames: oldFrames))
    }

    func commitSimple() -> NiriOperationPostCommit {
        NiriOperationPostCommit(kind: .simple)
    }
}

extension NiriLayoutHandler: LayoutFocusable, LayoutSizable {}
