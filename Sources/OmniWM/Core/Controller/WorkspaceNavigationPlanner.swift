import Foundation
import OmniWMIPC

enum WorkspaceNavigationPlanner {
    enum Operation: Equatable {
        case focusMonitorCyclic
        case focusMonitorLast
        case swapWorkspaceWithMonitor
        case switchWorkspaceExplicit
        case switchWorkspaceRelative
        case focusWorkspaceAnywhere
        case workspaceBackAndForth
        case moveWindowAdjacent
        case moveWindowExplicit
        case moveColumnAdjacent
        case moveColumnExplicit
        case moveWindowToWorkspaceOnMonitor
        case moveWindowHandle
    }

    enum Outcome: Equatable {
        case noop
        case execute
        case invalidTarget
        case blocked
    }

    enum FocusAction: Equatable {
        case none
        case workspaceHandoff
        case resolveTargetIfPresent
        case subject
        case recoverSource
        case clearManagedFocus
    }

    enum Subject: Equatable {
        case none
        case window(WindowToken)
        case column(WindowToken)
    }

    struct Intent: Equatable {
        var operation: Operation
        var direction: Direction = .right
        var currentWorkspaceId: WorkspaceDescriptor.ID?
        var sourceWorkspaceId: WorkspaceDescriptor.ID?
        var targetWorkspaceId: WorkspaceDescriptor.ID?
        var currentMonitorId: Monitor.ID?
        var previousMonitorId: Monitor.ID?
        var subjectToken: WindowToken?
        var focusedToken: WindowToken?
        var wrapAround = false
        var followFocus = false
    }

    struct Plan: Equatable {
        var outcome: Outcome = .noop
        var subject: Subject = .none
        var focusAction: FocusAction = .none
        var resolvedFocusToken: WindowToken?
        var sourceWorkspaceId: WorkspaceDescriptor.ID?
        var targetWorkspaceId: WorkspaceDescriptor.ID?
        var materializeTargetWorkspaceRawID: String?
        var sourceMonitorId: Monitor.ID?
        var targetMonitorId: Monitor.ID?
        var saveWorkspaceIds: [WorkspaceDescriptor.ID] = []
        var affectedWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        var affectedMonitorIds: [Monitor.ID] = []
        var shouldActivateTargetWorkspace = false
        var shouldSetInteractionMonitor = false
        var shouldSyncMonitorsToNiri = false
        var shouldHideFocusBorder = false
        var shouldCommitWorkspaceTransition = false

        init(outcome: Outcome = .noop) {
            self.outcome = outcome
        }
    }

    struct Input {
        struct MonitorSnapshot {
            var monitorId: Monitor.ID
            var frameMinX: CGFloat
            var frameMaxY: CGFloat
            var centerX: CGFloat
            var centerY: CGFloat
            var activeWorkspaceId: WorkspaceDescriptor.ID?
            var previousWorkspaceId: WorkspaceDescriptor.ID?
        }

        struct WorkspaceSnapshot {
            enum LayoutKind {
                case defaultLayout
                case niri
                case dwindle
            }

            var workspaceId: WorkspaceDescriptor.ID
            var monitorId: Monitor.ID?
            var layoutKind: LayoutKind
            var rememberedTiledFocusToken: WindowToken?
            var firstTiledFocusToken: WindowToken?
            var rememberedFloatingFocusToken: WindowToken?
            var firstFloatingFocusToken: WindowToken?
        }

        struct FocusSessionSnapshot {
            var pendingManagedTiledFocusToken: WindowToken? = nil
            var pendingManagedTiledFocusWorkspaceId: WorkspaceDescriptor.ID? = nil
            var confirmedTiledFocusToken: WindowToken? = nil
            var confirmedTiledFocusWorkspaceId: WorkspaceDescriptor.ID? = nil
            var confirmedFloatingFocusToken: WindowToken? = nil
            var confirmedFloatingFocusWorkspaceId: WorkspaceDescriptor.ID? = nil
        }

        var intent: Intent
        var adjacentFallbackWorkspaceNumber: UInt32?
        var activeColumnSubjectToken: WindowToken?
        var selectedColumnSubjectToken: WindowToken?
        var focus: FocusSessionSnapshot
        var monitors: [MonitorSnapshot]
        var workspaces: [WorkspaceSnapshot]

