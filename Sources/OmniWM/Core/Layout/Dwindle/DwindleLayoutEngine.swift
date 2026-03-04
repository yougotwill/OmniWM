import CoreGraphics
import Foundation
import QuartzCore

final class DwindleLayoutEngine {
    enum Backend {
        case zigContext
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        case legacyDeterministic
#endif
    }

    private struct ZigWorkspaceState {
        let context: DwindleZigKernel.LayoutContext
        var handlesById: [UUID: WindowHandle] = [:]
        var selectedWindowId: UUID?
        var focusedWindowId: UUID?
        var preselection: Direction?
        var lastFramesById: [UUID: CGRect] = [:]
        var animationNodeById: [UUID: DwindleNode] = [:]
    }

    let backend: Backend

    var settings: DwindleSettings = DwindleSettings() {
        didSet {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
            if backend == .legacyDeterministic {
                legacyEngine.settings = settings
            }
#endif
        }
    }
    private var monitorSettings: [Monitor.ID: ResolvedDwindleSettings] = [:]
    var animationClock: AnimationClock? {
        didSet {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
            if backend == .legacyDeterministic {
                legacyEngine.animationClock = animationClock
            }
#endif
        }
    }
    var displayRefreshRate: Double = 60.0 {
        didSet {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
            if backend == .legacyDeterministic {
                legacyEngine.displayRefreshRate = displayRefreshRate
            }
#endif
        }
    }
    var windowMovementAnimationConfig: CubicConfig = CubicConfig(duration: 0.3) {
        didSet {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
            if backend == .legacyDeterministic {
                legacyEngine.windowMovementAnimationConfig = windowMovementAnimationConfig
            }
#endif
        }
    }

    private var windowConstraints: [WindowHandle: WindowSizeConstraints] = [:]
    private var zigStates: [WorkspaceDescriptor.ID: ZigWorkspaceState] = [:]

#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
    private let legacy: LegacyDwindleLayoutEngine?
#endif

    init(backend: Backend = .zigContext) {
        self.backend = backend
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        switch backend {
        case .zigContext:
            legacy = nil
        case .legacyDeterministic:
            guard Self.isRunningUnderXCTest else {
                preconditionFailure("Dwindle legacy backend is test-only and unavailable in this runtime")
            }
            legacy = LegacyDwindleLayoutEngine()
        }
#endif
    }

#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
    private static var isRunningUnderXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment.keys.contains(where: { $0.hasPrefix("SWIFT_TESTING") })
        {
            return true
        }
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return true
        }

        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") || processName.contains("packagetests") {
            return true
        }

        let arguments = ProcessInfo.processInfo.arguments.joined(separator: " ").lowercased()
        if arguments.contains("xctest")
            || arguments.contains("swift-testing")
            || arguments.contains("packagetests")
        {
            return true
        }

        return Bundle.main.bundlePath.hasSuffix(".xctest")
    }

    private var legacyEngine: LegacyDwindleLayoutEngine {
        guard let legacy else {
            preconditionFailure("Dwindle legacy backend is not initialized")
        }
        return legacy
    }
