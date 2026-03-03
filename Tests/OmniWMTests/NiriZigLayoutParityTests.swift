import ApplicationServices
import Foundation
import QuartzCore
import Testing

@testable import OmniWM

private struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextBool(_ trueProbability: Double = 0.5) -> Bool {
        let value = Double(next() % 10_000) / 10_000.0
        return value < trueProbability
    }

    mutating func nextInt(_ range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func nextCGFloat(_ range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(next() % 1_000_000) / 1_000_000.0
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private struct ZigScenario {
    let engine: NiriLayoutEngine
    let workspaceId: WorkspaceDescriptor.ID
    let state: ViewportState
    let monitorFrame: CGRect
    let workingArea: WorkingAreaContext
    let gaps: (horizontal: CGFloat, vertical: CGFloat)
    let orientation: Monitor.Orientation
    let animationTime: TimeInterval
}

private struct ZigRunSnapshot {
    let frames: [WindowHandle: CGRect]
    let hidden: [WindowHandle: HideSide]
    let windowFrames: [WindowHandle: CGRect?]
    let columnFrames: [NodeId: CGRect?]
}

private func approxEqual(_ lhs: CGFloat, _ rhs: CGFloat, epsilon: CGFloat = 0.01) -> Bool {
    abs(lhs - rhs) <= epsilon
}

private func approxRectEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.01) -> Bool {
    approxEqual(lhs.origin.x, rhs.origin.x, epsilon: epsilon)
        && approxEqual(lhs.origin.y, rhs.origin.y, epsilon: epsilon)
        && approxEqual(lhs.width, rhs.width, epsilon: epsilon)
        && approxEqual(lhs.height, rhs.height, epsilon: epsilon)
}

private func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let idx = Int((Double(sorted.count - 1) * p).rounded(.toNearestOrAwayFromZero))
    return sorted[max(0, min(sorted.count - 1, idx))]
}

private func resetComputedLayoutState(
    engine: NiriLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) {
    for column in engine.columns(in: workspaceId) {
        column.frame = nil
        for window in column.windowNodes {
            window.frame = nil
            window.resolvedWidth = nil
            window.resolvedHeight = nil
            window.widthFixedByConstraint = false
            window.heightFixedByConstraint = false
        }
    }
}

private func runZigLayout(_ scenario: ZigScenario) -> ZigRunSnapshot {
    resetComputedLayoutState(engine: scenario.engine, workspaceId: scenario.workspaceId)

    var frames: [WindowHandle: CGRect] = [:]
    var hidden: [WindowHandle: HideSide] = [:]
    scenario.engine.calculateLayoutInto(
        frames: &frames,
        hiddenHandles: &hidden,
        state: scenario.state,
        workspaceId: scenario.workspaceId,
        monitorFrame: scenario.monitorFrame,
        screenFrame: scenario.workingArea.viewFrame,
        gaps: scenario.gaps,
        scale: scenario.workingArea.scale,
        workingArea: scenario.workingArea,
        orientation: scenario.orientation,
        animationTime: scenario.animationTime
    )

    let windows = scenario.engine.root(for: scenario.workspaceId)?.allWindows ?? []
    var windowFrames: [WindowHandle: CGRect?] = [:]
    for window in windows {
        windowFrames[window.handle] = window.frame
    }

    let columns = scenario.engine.columns(in: scenario.workspaceId)
    var columnFrames: [NodeId: CGRect?] = [:]
    for column in columns {
        columnFrames[column.id] = column.frame
    }

    return ZigRunSnapshot(
        frames: frames,
        hidden: hidden,
        windowFrames: windowFrames,
        columnFrames: columnFrames
    )
}

private func assertCommonInvariants(
    scenario: ZigScenario,
    snapshot: ZigRunSnapshot
) {
    let windows = scenario.engine.root(for: scenario.workspaceId)?.allWindows ?? []
    #expect(snapshot.frames.count == windows.count)

    for window in windows {
        let handle = window.handle
        #expect(snapshot.frames[handle] != nil)
        #expect(snapshot.windowFrames[handle] != nil)
    }

    for handle in snapshot.hidden.keys {
        #expect(snapshot.frames[handle] != nil)
    }

    for column in scenario.engine.columns(in: scenario.workspaceId) {
        #expect(snapshot.columnFrames[column.id] != nil)
    }
}

