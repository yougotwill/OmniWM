import AppKit
import CZigLayout
import Foundation

enum NiriLayoutZigKernel {
    struct WindowResult {
        let window: NiriWindow
        let baseFrame: CGRect
        let animatedFrame: CGRect
        let resolvedSpan: CGFloat
        let wasConstrained: Bool
        let hideSide: HideSide?
    }

    private static func orientationCode(_ orientation: Monitor.Orientation) -> UInt8 {
        switch orientation {
        case .horizontal:
            0
        case .vertical:
            1
        }
    }

    private static func sizingModeCode(_ mode: SizingMode) -> UInt8 {
        switch mode {
        case .normal:
            0
        case .fullscreen:
            1
        }
    }

    private static func hideSideFromCode(_ code: UInt8) -> HideSide? {
        if code == 1 {
            return .left
        }
        if code == 2 {
            return .right
        }
        return nil
    }

    static func run(
        columns: [NiriContainer],
        orientation: Monitor.Orientation,
        primaryGap: CGFloat,
        secondaryGap: CGFloat,
        workingFrame: CGRect,
        viewFrame: CGRect,
        fullscreenFrame: CGRect,
        viewStart: CGFloat,
        viewportSpan: CGFloat,
        workspaceOffset: CGFloat,
        scale: CGFloat,
        tabIndicatorWidth: CGFloat,
        time: TimeInterval
    ) -> [WindowResult] {
        guard !columns.isEmpty else { return [] }

        var columnInputs: [OmniNiriColumnInput] = []
        columnInputs.reserveCapacity(columns.count)

        var windowInputs: [OmniNiriWindowInput] = []
        var flatWindows: [NiriWindow] = []

        for column in columns {
            let start = windowInputs.count
            let windows = column.windowNodes
            flatWindows.append(contentsOf: windows)

            for window in windows {
                let weight: CGFloat
                let minConstraint: CGFloat
                let maxConstraint: CGFloat
                let hasMaxConstraint: Bool
                let hasFixedValue: Bool
                let fixedValue: CGFloat

                switch orientation {
                case .horizontal:
                    weight = max(0.1, window.heightWeight)
                    minConstraint = window.constraints.minSize.height
                    maxConstraint = window.constraints.maxSize.height
                    hasMaxConstraint = window.constraints.hasMaxHeight
                    switch window.height {
                    case let .fixed(h):
                        hasFixedValue = true
                        fixedValue = h
                    case .auto:
                        hasFixedValue = false
                        fixedValue = 0
                    }
                case .vertical:
                    weight = max(0.1, window.widthWeight)
                    minConstraint = window.constraints.minSize.width
                    maxConstraint = window.constraints.maxSize.width
                    hasMaxConstraint = window.constraints.hasMaxWidth
                    switch window.windowWidth {
                    case let .fixed(w):
                        hasFixedValue = true
                        fixedValue = w
                    case .auto:
                        hasFixedValue = false
                        fixedValue = 0
                    }
                }

                let renderOffset = window.renderOffset(at: time)
                windowInputs.append(
                    OmniNiriWindowInput(
                        weight: Double(weight),
                        min_constraint: Double(minConstraint),
                        max_constraint: Double(maxConstraint),
                        has_max_constraint: hasMaxConstraint ? 1 : 0,
                        is_constraint_fixed: window.constraints.isFixed ? 1 : 0,
                        has_fixed_value: hasFixedValue ? 1 : 0,
                        fixed_value: Double(fixedValue),
                        sizing_mode: sizingModeCode(window.sizingMode),
                        render_offset_x: Double(renderOffset.x),
                        render_offset_y: Double(renderOffset.y)
                    )
                )
            }

            let span: CGFloat = switch orientation {
            case .horizontal:
                column.cachedWidth
            case .vertical:
                column.cachedHeight
            }

            let columnRenderOffset = column.renderOffset(at: time)
            columnInputs.append(
                OmniNiriColumnInput(
                    span: Double(span),
                    render_offset_x: Double(columnRenderOffset.x),
                    render_offset_y: Double(columnRenderOffset.y),
                    is_tabbed: column.isTabbed ? 1 : 0,
                    tab_indicator_width: Double(column.isTabbed ? tabIndicatorWidth : 0),
                    window_start: start,
                    window_count: windows.count
                )
            )
        }

        var rawOutputs = [OmniNiriWindowOutput](
            repeating: OmniNiriWindowOutput(
                frame_x: 0,
                frame_y: 0,
                frame_width: 0,
                frame_height: 0,
                animated_x: 0,
                animated_y: 0,
                animated_width: 0,
                animated_height: 0,
                resolved_span: 0,
                was_constrained: 0,
                hide_side: 0,
                column_index: 0
            ),
            count: windowInputs.count
        )

        let rc: Int32 = columnInputs.withUnsafeBufferPointer { colBuf in
            windowInputs.withUnsafeBufferPointer { winBuf in
                rawOutputs.withUnsafeMutableBufferPointer { outBuf in
                    omni_niri_layout_pass(
                        colBuf.baseAddress,
                        colBuf.count,
                        winBuf.baseAddress,
                        winBuf.count,
                        Double(workingFrame.origin.x),
                        Double(workingFrame.origin.y),
                        Double(workingFrame.width),
                        Double(workingFrame.height),
                        Double(viewFrame.origin.x),
                        Double(viewFrame.origin.y),
                        Double(viewFrame.width),
                        Double(viewFrame.height),
                        Double(fullscreenFrame.origin.x),
                        Double(fullscreenFrame.origin.y),
                        Double(fullscreenFrame.width),
                        Double(fullscreenFrame.height),
                        Double(primaryGap),
                        Double(secondaryGap),
                        Double(viewStart),
                        Double(viewportSpan),
                        Double(workspaceOffset),
                        Double(scale),
                        orientationCode(orientation),
                        outBuf.baseAddress,
                        outBuf.count
                    )
                }
            }
        }

        precondition(
            rc == OMNI_OK,
            "omni_niri_layout_pass failed rc=\(rc) columns=\(columnInputs.count) windows=\(windowInputs.count)"
        )

        return zip(flatWindows, rawOutputs).map { window, output in
            WindowResult(
                window: window,
                baseFrame: CGRect(
                    x: output.frame_x,
                    y: output.frame_y,
                    width: output.frame_width,
                    height: output.frame_height
                ),
                animatedFrame: CGRect(
                    x: output.animated_x,
                    y: output.animated_y,
                    width: output.animated_width,
                    height: output.animated_height
                ),
                resolvedSpan: CGFloat(output.resolved_span),
                wasConstrained: output.was_constrained != 0,
                hideSide: hideSideFromCode(output.hide_side)
            )
        }
    }
}
