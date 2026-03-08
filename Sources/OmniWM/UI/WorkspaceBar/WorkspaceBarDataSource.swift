import AppKit
import Foundation
@MainActor
enum WorkspaceBarDataSource {
    private struct SortKey {
        let group: Int
        let primary: Int
        let secondary: Int
        let tertiary: Int
    }

    private struct WindowDedupKey: Hashable {
        let windowId: Int
        let handleId: UUID
    }

    private struct AppGroup {
        let key: String
        let displayName: String
    }

    private struct WorkspaceContext {
        let workspaceId: WorkspaceDescriptor.ID
        let rawName: String
        let isFocused: Bool
    }

    static func workspaceBarItems(
        for monitor: Monitor,
        deduplicate: Bool,
        hideEmpty: Bool,
        workspaceManager: WorkspaceManager,
        appInfoCache: AppInfoCache,
        workspaceStateExport: OmniWorkspaceRuntimeAdapter.StateExport?,
        controllerSnapshot: WMControllerControllerSnapshot?,
        focusedHandle: WindowHandle?,
        settings: SettingsStore
    ) -> [WorkspaceBarItem] {
        var workspaces = workspaceContexts(
            for: monitor,
            workspaceManager: workspaceManager,
            workspaceStateExport: workspaceStateExport
        )
        if hideEmpty {
            workspaces = workspaces.filter { workspace in
                if let snapshotWindows = authoritativeSnapshotWindows(
                    for: workspace.workspaceId,
                    controllerSnapshot: controllerSnapshot
                ) {
                    return !snapshotWindows.isEmpty
                }
                if let runtimeWindows = authoritativeRuntimeWindows(
                    for: workspace.workspaceId,
                    workspaceStateExport: workspaceStateExport
                ) {
                    return !runtimeWindows.isEmpty
                }
                return !workspaceManager.entries(in: workspace.workspaceId).isEmpty
            }
        }
        return workspaces.map { workspace in
            let windows: [WorkspaceBarWindowItem]
            if let snapshotWindows = authoritativeSnapshotWindows(
                for: workspace.workspaceId,
                controllerSnapshot: controllerSnapshot
            ) {
                windows = if deduplicate {
                    createDedupedWindowItems(
                        snapshotWindows: snapshotWindows,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                } else {
                    createIndividualWindowItems(
                        snapshotWindows: snapshotWindows,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                }
            } else if let runtimeWindows = authoritativeRuntimeWindows(
                for: workspace.workspaceId,
                workspaceStateExport: workspaceStateExport
            ) {
                windows = if deduplicate {
                    createDedupedWindowItems(
                        runtimeWindows: runtimeWindows,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                } else {
                    createIndividualWindowItems(
                        runtimeWindows: runtimeWindows,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                }
            } else {
                let entries = workspaceManager.entries(in: workspace.workspaceId)
                let orderMap = orderMap(
                    for: workspace.workspaceId,
                    entries: entries,
                    controllerSnapshot: controllerSnapshot
                )
                let orderedEntries = sortEntries(entries, orderMap: orderMap)
                let useLayoutOrder = !(orderMap?.isEmpty ?? true)
                windows = if deduplicate {
                    createDedupedWindowItems(
                        entries: orderedEntries,
                        useLayoutOrder: useLayoutOrder,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                } else {
                    createIndividualWindowItems(
                        entries: orderedEntries,
                        appInfoCache: appInfoCache,
                        focusedHandle: focusedHandle
                    )
                }
            }
            return WorkspaceBarItem(
                workspaceId: workspace.workspaceId,
                rawName: workspace.rawName,
                displayName: settings.displayName(for: workspace.rawName),
                isFocused: workspace.isFocused,
                windows: windows
            )
        }
    }

    private static func workspaceContexts(
        for monitor: Monitor,
        workspaceManager: WorkspaceManager,
        workspaceStateExport: OmniWorkspaceRuntimeAdapter.StateExport?
    ) -> [WorkspaceContext] {
        guard let workspaceStateExport else {
            let activeWorkspaceId = workspaceManager.activeWorkspace(on: monitor.id)?.id
            return workspaceManager.workspaces(on: monitor.id).map { workspace in
                WorkspaceContext(
                    workspaceId: workspace.id,
                    rawName: workspace.name,
                    isFocused: workspace.id == activeWorkspaceId
                )
            }
        }

        let workspaceById = Dictionary(
            workspaceStateExport.workspaces.map { ($0.workspaceId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let monitorRecord = workspaceStateExport.monitors.first(where: { $0.displayId == monitor.displayId })
        var seenWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
        var workspaceIds: [WorkspaceDescriptor.ID] = []

        func appendWorkspaceId(_ workspaceId: WorkspaceDescriptor.ID?) {
            guard let workspaceId,
                  workspaceById[workspaceId] != nil,
                  seenWorkspaceIds.insert(workspaceId).inserted else {
                return
            }
            workspaceIds.append(workspaceId)
        }

        for workspace in workspaceStateExport.workspaces where workspace.assignedDisplayId == monitor.displayId {
            appendWorkspaceId(workspace.workspaceId)
        }
        appendWorkspaceId(monitorRecord?.activeWorkspaceId)
        appendWorkspaceId(monitorRecord?.previousWorkspaceId)

        let activeWorkspaceId = monitorRecord?.activeWorkspaceId
        return workspaceIds
            .compactMap { workspaceId in
                guard let workspace = workspaceById[workspaceId] else { return nil }
                return WorkspaceContext(
                    workspaceId: workspace.workspaceId,
                    rawName: workspace.name,
                    isFocused: workspace.workspaceId == activeWorkspaceId
                )
            }
            .sorted { lhs, rhs in
                lhs.rawName.toLogicalSegments() < rhs.rawName.toLogicalSegments()
            }
    }

    private static func authoritativeSnapshotWindows(
        for workspaceId: WorkspaceDescriptor.ID,
        controllerSnapshot: WMControllerControllerSnapshot?
    ) -> [WMControllerControllerSnapshot.WindowRecord]? {
        guard let controllerSnapshot else { return nil }
        guard controllerSnapshot.workspaces.contains(where: { $0.workspaceId == workspaceId }) else {
            return nil
        }
        return controllerSnapshot.orderedWindows(in: workspaceId)
    }

    private static func authoritativeRuntimeWindows(
        for workspaceId: WorkspaceDescriptor.ID,
        workspaceStateExport: OmniWorkspaceRuntimeAdapter.StateExport?
    ) -> [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord]? {
        guard let workspaceStateExport else { return nil }
        guard workspaceStateExport.workspaces.contains(where: { $0.workspaceId == workspaceId }) else {
            return nil
        }
        return workspaceStateExport.windows.filter {
            $0.workspaceId == workspaceId &&
                $0.layoutReason == .standard &&
                $0.hiddenState == nil
        }
    }

    private static func orderMap(
        for workspaceId: WorkspaceDescriptor.ID,
        entries _: [WindowModel.Entry],
        controllerSnapshot: WMControllerControllerSnapshot?
    ) -> [WindowHandle: SortKey]? {
        if let controllerSnapshot {
            var order: [WindowHandle: SortKey] = [:]
            for window in controllerSnapshot.orderedWindows(in: workspaceId) {
                order[window.handle] = SortKey(
                    group: window.columnId == nil && window.columnIndex < 0 ? 1 : 0,
                    primary: normalizedIndex(window.columnIndex, fallback: window.orderIndex),
                    secondary: normalizedIndex(window.rowIndex, fallback: window.orderIndex),
                    tertiary: normalizedIndex(window.orderIndex, fallback: Int.max)
                )
            }
            if !order.isEmpty {
                return order
            }
        }
        return nil
    }
    private static func sortEntries(
        _ entries: [WindowModel.Entry],
        orderMap: [WindowHandle: SortKey]?
    ) -> [WindowModel.Entry] {
        guard let orderMap else { return entries }
        let fallbackOrder = Dictionary(uniqueKeysWithValues: entries.enumerated()
            .map { ($0.element.handle, $0.offset) })
        return entries.sorted { lhs, rhs in
            let lhsKey = orderMap[lhs.handle] ?? SortKey(
                group: 2,
                primary: Int.max,
                secondary: Int.max,
                tertiary: Int.max
            )
            let rhsKey = orderMap[rhs.handle] ?? SortKey(
                group: 2,
                primary: Int.max,
                secondary: Int.max,
                tertiary: Int.max
            )
            if lhsKey.group != rhsKey.group { return lhsKey.group < rhsKey.group }
            if lhsKey.primary != rhsKey.primary { return lhsKey.primary < rhsKey.primary }
            if lhsKey.secondary != rhsKey.secondary { return lhsKey.secondary < rhsKey.secondary }
            if lhsKey.tertiary != rhsKey.tertiary { return lhsKey.tertiary < rhsKey.tertiary }
            let lhsFallback = fallbackOrder[lhs.handle] ?? 0
            let rhsFallback = fallbackOrder[rhs.handle] ?? 0
            return lhsFallback < rhsFallback
        }
    }

    private static func normalizedIndex(_ value: Int, fallback: Int) -> Int {
        value >= 0 ? value : (fallback >= 0 ? fallback : Int.max)
    }
    private static func createDedupedWindowItems(
        entries: [WindowModel.Entry],
        useLayoutOrder: Bool,
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        let dedupedEntries = deduplicatedWindowEntries(entries)

        if useLayoutOrder {
            var groupedByApp: [String: [WindowModel.Entry]] = [:]
            var orderedGroups: [AppGroup] = []
            for entry in dedupedEntries {
                let group = appGroup(pid: entry.handle.pid, appInfoCache: appInfoCache)
                if groupedByApp[group.key] == nil {
                    groupedByApp[group.key] = []
                    orderedGroups.append(group)
                }
                groupedByApp[group.key]?.append(entry)
            }
            return orderedGroups.compactMap { group in
                guard let appEntries = groupedByApp[group.key], let firstEntry = appEntries.first else { return nil }
                let appInfo = appInfoCache.info(for: firstEntry.handle.pid)
                let anyFocused = appEntries.contains { $0.handle.id == focusedHandle?.id }
                let windowInfos = appEntries.map { entry -> WorkspaceBarWindowInfo in
                    WorkspaceBarWindowInfo(
                        id: entry.handle.id,
                        windowId: entry.windowId,
                        title: windowTitle(for: entry) ?? group.displayName,
                        isFocused: entry.handle.id == focusedHandle?.id
                    )
                }
                return WorkspaceBarWindowItem(
                    id: firstEntry.handle.id,
                    windowId: firstEntry.windowId,
                    appName: group.displayName,
                    icon: appInfo?.icon,
                    isFocused: anyFocused,
                    windowCount: appEntries.count,
                    allWindows: windowInfos
                )
            }
        }
        let groupedByApp = Dictionary(grouping: dedupedEntries) { entry -> String in
            appGroup(pid: entry.handle.pid, appInfoCache: appInfoCache).key
        }
        return groupedByApp.compactMap { key, appEntries -> WorkspaceBarWindowItem? in
            let firstEntry = appEntries.first!
            let appInfo = appInfoCache.info(for: firstEntry.handle.pid)
            let group = appGroup(pid: firstEntry.handle.pid, appInfoCache: appInfoCache)
            let anyFocused = appEntries.contains { $0.handle.id == focusedHandle?.id }
            let windowInfos = appEntries.map { entry -> WorkspaceBarWindowInfo in
                WorkspaceBarWindowInfo(
                    id: entry.handle.id,
                    windowId: entry.windowId,
                    title: windowTitle(for: entry) ?? group.displayName,
                    isFocused: entry.handle.id == focusedHandle?.id
                )
            }
            return WorkspaceBarWindowItem(
                id: firstEntry.handle.id,
                windowId: firstEntry.windowId,
                appName: group.displayName,
                icon: appInfo?.icon,
                isFocused: anyFocused,
                windowCount: appEntries.count,
                allWindows: windowInfos
            )
        }.sorted { $0.appName < $1.appName }
    }

    static func deduplicatedWindowEntries(_ entries: [WindowModel.Entry]) -> [WindowModel.Entry] {
        var seen: Set<WindowDedupKey> = []
        var duplicateCounts: [WindowDedupKey: Int] = [:]
        var deduped: [WindowModel.Entry] = []
        deduped.reserveCapacity(entries.count)

        for entry in entries {
            let key = WindowDedupKey(windowId: entry.windowId, handleId: entry.handle.id)
            if seen.insert(key).inserted {
                deduped.append(entry)
            } else {
                duplicateCounts[key, default: 0] += 1
            }
        }

        for (key, duplicateCount) in duplicateCounts.sorted(by: { lhs, rhs in
            if lhs.key.windowId != rhs.key.windowId {
                return lhs.key.windowId < rhs.key.windowId
            }
            return lhs.key.handleId.uuidString < rhs.key.handleId.uuidString
        }) {
            NSLog(
                "WorkspaceBarDataSource filtered duplicate export windowId=%d handleId=%@ duplicates=%d",
                key.windowId,
                key.handleId.uuidString,
                duplicateCount
            )
        }

        return deduped
    }

    private static func deduplicatedSnapshotWindows(
        _ windows: [WMControllerControllerSnapshot.WindowRecord]
    ) -> [WMControllerControllerSnapshot.WindowRecord] {
        var seen: Set<WindowDedupKey> = []
        var deduped: [WMControllerControllerSnapshot.WindowRecord] = []
        deduped.reserveCapacity(windows.count)

        for window in windows {
            let key = WindowDedupKey(windowId: window.windowId, handleId: window.handleId)
            if seen.insert(key).inserted {
                deduped.append(window)
            }
        }

        return deduped
    }

    private static func appGroup(pid: pid_t, appInfoCache: AppInfoCache) -> AppGroup {
        let appInfo = appInfoCache.info(for: pid)
        let displayName = appInfo?.name ?? "Unknown"
        if let bundleId = appInfo?.bundleId, !bundleId.isEmpty {
            return AppGroup(key: bundleId, displayName: displayName)
        }
        return AppGroup(key: "pid:\(pid)", displayName: displayName)
    }
    private static func createIndividualWindowItems(
        entries: [WindowModel.Entry],
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        entries.map { entry in
            let appInfo = appInfoCache.info(for: entry.handle.pid)
            let appName = appInfo?.name ?? "Unknown"
            let title = windowTitle(for: entry) ?? appName
            return WorkspaceBarWindowItem(
                id: entry.handle.id,
                windowId: entry.windowId,
                appName: appName,
                icon: appInfo?.icon,
                isFocused: entry.handle.id == focusedHandle?.id,
                windowCount: 1,
                allWindows: [
                    WorkspaceBarWindowInfo(
                        id: entry.handle.id,
                        windowId: entry.windowId,
                        title: title,
                        isFocused: entry.handle.id == focusedHandle?.id
                    )
                ]
            )
        }
    }
    private static func createDedupedWindowItems(
        snapshotWindows: [WMControllerControllerSnapshot.WindowRecord],
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        let dedupedWindows = deduplicatedSnapshotWindows(snapshotWindows)
        var groupedByApp: [String: [WMControllerControllerSnapshot.WindowRecord]] = [:]
        var orderedGroups: [AppGroup] = []

        for window in dedupedWindows {
            let group = appGroup(pid: window.pid, appInfoCache: appInfoCache)
            if groupedByApp[group.key] == nil {
                groupedByApp[group.key] = []
                orderedGroups.append(group)
            }
            groupedByApp[group.key]?.append(window)
        }

        return orderedGroups.compactMap { group in
            guard let appWindows = groupedByApp[group.key], let firstWindow = appWindows.first else { return nil }
            let appInfo = appInfoCache.info(for: firstWindow.pid)
            let anyFocused = appWindows.contains { isFocused(window: $0, focusedHandle: focusedHandle) }
            let windowInfos = appWindows.map { window in
                WorkspaceBarWindowInfo(
                    id: window.handleId,
                    windowId: window.windowId,
                    title: windowTitle(forWindowId: window.windowId) ?? group.displayName,
                    isFocused: isFocused(window: window, focusedHandle: focusedHandle)
                )
            }
            return WorkspaceBarWindowItem(
                id: firstWindow.handleId,
                windowId: firstWindow.windowId,
                appName: group.displayName,
                icon: appInfo?.icon,
                isFocused: anyFocused,
                windowCount: appWindows.count,
                allWindows: windowInfos
            )
        }
    }

    private static func createDedupedWindowItems(
        runtimeWindows: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord],
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        let dedupedWindows = deduplicatedRuntimeWindows(runtimeWindows)
        var groupedByApp: [String: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord]] = [:]
        var orderedGroups: [AppGroup] = []

        for window in dedupedWindows {
            let group = appGroup(pid: window.pid, appInfoCache: appInfoCache)
            if groupedByApp[group.key] == nil {
                groupedByApp[group.key] = []
                orderedGroups.append(group)
            }
            groupedByApp[group.key]?.append(window)
        }

        return orderedGroups.compactMap { group in
            guard let appWindows = groupedByApp[group.key], let firstWindow = appWindows.first else { return nil }
            let appInfo = appInfoCache.info(for: firstWindow.pid)
            let anyFocused = appWindows.contains { $0.handleId == focusedHandle?.id }
            let windowInfos = appWindows.map { window in
                WorkspaceBarWindowInfo(
                    id: window.handleId,
                    windowId: window.windowId,
                    title: windowTitle(forWindowId: window.windowId) ?? group.displayName,
                    isFocused: window.handleId == focusedHandle?.id
                )
            }
            return WorkspaceBarWindowItem(
                id: firstWindow.handleId,
                windowId: firstWindow.windowId,
                appName: group.displayName,
                icon: appInfo?.icon,
                isFocused: anyFocused,
                windowCount: appWindows.count,
                allWindows: windowInfos
            )
        }
    }

    private static func createIndividualWindowItems(
        snapshotWindows: [WMControllerControllerSnapshot.WindowRecord],
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        snapshotWindows.map { window in
            let appInfo = appInfoCache.info(for: window.pid)
            let appName = appInfo?.name ?? "Unknown"
            return WorkspaceBarWindowItem(
                id: window.handleId,
                windowId: window.windowId,
                appName: appName,
                icon: appInfo?.icon,
                isFocused: isFocused(window: window, focusedHandle: focusedHandle),
                windowCount: 1,
                allWindows: [
                    WorkspaceBarWindowInfo(
                        id: window.handleId,
                        windowId: window.windowId,
                        title: windowTitle(forWindowId: window.windowId) ?? appName,
                        isFocused: isFocused(window: window, focusedHandle: focusedHandle)
                    )
                ]
            )
        }
    }

    private static func createIndividualWindowItems(
        runtimeWindows: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord],
        appInfoCache: AppInfoCache,
        focusedHandle: WindowHandle?
    ) -> [WorkspaceBarWindowItem] {
        runtimeWindows.map { window in
            let appInfo = appInfoCache.info(for: window.pid)
            let appName = appInfo?.name ?? "Unknown"
            return WorkspaceBarWindowItem(
                id: window.handleId,
                windowId: window.windowId,
                appName: appName,
                icon: appInfo?.icon,
                isFocused: window.handleId == focusedHandle?.id,
                windowCount: 1,
                allWindows: [
                    WorkspaceBarWindowInfo(
                        id: window.handleId,
                        windowId: window.windowId,
                        title: windowTitle(forWindowId: window.windowId) ?? appName,
                        isFocused: window.handleId == focusedHandle?.id
                    )
                ]
            )
        }
    }

    private static func isFocused(
        window: WMControllerControllerSnapshot.WindowRecord,
        focusedHandle: WindowHandle?
    ) -> Bool {
        window.isFocused || window.handleId == focusedHandle?.id
    }

    private static func deduplicatedRuntimeWindows(
        _ windows: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord]
    ) -> [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord] {
        var seen: Set<WindowDedupKey> = []
        var deduped: [OmniWorkspaceRuntimeAdapter.StateExport.WindowRecord] = []
        deduped.reserveCapacity(windows.count)

        for window in windows {
            let key = WindowDedupKey(windowId: window.windowId, handleId: window.handleId)
            if seen.insert(key).inserted {
                deduped.append(window)
            }
        }

        return deduped
    }

    private static func windowTitle(for entry: WindowModel.Entry) -> String? {
        windowTitle(forWindowId: entry.windowId)
    }

    private static func windowTitle(forWindowId windowId: Int) -> String? {
        guard let rawWindowId = UInt32(exactly: windowId),
              let title = AXWindowService.titlePreferFast(windowId: rawWindowId),
              !title.isEmpty else {
            return nil
        }
        return title
    }
}
