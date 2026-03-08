import CZigLayout
import CoreGraphics
import Foundation

private func controllerRawValue<T: RawRepresentable>(_ value: T) -> UInt8 where T.RawValue: BinaryInteger {
    UInt8(truncatingIfNeeded: value.rawValue)
}

extension Direction {
    var controllerDirection: UInt8 {
        switch self {
        case .left:
            controllerRawValue(OMNI_NIRI_DIRECTION_LEFT)
        case .right:
            controllerRawValue(OMNI_NIRI_DIRECTION_RIGHT)
        case .up:
            controllerRawValue(OMNI_NIRI_DIRECTION_UP)
        case .down:
            controllerRawValue(OMNI_NIRI_DIRECTION_DOWN)
        }
    }

    init?(controllerDirection: UInt8) {
        switch controllerDirection {
        case controllerRawValue(OMNI_NIRI_DIRECTION_LEFT):
            self = .left
        case controllerRawValue(OMNI_NIRI_DIRECTION_RIGHT):
            self = .right
        case controllerRawValue(OMNI_NIRI_DIRECTION_UP):
            self = .up
        case controllerRawValue(OMNI_NIRI_DIRECTION_DOWN):
            self = .down
        default:
            return nil
        }
    }
}

extension OmniControllerCommand {
    static func make(
        kind: UInt8,
        direction: UInt8 = 0,
        workspaceIndex: Int64 = 0,
        monitorDirection: UInt8 = 0,
        workspaceId: UUID? = nil,
        windowHandleId: UUID? = nil,
        secondaryWindowHandleId: UUID? = nil
    ) -> OmniControllerCommand {
        OmniControllerCommand(
            kind: kind,
            direction: direction,
            workspace_index: workspaceIndex,
            monitor_direction: monitorDirection,
            has_workspace_id: workspaceId == nil ? 0 : 1,
            workspace_id: workspaceId.map(ZigNiriStateKernel.omniUUID(from:)) ?? OmniUuid128(),
            has_window_handle_id: windowHandleId == nil ? 0 : 1,
            window_handle_id: windowHandleId.map(ZigNiriStateKernel.omniUUID(from:)) ?? OmniUuid128(),
            has_secondary_window_handle_id: secondaryWindowHandleId == nil ? 0 : 1,
            secondary_window_handle_id: secondaryWindowHandleId.map(ZigNiriStateKernel.omniUUID(from:)) ?? OmniUuid128()
        )
    }

    static func switchWorkspaceAnywhere(workspaceId: WorkspaceDescriptor.ID) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE),
            workspaceId: workspaceId
        )
    }

    static func moveWindowToWorkspace(
        handleId: UUID,
        workspaceId: WorkspaceDescriptor.ID
    ) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX),
            workspaceId: workspaceId,
            windowHandleId: handleId
        )
    }

    static func focusWindow(handleId: UUID) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_HANDLE),
            windowHandleId: handleId
        )
    }

    static func overviewInsertWindow(
        handleId: UUID,
        targetHandleId: UUID,
        position: InsertPosition,
        workspaceId: WorkspaceDescriptor.ID
    ) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW),
            monitorDirection: rawInsertPosition(position),
            workspaceId: workspaceId,
            windowHandleId: handleId,
            secondaryWindowHandleId: targetHandleId
        )
    }

    static func overviewInsertWindowInNewColumn(
        handleId: UUID,
        insertIndex: Int,
        workspaceId: WorkspaceDescriptor.ID
    ) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_OVERVIEW_INSERT_WINDOW_IN_NEW_COLUMN),
            workspaceIndex: Int64(insertIndex),
            workspaceId: workspaceId,
            windowHandleId: handleId
        )
    }

    static func setActiveWorkspaceOnMonitor(
        workspaceId: WorkspaceDescriptor.ID,
        displayId: CGDirectDisplayID
    ) -> OmniControllerCommand {
        make(
            kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SET_ACTIVE_WORKSPACE_ON_MONITOR),
            workspaceIndex: Int64(displayId),
            workspaceId: workspaceId
        )
    }
}

private func rawInsertPosition(_ position: InsertPosition) -> UInt8 {
    switch position {
    case .before:
        controllerRawValue(OMNI_NIRI_INSERT_BEFORE)
    case .after:
        controllerRawValue(OMNI_NIRI_INSERT_AFTER)
    case .swap:
        controllerRawValue(OMNI_NIRI_INSERT_SWAP)
    }
}