#endif

    private func ensureZigState(for workspaceId: WorkspaceDescriptor.ID) -> Bool {
        if zigStates[workspaceId] != nil {
            return true
        }
        guard let context = DwindleZigKernel.LayoutContext() else {
            return false
        }
        zigStates[workspaceId] = ZigWorkspaceState(context: context)
        return true
    }

    private func withZigState<T>(
        for workspaceId: WorkspaceDescriptor.ID,
        _ body: (inout ZigWorkspaceState) -> T
    ) -> T? {
        guard ensureZigState(for: workspaceId), var state = zigStates[workspaceId] else {
            return nil
        }
        let result = body(&state)
        zigStates[workspaceId] = state
        return result
    }

    private func applyZigResult(_ result: DwindleZigKernel.OpResult, to state: inout ZigWorkspaceState) {
        state.selectedWindowId = result.selectedWindowId
        state.focusedWindowId = result.focusedWindowId
        state.preselection = result.preselection
    }

    private func ensureAnimationNode(
        in state: inout ZigWorkspaceState,
        windowId: UUID,
        handle: WindowHandle
    ) -> DwindleNode {
        if let existing = state.animationNodeById[windowId] {
            let fullscreen = existing.isFullscreen
            existing.kind = .leaf(handle: handle, fullscreen: fullscreen)
            return existing
        }

        let node = DwindleNode(kind: .leaf(handle: handle, fullscreen: false))
        node.cachedFrame = state.lastFramesById[windowId]
        state.animationNodeById[windowId] = node
        return node
    }

    private func applyZigOp(
        _ op: DwindleZigKernel.Op,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> DwindleZigKernel.OpResult? {
        withZigState(for: workspaceId) { state in
            let result = DwindleZigKernel.applyOp(context: state.context, op: op)
            if result.rc == 0 {
                applyZigResult(result, to: &state)
            }
            return result
        }
    }

    private func zigHandle(for windowId: UUID?, in workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
        guard let windowId,
              let state = zigStates[workspaceId]
        else {
            return nil
        }
        return state.handlesById[windowId]
    }

    private func zigFindNode(windowId: UUID) -> DwindleNode? {
        for state in zigStates.values {
            if let node = state.animationNodeById[windowId] {
                return node
            }
        }
        return nil
    }

    private func zigAnimationNode(for handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) -> DwindleNode? {
        zigStates[workspaceId]?.animationNodeById[handle.id]
    }

    private func dedupHandlesById(_ handles: [WindowHandle]) -> (order: [UUID], map: [UUID: WindowHandle]) {
        var order: [UUID] = []
        order.reserveCapacity(handles.count)

        var map: [UUID: WindowHandle] = [:]
        map.reserveCapacity(handles.count)

        for handle in handles where map[handle.id] == nil {
            order.append(handle.id)
            map[handle.id] = handle
        }

        return (order, map)
    }

    private func zigCurrentFrames(for workspaceId: WorkspaceDescriptor.ID) -> [WindowHandle: CGRect] {
        guard let state = zigStates[workspaceId] else {
            return [:]
        }

        var frames: [WindowHandle: CGRect] = [:]
        frames.reserveCapacity(state.lastFramesById.count)

        for (windowId, frame) in state.lastFramesById {
            guard let handle = state.handlesById[windowId] else { continue }
            frames[handle] = frame
        }

        return frames
    }

    func updateWindowConstraints(for handle: WindowHandle, constraints: WindowSizeConstraints) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.updateWindowConstraints(for: handle, constraints: constraints)
            return
        }
#endif
        windowConstraints[handle] = constraints
    }

    func constraints(for handle: WindowHandle) -> WindowSizeConstraints {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.constraints(for: handle)
        }
#endif
        return windowConstraints[handle] ?? .unconstrained
    }

    func updateMonitorSettings(_ resolved: ResolvedDwindleSettings, for monitorId: Monitor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.updateMonitorSettings(resolved, for: monitorId)
            return
        }
#endif
        monitorSettings[monitorId] = resolved
    }

    func cleanupRemovedMonitor(_ monitorId: Monitor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.cleanupRemovedMonitor(monitorId)
            return
        }
#endif
        monitorSettings.removeValue(forKey: monitorId)
    }

    func effectiveSettings(for monitorId: Monitor.ID) -> DwindleSettings {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.effectiveSettings(for: monitorId)
        }
#endif
        guard let resolved = monitorSettings[monitorId] else { return settings }

        var effective = settings
        effective.smartSplit = resolved.smartSplit
        effective.defaultSplitRatio = resolved.defaultSplitRatio
        effective.splitWidthMultiplier = resolved.splitWidthMultiplier
        if !resolved.singleWindowAspectRatio.isFillScreen {
            effective.singleWindowAspectRatio = resolved.singleWindowAspectRatio.size
        }
        if !resolved.useGlobalGaps {
            effective.innerGap = resolved.innerGap
            effective.outerGapTop = resolved.outerGapTop
            effective.outerGapBottom = resolved.outerGapBottom
            effective.outerGapLeft = resolved.outerGapLeft
            effective.outerGapRight = resolved.outerGapRight
        }
        return effective
    }

    func root(for workspaceId: WorkspaceDescriptor.ID) -> DwindleNode? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.root(for: workspaceId)
        }
#endif
        return nil
    }

    func ensureRoot(for workspaceId: WorkspaceDescriptor.ID) -> DwindleNode {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.ensureRoot(for: workspaceId)
        }
#endif
        _ = ensureZigState(for: workspaceId)
        return DwindleNode(kind: .leaf(handle: nil, fullscreen: false))
    }

    func removeLayout(for workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.removeLayout(for: workspaceId)
            return
        }
#endif

        if let state = zigStates.removeValue(forKey: workspaceId) {
            for handle in state.handlesById.values {
                windowConstraints.removeValue(forKey: handle)
            }
        }
    }

    func containsWindow(_ handle: WindowHandle, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.containsWindow(handle, in: workspaceId)
        }
#endif
        return zigStates[workspaceId]?.handlesById[handle.id] != nil
    }

    func findNode(for handle: WindowHandle) -> DwindleNode? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.findNode(for: handle)
        }