private func makeRandomScenario(seed: UInt64) -> ZigScenario {
    var rng = LCG(seed: seed)

    let engine = NiriLayoutEngine(maxWindowsPerColumn: 8)
    engine.renderStyle = .init(tabIndicatorWidth: rng.nextCGFloat(6 ... 24))

    let wsId = WorkspaceDescriptor.ID()
    let root = NiriRoot(workspaceId: wsId)
    engine.roots[wsId] = root

    let orientation: Monitor.Orientation = rng.nextBool() ? .horizontal : .vertical

    let monitorFrame = CGRect(
        x: rng.nextCGFloat(-300 ... 300),
        y: rng.nextCGFloat(-200 ... 200),
        width: rng.nextCGFloat(1280 ... 3440),
        height: rng.nextCGFloat(720 ... 1800)
    )

    let insetX = rng.nextCGFloat(0 ... 40)
    let insetY = rng.nextCGFloat(0 ... 40)
    let insetRight = rng.nextCGFloat(0 ... 40)
    let insetTop = rng.nextCGFloat(0 ... 40)
    let workingFrame = CGRect(
        x: monitorFrame.minX + insetX,
        y: monitorFrame.minY + insetY,
        width: max(200, monitorFrame.width - insetX - insetRight),
        height: max(200, monitorFrame.height - insetY - insetTop)
    )

    let workingArea = WorkingAreaContext(
        workingFrame: workingFrame,
        viewFrame: monitorFrame,
        scale: rng.nextCGFloat(1 ... 2.5)
    )

    let gaps = (
        horizontal: rng.nextCGFloat(4 ... 24),
        vertical: rng.nextCGFloat(4 ... 24)
    )

    let animationTime = CACurrentMediaTime()
    let columnCount = rng.nextInt(1 ... 6)

    for _ in 0 ..< columnCount {
        let column = NiriContainer()
        if rng.nextBool(0.3) {
            column.displayMode = .tabbed
        }

        column.width = .proportion(rng.nextCGFloat(0.2 ... 1.2))
        column.height = .proportion(rng.nextCGFloat(0.2 ... 1.2))

        if orientation == .horizontal {
            column.cachedWidth = rng.nextBool(0.75) ? rng.nextCGFloat(160 ... 900) : 0
            column.cachedHeight = rng.nextCGFloat(100 ... 1000)
        } else {
            column.cachedHeight = rng.nextBool(0.75) ? rng.nextCGFloat(120 ... 900) : 0
            column.cachedWidth = rng.nextCGFloat(100 ... 1000)
        }

        if rng.nextBool(0.35) {
            column.moveAnimation = MoveAnimation(
                animation: SpringAnimation(
                    from: 1,
                    to: 0,
                    startTime: animationTime,
                    config: .balanced,
                    displayRefreshRate: 120
                ),
                fromOffset: rng.nextCGFloat(-120 ... 120)
            )
        }

        root.appendChild(column)

        let windowCount = rng.nextInt(1 ... 4)
        for _ in 0 ..< windowCount {
            let handle = makeTestHandle(pid: pid_t(rng.nextInt(20 ... 5000)))
            let window = NiriWindow(handle: handle)
            engine.handleToNode[handle] = window

            if rng.nextBool(0.15) {
                window.sizingMode = .fullscreen
            }

            if rng.nextBool(0.35) {
                window.height = .fixed(rng.nextCGFloat(80 ... 500))
            } else {
                window.height = .auto(weight: rng.nextCGFloat(0.2 ... 3.0))
            }

            if rng.nextBool(0.35) {
                window.windowWidth = .fixed(rng.nextCGFloat(120 ... 900))
            } else {
                window.windowWidth = .auto(weight: rng.nextCGFloat(0.2 ... 3.0))
            }

            let minWidth = rng.nextCGFloat(50 ... 260)
            let minHeight = rng.nextCGFloat(50 ... 260)
            let hasMaxWidth = rng.nextBool(0.6)
            let hasMaxHeight = rng.nextBool(0.6)
            let maxWidth = hasMaxWidth ? rng.nextCGFloat(minWidth ... 1200) : 0
            let maxHeight = hasMaxHeight ? rng.nextCGFloat(minHeight ... 900) : 0
            let isFixedConstraint = rng.nextBool(0.1)

            window.constraints = WindowSizeConstraints(
                minSize: CGSize(width: minWidth, height: minHeight),
                maxSize: CGSize(width: maxWidth, height: maxHeight),
                isFixed: isFixedConstraint
            )

            if rng.nextBool(0.35) {
                window.moveXAnimation = MoveAnimation(
                    animation: SpringAnimation(
                        from: 1,
                        to: 0,
                        startTime: animationTime,
                        config: .snappy,
                        displayRefreshRate: 120
                    ),
                    fromOffset: rng.nextCGFloat(-80 ... 80)
                )
            }
            if rng.nextBool(0.35) {
                window.moveYAnimation = MoveAnimation(
                    animation: SpringAnimation(
                        from: 1,
                        to: 0,
                        startTime: animationTime,
                        config: .snappy,
                        displayRefreshRate: 120
                    ),
                    fromOffset: rng.nextCGFloat(-80 ... 80)
                )
            }

            column.appendChild(window)
        }

        if column.isTabbed {
            column.setActiveTileIdx(rng.nextInt(0 ... max(0, column.windowNodes.count - 1)))
        }
    }

    var state = ViewportState()
    state.activeColumnIndex = rng.nextInt(0 ... max(0, columnCount - 1))
    state.viewOffsetPixels = .static(rng.nextCGFloat(-600 ... 300))

    return ZigScenario(
        engine: engine,
        workspaceId: wsId,
        state: state,
        monitorFrame: monitorFrame,
        workingArea: workingArea,
        gaps: gaps,
        orientation: orientation,
        animationTime: animationTime
    )
}

