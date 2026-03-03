import AppKit
import Foundation

extension CGFloat {
    func roundedToPhysicalPixel(scale: CGFloat) -> CGFloat {
        (self * scale).rounded() / scale
    }
}

extension CGPoint {
    func roundedToPhysicalPixels(scale: CGFloat) -> CGPoint {
        CGPoint(
            x: x.roundedToPhysicalPixel(scale: scale),
            y: y.roundedToPhysicalPixel(scale: scale)
        )
    }
}

extension CGSize {
    func roundedToPhysicalPixels(scale: CGFloat) -> CGSize {
        CGSize(
            width: width.roundedToPhysicalPixel(scale: scale),
            height: height.roundedToPhysicalPixel(scale: scale)
        )
    }
}

extension CGRect {
    func roundedToPhysicalPixels(scale: CGFloat) -> CGRect {
        CGRect(
            origin: origin.roundedToPhysicalPixels(scale: scale),
            size: size.roundedToPhysicalPixels(scale: scale)
        )
    }
}

struct LayoutResult {
    let frames: [WindowHandle: CGRect]
    let hiddenHandles: [WindowHandle: HideSide]
}

extension NiriLayoutEngine {
    private func workspaceSwitchOffset(
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        time: TimeInterval
    ) -> CGFloat {
        guard let monitorId = monitorContaining(workspace: workspaceId),
              let monitor = monitors[monitorId],
              let workspaceIndex = monitor.workspaceOrder.firstIndex(of: workspaceId) else {
            return 0
        }

        let renderIndex = monitor.workspaceRenderIndex(at: time)
        let delta = Double(workspaceIndex) - renderIndex
        if abs(delta) < 0.001 {
            return 0
        }

        let reduceMotionScale: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.25 : 1.0
        return CGFloat(delta) * monitorFrame.width * reduceMotionScale
    }

    func calculateLayout(
        state: ViewportState,
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        screenFrame: CGRect? = nil,
        gaps: (horizontal: CGFloat, vertical: CGFloat),
        scale: CGFloat = 2.0,
        workingArea: WorkingAreaContext? = nil,
        orientation: Monitor.Orientation = .horizontal
    ) -> [WindowHandle: CGRect] {
        calculateLayoutWithVisibility(
            state: state,
            workspaceId: workspaceId,
            monitorFrame: monitorFrame,
            screenFrame: screenFrame,
            gaps: gaps,
            scale: scale,
            workingArea: workingArea,
            orientation: orientation
        ).frames
    }

    func calculateLayoutWithVisibility(
        state: ViewportState,
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        screenFrame: CGRect? = nil,
        gaps: (horizontal: CGFloat, vertical: CGFloat),
        scale: CGFloat = 2.0,
        workingArea: WorkingAreaContext? = nil,
        orientation: Monitor.Orientation = .horizontal,
        animationTime: TimeInterval? = nil
    ) -> LayoutResult {
        var frames: [WindowHandle: CGRect] = [:]
        var hiddenHandles: [WindowHandle: HideSide] = [:]
        calculateLayoutInto(
            frames: &frames,
            hiddenHandles: &hiddenHandles,
            state: state,
            workspaceId: workspaceId,
            monitorFrame: monitorFrame,
            screenFrame: screenFrame,
            gaps: gaps,
            scale: scale,
            workingArea: workingArea,
            orientation: orientation,
            animationTime: animationTime
        )
        return LayoutResult(frames: frames, hiddenHandles: hiddenHandles)
    }

    func calculateLayoutInto(
        frames: inout [WindowHandle: CGRect],
        hiddenHandles: inout [WindowHandle: HideSide],
        state: ViewportState,
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        screenFrame: CGRect? = nil,
        gaps: (horizontal: CGFloat, vertical: CGFloat),
        scale: CGFloat = 2.0,
        workingArea: WorkingAreaContext? = nil,
        orientation: Monitor.Orientation = .horizontal,
        animationTime: TimeInterval? = nil
    ) {
        calculateLayoutIntoZig(
            frames: &frames,
            hiddenHandles: &hiddenHandles,
            state: state,
            workspaceId: workspaceId,
            monitorFrame: monitorFrame,
            screenFrame: screenFrame,
            gaps: gaps,
            scale: scale,
            workingArea: workingArea,
            orientation: orientation,
            animationTime: animationTime
        )
    }

