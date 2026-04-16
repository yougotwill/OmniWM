import Foundation

enum RefreshPlannerEvent: Equatable {
    case requested(RefreshRequestEvent)
    case completed(RefreshCompletionEvent)
}

struct RefreshPlannerResult: Equatable {
    var snapshot: RefreshOrchestrationSnapshot
    var decision: OrchestrationDecision
    var plan: OrchestrationPlan

    func asOrchestrationResult(
        focus: FocusOrchestrationSnapshot
    ) -> OrchestrationResult {
        OrchestrationResult(
            snapshot: .init(
                refresh: snapshot,
                focus: focus
            ),
            decision: decision,
            plan: plan
        )
    }
}

enum RefreshPlanner {
    static func step(
        snapshot: RefreshOrchestrationSnapshot,
        event: RefreshPlannerEvent
    ) -> RefreshPlannerResult {
        switch event {
        case let .requested(request):
            reduceRequest(snapshot: snapshot, request: request)
        case let .completed(completion):
            reduceCompletion(snapshot: snapshot, completion: completion)
        }
    }

    private static func reduceRequest(
        snapshot: RefreshOrchestrationSnapshot,
        request: RefreshRequestEvent
    ) -> RefreshPlannerResult {
        if request.shouldDropWhileBusy,
           request.isIncrementalRefreshInProgress
            || request.isImmediateLayoutInProgress
            || request.hasActiveAnimationRefreshes
        {
            return .init(
                snapshot: snapshot,
                decision: .refreshDropped(reason: request.refresh.reason),
                plan: .init()
            )
        }

        if let activeRefresh = snapshot.activeRefresh {
            let handled = handleRefresh(
                request.refresh,
                activeRefresh: activeRefresh,
                pendingRefresh: snapshot.pendingRefresh
            )
            return .init(
                snapshot: .init(
                    activeRefresh: handled.activeRefresh,
                    pendingRefresh: handled.pendingRefresh
                ),
                decision: handled.decision,
                plan: .init(actions: handled.actions)
            )
        }

        let hadPendingRefresh = snapshot.pendingRefresh != nil
        let mergedRefresh = mergePendingRefresh(
            snapshot.pendingRefresh,
            incoming: request.refresh
        )
        return .init(
            snapshot: .init(
                activeRefresh: mergedRefresh,
                pendingRefresh: nil
            ),
            decision: hadPendingRefresh
                ? .refreshMerged(cycleId: mergedRefresh.cycleId, kind: mergedRefresh.kind)
                : .refreshQueued(cycleId: mergedRefresh.cycleId, kind: mergedRefresh.kind),
            plan: .init(actions: [.startRefresh(mergedRefresh)])
        )
    }

    private static func reduceCompletion(
        snapshot: RefreshOrchestrationSnapshot,
        completion: RefreshCompletionEvent
    ) -> RefreshPlannerResult {
        var updatedSnapshot = snapshot
        let completedRefresh = updatedSnapshot.activeRefresh ?? completion.refresh
        updatedSnapshot.activeRefresh = nil

        var actions: [OrchestrationPlan.Action] = []

        if completion.didComplete {
            if completion.didExecutePlan {
                if !completedRefresh.postLayoutAttachmentIds.isEmpty {
                    actions.append(
                        .discardPostLayoutAttachments(completedRefresh.postLayoutAttachmentIds)
                    )
                }
            } else {
                if completedRefresh.kind != .visibilityRefresh,
                   completedRefresh.needsVisibilityReconciliation
                {
                    actions.append(.performVisibilitySideEffects)
                    actions.append(.requestWorkspaceBarRefresh)
                }
                if !completedRefresh.postLayoutAttachmentIds.isEmpty {
                    actions.append(
                        .runPostLayoutAttachments(completedRefresh.postLayoutAttachmentIds)
                    )
                }
            }

            if let followUp = completedRefresh.followUpRefresh {
                let followUpRefresh = ScheduledRefresh(
                    cycleId: completedRefresh.cycleId &+ 1,
                    kind: followUp.kind,
                    reason: followUp.reason,
                    affectedWorkspaceIds: followUp.affectedWorkspaceIds
                )
                updatedSnapshot.pendingRefresh = mergePendingRefresh(
                    updatedSnapshot.pendingRefresh,
                    incoming: followUpRefresh
                )
            }
        } else {
            updatedSnapshot.pendingRefresh = preserveCancelledRefreshState(
                completedRefresh,
                pendingRefresh: updatedSnapshot.pendingRefresh
            )
        }

        if let pendingRefresh = updatedSnapshot.pendingRefresh {
            updatedSnapshot.activeRefresh = pendingRefresh
            updatedSnapshot.pendingRefresh = nil
            actions.append(.startRefresh(pendingRefresh))
        }

        return .init(
            snapshot: updatedSnapshot,
            decision: .refreshCompleted(
                cycleId: completedRefresh.cycleId,
                didComplete: completion.didComplete
            ),
            plan: .init(actions: actions)
        )
    }