        @MainActor
        static func capture(
            controller: WMController,
            intent: Intent
        ) -> Input {
            let manager = controller.workspaceManager

            let monitors = manager.monitors.map { monitor in
                MonitorSnapshot(
                    monitorId: monitor.id,
                    frameMinX: monitor.frame.minX,
                    frameMaxY: monitor.frame.maxY,
                    centerX: monitor.frame.midX,
                    centerY: monitor.frame.midY,
                    activeWorkspaceId: manager.activeWorkspace(on: monitor.id)?.id,
                    previousWorkspaceId: manager.previousWorkspace(on: monitor.id)?.id
                )
            }

            let workspaces = manager.workspaces.map { workspace in
                WorkspaceSnapshot(
                    workspaceId: workspace.id,
                    monitorId: manager.monitorId(for: workspace.id),
                    layoutKind: layoutKind(
                        controller.settings.layoutType(for: workspace.name)
                    ),
                    rememberedTiledFocusToken: eligibleFocusCandidate(
                        manager: manager,
                        token: manager.lastFocusedToken(in: workspace.id),
                        workspaceId: workspace.id,
                        mode: .tiling
                    ),
                    firstTiledFocusToken: firstEligibleFocusToken(
                        manager: manager,
                        workspaceId: workspace.id,
                        mode: .tiling
                    ),
                    rememberedFloatingFocusToken: eligibleFocusCandidate(
                        manager: manager,
                        token: manager.lastFloatingFocusedToken(in: workspace.id),
                        workspaceId: workspace.id,
                        mode: .floating
                    ),
                    firstFloatingFocusToken: firstEligibleFocusToken(
                        manager: manager,
                        workspaceId: workspace.id,
                        mode: .floating
                    )
                )
            }

            let focus = focusSessionSnapshot(manager: manager)
            let sourceWorkspaceId = intent.sourceWorkspaceId
            return Input(
                intent: intent,
                adjacentFallbackWorkspaceNumber: adjacentFallbackWorkspaceNumber(
                    controller: controller,
                    intent: intent
                ),
                activeColumnSubjectToken: sourceWorkspaceId.flatMap {
                    activeColumnSubjectToken(
                        controller: controller,
                        workspaceId: $0
                    )
                },
                selectedColumnSubjectToken: sourceWorkspaceId.flatMap {
                    selectedColumnSubjectToken(
                        controller: controller,
                        workspaceId: $0
                    )
                },
                focus: focus,
                monitors: monitors,
                workspaces: workspaces
            )
        }

        @MainActor
        private static func focusSessionSnapshot(
            manager: WorkspaceManager
        ) -> FocusSessionSnapshot {
            let pendingManagedTiled: (WindowToken, WorkspaceDescriptor.ID)?
            if let token = manager.pendingFocusedToken,
               let workspaceId = manager.pendingFocusedWorkspaceId,
               eligibleFocusCandidate(
                   manager: manager,
                   token: token,
                   workspaceId: workspaceId,
                   mode: .tiling
               ) != nil
            {
                pendingManagedTiled = (token, workspaceId)
            } else {
                pendingManagedTiled = nil
            }

            let confirmedManagedFocus: (WindowToken, WorkspaceDescriptor.ID, TrackedWindowMode)?
            if let token = manager.focusedToken,
               let entry = manager.entry(for: token),
               isFocusResolutionEligible(
                   entry,
                   in: entry.workspaceId,
                   mode: entry.mode
               )
            {
                confirmedManagedFocus = (token, entry.workspaceId, entry.mode)
            } else {
                confirmedManagedFocus = nil
            }

            let confirmedTiledToken: WindowToken?
            let confirmedTiledWorkspaceId: WorkspaceDescriptor.ID?
            let confirmedFloatingToken: WindowToken?
            let confirmedFloatingWorkspaceId: WorkspaceDescriptor.ID?
            if let confirmedManagedFocus {
                switch confirmedManagedFocus.2 {
                case .tiling:
                    confirmedTiledToken = confirmedManagedFocus.0
                    confirmedTiledWorkspaceId = confirmedManagedFocus.1
                    confirmedFloatingToken = nil
                    confirmedFloatingWorkspaceId = nil
                case .floating:
                    confirmedTiledToken = nil
                    confirmedTiledWorkspaceId = nil
                    confirmedFloatingToken = confirmedManagedFocus.0
                    confirmedFloatingWorkspaceId = confirmedManagedFocus.1
                }
            } else {
                confirmedTiledToken = nil
                confirmedTiledWorkspaceId = nil
                confirmedFloatingToken = nil
                confirmedFloatingWorkspaceId = nil
            }

            return FocusSessionSnapshot(
                pendingManagedTiledFocusToken: pendingManagedTiled?.0,
                pendingManagedTiledFocusWorkspaceId: pendingManagedTiled?.1,
                confirmedTiledFocusToken: confirmedTiledToken,
                confirmedTiledFocusWorkspaceId: confirmedTiledWorkspaceId,
                confirmedFloatingFocusToken: confirmedFloatingToken,
                confirmedFloatingFocusWorkspaceId: confirmedFloatingWorkspaceId
            )
        }

        @MainActor
        private static func activeColumnSubjectToken(
            controller: WMController,
            workspaceId: WorkspaceDescriptor.ID
        ) -> WindowToken? {
            guard let engine = controller.niriEngine else { return nil }
            let columns = engine.columns(in: workspaceId)
            guard !columns.isEmpty else { return nil }
            let state = controller.workspaceManager.niriViewportState(for: workspaceId)
            let clampedIndex = min(max(state.activeColumnIndex, 0), columns.count - 1)
            let column = columns[clampedIndex]
            return column.activeWindow?.token ?? column.windowNodes.first?.token
        }

        @MainActor
        private static func selectedColumnSubjectToken(
            controller: WMController,
            workspaceId: WorkspaceDescriptor.ID
        ) -> WindowToken? {
            guard let engine = controller.niriEngine else { return nil }
            let state = controller.workspaceManager.niriViewportState(for: workspaceId)
            guard let selectedNodeId = state.selectedNodeId,
                  let node = engine.findNode(by: selectedNodeId) as? NiriWindow
            else {
                return nil
            }
            return node.token
        }

        @MainActor
        private static func eligibleFocusCandidate(
            manager: WorkspaceManager,
            token: WindowToken?,
            workspaceId: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode
        ) -> WindowToken? {
            guard let token,
                  let entry = manager.entry(for: token),
                  isFocusResolutionEligible(entry, in: workspaceId, mode: mode)
            else {
                return nil
            }
            return token
        }

