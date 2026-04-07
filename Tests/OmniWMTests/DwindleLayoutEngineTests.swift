import ApplicationServices
import CoreGraphics
import Foundation
@testable import OmniWM
import QuartzCore
import Testing

private func hasDwindleAnimationDirective(
    _ directives: [AnimationDirective],
    workspaceId: WorkspaceDescriptor.ID,
    monitorId: Monitor.ID
) -> Bool {
    directives.contains { directive in
        if case let .startDwindleAnimation(candidateWorkspaceId, candidateMonitorId) = directive {
            return candidateWorkspaceId == workspaceId && candidateMonitorId == monitorId
        }
        return false
    }
}

private func layoutTokenSet(_ changes: [LayoutFrameChange]) -> Set<WindowToken> {
    Set(changes.map(\.token))
}

private func applyResolvedDwindleSettingsForEngineTests(
    _ settings: ResolvedDwindleSettings,
    to engine: DwindleLayoutEngine
) {
    engine.settings.smartSplit = settings.smartSplit
    engine.settings.defaultSplitRatio = settings.defaultSplitRatio
    engine.settings.splitWidthMultiplier = settings.splitWidthMultiplier
    engine.settings.singleWindowAspectRatio = settings.singleWindowAspectRatio.size
    engine.settings.innerGap = settings.innerGap
    engine.settings.outerGapTop = settings.outerGapTop
    engine.settings.outerGapBottom = settings.outerGapBottom
    engine.settings.outerGapLeft = settings.outerGapLeft
    engine.settings.outerGapRight = settings.outerGapRight
}

private func warmReferenceDwindleImportForEngineTests(
    tokens: [WindowToken],
    screen: CGRect,
    settings: ResolvedDwindleSettings
) -> (order: [WindowToken], frames: [WindowToken: CGRect]) {
    let engine = DwindleLayoutEngine()
    let workspaceId = UUID()
    applyResolvedDwindleSettingsForEngineTests(settings, to: engine)

    var activeFrame: CGRect?
    for token in tokens {
        _ = engine.addWindow(token: token, to: workspaceId, activeWindowFrame: activeFrame)
        let frames = engine.calculateLayout(for: workspaceId, screen: screen)
        activeFrame = frames[token]
    }

    return (
        order: engine.root(for: workspaceId)?.collectAllWindows() ?? [],
        frames: engine.currentFrames(in: workspaceId)
    )
}

private func makeDwindleTestToken(_ windowId: Int, pid: pid_t = 999) -> WindowToken {
    WindowToken(pid: pid, windowId: windowId)
}

private func makeDwindleLeaf(
    _ token: WindowToken? = nil,
    fullscreen: Bool = false
) -> DwindleNode {
    DwindleNode(kind: .leaf(handle: token, fullscreen: fullscreen))
}

@MainActor
private func configureWorkspaceAsDwindle(
    on controller: WMController,
    workspaceId: WorkspaceDescriptor.ID
) {
    configureWorkspacesAsDwindle(on: controller, workspaceIds: [workspaceId])
}

@MainActor
private func configureWorkspacesAsDwindle(
    on controller: WMController,
    workspaceIds: [WorkspaceDescriptor.ID]
) {
    let targetNames = Set(
        workspaceIds.compactMap { workspaceId in
            controller.workspaceManager.descriptor(for: workspaceId)?.name
        }
    )
    guard !targetNames.isEmpty else { return }

    var configurations = controller.settings.workspaceConfigurations.map { configuration in
        targetNames.contains(configuration.name)
            ? configuration.with(layoutType: .dwindle)
            : configuration
    }
    let configuredNames = Set(configurations.map(\.name))
    let missingConfigurations = workspaceIds.compactMap { workspaceId -> WorkspaceConfiguration? in
        guard let workspace = controller.workspaceManager.descriptor(for: workspaceId),
              !configuredNames.contains(workspace.name)
        else {
            return nil
        }
        return WorkspaceConfiguration(name: workspace.name, layoutType: .dwindle)
    }

    configurations.append(contentsOf: missingConfigurations)
    controller.settings.workspaceConfigurations = configurations
}

struct DwindleLayoutEngineTests {
    @Test func `empty workspace returns no frames`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        #expect(engine.calculateLayout(for: wsId, screen: screen).isEmpty)