private func makeHiddenSidesScenario() -> ZigScenario {
    let engine = NiriLayoutEngine(maxWindowsPerColumn: 8)
    engine.renderStyle = .init(tabIndicatorWidth: 12)

    let wsId = WorkspaceDescriptor.ID()
    let root = NiriRoot(workspaceId: wsId)
    engine.roots[wsId] = root

    for i in 0 ..< 3 {
        let column = NiriContainer()
        column.cachedWidth = 620
        root.appendChild(column)

        let handle = makeTestHandle(pid: pid_t(2000 + i))
        let window = NiriWindow(handle: handle)
        engine.handleToNode[handle] = window
        column.appendChild(window)
    }

    var state = ViewportState()
    state.activeColumnIndex = 1
    state.viewOffsetPixels = .static(0)

    let monitorFrame = CGRect(x: 0, y: 0, width: 500, height: 900)
    let workingArea = WorkingAreaContext(
        workingFrame: CGRect(x: 0, y: 0, width: 500, height: 900),
        viewFrame: monitorFrame,
        scale: 2.0
    )

    return ZigScenario(
        engine: engine,
        workspaceId: wsId,
        state: state,
        monitorFrame: monitorFrame,
        workingArea: workingArea,
        gaps: (horizontal: 16, vertical: 12),
        orientation: .horizontal,
        animationTime: CACurrentMediaTime()
    )
}

private func makeConstraintFullscreenScenario() -> ZigScenario {
    let engine = NiriLayoutEngine(maxWindowsPerColumn: 8)
    engine.renderStyle = .init(tabIndicatorWidth: 12)

    let wsId = WorkspaceDescriptor.ID()
    let root = NiriRoot(workspaceId: wsId)
    engine.roots[wsId] = root

    let column = NiriContainer()
    column.cachedWidth = 900
    root.appendChild(column)

    let fullscreenHandle = makeTestHandle(pid: 7001)
    let fullscreenWindow = NiriWindow(handle: fullscreenHandle)
    fullscreenWindow.sizingMode = .fullscreen
    engine.handleToNode[fullscreenHandle] = fullscreenWindow
    column.appendChild(fullscreenWindow)

    let constrainedHandle = makeTestHandle(pid: 7002)
    let constrainedWindow = NiriWindow(handle: constrainedHandle)
    constrainedWindow.height = .fixed(240)
    constrainedWindow.constraints = WindowSizeConstraints(
        minSize: CGSize(width: 80, height: 200),
        maxSize: CGSize(width: 0, height: 260),
        isFixed: false
    )
    engine.handleToNode[constrainedHandle] = constrainedWindow
    column.appendChild(constrainedWindow)

    var state = ViewportState()
    state.activeColumnIndex = 0
    state.viewOffsetPixels = .static(0)

    let monitorFrame = CGRect(x: 100, y: 120, width: 1440, height: 900)
    let workingFrame = CGRect(x: 120, y: 140, width: 1400, height: 860)
    let workingArea = WorkingAreaContext(
        workingFrame: workingFrame,
        viewFrame: monitorFrame,
        scale: 2.0
    )

    return ZigScenario(
        engine: engine,
        workspaceId: wsId,
        state: state,
        monitorFrame: monitorFrame,
        workingArea: workingArea,
        gaps: (horizontal: 12, vertical: 10),
        orientation: .horizontal,
        animationTime: CACurrentMediaTime()
    )
}

