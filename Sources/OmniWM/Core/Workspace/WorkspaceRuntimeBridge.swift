import Foundation

@MainActor
final class WorkspaceRuntimeBridge {
    @MainActor
    private protocol Backend: AnyObject {
        func upsert(window: AXWindowRef, pid: pid_t, windowId: Int, workspace: WorkspaceDescriptor.ID) -> WindowHandle
        func windows(in workspace: WorkspaceDescriptor.ID) -> [WindowModel.Entry]
        func workspace(for handle: WindowHandle) -> WorkspaceDescriptor.ID?
        func entry(for handle: WindowHandle) -> WindowModel.Entry?
        func entry(forPid pid: pid_t, windowId: Int) -> WindowModel.Entry?
        func entries(forPid pid: pid_t) -> [WindowModel.Entry]
        func entry(forWindowId windowId: Int) -> WindowModel.Entry?
        func entry(forWindowId windowId: Int, inVisibleWorkspaces visibleIds: Set<WorkspaceDescriptor.ID>) -> WindowModel.Entry?
        func allEntries() -> [WindowModel.Entry]
        func removeMissing(keys activeKeys: Set<WindowModel.WindowKey>, requiredConsecutiveMisses: Int)
        func removeWindow(key: WindowModel.WindowKey)
        func updateWorkspace(for handle: WindowHandle, workspace: WorkspaceDescriptor.ID)
        func setHiddenState(_ state: WindowModel.HiddenState?, for handle: WindowHandle)
        func hiddenState(for handle: WindowHandle) -> WindowModel.HiddenState?
        func isHiddenInCorner(_ handle: WindowHandle) -> Bool
        func layoutReason(for handle: WindowHandle) -> LayoutReason
        func setLayoutReason(_ reason: LayoutReason, for handle: WindowHandle)
        func restoreFromNativeState(for handle: WindowHandle) -> ParentKind?
        func cachedConstraints(for handle: WindowHandle, maxAge: TimeInterval) -> WindowSizeConstraints?
        func setCachedConstraints(_ constraints: WindowSizeConstraints, for handle: WindowHandle)
    }

    private let backend: any Backend

    init(runtimeAdapter: OmniWorkspaceRuntimeAdapter) {
        backend = RuntimeBackend(runtime: runtimeAdapter)
    }

    func upsert(window: AXWindowRef, pid: pid_t, windowId: Int, workspace: WorkspaceDescriptor.ID) -> WindowHandle {
        backend.upsert(window: window, pid: pid, windowId: windowId, workspace: workspace)
    }

    func windows(in workspace: WorkspaceDescriptor.ID) -> [WindowModel.Entry] {
        backend.windows(in: workspace)
    }

    func workspace(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
        backend.workspace(for: handle)
    }

    func entry(for handle: WindowHandle) -> WindowModel.Entry? {
        backend.entry(for: handle)
    }

    func entry(forPid pid: pid_t, windowId: Int) -> WindowModel.Entry? {
        backend.entry(forPid: pid, windowId: windowId)
    }

    func entries(forPid pid: pid_t) -> [WindowModel.Entry] {
        backend.entries(forPid: pid)
    }

    func entry(forWindowId windowId: Int) -> WindowModel.Entry? {
        backend.entry(forWindowId: windowId)
    }

    func entry(forWindowId windowId: Int, inVisibleWorkspaces visibleIds: Set<WorkspaceDescriptor.ID>) -> WindowModel.Entry? {
        backend.entry(forWindowId: windowId, inVisibleWorkspaces: visibleIds)
    }

    func allEntries() -> [WindowModel.Entry] {
        backend.allEntries()
    }

    func removeMissing(keys activeKeys: Set<WindowModel.WindowKey>, requiredConsecutiveMisses: Int = 1) {
        backend.removeMissing(keys: activeKeys, requiredConsecutiveMisses: requiredConsecutiveMisses)
    }