        let placeholderRoot = engine.ensureRoot(for: wsId)
        #expect(engine.calculateLayout(for: wsId, screen: screen).isEmpty)
        #expect(placeholderRoot.cachedFrame == nil)
    }

    @Test func `single window applies outer gaps before aspect ratio`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let token = makeDwindleTestToken(1001)
        let root = engine.ensureRoot(for: wsId)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

        root.kind = .leaf(handle: token, fullscreen: false)
        engine.settings.singleWindowAspectRatio = CGSize(width: 4, height: 3)
        engine.settings.singleWindowAspectRatioTolerance = 0.1
        engine.settings.outerGapTop = 50
        engine.settings.outerGapBottom = 50
        engine.settings.outerGapLeft = 100
        engine.settings.outerGapRight = 100

        let frames = engine.calculateLayout(for: wsId, screen: screen)
        let expected = CGRect(x: 200, y: 50, width: 1200, height: 900)

        #expect(frames[token] == expected)
        #expect(root.cachedFrame == expected)
    }

    @Test func `single window tolerance keeps full tiling area when aspect is close enough`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let token = makeDwindleTestToken(1002)
        let root = engine.ensureRoot(for: wsId)
        let screen = CGRect(x: 0, y: 0, width: 1340, height: 1000)

        root.kind = .leaf(handle: token, fullscreen: false)
        engine.settings.singleWindowAspectRatio = CGSize(width: 4, height: 3)
        engine.settings.singleWindowAspectRatioTolerance = 0.01

        let frames = engine.calculateLayout(for: wsId, screen: screen)

        #expect(frames[token] == screen)
        #expect(root.cachedFrame == screen)
    }

    @Test func `single window fill mode uses entire tiling area`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let token = makeDwindleTestToken(1017)
        let root = engine.ensureRoot(for: wsId)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

        root.kind = .leaf(handle: token, fullscreen: false)
        engine.settings.singleWindowAspectRatio = DwindleSingleWindowAspectRatio.fill.size
        engine.settings.outerGapTop = 10
        engine.settings.outerGapBottom = 30
        engine.settings.outerGapLeft = 20
        engine.settings.outerGapRight = 40

        let frames = engine.calculateLayout(for: wsId, screen: screen)
        let expected = CGRect(x: 20, y: 30, width: 1540, height: 960)

        #expect(frames[token] == expected)
        #expect(root.cachedFrame == expected)
    }

    @Test func `single fullscreen window uses full screen rect`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let token = makeDwindleTestToken(1003)
        let root = engine.ensureRoot(for: wsId)
        let screen = CGRect(x: 10, y: 20, width: 1280, height: 720)

        root.kind = .leaf(handle: token, fullscreen: true)
        engine.settings.outerGapTop = 30
        engine.settings.outerGapBottom = 40
        engine.settings.outerGapLeft = 50
        engine.settings.outerGapRight = 60

        let frames = engine.calculateLayout(for: wsId, screen: screen)

        #expect(frames[token] == screen)
        #expect(root.cachedFrame == screen)
    }

    @Test func `fullscreen leaf in multi window layout uses tiling area`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let coveredToken = makeDwindleTestToken(1018)
        let fullscreenToken = makeDwindleTestToken(1019)
        let coveredLeaf = makeDwindleLeaf(coveredToken)
        let fullscreenLeaf = makeDwindleLeaf(fullscreenToken, fullscreen: true)
        let root = engine.ensureRoot(for: wsId)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let tilingArea = CGRect(x: 30, y: 20, width: 930, height: 470)

        root.kind = .split(orientation: .horizontal, ratio: 1.0)
        root.replaceChildren(first: coveredLeaf, second: fullscreenLeaf)
        engine.settings.innerGap = 10
        engine.settings.outerGapTop = 10
        engine.settings.outerGapBottom = 20
        engine.settings.outerGapLeft = 30
        engine.settings.outerGapRight = 40

        let frames = engine.calculateLayout(for: wsId, screen: screen)

        #expect(root.cachedFrame == tilingArea)
        #expect(coveredLeaf.cachedFrame == CGRect(x: 60, y: 40, width: 430, height: 440))
        #expect(fullscreenLeaf.cachedFrame == tilingArea)
        #expect(frames[coveredToken] == coveredLeaf.cachedFrame)
        #expect(frames[fullscreenToken] == fullscreenLeaf.cachedFrame)
    }

    @Test func `horizontal split applies inner gaps and caches split frames`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let leftToken = makeDwindleTestToken(1004)
        let rightToken = makeDwindleTestToken(1005)
        let leftLeaf = makeDwindleLeaf(leftToken)
        let rightLeaf = makeDwindleLeaf(rightToken)
        let root = engine.ensureRoot(for: wsId)

        root.kind = .split(orientation: .horizontal, ratio: 1.0)
        root.replaceChildren(first: leftLeaf, second: rightLeaf)
        engine.settings.innerGap = 10

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1000, height: 500)
        )

        #expect(root.cachedFrame == CGRect(x: 0, y: 0, width: 1000, height: 500))
        #expect(leftLeaf.cachedFrame == CGRect(x: 0, y: 0, width: 495, height: 500))
        #expect(rightLeaf.cachedFrame == CGRect(x: 505, y: 0, width: 495, height: 500))
        #expect(frames[leftToken] == leftLeaf.cachedFrame)
        #expect(frames[rightToken] == rightLeaf.cachedFrame)
    }

    @Test func `vertical split applies inner gaps`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let bottomToken = makeDwindleTestToken(1006)
        let topToken = makeDwindleTestToken(1007)
        let bottomLeaf = makeDwindleLeaf(bottomToken)
        let topLeaf = makeDwindleLeaf(topToken)
        let root = engine.ensureRoot(for: wsId)

        root.kind = .split(orientation: .vertical, ratio: 1.0)
        root.replaceChildren(first: bottomLeaf, second: topLeaf)
        engine.settings.innerGap = 10

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )

        #expect(bottomLeaf.cachedFrame == CGRect(x: 0, y: 0, width: 1000, height: 395))
        #expect(topLeaf.cachedFrame == CGRect(x: 0, y: 405, width: 1000, height: 395))
        #expect(frames[bottomToken] == bottomLeaf.cachedFrame)
        #expect(frames[topToken] == topLeaf.cachedFrame)
    }

    @Test func `split ratio clamps using aggregated subtree min sizes`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let firstToken = makeDwindleTestToken(1008)
        let secondToken = makeDwindleTestToken(1009)
        let thirdToken = makeDwindleTestToken(1010)
        let firstLeaf = makeDwindleLeaf(firstToken)
        let secondLeaf = makeDwindleLeaf(secondToken)
        let thirdLeaf = makeDwindleLeaf(thirdToken)
        let leftSubtree = DwindleNode(kind: .split(orientation: .vertical, ratio: 1.0))
        let root = engine.ensureRoot(for: wsId)

        leftSubtree.replaceChildren(first: firstLeaf, second: secondLeaf)
        root.kind = .split(orientation: .horizontal, ratio: 0.3)
        root.replaceChildren(first: leftSubtree, second: thirdLeaf)
        engine.settings.innerGap = 0

        engine.updateWindowConstraints(
            for: firstToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 300, height: 200), maxSize: .zero, isFixed: false)
        )
        engine.updateWindowConstraints(
            for: secondToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 100, height: 400), maxSize: .zero, isFixed: false)
        )
        engine.updateWindowConstraints(
            for: thirdToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 200, height: 100), maxSize: .zero, isFixed: false)
        )

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 700, height: 800)
        )

        #expect(leftSubtree.cachedFrame == CGRect(x: 0, y: 0, width: 300, height: 800))
        #expect(frames[firstToken] == CGRect(x: 0, y: 0, width: 300, height: 400))
        #expect(frames[secondToken] == CGRect(x: 0, y: 400, width: 300, height: 400))
        #expect(frames[thirdToken] == CGRect(x: 300, y: 0, width: 400, height: 800))
    }

    @Test func `split ratio uses min size fraction when total minimum exceeds available space`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let firstToken = makeDwindleTestToken(1011)
        let secondToken = makeDwindleTestToken(1012)
        let firstLeaf = makeDwindleLeaf(firstToken)
        let secondLeaf = makeDwindleLeaf(secondToken)
        let root = engine.ensureRoot(for: wsId)

        root.kind = .split(orientation: .horizontal, ratio: 1.0)
        root.replaceChildren(first: firstLeaf, second: secondLeaf)
        engine.settings.innerGap = 0
        engine.updateWindowConstraints(
            for: firstToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 500, height: 1), maxSize: .zero, isFixed: false)
        )
        engine.updateWindowConstraints(
            for: secondToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 300, height: 1), maxSize: .zero, isFixed: false)
        )

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 600, height: 200)
        )

        #expect(frames[firstToken] == CGRect(x: 0, y: 0, width: 375, height: 200))
        #expect(frames[secondToken] == CGRect(x: 375, y: 0, width: 225, height: 200))
    }

    @Test func `placeholder leaf uses fallback min size without producing output frame`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let firstToken = makeDwindleTestToken(1013)
        let secondToken = makeDwindleTestToken(1014)
        let placeholder = makeDwindleLeaf(nil)
        let firstLeaf = makeDwindleLeaf(firstToken)
        let secondLeaf = makeDwindleLeaf(secondToken)
        let rightSubtree = DwindleNode(kind: .split(orientation: .horizontal, ratio: 1.0))
        let root = engine.ensureRoot(for: wsId)

        rightSubtree.replaceChildren(first: firstLeaf, second: secondLeaf)
        root.kind = .split(orientation: .vertical, ratio: 1.0)
        root.replaceChildren(first: placeholder, second: rightSubtree)
        engine.settings.innerGap = 0

        engine.updateWindowConstraints(
            for: firstToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 100, height: 400), maxSize: .zero, isFixed: false)
        )
        engine.updateWindowConstraints(
            for: secondToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 100, height: 400), maxSize: .zero, isFixed: false)
        )

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 400, height: 200)
        )

        #expect(frames.count == 2)
        #expect(placeholder.cachedFrame == nil)
        #expect(abs((rightSubtree.cachedFrame?.height ?? 0) - (200 * (CGFloat(400) / 401))) < 0.001)
        let expectedY = CGFloat(200) / 401
        let expectedHeight = 200 * (CGFloat(400) / 401)
        #expect(abs((frames[firstToken]?.minY ?? 0) - expectedY) < 0.001)
        #expect(abs((frames[firstToken]?.height ?? 0) - expectedHeight) < 0.001)
        #expect(abs((frames[secondToken]?.minY ?? 0) - expectedY) < 0.001)
        #expect(abs((frames[secondToken]?.height ?? 0) - expectedHeight) < 0.001)
        #expect(frames[firstToken]?.width == 200)
        #expect(frames[secondToken]?.width == 200)
    }

    @Test func `missing child uses fallback min size during split clamping`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let firstToken = makeDwindleTestToken(1015)
        let secondToken = makeDwindleTestToken(1016)
        let firstLeaf = makeDwindleLeaf(firstToken)
        let secondLeaf = makeDwindleLeaf(secondToken)
        let firstSubtree = DwindleNode(kind: .split(orientation: .horizontal, ratio: 1.0))
        let root = engine.ensureRoot(for: wsId)

        firstSubtree.replaceChildren(first: firstLeaf, second: secondLeaf)
        root.kind = .split(orientation: .vertical, ratio: 1.0)
        root.children = [firstSubtree]
        firstSubtree.parent = root
        engine.settings.innerGap = 0

        engine.updateWindowConstraints(
            for: firstToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 100, height: 500), maxSize: .zero, isFixed: false)
        )
        engine.updateWindowConstraints(
            for: secondToken,
            constraints: WindowSizeConstraints(minSize: CGSize(width: 100, height: 500), maxSize: .zero, isFixed: false)
        )

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 600, height: 300)
        )

        #expect(root.cachedFrame == CGRect(x: 0, y: 0, width: 600, height: 300))
        #expect(abs((firstSubtree.cachedFrame?.height ?? 0) - (300 * (CGFloat(500) / 501))) < 0.001)
        #expect(frames[firstToken] == CGRect(x: 0, y: 0, width: 300, height: 300 * (CGFloat(500) / 501)))
        #expect(frames[secondToken] == CGRect(x: 300, y: 0, width: 300, height: 300 * (CGFloat(500) / 501)))
    }

    @Test func `sync windows keeps stable node for reobserved token`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()

        let original = makeTestHandle(pid: 31)
        let refreshed = WindowHandle(
            id: original.id,
            pid: original.pid,
            axElement: AXUIElementCreateSystemWide()
        )

        _ = engine.syncWindows([original], in: wsId, focusedHandle: original)
        let originalNodeId = engine.findNode(for: original.id)?.id

        _ = engine.syncWindows([refreshed], in: wsId, focusedHandle: refreshed)

        #expect(engine.windowCount(in: wsId) == 1)
        #expect(engine.findNode(for: refreshed.id)?.id == originalNodeId)
    }

    @Test func `rekey window keeps leaf stable across sync`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()

        let handle1 = makeTestHandle(pid: 73)
        let handle2 = makeTestHandle(pid: 74)

        _ = engine.syncWindows([handle1, handle2], in: wsId, focusedHandle: handle1)
        let originalNodeId = engine.findNode(for: handle2.id)?.id
        let replacementToken = WindowToken(pid: handle2.pid, windowId: handle2.windowId + 1000)

        #expect(engine.rekeyWindow(from: handle2.id, to: replacementToken, in: wsId))

        let removed = engine.syncWindows([handle1.id, replacementToken], in: wsId, focusedToken: handle1.id)

        #expect(removed.isEmpty)
        #expect(engine.windowCount(in: wsId) == 2)
        #expect(engine.findNode(for: handle2.id) == nil)
        #expect(engine.findNode(for: replacementToken)?.id == originalNodeId)
    }

    @Test func `layout and frame caches use stable tokens`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let handle1 = makeTestHandle(pid: 41)
        let handle2 = makeTestHandle(pid: 42)

        _ = engine.syncWindows([handle1, handle2], in: wsId, focusedHandle: handle1)

        let baseFrames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )
        #expect(Set(baseFrames.keys) == Set([handle1.id, handle2.id]))

        let currentFrames = engine.currentFrames(in: wsId)
        #expect(Set(currentFrames.keys) == Set([handle1.id, handle2.id]))

        engine.removeWindow(token: handle2.id, from: wsId)

        let updatedFrames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )
        #expect(Set(updatedFrames.keys) == Set([handle1.id]))
        #expect(engine.findNode(for: handle2.id) == nil)
    }

    @Test func `sync windows preserves caller order for fresh layouts`() {
        let forwardEngine = DwindleLayoutEngine()
        let reverseEngine = DwindleLayoutEngine()
        let wsId = UUID()
        let handleA = makeTestHandle(pid: 141)
        let handleB = makeTestHandle(pid: 142)
        let handleC = makeTestHandle(pid: 143)
        let forwardOrder = [handleA, handleB, handleC]
        let reverseOrder = [handleC, handleB, handleA]

        _ = forwardEngine.syncWindows(forwardOrder, in: wsId, focusedHandle: nil)
        _ = reverseEngine.syncWindows(reverseOrder, in: wsId, focusedHandle: nil)

        guard let forwardRoot = forwardEngine.root(for: wsId),
              let reverseRoot = reverseEngine.root(for: wsId)
        else {
            Issue.record("Expected Dwindle roots for fresh sync order test")
            return
        }

        #expect(forwardRoot.collectAllWindows() == forwardOrder.map(\.id))
        #expect(reverseRoot.collectAllWindows() == reverseOrder.map(\.id))
        #expect(forwardEngine.selectedNode(in: wsId)?.windowToken == handleC.id)
        #expect(reverseEngine.selectedNode(in: wsId)?.windowToken == handleA.id)

        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let forwardFrames = forwardEngine.calculateLayout(for: wsId, screen: screen)
        let reverseFrames = reverseEngine.calculateLayout(for: wsId, screen: screen)
        #expect(forwardFrames != reverseFrames)
    }

    @Test func `cold bootstrap sync matches warm incremental reference`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let handles = [
            makeTestHandle(pid: 241),
            makeTestHandle(pid: 242),
            makeTestHandle(pid: 243)
        ]
        let tokens = handles.map(\.id)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let settings = ResolvedDwindleSettings(
            smartSplit: true,
            defaultSplitRatio: 1.0,
            splitWidthMultiplier: 0.85,
            singleWindowAspectRatio: .fill,
            useGlobalGaps: false,
            innerGap: 12,
            outerGapTop: 16,
            outerGapBottom: 10,
            outerGapLeft: 14,
            outerGapRight: 18
        )
        applyResolvedDwindleSettingsForEngineTests(settings, to: engine)

        _ = engine.syncWindows(
            tokens,
            in: wsId,
            focusedToken: tokens.first,
            bootstrapScreen: screen
        )
        let coldFrames = engine.calculateLayout(for: wsId, screen: screen)
        let warmReference = warmReferenceDwindleImportForEngineTests(
            tokens: tokens,
            screen: screen,
            settings: settings
        )

        #expect(engine.root(for: wsId)?.collectAllWindows() == warmReference.order)
        #expect(coldFrames == warmReference.frames)
    }

    @Test func `selection survives sibling collapse after removal`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let left = makeTestHandle(pid: 81)
        let right = makeTestHandle(pid: 82)

        _ = engine.syncWindows([left, right], in: wsId, focusedHandle: left)
        guard let rightNode = engine.findNode(for: right.id) else {
            Issue.record("Expected surviving sibling node for Dwindle removal regression test")
            return
        }

        engine.setSelectedNode(rightNode, in: wsId)
        engine.removeWindow(token: left.id, from: wsId)

        #expect(engine.selectedNode(in: wsId)?.windowToken == right.id)
        #expect(engine.toggleFullscreen(in: wsId) == right.id)
    }

    @Test func `focus hit test misses empty workspace`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()

        #expect(engine.hitTestFocusableWindow(point: .zero, in: wsId, at: CACurrentMediaTime()) == nil)
    }

    @Test func `focus hit test returns matching leaf`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let firstHandle = makeTestHandle(pid: 51)
        let secondHandle = makeTestHandle(pid: 52)

        _ = engine.syncWindows([firstHandle, secondHandle], in: wsId, focusedHandle: firstHandle)
        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let secondFrame = frames[secondHandle.id] else {
            Issue.record("Expected a Dwindle frame for matching-leaf focus hit-test")
            return
        }

        #expect(
            engine.hitTestFocusableWindow(
                point: CGPoint(x: secondFrame.midX, y: secondFrame.midY),
                in: wsId,
                at: CACurrentMediaTime()
            ) == secondHandle.id
        )
    }

    @Test func `focus hit test prefers fullscreen window over covered tile`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let coveredHandle = makeTestHandle(pid: 61)
        let fullscreenHandle = makeTestHandle(pid: 62)

        _ = engine.syncWindows([coveredHandle, fullscreenHandle], in: wsId, focusedHandle: fullscreenHandle)
        _ = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let fullscreenNode = engine.findNode(for: fullscreenHandle.id) else {
            Issue.record("Expected a fullscreen node for Dwindle focus hit-test")
            return
        }

        engine.setSelectedNode(fullscreenNode, in: wsId)
        #expect(engine.toggleFullscreen(in: wsId) == fullscreenHandle.id)

        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let coveredFrame = frames[coveredHandle.id],
              let fullscreenFrame = frames[fullscreenHandle.id]
        else {
            Issue.record("Expected covered and fullscreen frames for Dwindle focus hit-test")
            return
        }

        let overlapPoint = CGPoint(x: coveredFrame.midX, y: coveredFrame.midY)
        #expect(coveredFrame.contains(overlapPoint))
        #expect(fullscreenFrame.contains(overlapPoint))
        #expect(
            engine.hitTestFocusableWindow(
                point: overlapPoint,
                in: wsId,
                at: CACurrentMediaTime()
            ) == fullscreenHandle.id
        )
    }

    @Test func `focus hit test uses presented frame during animation`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let handle = makeTestHandle(pid: 71)

        _ = engine.syncWindows([handle], in: wsId, focusedHandle: handle)
        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let baseFrame = frames[handle.id],
              let node = engine.findNode(for: handle.id)
        else {
            Issue.record("Expected Dwindle node state for animation-aware focus hit-test")
            return
        }

        let animatedStartFrame = baseFrame.offsetBy(dx: baseFrame.width + 120, dy: 0)
        node.animateFrom(
            oldFrame: animatedStartFrame,
            newFrame: baseFrame,
            clock: nil,
            config: CubicConfig(duration: 10.0)
        )

        let animatedPoint = CGPoint(x: animatedStartFrame.midX, y: animatedStartFrame.midY)
        #expect(baseFrame.contains(animatedPoint) == false)
        #expect(
            engine.hitTestFocusableWindow(
                point: animatedPoint,
                in: wsId,
                at: CACurrentMediaTime()
            ) == handle.id
        )
    }

    @Test @MainActor func `steady relayout plan uses tokens without visibility diffs`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or active workspace for Dwindle plan test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        let firstToken = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 601)
        let secondToken = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 602)
        _ = controller.workspaceManager.setManagedFocus(firstToken, in: workspaceId, onMonitor: monitor.id)

        let plans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        guard let plan = plans.first else {
            Issue.record("Expected a Dwindle layout plan for the active workspace")
            return
        }

        #expect(layoutTokenSet(plan.diff.frameChanges) == Set([firstToken, secondToken]))
        #expect(plan.diff.visibilityChanges.isEmpty)
    }

    @Test @MainActor func `relayout plan starts animation when frames change`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or active workspace for Dwindle animation test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        _ = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 701)
        let initialPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(initialPlans)

        _ = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 702)
        let plans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        guard let plan = plans.first else {
            Issue.record("Expected a Dwindle layout plan after adding a window")
            return
        }

        #expect(
            hasDwindleAnimationDirective(
                plan.animationDirectives,
                workspaceId: workspaceId,
                monitorId: monitor.id
            )
        )
        #expect(plan.diff.visibilityChanges.isEmpty)
    }

    @Test @MainActor func `active animation tick reapplies focused border`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or active workspace for Dwindle border animation test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        controller.setBordersEnabled(true)
        await waitForLayoutPlanRefreshWork(on: controller)

        let firstToken = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 703)
        _ = controller.workspaceManager.setManagedFocus(firstToken, in: workspaceId, onMonitor: monitor.id)

        let initialPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(initialPlans)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == 703)

        _ = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 704)
        let animationPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(animationPlans)
        #expect(controller.dwindleLayoutHandler.dwindleAnimationByDisplay[monitor.displayId]?.0 == workspaceId)

        controller.borderManager.hideBorder()
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == nil)

        controller.dwindleLayoutHandler.tickDwindleAnimation(
            targetTime: controller.animationClock.now(),
            displayId: monitor.displayId
        )

        #expect(controller.dwindleLayoutHandler.dwindleAnimationByDisplay[monitor.displayId]?.0 == workspaceId)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == 703)
    }

    @Test @MainActor func `fullscreen relayout suppresses focused border`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or workspace for fullscreen border regression test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        controller.setBordersEnabled(true)
        await waitForLayoutPlanRefreshWork(on: controller)
        guard let engine = controller.dwindleEngine else {
            Issue.record("Missing Dwindle engine for fullscreen border regression test")
            return
        }

        let firstToken = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 707)
        _ = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 708)
        _ = controller.workspaceManager.setManagedFocus(firstToken, in: workspaceId, onMonitor: monitor.id)

        let initialPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(initialPlans)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == 707)

        guard let fullscreenNode = engine.findNode(for: firstToken) else {
            Issue.record("Missing Dwindle node for fullscreen border regression test")
            return
        }

        engine.setSelectedNode(fullscreenNode, in: workspaceId)
        #expect(engine.toggleFullscreen(in: workspaceId) == firstToken)

        let fullscreenPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(fullscreenPlans)

        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == nil)
        #expect(lastAppliedBorderFrameForLayoutPlanTests(on: controller) == nil)
    }

    @Test @MainActor func `active animation tick keeps border hidden during preserved non managed focus`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing monitor or active workspace for Dwindle preserved-focus border test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        controller.setBordersEnabled(true)
        await waitForLayoutPlanRefreshWork(on: controller)

        let firstToken = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 705)
        _ = controller.workspaceManager.setManagedFocus(firstToken, in: workspaceId, onMonitor: monitor.id)

        let initialPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(initialPlans)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == 705)

        _ = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 706)
        let animationPlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(animationPlans)
        #expect(controller.dwindleLayoutHandler.dwindleAnimationByDisplay[monitor.displayId]?.0 == workspaceId)

        _ = controller.workspaceManager.enterNonManagedFocus(
            appFullscreen: false,
            preserveFocusedToken: true
        )
        controller.borderManager.hideBorder()
        #expect(controller.workspaceManager.focusedToken == firstToken)
        #expect(controller.workspaceManager.isNonManagedFocusActive)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == nil)

        controller.dwindleLayoutHandler.tickDwindleAnimation(
            targetTime: controller.animationClock.now(),
            displayId: monitor.displayId
        )

        #expect(controller.dwindleLayoutHandler.dwindleAnimationByDisplay[monitor.displayId]?.0 == workspaceId)
        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == nil)
    }

    @Test @MainActor func `relayout plan uses resolved monitor settings from snapshot`() async throws {
        let monitor = makeLayoutPlanTestMonitor(name: "SquareTest")
        let controller = makeLayoutPlanTestController(monitors: [monitor])
        guard let workspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
        else {
            Issue.record("Missing active workspace for Dwindle settings test")
            return
        }

        configureWorkspaceAsDwindle(on: controller, workspaceId: workspaceId)
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        let token = addLayoutPlanTestWindow(on: controller, workspaceId: workspaceId, windowId: 801)

        let baselinePlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        guard let baselinePlan = baselinePlans.first,
              let baselineFrame = baselinePlan.diff.frameChanges.first(where: { $0.token == token })?.frame
        else {
            Issue.record("Expected a baseline Dwindle frame for the single window")
            return
        }

        controller.settings.updateDwindleSettings(
            MonitorDwindleSettings(
                monitorName: monitor.name,
                monitorDisplayId: monitor.displayId,
                singleWindowAspectRatio: .square
            )
        )

        let overridePlans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [workspaceId]
        )
        guard let overridePlan = overridePlans.first,
              let overrideFrame = overridePlan.diff.frameChanges.first(where: { $0.token == token })?.frame
        else {
            Issue.record("Expected a Dwindle frame after applying monitor override settings")
            return
        }

        #expect(baselineFrame.width > overrideFrame.width)
        #expect(abs(overrideFrame.width - overrideFrame.height) < 0.5)
    }

    @Test @MainActor func `non focused workspace plan does not clear focused border`() async throws {
        let fixture = makeTwoMonitorLayoutPlanTestController()
        let controller = fixture.controller
        controller.setBordersEnabled(true)
        configureWorkspacesAsDwindle(
            on: controller,
            workspaceIds: [fixture.primaryWorkspaceId, fixture.secondaryWorkspaceId]
        )
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        let primaryToken = addLayoutPlanTestWindow(
            on: controller,
            workspaceId: fixture.primaryWorkspaceId,
            windowId: 901
        )
        _ = addLayoutPlanTestWindow(
            on: controller,
            workspaceId: fixture.secondaryWorkspaceId,
            windowId: 902
        )
        _ = controller.workspaceManager.setManagedFocus(
            primaryToken,
            in: fixture.primaryWorkspaceId,
            onMonitor: fixture.primaryMonitor.id
        )

        let plans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [fixture.primaryWorkspaceId, fixture.secondaryWorkspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(plans)

        #expect(lastAppliedBorderWindowIdForLayoutPlanTests(on: controller) == 901)
    }

    @Test @MainActor func `visible secondary workspace plan restores inactive hidden windows`() async throws {
        let fixture = makeTwoMonitorLayoutPlanTestController()
        let controller = fixture.controller
        configureWorkspacesAsDwindle(
            on: controller,
            workspaceIds: [fixture.primaryWorkspaceId, fixture.secondaryWorkspaceId]
        )
        guard controller.workspaceManager.monitor(for: fixture.secondaryWorkspaceId)?.id == fixture.secondaryMonitor.id
        else {
            Issue.record("Expected the secondary workspace to remain assigned to the visible secondary monitor")
            return
        }
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        let token = addLayoutPlanTestWindow(
            on: controller,
            workspaceId: fixture.secondaryWorkspaceId,
            windowId: 905
        )
        setWorkspaceInactiveHiddenStateForLayoutPlanTests(
            on: controller,
            token: token,
            monitor: fixture.secondaryMonitor
        )

        let plans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [fixture.primaryWorkspaceId, fixture.secondaryWorkspaceId]
        )
        guard let secondaryPlan = plans.first(where: { $0.workspaceId == fixture.secondaryWorkspaceId }) else {
            Issue.record("Expected a plan for the visible secondary workspace")
            return
        }

        #expect(secondaryPlan.diff.restoreChanges.contains { $0.token == token })
    }

    @Test @MainActor func `stale dwindle animation stops before restoring inactive workspace windows`() async throws {
        let controller = makeLayoutPlanTestController()
        guard let monitor = controller.workspaceManager.monitors.first,
              let originalWorkspaceId = controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id,
              let replacementWorkspaceId = controller.workspaceManager.workspaceId(for: "2", createIfMissing: true)
        else {
            Issue.record("Missing monitor or workspaces for stale Dwindle animation test")
            return
        }

        configureWorkspacesAsDwindle(
            on: controller,
            workspaceIds: [originalWorkspaceId, replacementWorkspaceId]
        )
        controller.enableDwindleLayout()
        await waitForLayoutPlanRefreshWork(on: controller)

        let token = addLayoutPlanTestWindow(on: controller, workspaceId: originalWorkspaceId, windowId: 903)
        _ = controller.workspaceManager.setManagedFocus(token, in: originalWorkspaceId, onMonitor: monitor.id)

        let plans = try await controller.dwindleLayoutHandler.layoutWithDwindleEngine(
            activeWorkspaces: [originalWorkspaceId]
        )
        controller.layoutRefreshController.executeLayoutPlans(plans)

        setWorkspaceInactiveHiddenStateForLayoutPlanTests(on: controller, token: token, monitor: monitor)
        #expect(
            controller.dwindleLayoutHandler.registerDwindleAnimation(
                originalWorkspaceId,
                monitor: monitor,
                on: monitor.displayId
            )
        )
        _ = controller.workspaceManager.setActiveWorkspace(replacementWorkspaceId, on: monitor.id)

        controller.dwindleLayoutHandler.tickDwindleAnimation(targetTime: 1, displayId: monitor.displayId)

        #expect(controller.dwindleLayoutHandler.dwindleAnimationByDisplay[monitor.displayId] == nil)
        #expect(controller.workspaceManager.hiddenState(for: token)?.workspaceInactive == true)
    }

    @Test func `summon window right reinserts window as right sibling`() {
        let engine = DwindleLayoutEngine()
        let wsId = UUID()
        let anchor = makeTestHandle(pid: 81)
        let summoned = makeTestHandle(pid: 82)

        _ = engine.syncWindows([anchor, summoned], in: wsId, focusedHandle: anchor)
        _ = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        let moved = engine.summonWindowRight(summoned.id, beside: anchor.id, in: wsId)
        let frames = engine.calculateLayout(
            for: wsId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let anchorFrame = frames[anchor.id],
              let summonedFrame = frames[summoned.id]
        else {
            Issue.record("Expected both frames after Dwindle summon-right")
            return
        }

        #expect(moved)
        #expect(summonedFrame.minX >= anchorFrame.maxX - 1.0)
        #expect(engine.selectedNode(in: wsId)?.windowToken == summoned.id)
    }

    @Test func `preselection adds cross workspace window as right sibling`() {
        let engine = DwindleLayoutEngine()
        let targetWorkspaceId = UUID()
        let sourceWorkspaceId = UUID()
        let anchor = makeTestHandle(pid: 91)
        let summoned = makeTestHandle(pid: 92)
        let fallback = makeTestHandle(pid: 93)

        _ = engine.syncWindows([anchor], in: targetWorkspaceId, focusedHandle: anchor)
        _ = engine.syncWindows([summoned, fallback], in: sourceWorkspaceId, focusedHandle: summoned)
        _ = engine.calculateLayout(
            for: targetWorkspaceId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )
        _ = engine.calculateLayout(
            for: sourceWorkspaceId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let anchorNode = engine.findNode(for: anchor.id) else {
            Issue.record("Expected anchor node for Dwindle cross-workspace summon")
            return
        }

        engine.setSelectedNode(anchorNode, in: targetWorkspaceId)
        engine.setPreselection(.right, in: targetWorkspaceId)
        engine.removeWindow(token: summoned.id, from: sourceWorkspaceId)
        _ = engine.syncWindows(
            [anchor.id, summoned.id],
            in: targetWorkspaceId,
            focusedToken: anchor.id
        )

        let targetFrames = engine.calculateLayout(
            for: targetWorkspaceId,
            screen: CGRect(x: 0, y: 0, width: 1600, height: 1000)
        )

        guard let anchorFrame = targetFrames[anchor.id],
              let summonedFrame = targetFrames[summoned.id]
        else {
            Issue.record("Expected target workspace frames after cross-workspace Dwindle summon")
            return
        }

        #expect(engine.windowCount(in: sourceWorkspaceId) == 1)
        #expect(summonedFrame.minX >= anchorFrame.maxX - 1.0)
    }
}