        @MainActor
        private static func firstEligibleFocusToken(
            manager: WorkspaceManager,
            workspaceId: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode
        ) -> WindowToken? {
            let entries: [WindowModel.Entry]
            switch mode {
            case .tiling:
                entries = manager.tiledEntries(in: workspaceId)
            case .floating:
                entries = manager.floatingEntries(in: workspaceId)
            }
            return entries.first {
                isFocusResolutionEligible($0, in: workspaceId, mode: mode)
            }?.token
        }

        private static func isFocusResolutionEligible(
            _ entry: WindowModel.Entry,
            in workspaceId: WorkspaceDescriptor.ID,
            mode: TrackedWindowMode
        ) -> Bool {
            guard entry.workspaceId == workspaceId,
                  entry.mode == mode
            else {
                return false
            }

            guard entry.hiddenProportionalPosition != nil else {
                return true
            }

            if case .workspaceInactive = entry.hiddenReason {
                return true
            }

            return false
        }

        @MainActor
        private static func adjacentFallbackWorkspaceNumber(
            controller: WMController,
            intent: Intent
        ) -> UInt32? {
            guard intent.operation == .moveWindowAdjacent || intent.operation == .moveColumnAdjacent,
                  let sourceWorkspaceId = intent.sourceWorkspaceId,
                  let currentWorkspaceName = controller.workspaceManager.descriptor(for: sourceWorkspaceId)?.name,
                  let currentWorkspaceNumber = WorkspaceIDPolicy.workspaceNumber(from: currentWorkspaceName)
            else {
                return nil
            }

            let candidateNumber = intent.direction == .down
                ? currentWorkspaceNumber + 1
                : currentWorkspaceNumber - 1
            guard let candidateRawID = WorkspaceIDPolicy.rawID(from: candidateNumber) else {
                return nil
            }

            let configuredWorkspaceNames = Set(controller.settings.workspaceConfigurations.map(\.name))
            guard configuredWorkspaceNames.contains(candidateRawID),
                  controller.workspaceManager.workspaceId(named: candidateRawID) == nil
            else {
                return nil
            }

            return UInt32(exactly: candidateNumber)
        }

        private static func layoutKind(
            _ layoutType: LayoutType
        ) -> WorkspaceSnapshot.LayoutKind {
            switch layoutType {
            case .defaultLayout:
                .defaultLayout
            case .niri:
                .niri
            case .dwindle:
                .dwindle
            }
        }
    }

    static func plan(_ input: Input) -> Plan {
        switch input.intent.operation {
        case .switchWorkspaceExplicit:
            planSwitchWorkspaceExplicit(input)
        case .switchWorkspaceRelative:
            planSwitchWorkspaceRelative(input)
        case .focusWorkspaceAnywhere:
            planFocusWorkspaceAnywhere(input)
        case .workspaceBackAndForth:
            planWorkspaceBackAndForth(input)
        case .focusMonitorCyclic:
            planFocusMonitorCyclic(input)
        case .focusMonitorLast:
            planFocusMonitorLast(input)
        case .swapWorkspaceWithMonitor:
            planSwapWorkspaceWithMonitor(input)
        case .moveWindowAdjacent:
            planMoveWindowAdjacent(input)
        case .moveColumnAdjacent:
            planMoveColumnAdjacent(input)
        case .moveColumnExplicit:
            planMoveColumnExplicit(input)
        case .moveWindowExplicit, .moveWindowHandle:
            planMoveWindowExplicit(input)
        case .moveWindowToWorkspaceOnMonitor:
            planMoveWindowToWorkspaceOnMonitor(input)
        }
    }
}

private extension WorkspaceNavigationPlanner {
    struct MonitorSelectionRank {
        var primary: CGFloat
        var secondary: CGFloat
        var distance: CGFloat?
    }

    enum MonitorSelectionMode {
        case directional
        case wrapped
    }