    private static func handleRefresh(
        _ refresh: ScheduledRefresh,
        activeRefresh: ScheduledRefresh,
        pendingRefresh: ScheduledRefresh?
    ) -> (
        activeRefresh: ScheduledRefresh,
        pendingRefresh: ScheduledRefresh?,
        decision: OrchestrationDecision,
        actions: [OrchestrationPlan.Action]
    ) {
        var updatedActiveRefresh = activeRefresh
        var updatedPendingRefresh = pendingRefresh
        var actions: [OrchestrationPlan.Action] = []

        switch activeRefresh.kind {
        case .fullRescan:
            switch refresh.kind {
            case .visibilityRefresh:
                updatedActiveRefresh = absorbIntoActiveFullRescan(
                    activeRefresh,
                    refresh: refresh
                )
                return (
                    updatedActiveRefresh,
                    updatedPendingRefresh,
                    .refreshMerged(
                        cycleId: updatedActiveRefresh.cycleId,
                        kind: updatedActiveRefresh.kind
                    ),
                    actions
                )
            default:
                updatedPendingRefresh = mergePendingRefresh(
                    updatedPendingRefresh,
                    incoming: refresh
                )
            }

        case .visibilityRefresh:
            updatedPendingRefresh = mergePendingRefresh(
                updatedPendingRefresh,
                incoming: refresh
            )

        case .windowRemoval:
            updatedPendingRefresh = mergePendingRefresh(
                updatedPendingRefresh,
                incoming: refresh
            )

        case .immediateRelayout:
            switch refresh.kind {
            case .fullRescan, .immediateRelayout, .windowRemoval:
                updatedPendingRefresh = mergePendingRefresh(
                    updatedPendingRefresh,
                    incoming: refresh
                )
                actions.append(.cancelActiveRefresh(cycleId: activeRefresh.cycleId))
                return (
                    updatedActiveRefresh,
                    updatedPendingRefresh,
                    .refreshSuperseded(
                        activeCycleId: activeRefresh.cycleId,
                        pendingCycleId: updatedPendingRefresh?.cycleId ?? refresh.cycleId
                    ),
                    actions
                )
            case .relayout, .visibilityRefresh:
                updatedPendingRefresh = mergePendingRefresh(
                    updatedPendingRefresh,
                    incoming: refresh
                )
            }

        case .relayout:
            switch refresh.kind {
            case .fullRescan, .immediateRelayout, .relayout, .windowRemoval:
                updatedPendingRefresh = mergePendingRefresh(
                    updatedPendingRefresh,
                    incoming: refresh
                )
                actions.append(.cancelActiveRefresh(cycleId: activeRefresh.cycleId))
                return (
                    updatedActiveRefresh,
                    updatedPendingRefresh,
                    .refreshSuperseded(
                        activeCycleId: activeRefresh.cycleId,
                        pendingCycleId: updatedPendingRefresh?.cycleId ?? refresh.cycleId
                    ),
                    actions
                )
            case .visibilityRefresh:
                updatedPendingRefresh = mergePendingRefresh(
                    updatedPendingRefresh,
                    incoming: refresh
                )
            }
        }

        return (
            updatedActiveRefresh,
            updatedPendingRefresh,
            .refreshMerged(
                cycleId: updatedPendingRefresh?.cycleId ?? updatedActiveRefresh.cycleId,
                kind: updatedPendingRefresh?.kind ?? updatedActiveRefresh.kind
            ),
            actions
        )
    }