#endif
        return zigFindNode(windowId: handle.id)
    }

    private func findNode(windowId: UUID) -> DwindleNode? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return nil
        }
#endif
        return zigFindNode(windowId: windowId)
    }

    func windowCount(in workspaceId: WorkspaceDescriptor.ID) -> Int {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.windowCount(in: workspaceId)
        }
#endif
        return zigStates[workspaceId]?.handlesById.count ?? 0
    }

    func selectedNode(in workspaceId: WorkspaceDescriptor.ID) -> DwindleNode? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.selectedNode(in: workspaceId)
        }
#endif
        guard let handle = selectedWindowHandle(in: workspaceId) else {
            return nil
        }
        return findNode(for: handle)
    }

    func selectedWindowHandle(in workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.selectedNode(in: workspaceId)?.windowHandle
        }
#endif
        guard let state = zigStates[workspaceId],
              let selectedId = state.selectedWindowId
        else {
            return nil
        }
        return state.handlesById[selectedId]
    }

    func setSelectedNode(_ node: DwindleNode?, in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.setSelectedNode(node, in: workspaceId)
            return
        }
#endif
        guard var state = zigStates[workspaceId] else { return }
        state.selectedWindowId = node?.windowHandle?.id
        zigStates[workspaceId] = state
    }

    func setPreselection(_ direction: Direction?, in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.setPreselection(direction, in: workspaceId)
            return
        }
#endif
        let op: DwindleZigKernel.Op = if let direction {
            .setPreselection(direction: direction)
        } else {
            .clearPreselection
        }
        _ = applyZigOp(op, in: workspaceId)
    }

    func getPreselection(in workspaceId: WorkspaceDescriptor.ID) -> Direction? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.getPreselection(in: workspaceId)
        }
#endif
        return zigStates[workspaceId]?.preselection
    }

    @discardableResult
    func addWindow(
        handle: WindowHandle,
        to workspaceId: WorkspaceDescriptor.ID,
        activeWindowFrame: CGRect?
    ) -> DwindleNode {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.addWindow(handle: handle, to: workspaceId, activeWindowFrame: activeWindowFrame)
        }
#endif

        guard var state = zigStates[workspaceId] ?? (ensureZigState(for: workspaceId) ? zigStates[workspaceId] : nil) else {
            return DwindleNode(kind: .leaf(handle: handle, fullscreen: false))
        }

        if let existing = state.animationNodeById[handle.id] {
            let fullscreen = existing.isFullscreen
            existing.kind = .leaf(handle: handle, fullscreen: fullscreen)
            state.handlesById[handle.id] = handle
            zigStates[workspaceId] = state
            return existing
        }

        let previousState = state
        state.handlesById[handle.id] = handle
        let node = ensureAnimationNode(in: &state, windowId: handle.id, handle: handle)

        let result = DwindleZigKernel.applyOp(context: state.context, op: .addWindow(windowId: handle.id))
        guard result.rc == 0 else {
            zigStates[workspaceId] = previousState
            return node
        }

        applyZigResult(result, to: &state)
        zigStates[workspaceId] = state
        return node
    }

    func removeWindow(handle: WindowHandle, from workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.removeWindow(handle: handle, from: workspaceId)
            return
        }
#endif

        guard var state = zigStates[workspaceId], state.handlesById[handle.id] != nil else {
            return
        }

        let previousById = state.handlesById
        let result = DwindleZigKernel.applyOp(context: state.context, op: .removeWindow(windowId: handle.id))
        guard result.rc == 0 else {
            return
        }

        applyZigResult(result, to: &state)

        for removedId in result.removedWindowIds {
            if let removedHandle = previousById[removedId] {
                windowConstraints.removeValue(forKey: removedHandle)
            }
            state.handlesById.removeValue(forKey: removedId)
            state.animationNodeById.removeValue(forKey: removedId)
            state.lastFramesById.removeValue(forKey: removedId)
        }

        zigStates[workspaceId] = state
    }

    func syncWindows(
        _ handles: [WindowHandle],
        in workspaceId: WorkspaceDescriptor.ID,
        focusedHandle: WindowHandle?
    ) -> Set<WindowHandle> {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.syncWindows(handles, in: workspaceId, focusedHandle: focusedHandle)
        }
