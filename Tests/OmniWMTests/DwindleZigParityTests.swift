import Foundation
import Testing

@testable import OmniWM

private let dwindleAbiOK: Int32 = 0

private struct DwindleParityLCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
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

private struct DwindleSeedExport {
    let nodes: [DwindleZigKernel.SeedNode]
    let state: DwindleZigKernel.SeedState
    let handles: [WindowHandle]
}

private func approxRectEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.5) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= epsilon
        && abs(lhs.origin.y - rhs.origin.y) <= epsilon
        && abs(lhs.width - rhs.width) <= epsilon
        && abs(lhs.height - rhs.height) <= epsilon
}

private func orientationCode(_ orientation: DwindleOrientation) -> DwindleZigKernel.Orientation {
    switch orientation {
    case .horizontal:
        return .horizontal
    case .vertical:
        return .vertical
    }
}

private func randomDirection(_ rng: inout DwindleParityLCG) -> Direction {
    switch rng.nextInt(0 ... 3) {
    case 0:
        return .left
    case 1:
        return .right
    case 2:
        return .up
    default:
        return .down
    }
}

private func makeSeedExport(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> DwindleSeedExport? {
    guard let root = engine.root(for: workspaceId) else { return nil }

    var orderedNodes: [DwindleNode] = []
    orderedNodes.reserveCapacity(64)

    func collect(_ node: DwindleNode) {
        orderedNodes.append(node)
        for child in node.children {
            collect(child)
        }
    }

    collect(root)

    var indexById: [DwindleNodeId: Int] = [:]
    indexById.reserveCapacity(orderedNodes.count)
    for (idx, node) in orderedNodes.enumerated() {
        indexById[node.id] = idx
    }

    let seedNodes: [DwindleZigKernel.SeedNode] = orderedNodes.map { node in
        let parentIndex = node.parent.flatMap { indexById[$0.id] } ?? -1
        let firstChildIndex = node.children.indices.contains(0)
            ? (indexById[node.children[0].id] ?? -1)
            : -1
        let secondChildIndex = node.children.indices.contains(1)
            ? (indexById[node.children[1].id] ?? -1)
            : -1

        switch node.kind {
        case let .leaf(handle, fullscreen):
            return DwindleZigKernel.SeedNode(
                nodeId: node.id,
                parentIndex: parentIndex,
                firstChildIndex: firstChildIndex,
                secondChildIndex: secondChildIndex,
                kind: .leaf,
                orientation: .horizontal,
                ratio: 1.0,
                windowId: handle?.id,
                isFullscreen: fullscreen
            )

        case let .split(orientation, ratio):
            return DwindleZigKernel.SeedNode(
                nodeId: node.id,
                parentIndex: parentIndex,
                firstChildIndex: firstChildIndex,
                secondChildIndex: secondChildIndex,
                kind: .split,
                orientation: orientationCode(orientation),
                ratio: ratio,
                windowId: nil,
                isFullscreen: false
            )
        }
    }

    let selectedIndex = engine.selectedNode(in: workspaceId).flatMap { indexById[$0.id] } ?? -1
    let rootIndex = indexById[root.id] ?? -1

    let state = DwindleZigKernel.SeedState(
        rootNodeIndex: rootIndex,
        selectedNodeIndex: selectedIndex,
        preselection: engine.getPreselection(in: workspaceId)
    )

    return DwindleSeedExport(
        nodes: seedNodes,
        state: state,
        handles: root.collectAllWindows()
    )
}

private func makeKernelConstraints(
    engine: DwindleLayoutEngine,
    handles: [WindowHandle]
) -> [DwindleZigKernel.WindowConstraint] {
    handles.map { handle in
        DwindleZigKernel.WindowConstraint(
            windowId: handle.id,
            constraints: engine.constraints(for: handle)
        )
    }
}

private func runScenarioParity(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID,
    screen: CGRect
) {
    guard let export = makeSeedExport(engine: engine, workspaceId: workspaceId) else {
        #expect(Bool(false))
        return
    }

    let swiftFrames = engine.calculateLayout(for: workspaceId, screen: screen)

    guard let context = DwindleZigKernel.LayoutContext() else {
        #expect(Bool(false))
        return
    }

    let seedRC = DwindleZigKernel.seedState(
        context: context,
        nodes: export.nodes,
        state: export.state
    )
    #expect(seedRC == dwindleAbiOK)
    guard seedRC == dwindleAbiOK else { return }

    let kernelRequest = DwindleZigKernel.LayoutRequest(screen: screen, settings: engine.settings)
    let kernelConstraints = makeKernelConstraints(engine: engine, handles: export.handles)
    let layoutResult = DwindleZigKernel.calculateLayout(
        context: context,
        request: kernelRequest,
        constraints: kernelConstraints
    )

    #expect(layoutResult.rc == dwindleAbiOK)
    guard layoutResult.rc == dwindleAbiOK else { return }

    #expect(layoutResult.frameCount == swiftFrames.count)
    #expect(layoutResult.framesByWindowId.count == swiftFrames.count)

    for handle in export.handles {
        guard let swiftFrame = swiftFrames[handle],
              let zigFrame = layoutResult.framesByWindowId[handle.id]
        else {
            #expect(Bool(false))
            continue
        }

        #expect(approxRectEqual(swiftFrame, zigFrame))
    }

    let directions: [Direction] = [.left, .right, .up, .down]
    for handle in export.handles {
        for direction in directions {
            let expectedNeighborId = engine.findGeometricNeighbor(
                from: handle,
                direction: direction,
                in: workspaceId
            )?.id

            let neighborResult = DwindleZigKernel.findNeighbor(
                context: context,
                windowId: handle.id,
                direction: direction,
                innerGap: engine.settings.innerGap
            )

            #expect(neighborResult.rc == dwindleAbiOK)
            guard neighborResult.rc == dwindleAbiOK else { continue }
            #expect(neighborResult.neighborWindowId == expectedNeighborId)
        }
    }
}

private func makeScenario(
    seed: UInt64,
    windowCount: Int
) -> (engine: DwindleLayoutEngine, workspaceId: WorkspaceDescriptor.ID, screen: CGRect) {
    var rng = DwindleParityLCG(seed: seed)

    let engine = DwindleLayoutEngine(backend: .legacyDeterministic)
    engine.settings.smartSplit = rng.nextBool(0.7)
    engine.settings.defaultSplitRatio = rng.nextCGFloat(0.3 ... 1.7)
    engine.settings.splitWidthMultiplier = rng.nextCGFloat(0.7 ... 1.8)
    engine.settings.singleWindowAspectRatio = CGSize(
        width: rng.nextCGFloat(3 ... 21),
        height: rng.nextCGFloat(2 ... 12)
    )
    engine.settings.singleWindowAspectRatioTolerance = rng.nextCGFloat(0.01 ... 0.2)
    engine.settings.innerGap = rng.nextCGFloat(0 ... 24)
    engine.settings.outerGapTop = rng.nextCGFloat(0 ... 18)
    engine.settings.outerGapBottom = rng.nextCGFloat(0 ... 18)
    engine.settings.outerGapLeft = rng.nextCGFloat(0 ... 18)
    engine.settings.outerGapRight = rng.nextCGFloat(0 ... 18)

    let workspaceId = WorkspaceDescriptor.ID()
    let screen = CGRect(
        x: rng.nextCGFloat(-200 ... 200),
        y: rng.nextCGFloat(-120 ... 120),
        width: rng.nextCGFloat(900 ... 2800),
        height: rng.nextCGFloat(600 ... 1600)
    )

    var activeFrame: CGRect?

    for idx in 0 ..< windowCount {
        let handle = makeTestHandle(pid: pid_t(90_000 + idx))
        _ = engine.addWindow(handle: handle, to: workspaceId, activeWindowFrame: activeFrame)

        let minWidth = rng.nextCGFloat(1 ... 260)
        let minHeight = rng.nextCGFloat(1 ... 260)
        let hasMaxWidth = rng.nextBool(0.65)
        let hasMaxHeight = rng.nextBool(0.65)
        let maxWidth = hasMaxWidth ? rng.nextCGFloat(minWidth ... minWidth + 1200) : 0
        let maxHeight = hasMaxHeight ? rng.nextCGFloat(minHeight ... minHeight + 900) : 0

        let constraints = WindowSizeConstraints(
            minSize: CGSize(width: minWidth, height: minHeight),
            maxSize: CGSize(width: maxWidth, height: maxHeight),
            isFixed: rng.nextBool(0.1)
        )
        engine.updateWindowConstraints(for: handle, constraints: constraints)

        if idx > 0 {
            if rng.nextBool(0.35) {
                engine.toggleOrientation(in: workspaceId)
            }
            if rng.nextBool(0.6) {
                engine.cycleSplitRatio(forward: rng.nextBool(), in: workspaceId)
            }
            if rng.nextBool(0.35) {
                engine.resizeSelected(
                    by: rng.nextCGFloat(0.05 ... 0.25),
                    direction: randomDirection(&rng),
                    in: workspaceId
                )
            }
            if rng.nextBool(0.2) {
                engine.swapSplit(in: workspaceId)
            }
            if rng.nextBool(0.15) {
                _ = engine.toggleFullscreen(in: workspaceId)
            }
        }

        let frames = engine.calculateLayout(for: workspaceId, screen: screen)
        activeFrame = frames[handle]
    }

    return (engine, workspaceId, screen)
}

@Suite struct DwindleZigParityTests {
    @MainActor
    @Test func parityAcrossOneToEightWindows() {
        for count in 1 ... 8 {
            let scenario = makeScenario(
                seed: UInt64(0xD00D_F00D + count * 17),
                windowCount: count
            )
            runScenarioParity(
                engine: scenario.engine,
                workspaceId: scenario.workspaceId,
                screen: scenario.screen
            )
        }
    }

    @MainActor
    @Test func constrainedSplitAndAspectParity() {
        let scenario = makeScenario(seed: 0xABCD_1234, windowCount: 6)
        runScenarioParity(
            engine: scenario.engine,
            workspaceId: scenario.workspaceId,
            screen: scenario.screen
        )
    }

    @MainActor
    @Test func randomizedParitySweep() {
        for i in 0 ..< 100 {
            let count = (i % 9) + 1
            let scenario = makeScenario(
                seed: UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15,
                windowCount: count
            )
            runScenarioParity(
                engine: scenario.engine,
                workspaceId: scenario.workspaceId,
                screen: scenario.screen
            )
        }
    }
}