    func removeWindow(key: WindowModel.WindowKey) {
        backend.removeWindow(key: key)
    }

    func updateWorkspace(for handle: WindowHandle, workspace: WorkspaceDescriptor.ID) {
        backend.updateWorkspace(for: handle, workspace: workspace)
    }

    func setHiddenState(_ state: WindowModel.HiddenState?, for handle: WindowHandle) {
        backend.setHiddenState(state, for: handle)
    }

    func hiddenState(for handle: WindowHandle) -> WindowModel.HiddenState? {
        backend.hiddenState(for: handle)
    }

    func isHiddenInCorner(_ handle: WindowHandle) -> Bool {
        backend.isHiddenInCorner(handle)
    }

    func layoutReason(for handle: WindowHandle) -> LayoutReason {
        backend.layoutReason(for: handle)
    }

    func setLayoutReason(_ reason: LayoutReason, for handle: WindowHandle) {
        backend.setLayoutReason(reason, for: handle)
    }

    func restoreFromNativeState(for handle: WindowHandle) -> ParentKind? {
        backend.restoreFromNativeState(for: handle)
    }

    func cachedConstraints(for handle: WindowHandle, maxAge: TimeInterval = 5.0) -> WindowSizeConstraints? {
        backend.cachedConstraints(for: handle, maxAge: maxAge)
    }

    func setCachedConstraints(_ constraints: WindowSizeConstraints, for handle: WindowHandle) {
        backend.setCachedConstraints(constraints, for: handle)
    }
}

private extension WorkspaceRuntimeBridge {
    @MainActor
    final class RuntimeBackend: Backend {
        private struct WindowKey: Hashable {
            let pid: pid_t
            let windowId: Int
        }

        private let runtime: OmniWorkspaceRuntimeAdapter
        private var entries: [WindowHandle: WindowModel.Entry] = [:]
        private var keyToHandle: [WindowKey: WindowHandle] = [:]
        private var handlesByWorkspace: [WorkspaceDescriptor.ID: [WindowHandle]] = [:]
        private var handleIndexByWorkspace: [WorkspaceDescriptor.ID: [WindowHandle: Int]] = [:]
        private var windowIdToHandle: [Int: WindowHandle] = [:]
        private var handleById: [UUID: WindowHandle] = [:]

        init(runtime: OmniWorkspaceRuntimeAdapter) {
            self.runtime = runtime
            refreshFromRuntimeState()
        }

        func upsert(window: AXWindowRef, pid: pid_t, windowId: Int, workspace: WorkspaceDescriptor.ID) -> WindowHandle {
            let key = WindowKey(pid: pid, windowId: windowId)
            let preferredHandleId = keyToHandle[key]?.id

            if let handleId = runtime.windowUpsert(
                pid: pid,
                windowId: windowId,
                workspaceId: workspace,
                preferredHandleId: preferredHandleId
            ) {
                refreshFromRuntimeState()
                let handle = resolveHandle(id: handleId, pid: pid)
                if let entry = entries[handle] {
                    entry.axRef = window
                }
                return handle
            }

            if let existing = keyToHandle[key] {
                entries[existing]?.axRef = window
                return existing
            }

            let fallback = WindowHandle(id: UUID(), pid: pid)
            let fallbackEntry = WindowModel.Entry(
                handle: fallback,
                axRef: window,
                workspaceId: workspace,
                windowId: windowId,
                hiddenProportionalPosition: nil
            )
            entries[fallback] = fallbackEntry
            keyToHandle[key] = fallback
            windowIdToHandle[windowId] = fallback
            appendHandle(fallback, to: workspace)
            handleById[fallback.id] = fallback
            return fallback
        }

        func windows(in workspace: WorkspaceDescriptor.ID) -> [WindowModel.Entry] {
            guard let handles = handlesByWorkspace[workspace] else { return [] }
            return handles.compactMap { entries[$0] }
        }