extension HotkeyCommand {
    var controllerCommand: OmniControllerCommand? {
        switch self {
        case let .focus(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_DIRECTION),
                direction: direction.controllerDirection
            )
        case .focusPrevious:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_PREVIOUS))
        case let .move(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_DIRECTION),
                direction: direction.controllerDirection
            )
        case let .swap(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWAP_DIRECTION),
                direction: direction.controllerDirection
            )
        case let .moveToWorkspace(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_WORKSPACE_INDEX),
                workspaceIndex: Int64(index)
            )
        case .moveWindowToWorkspaceUp:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_UP))
        case .moveWindowToWorkspaceDown:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_ADJACENT_WORKSPACE_DOWN))
        case let .moveColumnToWorkspace(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_WORKSPACE_INDEX),
                workspaceIndex: Int64(index)
            )
        case .moveColumnToWorkspaceUp:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_UP))
        case .moveColumnToWorkspaceDown:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_ADJACENT_WORKSPACE_DOWN))
        case let .switchWorkspace(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_INDEX),
                workspaceIndex: Int64(index)
            )
        case .switchWorkspaceNext:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_NEXT))
        case .switchWorkspacePrevious:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_PREVIOUS))
        case let .moveToMonitor(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_FOCUSED_WINDOW_TO_MONITOR_DIRECTION),
                direction: direction.controllerDirection
            )
        case let .focusMonitor(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_DIRECTION),
                direction: direction.controllerDirection
            )
        case .focusMonitorPrevious:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_PREVIOUS))
        case .focusMonitorNext:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_NEXT))
        case .focusMonitorLast:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_MONITOR_LAST))
        case let .moveColumnToMonitor(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_TO_MONITOR_DIRECTION),
                direction: direction.controllerDirection
            )
        case .toggleFullscreen:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_FULLSCREEN))
        case .toggleNativeFullscreen:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_NATIVE_FULLSCREEN))
        case let .moveColumn(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_COLUMN_DIRECTION),
                direction: direction.controllerDirection
            )
        case let .consumeWindow(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_CONSUME_WINDOW_DIRECTION),
                direction: direction.controllerDirection
            )
        case let .expelWindow(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_EXPEL_WINDOW_DIRECTION),
                direction: direction.controllerDirection
            )
        case .toggleColumnTabbed:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_TABBED))
        case .focusDownOrLeft:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_DOWN_OR_LEFT))
        case .focusUpOrRight:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_UP_OR_RIGHT))
        case .focusColumnFirst:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_FIRST))
        case .focusColumnLast:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_LAST))
        case let .focusColumn(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_COLUMN_INDEX),
                workspaceIndex: Int64(index)
            )
        case .focusWindowTop:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_TOP))
        case .focusWindowBottom:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_FOCUS_WINDOW_BOTTOM))
        case .cycleColumnWidthForward:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_FORWARD))
        case .cycleColumnWidthBackward:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_CYCLE_COLUMN_WIDTH_BACKWARD))
        case .toggleColumnFullWidth:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_COLUMN_FULL_WIDTH))
        case let .moveWorkspaceToMonitor(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_DIRECTION),
                direction: direction.controllerDirection
            )
        case .moveWorkspaceToMonitorNext:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_NEXT))
        case .moveWorkspaceToMonitorPrevious:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_WORKSPACE_TO_MONITOR_PREVIOUS))
        case let .swapWorkspaceWithMonitor(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWAP_WORKSPACE_WITH_MONITOR_DIRECTION),
                direction: direction.controllerDirection
            )
        case .balanceSizes:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_BALANCE_SIZES))
        case .moveToRoot:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_MOVE_TO_ROOT))
        case .toggleSplit:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_TOGGLE_SPLIT))
        case .swapSplit:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_SWAP_SPLIT))
        case let .resizeInDirection(direction, grow):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_RESIZE_DIRECTION),
                direction: direction.controllerDirection,
                monitorDirection: grow ? 1 : 0
            )
        case let .preselect(direction):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_DIRECTION),
                direction: direction.controllerDirection
            )
        case .preselectClear:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_DWINDLE_PRESELECT_CLEAR))
        case let .summonWorkspace(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SUMMON_WORKSPACE),
                workspaceIndex: Int64(index)
            )
        case .workspaceBackAndForth:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_WORKSPACE_BACK_AND_FORTH))
        case let .focusWorkspaceAnywhere(index):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_SWITCH_WORKSPACE_ANYWHERE),
                workspaceIndex: Int64(index)
            )
        case let .moveWindowToWorkspaceOnMonitor(workspaceIndex, monitorDirection):
            return .make(
                kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_MOVE_WINDOW_TO_WORKSPACE_ON_MONITOR),
                workspaceIndex: Int64(workspaceIndex),
                monitorDirection: monitorDirection.controllerDirection
            )
        case .openWindowFinder:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_OPEN_WINDOW_FINDER))
        case .raiseAllFloatingWindows:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_RAISE_ALL_FLOATING_WINDOWS))
        case .openMenuAnywhere:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_OPEN_MENU_ANYWHERE))
        case .openMenuPalette:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_OPEN_MENU_PALETTE))
        case .toggleHiddenBar:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_HIDDEN_BAR))
        case .toggleQuakeTerminal:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_QUAKE_TERMINAL))
        case .toggleWorkspaceLayout:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_WORKSPACE_LAYOUT))
        case .toggleOverview:
            return .make(kind: controllerRawValue(OMNI_CONTROLLER_COMMAND_TOGGLE_OVERVIEW))
        }
    }
}
