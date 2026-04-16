enum OrchestrationCore {
    static func step(
        snapshot: OrchestrationSnapshot,
        event: OrchestrationEvent
    ) -> OrchestrationResult {
        switch event {
        case let .refreshRequested(request):
            return RefreshPlanner.step(
                snapshot: snapshot.refresh,
                event: .requested(request)
            )
            .asOrchestrationResult(focus: snapshot.focus)

        case let .refreshCompleted(completion):
            return RefreshPlanner.step(
                snapshot: snapshot.refresh,
                event: .completed(completion)
            )
            .asOrchestrationResult(focus: snapshot.focus)

        case let .focusRequested(request):
            return FocusPlanner.step(
                snapshot: snapshot.focus,
                event: .requested(request)
            )
            .asOrchestrationResult(refresh: snapshot.refresh)

        case let .activationObserved(observation):
            return FocusPlanner.step(
                snapshot: snapshot.focus,
                event: .activationObserved(observation)
            )
            .asOrchestrationResult(refresh: snapshot.refresh)
        }
    }
}