        func workspace(for handle: WindowHandle) -> WorkspaceDescriptor.ID? {
            entries[handle]?.workspaceId
        }

        func entry(for handle: WindowHandle) -> WindowModel.Entry? {
            entries[handle]
        }

        func entry(forPid pid: pid_t, windowId: Int) -> WindowModel.Entry? {
            let key = WindowKey(pid: pid, windowId: windowId)
            guard let handle = keyToHandle[key] else { return nil }
            return entries[handle]
        }

        func entries(forPid pid: pid_t) -> [WindowModel.Entry] {
            entries.values.filter { $0.handle.pid == pid }
        }

        func entry(forWindowId windowId: Int) -> WindowModel.Entry? {
            guard let handle = windowIdToHandle[windowId] else { return nil }
            return entries[handle]
        }

        func entry(forWindowId windowId: Int, inVisibleWorkspaces visibleIds: Set<WorkspaceDescriptor.ID>) -> WindowModel.Entry? {
            guard let handle = windowIdToHandle[windowId],
                  let entry = entries[handle],
                  visibleIds.contains(entry.workspaceId)
            else {
                return nil
            }
            return entry
        }

        func allEntries() -> [WindowModel.Entry] {
            Array(entries.values)
        }

        func removeMissing(keys activeKeys: Set<WindowModel.WindowKey>, requiredConsecutiveMisses: Int) {
            runtime.windowRemoveMissing(keys: activeKeys, requiredConsecutiveMisses: requiredConsecutiveMisses)
            refreshFromRuntimeState()
        }

        func removeWindow(key: WindowModel.WindowKey) {
            runtime.windowRemove(key: key)
            refreshFromRuntimeState()
        }

        func updateWorkspace(for handle: WindowHandle, workspace: WorkspaceDescriptor.ID) {
            guard runtime.windowSetWorkspace(handleId: handle.id, workspaceId: workspace) else { return }
            refreshFromRuntimeState()
        }

        func setHiddenState(_ state: WindowModel.HiddenState?, for handle: WindowHandle) {
            guard runtime.windowSetHiddenState(handleId: handle.id, state: state) else { return }
            refreshFromRuntimeState()
        }

        func hiddenState(for handle: WindowHandle) -> WindowModel.HiddenState? {
            guard let entry = entries[handle],
                  let proportionalPosition = entry.hiddenProportionalPosition
            else {
                return nil
            }
            return WindowModel.HiddenState(
                proportionalPosition: proportionalPosition,
                referenceMonitorId: entry.hiddenReferenceMonitorId,
                workspaceInactive: entry.hiddenByWorkspaceInactivity
            )
        }

        func isHiddenInCorner(_ handle: WindowHandle) -> Bool {
            entries[handle]?.hiddenProportionalPosition != nil
        }

        func layoutReason(for handle: WindowHandle) -> LayoutReason {
            entries[handle]?.layoutReason ?? .standard
        }

        func setLayoutReason(_ reason: LayoutReason, for handle: WindowHandle) {
            guard let entry = entries[handle] else { return }
            if reason != .standard, entry.layoutReason == .standard {
                entry.prevParentKind = entry.parentKind
            }
            guard runtime.windowSetLayoutReason(handleId: handle.id, reason: reason) else { return }
            refreshFromRuntimeState()
        }

        func restoreFromNativeState(for handle: WindowHandle) -> ParentKind? {
            guard let entry = entries[handle],
                  entry.layoutReason != .standard,
                  let prevKind = entry.prevParentKind
            else {
                return nil
            }
            guard runtime.windowSetLayoutReason(handleId: handle.id, reason: .standard) else { return nil }
            refreshFromRuntimeState()
            if let refreshed = entries[handle] {
                refreshed.parentKind = prevKind
                refreshed.prevParentKind = nil
                refreshed.layoutReason = .standard
            }
            return prevKind
        }