    private static func preserveCancelledRefreshState(
        _ cancelledRefresh: ScheduledRefresh,
        pendingRefresh: ScheduledRefresh?
    ) -> ScheduledRefresh {
        guard var pendingRefresh else {
            return cancelledRefresh
        }

        if !cancelledRefresh.postLayoutAttachmentIds.isEmpty {
            pendingRefresh.postLayoutAttachmentIds =
                cancelledRefresh.postLayoutAttachmentIds + pendingRefresh.postLayoutAttachmentIds
        }

        pendingRefresh.affectedWorkspaceIds.formUnion(cancelledRefresh.affectedWorkspaceIds)

        if cancelledRefresh.kind == .windowRemoval,
           !cancelledRefresh.windowRemovalPayloads.isEmpty
        {
            pendingRefresh.windowRemovalPayloads =
                cancelledRefresh.windowRemovalPayloads + pendingRefresh.windowRemovalPayloads
            if pendingRefresh.kind != .fullRescan,
               pendingRefresh.kind != .windowRemoval
            {
                pendingRefresh.kind = .windowRemoval
                pendingRefresh.reason = cancelledRefresh.reason
            }
        }

        mergeAbsorbedVisibility(into: &pendingRefresh, incoming: cancelledRefresh)
        pendingRefresh.followUpRefresh = mergeFollowUpRefresh(
            existing: cancelledRefresh.followUpRefresh,
            incoming: pendingRefresh.followUpRefresh
        )

        return pendingRefresh
    }

