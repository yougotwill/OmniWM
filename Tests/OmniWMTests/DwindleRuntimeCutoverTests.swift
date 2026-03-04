import CoreGraphics
import Foundation
import Testing

@testable import OmniWM

private func dwindleRuntimeApproxRectEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.5) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= epsilon
        && abs(lhs.origin.y - rhs.origin.y) <= epsilon
        && abs(lhs.width - rhs.width) <= epsilon
        && abs(lhs.height - rhs.height) <= epsilon
}

private func dwindleRuntimeAssertFrameParity(
    _ lhs: [WindowHandle: CGRect],
    _ rhs: [WindowHandle: CGRect]
) {
    #expect(lhs.count == rhs.count)
    for (handle, lhsFrame) in lhs {
        guard let rhsFrame = rhs[handle] else {
            #expect(Bool(false))
            continue
        }
        #expect(dwindleRuntimeApproxRectEqual(lhsFrame, rhsFrame))
    }
}

@Suite struct DwindleRuntimeCutoverTests {
    @MainActor
    @Test func defaultBackendUsesZigContext() {
        let engine = DwindleLayoutEngine()
        #expect(engine.backend == .zigContext)
    }

    @MainActor
    @Test func commandPathParityBetweenZigAndLegacyBackends() {
        let zigEngine = DwindleLayoutEngine()
        let legacyEngine = DwindleLayoutEngine(backend: .legacyDeterministic)

        zigEngine.settings.smartSplit = true
        zigEngine.settings.defaultSplitRatio = 1.0
        zigEngine.settings.splitWidthMultiplier = 1.0
        zigEngine.settings.innerGap = 8

        legacyEngine.settings = zigEngine.settings

        let workspaceId = WorkspaceDescriptor.ID()
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let handles: [WindowHandle] = [
            makeTestHandle(pid: 30101),
            makeTestHandle(pid: 30102),
            makeTestHandle(pid: 30103),
            makeTestHandle(pid: 30104),
        ]

        for (index, handle) in handles.enumerated() {
            let constraints = WindowSizeConstraints(
                minSize: CGSize(width: CGFloat(70 + index * 10), height: CGFloat(60 + index * 10)),
                maxSize: CGSize(width: 0, height: 0),
                isFixed: false
            )
            zigEngine.updateWindowConstraints(for: handle, constraints: constraints)
            legacyEngine.updateWindowConstraints(for: handle, constraints: constraints)
        }

        _ = zigEngine.syncWindows(handles, in: workspaceId, focusedHandle: nil)
        _ = legacyEngine.syncWindows(handles, in: workspaceId, focusedHandle: nil)

        func assertStateParity(label: String) {
            let zigFrames = zigEngine.calculateLayout(for: workspaceId, screen: screen)
            let legacyFrames = legacyEngine.calculateLayout(for: workspaceId, screen: screen)

            #expect(zigEngine.windowCount(in: workspaceId) == legacyEngine.windowCount(in: workspaceId), "\(label): window count")
            #expect(zigEngine.selectedWindowHandle(in: workspaceId)?.id == legacyEngine.selectedWindowHandle(in: workspaceId)?.id, "\(label): selected window")
            #expect(zigEngine.getPreselection(in: workspaceId) == legacyEngine.getPreselection(in: workspaceId), "\(label): preselection")
            dwindleRuntimeAssertFrameParity(zigFrames, legacyFrames)
        }

        assertStateParity(label: "initial")

        let zigFocusedLeft = zigEngine.moveFocus(direction: .left, in: workspaceId)
        let legacyFocusedLeft = legacyEngine.moveFocus(direction: .left, in: workspaceId)
        #expect(zigFocusedLeft?.id == legacyFocusedLeft?.id)
        assertStateParity(label: "moveFocus")

        #expect(
            zigEngine.swapWindows(direction: .right, in: workspaceId)
                == legacyEngine.swapWindows(direction: .right, in: workspaceId)
        )
        assertStateParity(label: "swapWindows")

        #expect(
            zigEngine.toggleFullscreen(in: workspaceId)?.id
                == legacyEngine.toggleFullscreen(in: workspaceId)?.id
        )
        assertStateParity(label: "toggleFullscreen")

        zigEngine.toggleOrientation(in: workspaceId)
        legacyEngine.toggleOrientation(in: workspaceId)
        assertStateParity(label: "toggleOrientation")

        zigEngine.resizeSelected(by: 0.15, direction: .left, in: workspaceId)
        legacyEngine.resizeSelected(by: 0.15, direction: .left, in: workspaceId)
        assertStateParity(label: "resizeSelected")

        zigEngine.balanceSizes(in: workspaceId)
        legacyEngine.balanceSizes(in: workspaceId)
        assertStateParity(label: "balanceSizes")

        zigEngine.cycleSplitRatio(forward: true, in: workspaceId)
        legacyEngine.cycleSplitRatio(forward: true, in: workspaceId)
        assertStateParity(label: "cycleSplitRatio")

        zigEngine.moveSelectionToRoot(stable: true, in: workspaceId)
        legacyEngine.moveSelectionToRoot(stable: true, in: workspaceId)
        assertStateParity(label: "moveSelectionToRoot")

        zigEngine.swapSplit(in: workspaceId)
        legacyEngine.swapSplit(in: workspaceId)
        assertStateParity(label: "swapSplit")

        zigEngine.setPreselection(.left, in: workspaceId)
        legacyEngine.setPreselection(.left, in: workspaceId)
        assertStateParity(label: "setPreselection")

        zigEngine.setPreselection(nil, in: workspaceId)
        legacyEngine.setPreselection(nil, in: workspaceId)
        assertStateParity(label: "clearPreselection")

        let h5 = makeTestHandle(pid: 30105)
        let h5Constraints = WindowSizeConstraints(
            minSize: CGSize(width: 100, height: 90),
            maxSize: CGSize(width: 0, height: 0),
            isFixed: false
        )
        zigEngine.updateWindowConstraints(for: h5, constraints: h5Constraints)
        legacyEngine.updateWindowConstraints(for: h5, constraints: h5Constraints)

        let newOrder = [handles[2], h5, handles[3]]
        let zigRemoved = zigEngine.syncWindows(newOrder, in: workspaceId, focusedHandle: nil)
        let legacyRemoved = legacyEngine.syncWindows(newOrder, in: workspaceId, focusedHandle: nil)

        #expect(Set(zigRemoved.map(\.id)) == Set(legacyRemoved.map(\.id)))
        assertStateParity(label: "syncWindows")
    }

    @MainActor
    @Test func zigLayoutFailureReturnsStaleFramesInsteadOfCrashing() {
        let engine = DwindleLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let handle = makeTestHandle(pid: 30201)

        _ = engine.syncWindows([handle], in: workspaceId, focusedHandle: nil)

        let validScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let baseline = engine.calculateLayout(for: workspaceId, screen: validScreen)
        #expect(!baseline.isEmpty)

        let invalidScreen = CGRect(x: 0, y: 0, width: CGFloat.nan, height: 900)
        let staleFrames = engine.calculateLayout(for: workspaceId, screen: invalidScreen)

        #expect(staleFrames.count == baseline.count)
        for (window, baselineFrame) in baseline {
            guard let stale = staleFrames[window] else {
                #expect(Bool(false))
                continue
            }
            #expect(dwindleRuntimeApproxRectEqual(stale, baselineFrame))
        }
    }
}