    private func calculateLayoutIntoZig(
        frames: inout [WindowHandle: CGRect],
        hiddenHandles: inout [WindowHandle: HideSide],
        state: ViewportState,
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        screenFrame: CGRect? = nil,
        gaps: (horizontal: CGFloat, vertical: CGFloat),
        scale: CGFloat = 2.0,
        workingArea: WorkingAreaContext? = nil,
        orientation: Monitor.Orientation = .horizontal,
        animationTime: TimeInterval? = nil
    ) {
        let containers = columns(in: workspaceId)
        guard !containers.isEmpty else { return }

        let workingFrame = workingArea?.workingFrame ?? monitorFrame
        let viewFrame = workingArea?.viewFrame ?? screenFrame ?? monitorFrame
        let effectiveScale = workingArea?.scale ?? scale

        let primaryGap: CGFloat
        let secondaryGap: CGFloat
        switch orientation {
        case .horizontal:
            primaryGap = gaps.horizontal
            secondaryGap = gaps.vertical
        case .vertical:
            primaryGap = gaps.vertical
            secondaryGap = gaps.horizontal
        }

        let time = animationTime ?? CACurrentMediaTime()
        let workspaceOffset = workspaceSwitchOffset(
            workspaceId: workspaceId,
            monitorFrame: monitorFrame,
            time: time
        )
        let offsetFullscreenRect = workingFrame.offsetBy(dx: workspaceOffset, dy: 0)

        for container in containers {
            switch orientation {
            case .horizontal:
                if container.cachedWidth <= 0 {
                    container.resolveAndCacheWidth(workingAreaWidth: workingFrame.width, gaps: primaryGap)
                }
            case .vertical:
                if container.cachedHeight <= 0 {
                    container.resolveAndCacheHeight(workingAreaHeight: workingFrame.height, gaps: primaryGap)
                }
            }
        }

        let containerSpans: [CGFloat] = switch orientation {
        case .horizontal: containers.map { $0.cachedWidth }
        case .vertical: containers.map { $0.cachedHeight }
        }
        let containerRenderOffsets = containers.map { $0.renderOffset(at: time) }

        var containerPositions: [CGFloat] = []
        containerPositions.reserveCapacity(containers.count)
        var runningPos: CGFloat = 0
        var totalSpan: CGFloat = 0
        for i in 0 ..< containers.count {
            containerPositions.append(runningPos)
            let span = containerSpans[i]
            runningPos += span + primaryGap
            totalSpan += span
            if i < containers.count - 1 {
                totalSpan += primaryGap
            }
        }

        let viewOffset = state.viewOffsetPixels.value(at: time)
        let activeIdx = state.activeColumnIndex.clamped(to: 0 ... max(0, containers.count - 1))
        let activePos = containerPositions[activeIdx]
        let viewPos = activePos + viewOffset
        let viewStart = viewPos
        let viewportSpan: CGFloat = switch orientation {
        case .horizontal: workingFrame.width
        case .vertical: workingFrame.height
        }
        let viewEnd = viewStart + viewportSpan

        var usedIndices = Set<Int>()
        var containerSides: [Int: HideSide] = [:]

        for idx in 0 ..< containers.count {
            let containerPos = containerPositions[idx]
            let containerSpan = containerSpans[idx]
            let containerEnd = containerPos + containerSpan
            let renderOffset = containerRenderOffsets[idx]

            let isVisible = containerEnd > viewStart && containerPos < viewEnd
            if isVisible {
                usedIndices.insert(idx)
                let containerRect: CGRect
                switch orientation {
                case .horizontal:
                    let screenX = workingFrame.origin.x + containerPos - viewPos + renderOffset.x + workspaceOffset
                    let width = containerSpan.roundedToPhysicalPixel(scale: effectiveScale)
                    containerRect = CGRect(
                        x: screenX,
                        y: workingFrame.origin.y,
                        width: width,
                        height: workingFrame.height
                    ).roundedToPhysicalPixels(scale: effectiveScale)
                case .vertical:
                    let screenY = workingFrame.origin.y + containerPos - viewPos + renderOffset.y
                    let height = containerSpan.roundedToPhysicalPixel(scale: effectiveScale)
                    containerRect = CGRect(
                        x: workingFrame.origin.x + workspaceOffset,
                        y: screenY,
                        width: workingFrame.width,
                        height: height
                    ).roundedToPhysicalPixels(scale: effectiveScale)
                }
                containers[idx].frame = containerRect
            } else {
                let hideSide: HideSide = containerEnd <= viewStart ? .left : .right
                containerSides[idx] = hideSide
            }
        }

        if containers.count > usedIndices.count {
            let avgSpan = totalSpan / CGFloat(max(1, containers.count))
            let hiddenSpan = max(1, avgSpan).roundedToPhysicalPixel(scale: effectiveScale)
            for (idx, container) in containers.enumerated() {
                if usedIndices.contains(idx) { continue }

                let hiddenRect: CGRect
                switch orientation {
                case .horizontal:
                    let side = containerSides[idx] ?? .right
                    hiddenRect = hiddenColumnRect(
                        side: side,
                        width: hiddenSpan,
                        height: workingFrame.height,
                        screenY: viewFrame.maxY - 2,
                        edgeFrame: viewFrame,
                        scale: effectiveScale
                    ).offsetBy(dx: workspaceOffset, dy: 0).roundedToPhysicalPixels(scale: effectiveScale)
                case .vertical:
                    hiddenRect = hiddenRowRect(
                        screenRect: viewFrame,
                        width: workingFrame.width,
                        height: hiddenSpan
                    ).offsetBy(dx: workspaceOffset, dy: 0).roundedToPhysicalPixels(scale: effectiveScale)
                }
                container.frame = hiddenRect
            }
        }

        let kernelResults = NiriLayoutZigKernel.run(
            columns: containers,
            orientation: orientation,
            primaryGap: primaryGap,
            secondaryGap: secondaryGap,
            workingFrame: workingFrame,
            viewFrame: viewFrame,
            fullscreenFrame: offsetFullscreenRect,
            viewStart: viewStart,
            viewportSpan: viewportSpan,
            workspaceOffset: workspaceOffset,
            scale: effectiveScale,
            tabIndicatorWidth: renderStyle.tabIndicatorWidth,
            time: time
        )

        for result in kernelResults {
            let roundedBaseFrame = result.baseFrame.roundedToPhysicalPixels(scale: effectiveScale)
            let roundedAnimatedFrame = result.animatedFrame.roundedToPhysicalPixels(scale: effectiveScale)

            result.window.frame = roundedBaseFrame
            switch orientation {
            case .horizontal:
                result.window.resolvedHeight = result.resolvedSpan
                result.window.heightFixedByConstraint = result.wasConstrained
            case .vertical:
                result.window.resolvedWidth = result.resolvedSpan
                result.window.widthFixedByConstraint = result.wasConstrained
            }

            if let side = result.hideSide {
                hiddenHandles[result.window.handle] = side
            }
            frames[result.window.handle] = roundedAnimatedFrame
        }
    }

    private func hiddenRowRect(
        screenRect: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect {
        let origin = CGPoint(
            x: screenRect.maxX - 2,
            y: screenRect.maxY - 2
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func hiddenColumnRect(
        side: HideSide,
        width: CGFloat,
        height: CGFloat,
        screenY: CGFloat,
        edgeFrame: CGRect,
        scale: CGFloat
    ) -> CGRect {
        let edgeReveal = 1.0 / max(1.0, scale)
        let x: CGFloat
        switch side {
        case .left:
            x = edgeFrame.minX - width + edgeReveal
        case .right:
            x = edgeFrame.maxX - edgeReveal
        }
        let origin = CGPoint(x: x, y: screenY)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}