private func makeTabbedOverlayScenario() -> ZigScenario {
    let engine = NiriLayoutEngine(maxWindowsPerColumn: 8)
    engine.renderStyle = .init(tabIndicatorWidth: 12)

    let wsId = WorkspaceDescriptor.ID()
    let root = NiriRoot(workspaceId: wsId)
    engine.roots[wsId] = root

    let monitorFrame = CGRect(x: 120, y: 80, width: 1600, height: 980)
    let workingFrame = CGRect(x: 140, y: 100, width: 1560, height: 940)
    let workingArea = WorkingAreaContext(
        workingFrame: workingFrame,
        viewFrame: monitorFrame,
        scale: 2.0
    )

    let tabbedColumn = NiriContainer()
    tabbedColumn.displayMode = .tabbed
    tabbedColumn.cachedWidth = 520
    root.appendChild(tabbedColumn)

    for i in 0 ..< 3 {
        let handle = makeTestHandle(pid: pid_t(3000 + i))
        let window = NiriWindow(handle: handle)
        window.height = .auto(weight: 1)
        window.windowWidth = .auto(weight: 1)
        engine.handleToNode[handle] = window
        tabbedColumn.appendChild(window)
    }
    tabbedColumn.setActiveTileIdx(1)

    let normalColumn = NiriContainer()
    normalColumn.cachedWidth = 520
    root.appendChild(normalColumn)
    let normalHandle = makeTestHandle(pid: 4001)
    let normalWindow = NiriWindow(handle: normalHandle)
    engine.handleToNode[normalHandle] = normalWindow
    normalColumn.appendChild(normalWindow)

    var state = ViewportState()
    state.activeColumnIndex = 0
    state.viewOffsetPixels = .static(0)

    return ZigScenario(
        engine: engine,
        workspaceId: wsId,
        state: state,
        monitorFrame: monitorFrame,
        workingArea: workingArea,
        gaps: (horizontal: 16, vertical: 12),
        orientation: .horizontal,
        animationTime: CACurrentMediaTime()
    )
}

@Suite struct NiriZigLayoutParityTests {
    @MainActor
    @Test func deterministicFixtureSmoke() {
        let scenario = makeRandomScenario(seed: 0xA11CE_BAAD_F00D)
        let snapshot = runZigLayout(scenario)
        assertCommonInvariants(scenario: scenario, snapshot: snapshot)
    }

    @MainActor
    @Test func hiddenSideClassificationSmoke() {
        let scenario = makeHiddenSidesScenario()
        let snapshot = runZigLayout(scenario)
        assertCommonInvariants(scenario: scenario, snapshot: snapshot)

        let sides = Set(snapshot.hidden.values)
        #expect(sides.contains(.left))
        #expect(sides.contains(.right))
    }

    @MainActor
    @Test func constraintAndFullscreenSmoke() {
        let scenario = makeConstraintFullscreenScenario()
        let snapshot = runZigLayout(scenario)
        assertCommonInvariants(scenario: scenario, snapshot: snapshot)

        let windows = scenario.engine.root(for: scenario.workspaceId)?.allWindows ?? []
        guard let fullscreenWindow = windows.first(where: { $0.sizingMode == .fullscreen }) else {
            #expect(Bool(false))
            return
        }

        guard let frame = fullscreenWindow.frame else {
            #expect(Bool(false))
            return
        }

        let expected = scenario.workingArea.workingFrame.roundedToPhysicalPixels(scale: scenario.workingArea.scale)
        #expect(approxRectEqual(frame, expected))
    }

    @MainActor
    @Test func tabbedVisibleColumnFrameSetForOverlay() {
        let scenario = makeTabbedOverlayScenario()
        let snapshot = runZigLayout(scenario)
        assertCommonInvariants(scenario: scenario, snapshot: snapshot)

        let tabbedColumns = scenario.engine.columns(in: scenario.workspaceId).filter(\.isTabbed)
        #expect(!tabbedColumns.isEmpty)
        guard let tabbedColumn = tabbedColumns.first else { return }

        #expect(tabbedColumn.frame != nil)
        if let frame = tabbedColumn.frame {
            #expect(frame.intersects(scenario.workingArea.viewFrame))
        }
    }

    @MainActor
    @Test func randomizedSmoke1000Scenarios() {
        for i in 0 ..< 1000 {
            let scenario = makeRandomScenario(seed: UInt64(i + 1) &* 0x9E3779B97F4A7C15)
            let snapshot = runZigLayout(scenario)
            assertCommonInvariants(scenario: scenario, snapshot: snapshot)
        }
    }

    @MainActor
    @Test func benchmarkHarnessP95() {
        let scenario = makeRandomScenario(seed: 0xDEADBEEF)

        for _ in 0 ..< 30 {
            _ = runZigLayout(scenario)
        }

        var samples: [Double] = []
        samples.reserveCapacity(250)

        for _ in 0 ..< 250 {
            let t0 = CACurrentMediaTime()
            _ = runZigLayout(scenario)
            samples.append(CACurrentMediaTime() - t0)
        }

        let p95 = percentile(samples, 0.95)
        print(String(format: "Niri layout kernel benchmark p95 (zig-only): %.6f", p95))

        #expect(p95 > 0)
        #expect(p95 < 0.005)
    }
}
