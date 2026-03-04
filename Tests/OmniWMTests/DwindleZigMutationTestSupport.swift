import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private let dwindleMutationAbiOK: Int32 = 0

struct DwindleMutationSeedExport {
    let nodes: [DwindleZigKernel.SeedNode]
    let state: DwindleZigKernel.SeedState
}

struct DwindleMutationLCG {
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

func dwindleMutationApproxRectEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.5) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= epsilon
        && abs(lhs.origin.y - rhs.origin.y) <= epsilon
        && abs(lhs.width - rhs.width) <= epsilon
        && abs(lhs.height - rhs.height) <= epsilon
}

func dwindleMutationOrientationCode(_ orientation: DwindleOrientation) -> DwindleZigKernel.Orientation {
    switch orientation {
    case .horizontal:
        return .horizontal
    case .vertical:
        return .vertical
    }
}

func dwindleMutationExportSeed(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> DwindleMutationSeedExport? {
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
            let hasWindow = handle != nil
            return DwindleZigKernel.SeedNode(
                nodeId: node.id,
                parentIndex: parentIndex,
                firstChildIndex: firstChildIndex,
                secondChildIndex: secondChildIndex,
                kind: .leaf,
                orientation: .horizontal,
                ratio: 1.0,
                windowId: handle?.id,
                isFullscreen: hasWindow ? fullscreen : false
            )

        case let .split(orientation, ratio):
            return DwindleZigKernel.SeedNode(
                nodeId: node.id,
                parentIndex: parentIndex,
                firstChildIndex: firstChildIndex,
                secondChildIndex: secondChildIndex,
                kind: .split,
                orientation: dwindleMutationOrientationCode(orientation),
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

    return DwindleMutationSeedExport(nodes: seedNodes, state: state)
}

@discardableResult
func dwindleMutationSeedContext(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID,
    context: DwindleZigKernel.LayoutContext
) -> Int32 {
    guard let export = dwindleMutationExportSeed(engine: engine, workspaceId: workspaceId) else {
        return -1
    }
    return DwindleZigKernel.seedState(context: context, nodes: export.nodes, state: export.state)
}

func dwindleMutationKernelConstraints(
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

func dwindleMutationSelectedWindowId(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> UUID? {
    engine.selectedNode(in: workspaceId)?.windowHandle?.id
}

@discardableResult
func dwindleMutationNormalizeSelectionReference(
    engine: DwindleLayoutEngine,
    workspaceId: WorkspaceDescriptor.ID
) -> Bool {
    if let selected = engine.selectedNode(in: workspaceId),
       selected.isLeaf,
       selected.windowHandle != nil {
        return false
    }

    guard let root = engine.root(for: workspaceId) else {
        engine.setSelectedNode(nil, in: workspaceId)
        return true
    }

    if let leafWithWindow = root.collectAllLeaves().first(where: { $0.windowHandle != nil }) {
        let changed = engine.selectedNode(in: workspaceId)?.id != leafWithWindow.id
        engine.setSelectedNode(leafWithWindow, in: workspaceId)
        return changed
    }

    let fallback = root.descendToFirstLeaf()
    let changed = engine.selectedNode(in: workspaceId)?.id != fallback.id
    engine.setSelectedNode(fallback, in: workspaceId)
    return changed
}

func dwindleMutationMakeHandle(id: UUID, pid: pid_t) -> WindowHandle {
    WindowHandle(id: id, pid: pid, axElement: AXUIElementCreateSystemWide())
}

func dwindleMutationAssertLayoutAndNeighborParity(
    engine: DwindleLayoutEngine,
    context: DwindleZigKernel.LayoutContext,
    workspaceId: WorkspaceDescriptor.ID,
    screen: CGRect
) {
    let swiftFrames = engine.calculateLayout(for: workspaceId, screen: screen)
    let handles = engine.root(for: workspaceId)?.collectAllWindows() ?? []

    let kernelRequest = DwindleZigKernel.LayoutRequest(screen: screen, settings: engine.settings)
    let kernelConstraints = dwindleMutationKernelConstraints(engine: engine, handles: handles)
    let layoutResult = DwindleZigKernel.calculateLayout(
        context: context,
        request: kernelRequest,
        constraints: kernelConstraints
    )

    #expect(layoutResult.rc == dwindleMutationAbiOK)
    guard layoutResult.rc == dwindleMutationAbiOK else { return }

    #expect(layoutResult.frameCount == swiftFrames.count)
    #expect(layoutResult.framesByWindowId.count == swiftFrames.count)

    for handle in handles {
        guard let swiftFrame = swiftFrames[handle],
              let zigFrame = layoutResult.framesByWindowId[handle.id]
        else {
            #expect(Bool(false))
            continue
        }
        #expect(dwindleMutationApproxRectEqual(swiftFrame, zigFrame))
    }

    let directions: [Direction] = [.left, .right, .up, .down]
    for handle in handles {
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
            #expect(neighborResult.rc == dwindleMutationAbiOK)
            guard neighborResult.rc == dwindleMutationAbiOK else { continue }
            #expect(neighborResult.neighborWindowId == expectedNeighborId)
        }
    }
}