    private static func mergePendingRefresh(
        _ pendingRefresh: ScheduledRefresh?,
        incoming: ScheduledRefresh
    ) -> ScheduledRefresh {
        guard var pendingRefresh else {
            return incoming
        }

        let existingAffectedWorkspaceIds = pendingRefresh.affectedWorkspaceIds

        switch pendingRefresh.kind {
        case .fullRescan:
            switch incoming.kind {
            case .fullRescan:
                pendingRefresh.reason = incoming.reason
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            default:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            }

        case .visibilityRefresh:
            switch incoming.kind {
            case .fullRescan, .windowRemoval, .immediateRelayout, .relayout:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .visibilityRefresh:
                pendingRefresh.reason = incoming.reason
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
            }

        case .windowRemoval:
            switch incoming.kind {
            case .fullRescan:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .windowRemoval:
                pendingRefresh.reason = incoming.reason
                pendingRefresh.windowRemovalPayloads.append(
                    contentsOf: incoming.windowRemovalPayloads
                )
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .immediateRelayout:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeFollowUp(
                    into: &pendingRefresh,
                    kind: .immediateRelayout,
                    reason: incoming.reason,
                    affectedWorkspaceIds: incoming.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .relayout:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeFollowUp(
                    into: &pendingRefresh,
                    kind: .relayout,
                    reason: incoming.reason,
                    affectedWorkspaceIds: incoming.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .visibilityRefresh:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            }

        case .immediateRelayout:
            switch incoming.kind {
            case .fullRescan:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .windowRemoval:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                upgraded.followUpRefresh = pendingRefresh.followUpRefresh
                mergeFollowUp(
                    into: &upgraded,
                    kind: .immediateRelayout,
                    reason: pendingRefresh.reason,
                    affectedWorkspaceIds: pendingRefresh.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .visibilityRefresh:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .immediateRelayout:
                pendingRefresh.reason = incoming.reason
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                pendingRefresh.followUpRefresh = mergeFollowUpRefresh(
                    existing: pendingRefresh.followUpRefresh,
                    incoming: incoming.followUpRefresh
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .relayout:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeFollowUp(
                    into: &pendingRefresh,
                    kind: .relayout,
                    reason: incoming.reason,
                    affectedWorkspaceIds: incoming.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            }

        case .relayout:
            switch incoming.kind {
            case .fullRescan:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .windowRemoval:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                mergeFollowUp(
                    into: &upgraded,
                    kind: .relayout,
                    reason: pendingRefresh.reason,
                    affectedWorkspaceIds: pendingRefresh.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            case .visibilityRefresh:
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .relayout:
                pendingRefresh.reason = incoming.reason
                pendingRefresh.postLayoutAttachmentIds.append(
                    contentsOf: incoming.postLayoutAttachmentIds
                )
                pendingRefresh.followUpRefresh = mergeFollowUpRefresh(
                    existing: pendingRefresh.followUpRefresh,
                    incoming: incoming.followUpRefresh
                )
                mergeAbsorbedVisibility(into: &pendingRefresh, incoming: incoming)
            case .immediateRelayout:
                var upgraded = incoming
                upgraded.cycleId = pendingRefresh.cycleId
                upgraded.postLayoutAttachmentIds.append(
                    contentsOf: pendingRefresh.postLayoutAttachmentIds
                )
                upgraded.followUpRefresh = mergeFollowUpRefresh(
                    existing: pendingRefresh.followUpRefresh,
                    incoming: incoming.followUpRefresh
                )
                mergeFollowUp(
                    into: &upgraded,
                    kind: .relayout,
                    reason: pendingRefresh.reason,
                    affectedWorkspaceIds: pendingRefresh.affectedWorkspaceIds
                )
                mergeAbsorbedVisibility(into: &upgraded, incoming: pendingRefresh)
                mergeAbsorbedVisibility(into: &upgraded, incoming: incoming)
                pendingRefresh = upgraded
            }
        }

        pendingRefresh.affectedWorkspaceIds = existingAffectedWorkspaceIds
        pendingRefresh.affectedWorkspaceIds.formUnion(incoming.affectedWorkspaceIds)
        return pendingRefresh
    }

    private static func absorbIntoActiveFullRescan(
        _ activeRefresh: ScheduledRefresh,
        refresh: ScheduledRefresh
    ) -> ScheduledRefresh {
        var updatedRefresh = activeRefresh
        updatedRefresh.postLayoutAttachmentIds.append(
            contentsOf: refresh.postLayoutAttachmentIds
        )
        mergeAbsorbedVisibility(into: &updatedRefresh, incoming: refresh)
        return updatedRefresh
    }

    private static func mergeAbsorbedVisibility(
        into refresh: inout ScheduledRefresh,
        incoming: ScheduledRefresh
    ) {
        if incoming.kind == .visibilityRefresh {
            refresh.needsVisibilityReconciliation = true
            refresh.visibilityReason = incoming.reason
            return
        }

        if incoming.needsVisibilityReconciliation {
            refresh.needsVisibilityReconciliation = true
            if let visibilityReason = incoming.visibilityReason {
                refresh.visibilityReason = visibilityReason
            }
        }
    }

    private static func mergeFollowUp(
        into refresh: inout ScheduledRefresh,
        kind: ScheduledRefreshKind,
        reason: RefreshReason,
        affectedWorkspaceIds: Set<WorkspaceDescriptor.ID>
    ) {
        refresh.followUpRefresh = mergeFollowUpRefresh(
            existing: refresh.followUpRefresh,
            incoming: .init(
                kind: kind,
                reason: reason,
                affectedWorkspaceIds: affectedWorkspaceIds
            )
        )
    }

    private static func mergeFollowUpRefresh(
        existing: FollowUpRefresh?,
        incoming: FollowUpRefresh?
    ) -> FollowUpRefresh? {
        if existing == nil, incoming == nil {
            return nil
        }
        if existing == nil {
            return incoming
        }
        if incoming == nil {
            return existing
        }

        let existingFollowUp = existing!
        let incomingFollowUp = incoming!

        var merged = incomingFollowUp
        merged.affectedWorkspaceIds.formUnion(existingFollowUp.affectedWorkspaceIds)

        if existingFollowUp.kind == .immediateRelayout
            || incomingFollowUp.kind == .immediateRelayout
        {
            if incomingFollowUp.kind == .immediateRelayout {
                return merged
            }

            var kept = existingFollowUp
            kept.affectedWorkspaceIds.formUnion(incomingFollowUp.affectedWorkspaceIds)
            return kept
        }

        return merged
    }
}