#endif

        _ = focusedHandle

        guard var state = zigStates[workspaceId] ?? (ensureZigState(for: workspaceId) ? zigStates[workspaceId] : nil) else {
            return []
        }

        let deduped = dedupHandlesById(handles)
        let previousById = state.handlesById

        let result = DwindleZigKernel.applyOp(
            context: state.context,
            op: .syncWindows(windowIds: deduped.order)
        )

        guard result.rc == 0 else {
            return []
        }

        applyZigResult(result, to: &state)

        var removedHandles: [WindowHandle] = []
        removedHandles.reserveCapacity(result.removedWindowIds.count)
        for removedId in result.removedWindowIds {
            if let removed = previousById[removedId] {
                removedHandles.append(removed)
                windowConstraints.removeValue(forKey: removed)
            }
            state.animationNodeById.removeValue(forKey: removedId)
            state.lastFramesById.removeValue(forKey: removedId)
        }

        state.handlesById = deduped.map

        for (windowId, handle) in state.handlesById {
            let node = ensureAnimationNode(in: &state, windowId: windowId, handle: handle)
            node.cachedFrame = state.lastFramesById[windowId]
        }

        for existingId in Array(state.animationNodeById.keys) where state.handlesById[existingId] == nil {
            state.animationNodeById.removeValue(forKey: existingId)
            state.lastFramesById.removeValue(forKey: existingId)
        }

        zigStates[workspaceId] = state
        return Set(removedHandles)
    }

    func calculateLayout(
        for workspaceId: WorkspaceDescriptor.ID,
        screen: CGRect
    ) -> [WindowHandle: CGRect] {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.calculateLayout(for: workspaceId, screen: screen)
        }
#endif

        guard let output = withZigState(for: workspaceId, { state -> [WindowHandle: CGRect] in
            if state.handlesById.isEmpty {
                state.lastFramesById.removeAll(keepingCapacity: true)
                return [:]
            }

            let request = DwindleZigKernel.LayoutRequest(screen: screen, settings: settings)
            let kernelConstraints = state.handlesById.values.map { handle in
                DwindleZigKernel.WindowConstraint(windowId: handle.id, constraints: constraints(for: handle))
            }

            let layoutResult = DwindleZigKernel.calculateLayout(
                context: state.context,
                request: request,
                constraints: kernelConstraints
            )

            if layoutResult.rc != 0 {
                var staleFrames: [WindowHandle: CGRect] = [:]
                staleFrames.reserveCapacity(state.lastFramesById.count)
                for (windowId, frame) in state.lastFramesById {
                    guard let handle = state.handlesById[windowId] else { continue }
                    staleFrames[handle] = frame
                }
                return staleFrames
            }

            state.lastFramesById = layoutResult.framesByWindowId

            var framesByHandle: [WindowHandle: CGRect] = [:]
            framesByHandle.reserveCapacity(layoutResult.framesByWindowId.count)

            for (windowId, frame) in layoutResult.framesByWindowId {
                guard let handle = state.handlesById[windowId] else { continue }
                framesByHandle[handle] = frame
                let node = ensureAnimationNode(in: &state, windowId: windowId, handle: handle)
                node.cachedFrame = frame
            }

            for (windowId, node) in state.animationNodeById where layoutResult.framesByWindowId[windowId] == nil {
                node.cachedFrame = nil
            }

            return framesByHandle
        }) else {
            return [:]
        }

        return output
    }

    func currentFrames(in workspaceId: WorkspaceDescriptor.ID) -> [WindowHandle: CGRect] {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.currentFrames(in: workspaceId)
        }
#endif
        return zigCurrentFrames(for: workspaceId)
    }

    func findGeometricNeighbor(
        from handle: WindowHandle,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID
    ) -> WindowHandle? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.findGeometricNeighbor(from: handle, direction: direction, in: workspaceId)
        }
#endif

        guard let state = zigStates[workspaceId] else {
            return nil
        }

        let result = DwindleZigKernel.findNeighbor(
            context: state.context,
            windowId: handle.id,
            direction: direction,
            innerGap: settings.innerGap
        )

        guard result.rc == 0,
              let neighborId = result.neighborWindowId
        else {
            return nil
        }

        return state.handlesById[neighborId]
    }

    func moveFocus(direction: Direction, in workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.moveFocus(direction: direction, in: workspaceId)
        }
#endif

        guard let result = applyZigOp(.moveFocus(direction: direction), in: workspaceId),
              result.rc == 0,
              result.applied
        else {
            return nil
        }

        return zigHandle(for: result.selectedWindowId, in: workspaceId)
    }

    func swapWindows(direction: Direction, in workspaceId: WorkspaceDescriptor.ID) -> Bool {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.swapWindows(direction: direction, in: workspaceId)
        }