        func cachedConstraints(for handle: WindowHandle, maxAge: TimeInterval) -> WindowSizeConstraints? {
            guard let entry = entries[handle],
                  let cached = entry.cachedConstraints,
                  let cacheTime = entry.constraintsCacheTime,
                  Date().timeIntervalSince(cacheTime) < maxAge
            else {
                return nil
            }
            return cached
        }

        func setCachedConstraints(_ constraints: WindowSizeConstraints, for handle: WindowHandle) {
            guard let entry = entries[handle] else { return }
            entry.cachedConstraints = constraints
            entry.constraintsCacheTime = Date()
        }

        private func resolveHandle(id: UUID, pid: pid_t) -> WindowHandle {
            if let existing = handleById[id] {
                return existing
            }
            let handle = WindowHandle(id: id, pid: pid)
            handleById[id] = handle
            return handle
        }

        private func appendHandle(_ handle: WindowHandle, to workspace: WorkspaceDescriptor.ID) {
            var handles = handlesByWorkspace[workspace, default: []]
            var indexByHandle = handleIndexByWorkspace[workspace, default: [:]]
            guard indexByHandle[handle] == nil else { return }
            indexByHandle[handle] = handles.count
            handles.append(handle)
            handlesByWorkspace[workspace] = handles
            handleIndexByWorkspace[workspace] = indexByHandle
        }

        private func refreshFromRuntimeState() {
            guard let state = runtime.exportState() else { return }

            let previousEntriesById = Dictionary(uniqueKeysWithValues: entries.values.map { ($0.handle.id, $0) })

            entries.removeAll(keepingCapacity: true)
            keyToHandle.removeAll(keepingCapacity: true)
            handlesByWorkspace.removeAll(keepingCapacity: true)
            handleIndexByWorkspace.removeAll(keepingCapacity: true)
            windowIdToHandle.removeAll(keepingCapacity: true)

            var activeHandleIds: Set<UUID> = []

            for record in state.windows {
                let handle = resolveHandle(id: record.handleId, pid: record.pid)
                activeHandleIds.insert(record.handleId)

                let priorEntry = previousEntriesById[record.handleId]
                let entry: WindowModel.Entry
                if let priorEntry,
                   priorEntry.windowId == record.windowId
                {
                    entry = priorEntry
                    entry.axRef = AXWindowRef(pid: record.pid, windowId: record.windowId)
                    entry.workspaceId = record.workspaceId
                } else {
                    let entryAxRef = priorEntry?.axRef ?? AXWindowRef(pid: record.pid, windowId: record.windowId)
                    entry = WindowModel.Entry(
                        handle: handle,
                        axRef: entryAxRef,
                        workspaceId: record.workspaceId,
                        windowId: record.windowId,
                        hiddenProportionalPosition: nil
                    )
                    if let priorEntry {
                        entry.parentKind = priorEntry.parentKind
                        entry.prevParentKind = priorEntry.prevParentKind
                        entry.cachedConstraints = priorEntry.cachedConstraints
                        entry.constraintsCacheTime = priorEntry.constraintsCacheTime
                    }
                }

                if let hidden = record.hiddenState {
                    entry.hiddenProportionalPosition = hidden.proportionalPosition
                    entry.hiddenReferenceMonitorId = hidden.referenceMonitorId
                    entry.hiddenByWorkspaceInactivity = hidden.workspaceInactive
                } else {
                    entry.hiddenProportionalPosition = nil
                    entry.hiddenReferenceMonitorId = nil
                    entry.hiddenByWorkspaceInactivity = false
                }
                entry.layoutReason = record.layoutReason

                entries[handle] = entry
                let key = WindowKey(pid: record.pid, windowId: record.windowId)
                keyToHandle[key] = handle
                windowIdToHandle[record.windowId] = handle
                appendHandle(handle, to: record.workspaceId)
            }

            handleById = handleById.filter { activeHandleIds.contains($0.key) }
        }
    }
}