    static func planSwitchWorkspaceExplicit(_ input: Input) -> Plan {
        guard let targetIndex = explicitTargetWorkspaceIndex(input) else {
            return Plan(outcome: .invalidTarget)
        }
        let target = input.workspaces[targetIndex]
        guard let targetMonitorId = target.monitorId,
              findMonitorIndex(input.monitors, id: targetMonitorId) != nil
        else {
            return Plan(outcome: .invalidTarget)
        }
        if input.intent.currentWorkspaceId == target.workspaceId {
            return Plan(outcome: .noop)
        }

        var plan = Plan(outcome: .execute)
        plan.shouldHideFocusBorder = true
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: target)
        setWorkspaceTransitionFocus(input, plan: &plan, workspace: target, executeAction: .workspaceHandoff)
        if let currentWorkspaceId = input.intent.currentWorkspaceId {
            appendUnique(&plan.saveWorkspaceIds, value: currentWorkspaceId)
        }
        return plan
    }

    static func planSwitchWorkspaceRelative(_ input: Input) -> Plan {
        guard let currentMonitorId = input.intent.currentMonitorId,
              let currentWorkspaceId = input.intent.currentWorkspaceId
        else {
            return Plan(outcome: .blocked)
        }
        guard let targetIndex = relativeWorkspaceOnMonitor(
            input.workspaces,
            monitorId: currentMonitorId,
            currentWorkspaceId: currentWorkspaceId,
            offset: directionOffset(input.intent.direction),
            wrapAround: input.intent.wrapAround
        ) else {
            return Plan(outcome: .noop)
        }

        let target = input.workspaces[targetIndex]
        var plan = Plan(outcome: .execute)
        plan.shouldHideFocusBorder = true
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: target)
        setWorkspaceTransitionFocus(input, plan: &plan, workspace: target, executeAction: .workspaceHandoff)
        appendUnique(&plan.saveWorkspaceIds, value: currentWorkspaceId)
        return plan
    }

    static func planFocusWorkspaceAnywhere(_ input: Input) -> Plan {
        guard let targetIndex = explicitTargetWorkspaceIndex(input) else {
            return Plan(outcome: .invalidTarget)
        }
        let target = input.workspaces[targetIndex]
        guard let targetMonitorId = target.monitorId,
              findMonitorIndex(input.monitors, id: targetMonitorId) != nil
        else {
            return Plan(outcome: .invalidTarget)
        }

        var plan = Plan(outcome: .execute)
        plan.shouldHideFocusBorder = true
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldSyncMonitorsToNiri = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: target)
        setWorkspaceTransitionFocus(input, plan: &plan, workspace: target, executeAction: .workspaceHandoff)
        if let currentWorkspaceId = input.intent.currentWorkspaceId {
            appendUnique(&plan.saveWorkspaceIds, value: currentWorkspaceId)
        }
        if let currentMonitorId = input.intent.currentMonitorId,
           currentMonitorId != targetMonitorId,
           let visibleTargetIndex = activeOrFirstWorkspaceOnMonitor(
               input.monitors,
               input.workspaces,
               monitorId: targetMonitorId
           )
        {
            appendUnique(&plan.saveWorkspaceIds, value: input.workspaces[visibleTargetIndex].workspaceId)
        }
        return plan
    }

    static func planWorkspaceBackAndForth(_ input: Input) -> Plan {
        guard let currentMonitorId = input.intent.currentMonitorId,
              let currentMonitorIndex = findMonitorIndex(input.monitors, id: currentMonitorId)
        else {
            return Plan(outcome: .blocked)
        }
        let currentMonitor = input.monitors[currentMonitorIndex]
        guard let previousWorkspaceId = currentMonitor.previousWorkspaceId else {
            return Plan(outcome: .noop)
        }
        if previousWorkspaceId == currentMonitor.activeWorkspaceId {
            return Plan(outcome: .noop)
        }
        guard let targetIndex = findWorkspaceIndex(input.workspaces, id: previousWorkspaceId) else {
            return Plan(outcome: .noop)
        }

        let target = input.workspaces[targetIndex]
        var plan = Plan(outcome: .execute)
        plan.shouldHideFocusBorder = true
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: target)
        setWorkspaceTransitionFocus(input, plan: &plan, workspace: target, executeAction: .workspaceHandoff)
        if let currentWorkspaceId = input.intent.currentWorkspaceId {
            appendUnique(&plan.saveWorkspaceIds, value: currentWorkspaceId)
        }
        return plan
    }

    static func planFocusMonitorCyclic(_ input: Input) -> Plan {
        guard let currentMonitorId = input.intent.currentMonitorId else {
            return Plan(outcome: .blocked)
        }
        guard let targetMonitorIndex = cyclicMonitorIndex(
            input.monitors,
            currentMonitorId: currentMonitorId,
            previous: input.intent.direction == .left || input.intent.direction == .up
        ) else {
            return Plan(outcome: .noop)
        }
        let targetMonitor = input.monitors[targetMonitorIndex]
        guard let targetWorkspaceIndex = activeOrFirstWorkspaceOnMonitor(
            input.monitors,
            input.workspaces,
            monitorId: targetMonitor.monitorId
        ) else {
            return Plan(outcome: .noop)
        }

        let targetWorkspace = input.workspaces[targetWorkspaceIndex]
        var plan = Plan(outcome: .execute)
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: targetWorkspace)
        setWorkspaceTransitionFocus(
            input,
            plan: &plan,
            workspace: targetWorkspace,
            executeAction: .resolveTargetIfPresent
        )
        plan.affectedWorkspaceIds.insert(targetWorkspace.workspaceId)
        appendUnique(&plan.affectedMonitorIds, value: targetMonitor.monitorId)
        return plan
    }

    static func planFocusMonitorLast(_ input: Input) -> Plan {
        guard let currentMonitorId = input.intent.currentMonitorId,
              let previousMonitorId = input.intent.previousMonitorId
        else {
            return Plan(outcome: .blocked)
        }
        if currentMonitorId == previousMonitorId {
            return Plan(outcome: .noop)
        }
        guard findMonitorIndex(input.monitors, id: previousMonitorId) != nil else {
            return Plan(outcome: .noop)
        }
        guard let targetWorkspaceIndex = activeOrFirstWorkspaceOnMonitor(
            input.monitors,
            input.workspaces,
            monitorId: previousMonitorId
        ) else {
            return Plan(outcome: .noop)
        }

        let targetWorkspace = input.workspaces[targetWorkspaceIndex]
        var plan = Plan(outcome: .execute)
        plan.shouldActivateTargetWorkspace = true
        plan.shouldSetInteractionMonitor = true
        plan.shouldCommitWorkspaceTransition = true
        setTargetWorkspace(&plan, workspace: targetWorkspace)
        setWorkspaceTransitionFocus(
            input,
            plan: &plan,
            workspace: targetWorkspace,
            executeAction: .resolveTargetIfPresent
        )
        plan.affectedWorkspaceIds.insert(targetWorkspace.workspaceId)
        appendUnique(&plan.affectedMonitorIds, value: previousMonitorId)
        return plan
    }

    static func planSwapWorkspaceWithMonitor(_ input: Input) -> Plan {
        guard let currentMonitorId = input.intent.currentMonitorId,
              let currentWorkspaceId = input.intent.currentWorkspaceId,
              let sourceIndex = findWorkspaceIndex(input.workspaces, id: currentWorkspaceId)
        else {
            return Plan(outcome: .blocked)
        }
        guard let targetMonitorIndex = adjacentMonitorIndex(
            input.monitors,
            currentMonitorId: currentMonitorId,
            direction: input.intent.direction,
            wrapAround: false
        ) else {
            return Plan(outcome: .noop)
        }
        let targetMonitor = input.monitors[targetMonitorIndex]
        guard let targetWorkspaceIndex = activeOrFirstWorkspaceOnMonitor(
            input.monitors,
            input.workspaces,
            monitorId: targetMonitor.monitorId
        ) else {
            return Plan(outcome: .noop)
        }

        let source = input.workspaces[sourceIndex]
        let target = input.workspaces[targetWorkspaceIndex]
        var plan = Plan(outcome: .execute)
        plan.shouldSyncMonitorsToNiri = true
        plan.shouldCommitWorkspaceTransition = true
        setSourceWorkspace(&plan, workspace: source)
        setTargetWorkspace(&plan, workspace: target)
        setWorkspaceTransitionFocus(
            input,
            plan: &plan,
            workspace: target,
            executeAction: .resolveTargetIfPresent
        )
        appendUnique(&plan.saveWorkspaceIds, value: source.workspaceId)
        plan.affectedWorkspaceIds.insert(source.workspaceId)
        plan.affectedWorkspaceIds.insert(target.workspaceId)
        appendUnique(&plan.affectedMonitorIds, value: currentMonitorId)
        appendUnique(&plan.affectedMonitorIds, value: targetMonitor.monitorId)
        return plan
    }

    static func planMoveWindowAdjacent(_ input: Input) -> Plan {
        guard let sourceIndex = sourceWorkspaceIndex(input) else {
            return Plan(outcome: .blocked)
        }
        guard let focusedToken = input.intent.focusedToken else {
            return Plan(outcome: .blocked)
        }
        guard let currentMonitorId = input.intent.currentMonitorId else {
            return Plan(outcome: .blocked)
        }

        let source = input.workspaces[sourceIndex]
        if let targetIndex = relativeWorkspaceOnMonitor(
            input.workspaces,
            monitorId: currentMonitorId,
            currentWorkspaceId: source.workspaceId,
            offset: movementOffset(input.intent.direction),
            wrapAround: false
        ) {
            return commitTransferPlan(
                input: input,
                sourceWorkspace: source,
                targetWorkspace: input.workspaces[targetIndex],
                subject: .window(focusedToken),
                followFocus: false,
                commitTransition: true,
                saveSourceWorkspace: true
            )
        }

        guard let fallbackWorkspaceNumber = input.adjacentFallbackWorkspaceNumber else {
            return Plan(outcome: .noop)
        }
        return commitMaterializedTransferPlan(
            sourceWorkspace: source,
            targetMonitorId: currentMonitorId,
            targetWorkspaceNumber: fallbackWorkspaceNumber,
            subject: .window(focusedToken)
        )
    }

    static func planMoveColumnAdjacent(_ input: Input) -> Plan {
        guard let sourceIndex = sourceWorkspaceIndex(input) else {
            return Plan(outcome: .blocked)
        }
        let source = input.workspaces[sourceIndex]
        guard source.layoutKind == .niri,
              let activeColumnSubjectToken = input.activeColumnSubjectToken
        else {
            return Plan(outcome: .blocked)
        }
        guard let currentMonitorId = input.intent.currentMonitorId else {
            return Plan(outcome: .blocked)
        }

        if let targetIndex = relativeWorkspaceOnMonitor(
            input.workspaces,
            monitorId: currentMonitorId,
            currentWorkspaceId: source.workspaceId,
            offset: movementOffset(input.intent.direction),
            wrapAround: false
        ) {
            return commitTransferPlan(
                input: input,
                sourceWorkspace: source,
                targetWorkspace: input.workspaces[targetIndex],
                subject: .column(activeColumnSubjectToken),
                followFocus: false,
                commitTransition: true,
                saveSourceWorkspace: true
            )
        }

        guard let fallbackWorkspaceNumber = input.adjacentFallbackWorkspaceNumber else {
            return Plan(outcome: .noop)
        }
        return commitMaterializedTransferPlan(
            sourceWorkspace: source,
            targetMonitorId: currentMonitorId,
            targetWorkspaceNumber: fallbackWorkspaceNumber,
            subject: .column(activeColumnSubjectToken)
        )
    }

    static func planMoveColumnExplicit(_ input: Input) -> Plan {
        guard let sourceIndex = sourceWorkspaceIndex(input) else {
            return Plan(outcome: .blocked)
        }
        let source = input.workspaces[sourceIndex]
        let subjectToken = input.activeColumnSubjectToken ?? input.selectedColumnSubjectToken
        guard source.layoutKind == .niri,
              let subjectToken
        else {
            return Plan(outcome: .blocked)
        }
        guard let targetIndex = explicitTargetWorkspaceIndex(input) else {
            return Plan(outcome: .invalidTarget)
        }

        let target = input.workspaces[targetIndex]
        if source.workspaceId == target.workspaceId {
            return Plan(outcome: .noop)
        }
        return commitTransferPlan(
            input: input,
            sourceWorkspace: source,
            targetWorkspace: target,
            subject: .column(subjectToken),
            followFocus: false,
            commitTransition: true,
            saveSourceWorkspace: true
        )
    }

    static func planMoveWindowExplicit(_ input: Input) -> Plan {
        guard let targetIndex = explicitTargetWorkspaceIndex(input) else {
            return Plan(outcome: .invalidTarget)
        }
        let target = input.workspaces[targetIndex]
        let sourceIndex = sourceWorkspaceIndex(input)
        let subjectToken = input.intent.subjectToken ?? input.intent.focusedToken
        guard let subjectToken else {
            return Plan(outcome: .blocked)
        }
        if let sourceIndex,
           input.workspaces[sourceIndex].workspaceId == target.workspaceId
        {
            return Plan(outcome: .noop)
        }
        return commitTransferPlan(
            input: input,
            sourceWorkspace: sourceIndex.map { input.workspaces[$0] },
            targetWorkspace: target,
            subject: .window(subjectToken),
            followFocus: input.intent.followFocus,
            commitTransition: input.intent.operation != .moveWindowHandle,
            saveSourceWorkspace: false
        )
    }

    static func planMoveWindowToWorkspaceOnMonitor(_ input: Input) -> Plan {
        guard let sourceIndex = sourceWorkspaceIndex(input),
              let currentMonitorId = input.intent.currentMonitorId,
              let focusedToken = input.intent.focusedToken
        else {
            return Plan(outcome: .blocked)
        }
        guard let targetMonitorIndex = adjacentMonitorIndex(
            input.monitors,
            currentMonitorId: currentMonitorId,
            direction: input.intent.direction,
            wrapAround: false
        ) else {
            return Plan(outcome: .noop)
        }
        let targetMonitor = input.monitors[targetMonitorIndex]
        guard let targetIndex = explicitTargetWorkspaceIndex(input) else {
            return Plan(outcome: .invalidTarget)
        }
        let target = input.workspaces[targetIndex]
        guard target.monitorId == targetMonitor.monitorId else {
            return Plan(outcome: .invalidTarget)
        }
        if input.workspaces[sourceIndex].workspaceId == target.workspaceId {
            return Plan(outcome: .noop)
        }
        return commitTransferPlan(
            input: input,
            sourceWorkspace: input.workspaces[sourceIndex],
            targetWorkspace: target,
            subject: .window(focusedToken),
            followFocus: input.intent.followFocus,
            commitTransition: true,
            saveSourceWorkspace: false
        )
    }

    static func commitTransferPlan(
        input: Input,
        sourceWorkspace: Input.WorkspaceSnapshot?,
        targetWorkspace: Input.WorkspaceSnapshot,
        subject: Subject,
        followFocus: Bool,
        commitTransition: Bool,
        saveSourceWorkspace: Bool
    ) -> Plan {
        var plan = Plan(outcome: .execute)
        plan.focusAction = followFocus ? .subject : .recoverSource
        plan.shouldCommitWorkspaceTransition = commitTransition
        plan.shouldActivateTargetWorkspace = followFocus
        plan.shouldSetInteractionMonitor = followFocus
        plan.subject = subject
        setTargetWorkspace(&plan, workspace: targetWorkspace)
        plan.affectedWorkspaceIds.insert(targetWorkspace.workspaceId)
        if let targetMonitorId = plan.targetMonitorId {
            appendUnique(&plan.affectedMonitorIds, value: targetMonitorId)
        }

        if let sourceWorkspace {
            setSourceWorkspace(&plan, workspace: sourceWorkspace)
            if saveSourceWorkspace {
                appendUnique(&plan.saveWorkspaceIds, value: sourceWorkspace.workspaceId)
            }
            plan.affectedWorkspaceIds.insert(sourceWorkspace.workspaceId)
            if let sourceMonitorId = plan.sourceMonitorId {
                appendUnique(&plan.affectedMonitorIds, value: sourceMonitorId)
            }
        }

        return plan
    }

    static func commitMaterializedTransferPlan(
        sourceWorkspace: Input.WorkspaceSnapshot,
        targetMonitorId: Monitor.ID,
        targetWorkspaceNumber: UInt32,
        subject: Subject
    ) -> Plan {
        var plan = Plan(outcome: .execute)
        plan.focusAction = .recoverSource
        plan.shouldCommitWorkspaceTransition = true
        plan.materializeTargetWorkspaceRawID = WorkspaceIDPolicy.rawID(
            from: Int(targetWorkspaceNumber)
        )
        plan.targetMonitorId = targetMonitorId
        plan.subject = subject
        setSourceWorkspace(&plan, workspace: sourceWorkspace)
        appendUnique(&plan.saveWorkspaceIds, value: sourceWorkspace.workspaceId)
        plan.affectedWorkspaceIds.insert(sourceWorkspace.workspaceId)
        if let sourceMonitorId = plan.sourceMonitorId {
            appendUnique(&plan.affectedMonitorIds, value: sourceMonitorId)
        }
        appendUnique(&plan.affectedMonitorIds, value: targetMonitorId)
        return plan
    }

    static func resolveWorkspaceFocusToken(
        _ input: Input,
        workspace: Input.WorkspaceSnapshot
    ) -> WindowToken? {
        if let token = workspace.rememberedTiledFocusToken {
            return token
        }
        if input.focus.pendingManagedTiledFocusWorkspaceId == workspace.workspaceId,
           let token = input.focus.pendingManagedTiledFocusToken
        {
            return token
        }
        if input.focus.confirmedTiledFocusWorkspaceId == workspace.workspaceId,
           let token = input.focus.confirmedTiledFocusToken
        {
            return token
        }
        if let token = workspace.firstTiledFocusToken {
            return token
        }
        if let token = workspace.rememberedFloatingFocusToken {
            return token
        }
        if input.focus.confirmedFloatingFocusWorkspaceId == workspace.workspaceId,
           let token = input.focus.confirmedFloatingFocusToken
        {
            return token
        }
        return workspace.firstFloatingFocusToken
    }

    static func setWorkspaceTransitionFocus(
        _ input: Input,
        plan: inout Plan,
        workspace: Input.WorkspaceSnapshot,
        executeAction: FocusAction
    ) {
        let resolvedFocus = resolveWorkspaceFocusToken(input, workspace: workspace)
        plan.focusAction = resolvedFocus == nil ? .clearManagedFocus : executeAction
        plan.resolvedFocusToken = resolvedFocus
    }

    static func setSourceWorkspace(
        _ plan: inout Plan,
        workspace: Input.WorkspaceSnapshot
    ) {
        plan.sourceWorkspaceId = workspace.workspaceId
        plan.sourceMonitorId = workspace.monitorId
    }

    static func setTargetWorkspace(
        _ plan: inout Plan,
        workspace: Input.WorkspaceSnapshot
    ) {
        plan.targetWorkspaceId = workspace.workspaceId
        plan.targetMonitorId = workspace.monitorId
    }

    static func appendUnique<T: Equatable>(
        _ values: inout [T],
        value: T
    ) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    static func sourceWorkspaceIndex(_ input: Input) -> Int? {
        guard let sourceWorkspaceId = input.intent.sourceWorkspaceId else { return nil }
        return findWorkspaceIndex(input.workspaces, id: sourceWorkspaceId)
    }

    static func explicitTargetWorkspaceIndex(_ input: Input) -> Int? {
        guard let targetWorkspaceId = input.intent.targetWorkspaceId else { return nil }
        return findWorkspaceIndex(input.workspaces, id: targetWorkspaceId)
    }

    static func findMonitorIndex(
        _ monitors: [Input.MonitorSnapshot],
        id: Monitor.ID
    ) -> Int? {
        monitors.firstIndex { $0.monitorId == id }
    }

    static func findWorkspaceIndex(
        _ workspaces: [Input.WorkspaceSnapshot],
        id: WorkspaceDescriptor.ID
    ) -> Int? {
        workspaces.firstIndex { $0.workspaceId == id }
    }

    static func workspaceCountOnMonitor(
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID
    ) -> Int {
        workspaces.reduce(into: 0) { count, workspace in
            if workspace.monitorId == monitorId {
                count += 1
            }
        }
    }

    static func workspaceIndexOnMonitor(
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID,
        workspaceId: WorkspaceDescriptor.ID
    ) -> Int? {
        var filteredIndex = 0
        for workspace in workspaces where workspace.monitorId == monitorId {
            if workspace.workspaceId == workspaceId {
                return filteredIndex
            }
            filteredIndex += 1
        }
        return nil
    }

    static func workspaceAtMonitorIndex(
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID,
        desiredIndex: Int
    ) -> Int? {
        var filteredIndex = 0
        for (index, workspace) in workspaces.enumerated() where workspace.monitorId == monitorId {
            if filteredIndex == desiredIndex {
                return index
            }
            filteredIndex += 1
        }
        return nil
    }

    static func firstWorkspaceOnMonitor(
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID
    ) -> Int? {
        workspaces.firstIndex { $0.monitorId == monitorId }
    }

    static func activeOrFirstWorkspaceOnMonitor(
        _ monitors: [Input.MonitorSnapshot],
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID
    ) -> Int? {
        if let monitorIndex = findMonitorIndex(monitors, id: monitorId),
           let activeWorkspaceId = monitors[monitorIndex].activeWorkspaceId,
           let workspaceIndex = findWorkspaceIndex(workspaces, id: activeWorkspaceId)
        {
            return workspaceIndex
        }
        return firstWorkspaceOnMonitor(workspaces, monitorId: monitorId)
    }

    static func relativeWorkspaceOnMonitor(
        _ workspaces: [Input.WorkspaceSnapshot],
        monitorId: Monitor.ID,
        currentWorkspaceId: WorkspaceDescriptor.ID,
        offset: Int,
        wrapAround: Bool
    ) -> Int? {
        let count = workspaceCountOnMonitor(workspaces, monitorId: monitorId)
        guard count > 1 else { return nil }
        guard let currentIndex = workspaceIndexOnMonitor(
            workspaces,
            monitorId: monitorId,
            workspaceId: currentWorkspaceId
        ) else {
            return nil
        }

        let desired = currentIndex + offset
        if wrapAround {
            let wrapped = ((desired % count) + count) % count
            return workspaceAtMonitorIndex(workspaces, monitorId: monitorId, desiredIndex: wrapped)
        }
        guard desired >= 0, desired < count else { return nil }
        return workspaceAtMonitorIndex(workspaces, monitorId: monitorId, desiredIndex: desired)
    }

    static func directionOffset(_ direction: Direction) -> Int {
        switch direction {
        case .right, .down:
            1
        case .left, .up:
            -1
        }
    }

    static func movementOffset(_ direction: Direction) -> Int {
        direction == .down ? 1 : -1
    }

    static func monitorSortLess(
        _ lhs: Input.MonitorSnapshot,
        _ rhs: Input.MonitorSnapshot
    ) -> Bool {
        if lhs.frameMinX != rhs.frameMinX {
            return lhs.frameMinX < rhs.frameMinX
        }
        if lhs.frameMaxY != rhs.frameMaxY {
            return lhs.frameMaxY > rhs.frameMaxY
        }
        return lhs.monitorId.displayId < rhs.monitorId.displayId
    }

    static func monitorSortLess(
        _ monitors: [Input.MonitorSnapshot],
        lhsIndex: Int,
        rhsIndex: Int
    ) -> Bool {
        let lhs = monitors[lhsIndex]
        let rhs = monitors[rhsIndex]
        if lhs.frameMinX != rhs.frameMinX {
            return lhs.frameMinX < rhs.frameMinX
        }
        if lhs.frameMaxY != rhs.frameMaxY {
            return lhs.frameMaxY > rhs.frameMaxY
        }
        return lhsIndex < rhsIndex
    }

    static func cyclicMonitorIndex(
        _ monitors: [Input.MonitorSnapshot],
        currentMonitorId: Monitor.ID,
        previous: Bool
    ) -> Int? {
        guard monitors.count > 1,
              let currentIndex = findMonitorIndex(monitors, id: currentMonitorId)
        else {
            return nil
        }
        let sortedIndices = monitors.indices.sorted { lhs, rhs in
            monitorSortLess(monitors, lhsIndex: lhs, rhsIndex: rhs)
        }
        guard let currentRank = sortedIndices.firstIndex(of: currentIndex) else {
            return nil
        }
        let desiredRank = previous
            ? (currentRank > 0 ? currentRank - 1 : sortedIndices.count - 1)
            : ((currentRank + 1) % sortedIndices.count)
        return sortedIndices[desiredRank]
    }

    static func adjacentMonitorIndex(
        _ monitors: [Input.MonitorSnapshot],
        currentMonitorId: Monitor.ID,
        direction: Direction,
        wrapAround: Bool
    ) -> Int? {
        guard let currentIndex = findMonitorIndex(monitors, id: currentMonitorId) else {
            return nil
        }
        let current = monitors[currentIndex]
        var bestDirectional: Int?
        var bestWrapped: Int?

        for (candidateIndex, candidate) in monitors.enumerated() where candidate.monitorId != current.monitorId {
            let dx = candidate.centerX - current.centerX
            let dy = candidate.centerY - current.centerY
            let isDirectional: Bool
            switch direction {
            case .left:
                isDirectional = dx < 0
            case .right:
                isDirectional = dx > 0
            case .up:
                isDirectional = dy > 0
            case .down:
                isDirectional = dy < 0
            }

            if isDirectional {
                if let currentBest = bestDirectional {
                    if betterMonitorCandidate(
                        lhs: candidate,
                        rhs: monitors[currentBest],
                        current: current,
                        direction: direction,
                        mode: .directional
                    ) {
                        bestDirectional = candidateIndex
                    }
                } else {
                    bestDirectional = candidateIndex
                }
            }

            if wrapAround {
                if let currentBest = bestWrapped {
                    if betterMonitorCandidate(
                        lhs: candidate,
                        rhs: monitors[currentBest],
                        current: current,
                        direction: direction,
                        mode: .wrapped
                    ) {
                        bestWrapped = candidateIndex
                    }
                } else {
                    bestWrapped = candidateIndex
                }
            }
        }

        return bestDirectional ?? bestWrapped
    }

    static func betterMonitorCandidate(
        lhs: Input.MonitorSnapshot,
        rhs: Input.MonitorSnapshot,
        current: Input.MonitorSnapshot,
        direction: Direction,
        mode: MonitorSelectionMode
    ) -> Bool {
        let lhsRank = monitorSelectionRank(candidate: lhs, current: current, direction: direction, mode: mode)
        let rhsRank = monitorSelectionRank(candidate: rhs, current: current, direction: direction, mode: mode)

        if lhsRank.primary != rhsRank.primary {
            return lhsRank.primary < rhsRank.primary
        }
        if lhsRank.secondary != rhsRank.secondary {
            return lhsRank.secondary < rhsRank.secondary
        }
        if let lhsDistance = lhsRank.distance,
           let rhsDistance = rhsRank.distance,
           lhsDistance != rhsDistance
        {
            return lhsDistance < rhsDistance
        }
        return monitorSortLess(lhs, rhs)
    }

    static func monitorSelectionRank(
        candidate: Input.MonitorSnapshot,
        current: Input.MonitorSnapshot,
        direction: Direction,
        mode: MonitorSelectionMode
    ) -> MonitorSelectionRank {
        let dx = candidate.centerX - current.centerX
        let dy = candidate.centerY - current.centerY

        switch mode {
        case .directional:
            switch direction {
            case .left, .right:
                return .init(primary: abs(dx), secondary: abs(dy), distance: dx * dx + dy * dy)
            case .up, .down:
                return .init(primary: abs(dy), secondary: abs(dx), distance: dx * dx + dy * dy)
            }
        case .wrapped:
            switch direction {
            case .right:
                return .init(primary: candidate.centerX, secondary: abs(dy), distance: nil)
            case .left:
                return .init(primary: -candidate.centerX, secondary: abs(dy), distance: nil)
            case .up:
                return .init(primary: candidate.centerY, secondary: abs(dx), distance: nil)
            case .down:
                return .init(primary: -candidate.centerY, secondary: abs(dx), distance: nil)
            }
        }
    }
}