#endif

        guard let result = applyZigOp(.swapWindows(direction: direction), in: workspaceId) else {
            return false
        }
        return result.rc == 0 && result.applied
    }

    func toggleOrientation(in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.toggleOrientation(in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.toggleOrientation, in: workspaceId)
    }

    func toggleFullscreen(in workspaceId: WorkspaceDescriptor.ID) -> WindowHandle? {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.toggleFullscreen(in: workspaceId)
        }
#endif

        guard let result = applyZigOp(.toggleFullscreen, in: workspaceId),
              result.rc == 0,
              result.applied
        else {
            return nil
        }

        return zigHandle(for: result.selectedWindowId, in: workspaceId)
    }

    func moveSelectionToRoot(stable: Bool, in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.moveSelectionToRoot(stable: stable, in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.moveSelectionToRoot(stable: stable), in: workspaceId)
    }

    func resizeSelected(
        by delta: CGFloat,
        direction: Direction,
        in workspaceId: WorkspaceDescriptor.ID
    ) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.resizeSelected(by: delta, direction: direction, in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.resizeSelected(delta: delta, direction: direction), in: workspaceId)
    }

    func balanceSizes(in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.balanceSizes(in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.balanceSizes, in: workspaceId)
    }

    func swapSplit(in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.swapSplit(in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.swapSplit, in: workspaceId)
    }

    func cycleSplitRatio(forward: Bool, in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.cycleSplitRatio(forward: forward, in: workspaceId)
            return
        }
#endif

        _ = applyZigOp(.cycleSplitRatio(forward: forward), in: workspaceId)
    }

    func tickAnimations(at time: TimeInterval, in workspaceId: WorkspaceDescriptor.ID) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.tickAnimations(at: time, in: workspaceId)
            return
        }
#endif

        guard let state = zigStates[workspaceId] else {
            return
        }

        for node in state.animationNodeById.values {
            node.tickAnimations(at: time)
        }
    }

    func hasActiveAnimations(in workspaceId: WorkspaceDescriptor.ID, at time: TimeInterval) -> Bool {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.hasActiveAnimations(in: workspaceId, at: time)
        }
#endif

        guard let state = zigStates[workspaceId] else {
            return false
        }

        for node in state.animationNodeById.values where node.hasActiveAnimations(at: time) {
            return true
        }
        return false
    }

    func animateWindowMovements(
        oldFrames: [WindowHandle: CGRect],
        newFrames: [WindowHandle: CGRect]
    ) {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            legacyEngine.animateWindowMovements(oldFrames: oldFrames, newFrames: newFrames)
            return
        }
#endif

        for (handle, newFrame) in newFrames {
            guard let oldFrame = oldFrames[handle] else { continue }

            let changed = abs(oldFrame.origin.x - newFrame.origin.x) > 0.5
                || abs(oldFrame.origin.y - newFrame.origin.y) > 0.5
                || abs(oldFrame.width - newFrame.width) > 0.5
                || abs(oldFrame.height - newFrame.height) > 0.5

            guard changed,
                  let workspaceId = zigStates.keys.first(where: { zigStates[$0]?.animationNodeById[handle.id] != nil }),
                  let node = zigAnimationNode(for: handle, in: workspaceId)
            else {
                continue
            }

            node.animateFrom(
                oldFrame: oldFrame,
                newFrame: newFrame,
                clock: animationClock,
                config: windowMovementAnimationConfig
            )
        }
    }

    func calculateAnimatedFrames(
        baseFrames: [WindowHandle: CGRect],
        in workspaceId: WorkspaceDescriptor.ID,
        at time: TimeInterval
    ) -> [WindowHandle: CGRect] {
#if OMNI_DWINDLE_LEGACY_TEST_BACKEND
        if backend == .legacyDeterministic {
            return legacyEngine.calculateAnimatedFrames(baseFrames: baseFrames, in: workspaceId, at: time)
        }
#endif

        var result = baseFrames

        for (handle, frame) in baseFrames {
            guard let node = zigAnimationNode(for: handle, in: workspaceId) else { continue }

            let posOffset = node.renderOffset(at: time)
            let sizeOffset = node.renderSizeOffset(at: time)

            let hasAnimation = abs(posOffset.x) > 0.1
                || abs(posOffset.y) > 0.1
                || abs(sizeOffset.width) > 0.1
                || abs(sizeOffset.height) > 0.1

            if hasAnimation {
                result[handle] = CGRect(
                    x: frame.origin.x + posOffset.x,
                    y: frame.origin.y + posOffset.y,
                    width: frame.width + sizeOffset.width,
                    height: frame.height + sizeOffset.height
                )
            }
        }

        return result
    }
}
