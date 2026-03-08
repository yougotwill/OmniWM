import AppKit
import Foundation
import ScreenCaptureKit
@MainActor
final class OverviewController {
    private enum ScrollTuning {
        static let preciseScrollMultiplier: CGFloat = 3.5
        static let nonPreciseScrollMultiplier: CGFloat = 2.0
        static let zoomStep: CGFloat = 0.05
        static let zoomEpsilon: CGFloat = 0.0001
    }
    private weak var wmController: WMController?
    private(set) var state: OverviewState = .closed
    private var layout: OverviewLayout = .init()
    private var searchQuery: String = ""
    private var windows: [OverviewWindow] = []
    private var animator: OverviewAnimator?
    private var thumbnailCache: [Int: CGImage] = [:]
    private var thumbnailCaptureTask: Task<Void, Never>?
    private var inputHandler: OverviewInputHandler?
    private var dragGhostController: DragGhostController?
    private var dragSession: DragSession?
    var onActivateWindow: ((WindowHandle, WorkspaceDescriptor.ID) -> Void)?
    var onCloseWindow: ((WindowHandle) -> Void)?
    var isOpen: Bool { state.isOpen }
    init(wmController: WMController) {
        self.wmController = wmController
        self.animator = OverviewAnimator(controller: self)
        self.inputHandler = OverviewInputHandler(controller: self)
    }
    func toggle() {
        switch state {
        case .closed:
            open()
        case .open:
            dismiss()
        case .opening, .closing:
            break
        }
    }
    func open() {
        guard case .closed = state else { return }
        guard let wmController else { return }
        buildLayout()
        createWindows()
        startThumbnailCapture()
        let monitor = wmController.workspaceManager.monitors.first
        let displayId = monitor?.displayId ?? CGMainDisplayID()
        let refreshRate = detectRefreshRate(for: displayId)
        state = .opening(progress: 0)
        animator?.startOpenAnimation(displayId: displayId, refreshRate: refreshRate)
        updateWindowDisplays()
        for window in windows {
            window.show()
        }
    }
    func dismiss() {
        guard state.isOpen else { return }
        let targetWindow = layout.selectedWindow()?.handle
        let monitor = wmController?.workspaceManager.monitors.first
        let displayId = monitor?.displayId ?? CGMainDisplayID()
        let refreshRate = detectRefreshRate(for: displayId)
        state = .closing(targetWindow: targetWindow, progress: 0)
        animator?.startCloseAnimation(
            targetWindow: targetWindow,
            displayId: displayId,
            refreshRate: refreshRate
        )
    }
    private func buildLayout() {
        guard wmController != nil else { return }
        let workspaces = overviewWorkspaceContexts()
        let windowData = overviewWindowData()
        guard let screen = NSScreen.main else { return }
        let previousScale = layout.scale
        layout = OverviewLayoutCalculator.calculateLayout(
            workspaces: workspaces,
            windows: windowData,
            screenFrame: screen.frame,
            searchQuery: searchQuery,
            scale: previousScale
        )
        if let firstWindow = layout.allWindows.first {
            layout.setSelected(handle: firstWindow.handle)
        }
        buildNiriColumnLayout(windowData: windowData)
        buildNiriDropZones()
    }

    func overviewWorkspaceContexts() -> [(id: WorkspaceDescriptor.ID, name: String, isActive: Bool)] {
        guard let wmController else { return [] }
        let workspaceManager = wmController.workspaceManager

        if wmController.latestWorkspaceStateExport != nil {
            return workspaceManager.monitors.flatMap { monitor in
                let activeWorkspaceId = wmController.activeWorkspaceId(on: monitor)
                let runtimeWorkspaces = wmController.runtimeWorkspaceRecords(on: monitor) ?? []
                return runtimeWorkspaces.map { workspace in
                    (
                        id: workspace.workspaceId,
                        name: wmController.settings.displayName(for: workspace.name),
                        isActive: workspace.workspaceId == activeWorkspaceId
                    )
                }
            }
        }

        return workspaceManager.monitors.flatMap { monitor in
            let activeWorkspace = workspaceManager.activeWorkspace(on: monitor.id)
            return workspaceManager.workspaces(on: monitor.id).map { workspace in
                (
                    id: workspace.id,
                    name: wmController.settings.displayName(for: workspace.name),
                    isActive: workspace.id == activeWorkspace?.id
                )
            }
        }
    }

    private func overviewWindowData()
        -> [WindowHandle: (entry: WindowModel.Entry, title: String, appName: String, appIcon: NSImage?, frame: CGRect)]
    {
        guard let wmController else { return [:] }
        let workspaceManager = wmController.workspaceManager
        let appInfoCache = wmController.appInfoCache

        if let stateExport = wmController.latestWorkspaceStateExport {
            var windowData: [WindowHandle: (entry: WindowModel.Entry, title: String, appName: String, appIcon: NSImage?, frame: CGRect)] = [:]
            for record in stateExport.windows where record.layoutReason == .standard && record.hiddenState == nil {
                let handle = WindowHandle(id: record.handleId, pid: record.pid)
                let managerEntry = workspaceManager.entry(for: handle)
                let entry = managerEntry ?? WindowModel.Entry(
                    handle: handle,
                    axRef: AXWindowRef(pid: record.pid, windowId: record.windowId),
                    workspaceId: record.workspaceId,
                    windowId: record.windowId,
                    hiddenProportionalPosition: nil
                )
                let title = UInt32(exactly: record.windowId)
                    .flatMap(AXWindowService.titlePreferFast(windowId:))
                    ?? ""
                let appInfo = appInfoCache.info(for: record.pid)
                let frame = managerEntry.flatMap { AXWindowService.framePreferFast($0.axRef) } ?? .zero
                windowData[handle] = (
                    entry: entry,
                    title: title.isEmpty ? (appInfo?.name ?? "Window") : title,
                    appName: appInfo?.name ?? "Unknown",
                    appIcon: appInfo?.icon,
                    frame: frame
                )
            }
            return windowData
        }

        var windowData: [WindowHandle: (entry: WindowModel.Entry, title: String, appName: String, appIcon: NSImage?, frame: CGRect)] = [:]
        for monitor in workspaceManager.monitors {
            for workspace in workspaceManager.workspaces(on: monitor.id) {
                for entry in workspaceManager.entries(in: workspace.id) {
                    guard entry.layoutReason == .standard else { continue }
                    let title = AXWindowService.titlePreferFast(windowId: UInt32(entry.windowId)) ?? ""
                    let appInfo = appInfoCache.info(for: entry.handle.pid)
                    let frame = AXWindowService.framePreferFast(entry.axRef) ?? .zero
                    windowData[entry.handle] = (
                        entry: entry,
                        title: title.isEmpty ? (appInfo?.name ?? "Window") : title,
                        appName: appInfo?.name ?? "Unknown",
                        appIcon: appInfo?.icon,
                        frame: frame
                    )
                }
            }
        }
        return windowData
    }
    private func createWindows() {
        closeWindows()
        guard let wmController else { return }
        for monitor in wmController.workspaceManager.monitors {
            let window = OverviewWindow(monitor: monitor)
            window.onWindowSelected = { [weak self] handle in
                self?.selectAndActivateWindow(handle)
            }
            window.onWindowClosed = { [weak self] handle in
                self?.closeWindow(handle)
            }
            window.onDismiss = { [weak self] in
                self?.dismiss()
            }
            window.onSearchChanged = { [weak self] query in
                self?.updateSearchQuery(query)
            }
            window.onNavigate = { [weak self] direction in
                self?.navigateSelection(direction)
            }
            window.onScroll = { [weak self] delta in
                self?.adjustScrollOffset(by: delta)
            }
            window.onScrollWithModifiers = { [weak self] delta, modifiers, isPrecise in
                self?.handleScroll(delta: delta, modifiers: modifiers, isPrecise: isPrecise)
            }
            window.onDragBegin = { [weak self] handle, start in
                self?.beginDrag(handle: handle, startPoint: start)
            }
            window.onDragUpdate = { [weak self] point in
                self?.updateDrag(at: point)
            }
            window.onDragEnd = { [weak self] point in
                self?.endDrag(at: point)
            }
            window.onDragCancel = { [weak self] in
                self?.cancelDrag()
            }
            windows.append(window)
        }
    }
    private func closeWindows() {
        for window in windows {
            window.hide()
            window.close()
        }
        windows.removeAll()
    }
    func isPointInside(_ point: CGPoint) -> Bool {
        guard state.isOpen else { return false }
        for window in windows {
            if window.frame.contains(point) {
                return true
            }
        }
        return false
    }
    private func updateWindowDisplays() {
        for window in windows {
            window.updateLayout(layout, state: state, searchQuery: searchQuery)
            window.updateThumbnails(thumbnailCache)
        }
    }
    private func startThumbnailCapture() {
        thumbnailCaptureTask?.cancel()
        thumbnailCaptureTask = Task { [weak self] in
            await self?.captureThumbnails()
        }
    }
    private func captureThumbnails() async {
        let windowIds = layout.allWindows.map(\.windowId)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let windowMap = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            for windowId in windowIds {
                guard !Task.isCancelled else { return }
                guard let scWindow = windowMap[CGWindowID(windowId)] else { continue }
                if let thumbnail = await captureWindowThumbnail(scWindow: scWindow) {
                    thumbnailCache[windowId] = thumbnail
                    updateWindowDisplays()
                }
            }
        } catch {
            return
        }
    }
    private func captureWindowThumbnail(scWindow: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        let maxDimension: CGFloat = 400
        let aspectRatio = scWindow.frame.width / max(1, scWindow.frame.height)
        if aspectRatio > 1 {
            config.width = Int(maxDimension)
            config.height = Int(maxDimension / aspectRatio)
        } else {
            config.width = Int(maxDimension * aspectRatio)
            config.height = Int(maxDimension)
        }
        config.showsCursor = false
        config.capturesAudio = false
        config.scalesToFit = true
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return image
        } catch {
            return nil
        }
    }
    func updateAnimationProgress(_ progress: Double, state: OverviewState) {
        self.state = state
        updateWindowDisplays()
    }
    func onAnimationComplete(state: OverviewState) {
        self.state = state
        if case .closed = state {
            cleanup()
        }
        updateWindowDisplays()
    }
    func focusTargetWindow(_ handle: WindowHandle) {
        guard let wmController else { return }
        guard let workspaceId = wmController.runtimeWorkspaceId(for: handle) else { return }
        onActivateWindow?(handle, workspaceId)
    }
    func selectAndActivateWindow(_ handle: WindowHandle) {
        layout.setSelected(handle: handle)
        updateWindowDisplays()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self.dismiss()
        }
    }
    func closeWindow(_ handle: WindowHandle) {
        onCloseWindow?(handle)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.rebuildLayoutAfterWindowClose(removedHandle: handle)
        }
    }
    private func rebuildLayoutAfterWindowClose(removedHandle: WindowHandle) {
        let wasSelected = layout.selectedWindow()?.handle == removedHandle
        buildLayout()
        thumbnailCache.removeValue(forKey: layout.allWindows.first { $0.handle == removedHandle }?.windowId ?? 0)
        if wasSelected {
            if let first = layout.allWindows.first {
                layout.setSelected(handle: first.handle)
            }
        }
        updateWindowDisplays()
    }
    func updateSearchQuery(_ query: String) {
        searchQuery = query
        inputHandler?.searchQuery = query
        OverviewSearchFilter.filterWindows(in: &layout, query: query)
        OverviewSearchFilter.updateSelectionForSearch(layout: &layout)
        updateWindowDisplays()
    }
    func navigateSelection(_ direction: Direction) {
        let currentHandle = layout.selectedWindow()?.handle
        if let nextHandle = OverviewLayoutCalculator.findNextWindow(
            in: layout,
            from: currentHandle,
            direction: direction
        ) {
            layout.setSelected(handle: nextHandle)
            updateWindowDisplays()
        }
    }
    func activateSelectedWindow() {
        guard let selected = layout.selectedWindow() else { return }
        selectAndActivateWindow(selected.handle)
    }
    func adjustScrollOffset(by delta: CGFloat) {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let nextOffset = layout.scrollOffset - delta
        layout.scrollOffset = OverviewLayoutCalculator.clampedScrollOffset(
            nextOffset,
            layout: layout,
            screenFrame: screenFrame
        )
        updateWindowDisplays()
    }
    func handleScroll(delta: CGFloat, modifiers: NSEvent.ModifierFlags) {
        handleScroll(delta: delta, modifiers: modifiers, isPrecise: false)
    }
    func handleScroll(delta: CGFloat, modifiers: NSEvent.ModifierFlags, isPrecise: Bool) {
        if modifiers.contains([.option, .shift]) {
            guard abs(delta) > ScrollTuning.zoomEpsilon else { return }
            let step: CGFloat = delta > 0 ? ScrollTuning.zoomStep : -ScrollTuning.zoomStep
            layout.scale = (layout.scale + step).clamped(to: 0.5 ... 1.5)
            let previousOffset = layout.scrollOffset
            buildLayout()
            let screenFrame = NSScreen.main?.frame ?? .zero
            layout.scrollOffset = OverviewLayoutCalculator.clampedScrollOffset(
                previousOffset,
                layout: layout,
                screenFrame: screenFrame
            )
            updateWindowDisplays()
        } else {
            let multiplier = isPrecise
                ? ScrollTuning.preciseScrollMultiplier
                : ScrollTuning.nonPreciseScrollMultiplier
            adjustScrollOffset(by: delta * multiplier)
        }
    }
    private func cleanup() {
        thumbnailCaptureTask?.cancel()
        thumbnailCaptureTask = nil
        thumbnailCache.removeAll()
        inputHandler?.reset()
        searchQuery = ""
        layout = .init()
        dragGhostController?.endDrag()
        dragGhostController = nil
        dragSession = nil
        closeWindows()
    }
    private func detectRefreshRate(for displayId: CGDirectDisplayID) -> Double {
        if let mode = CGDisplayCopyDisplayMode(displayId) {
            return mode.refreshRate > 0 ? mode.refreshRate : 60.0
        }
        return 60.0
    }
    deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }
}
private extension OverviewController {
    struct DragSession {
        let handle: WindowHandle
        let windowId: Int
        let workspaceId: WorkspaceDescriptor.ID
        let startPoint: CGPoint
    }
    func beginDrag(handle: WindowHandle, startPoint: CGPoint) {
        guard let wmController else { return }
        guard let entry = wmController.workspaceManager.entry(for: handle) else { return }
        dragSession = DragSession(
            handle: handle,
            windowId: entry.windowId,
            workspaceId: entry.workspaceId,
            startPoint: startPoint
        )
        if let frame = AXWindowService.framePreferFast(entry.axRef) {
            if dragGhostController == nil {
                dragGhostController = DragGhostController()
            }
            dragGhostController?.beginDrag(
                windowId: entry.windowId,
                originalFrame: frame,
                cursorLocation: startPoint
            )
        }
    }
    func updateDrag(at point: CGPoint) {
        guard dragSession != nil else { return }
        dragGhostController?.updatePosition(cursorLocation: point)
        let target = resolveDragTarget(at: point)
        if target != layout.dragTarget {
            layout.dragTarget = target
            updateWindowDisplays()
        }
    }
    func endDrag(at point: CGPoint) {
        guard let session = dragSession else { return }
        dragGhostController?.updatePosition(cursorLocation: point)
        let target = layout.dragTarget
        layout.dragTarget = nil
        dragGhostController?.endDrag()
        dragSession = nil
        guard let target else {
            updateWindowDisplays()
            return
        }
        performDragAction(
            session: session,
            target: target
        )
        buildLayout()
        updateWindowDisplays()
    }
    func cancelDrag() {
        layout.dragTarget = nil
        dragGhostController?.endDrag()
        dragSession = nil
        updateWindowDisplays()
    }
    func resolveDragTarget(at point: CGPoint) -> OverviewDragTarget? {
        if let window = layout.windowAt(point: point) {
            guard window.handle != dragSession?.handle else { return nil }
            if isNiriLayout(workspaceId: window.workspaceId) {
                let position = layout.insertPosition(for: window, at: point)
                return .niriWindowInsert(
                    workspaceId: window.workspaceId,
                    targetHandle: window.handle,
                    position: position
                )
            }
            return .workspaceMove(workspaceId: window.workspaceId)
        }
        if let zone = layout.columnDropZone(at: point) {
            return .niriColumnInsert(
                workspaceId: zone.workspaceId,
                insertIndex: zone.insertIndex
            )
        }
        if let section = layout.workspaceSection(at: point) {
            return .workspaceMove(workspaceId: section.workspaceId)
        }
        return nil
    }
    func performDragAction(session: DragSession, target: OverviewDragTarget) {
        guard let wmController else { return }
        switch target {
        case let .workspaceMove(targetWsId):
            guard targetWsId != session.workspaceId else { return }
            _ = wmController.moveWindowToWorkspace(handle: session.handle, toWorkspaceId: targetWsId)
        case let .niriWindowInsert(targetWsId, targetHandle, position):
            guard isNiriLayout(workspaceId: targetWsId) else { return }
            if targetWsId != session.workspaceId {
                _ = wmController.moveWindowToWorkspace(handle: session.handle, toWorkspaceId: targetWsId)
            }
            let niriPosition = overviewInsertPositionToNiri(position)
            wmController.overviewInsertWindow(
                handle: session.handle,
                targetHandle: targetHandle,
                position: niriPosition,
                in: targetWsId
            )
            wmController.startWorkspaceAnimation(for: targetWsId)
        case let .niriColumnInsert(targetWsId, insertIndex):
            guard isNiriLayout(workspaceId: targetWsId) else { return }
            if targetWsId != session.workspaceId {
                _ = wmController.moveWindowToWorkspace(handle: session.handle, toWorkspaceId: targetWsId)
            }
            wmController.overviewInsertWindowInNewColumn(
                handle: session.handle,
                insertIndex: insertIndex,
                in: targetWsId
            )
            wmController.startWorkspaceAnimation(for: targetWsId)
        }
        wmController.refreshLayout()
    }
    func isNiriLayout(workspaceId: WorkspaceDescriptor.ID) -> Bool {
        guard let wmController else { return false }
        let layoutType = wmController.effectiveLayoutType(forWorkspaceId: workspaceId)
        return layoutType != .dwindle
    }
    func buildNiriDropZones() {
        guard let wmController else { return }
        let gapBase = CGFloat(wmController.workspaceManager.gaps)
        var zonesByWorkspace: [WorkspaceDescriptor.ID: [OverviewColumnDropZone]] = [:]
        for section in layout.workspaceSections {
            guard isNiriLayout(workspaceId: section.workspaceId) else { continue }
            let niriColumns = layout.niriColumnsByWorkspace[section.workspaceId] ?? []
            guard !niriColumns.isEmpty else { continue }
            let columnFrames = niriColumns.map(\.frame)
            let zoneWidth = max(12.0, min(30.0, gapBase))
            var zones: [OverviewColumnDropZone] = []
            let leftBoundary = columnFrames.first?.minX ?? section.gridFrame.minX
            zones.append(OverviewColumnDropZone(
                workspaceId: section.workspaceId,
                insertIndex: 0,
                frame: CGRect(
                    x: leftBoundary - zoneWidth / 2,
                    y: section.gridFrame.minY,
                    width: zoneWidth,
                    height: section.gridFrame.height
                )
            ))
            if columnFrames.count > 1 {
                for idx in 0 ..< (columnFrames.count - 1) {
                    let boundary = (columnFrames[idx].maxX + columnFrames[idx + 1].minX) / 2
                    zones.append(OverviewColumnDropZone(
                        workspaceId: section.workspaceId,
                        insertIndex: idx + 1,
                        frame: CGRect(
                            x: boundary - zoneWidth / 2,
                            y: section.gridFrame.minY,
                            width: zoneWidth,
                            height: section.gridFrame.height
                        )
                    ))
                }
            }
            let rightBoundary = columnFrames.last?.maxX ?? section.gridFrame.maxX
            zones.append(OverviewColumnDropZone(
                workspaceId: section.workspaceId,
                insertIndex: columnFrames.count,
                frame: CGRect(
                    x: rightBoundary - zoneWidth / 2,
                    y: section.gridFrame.minY,
                    width: zoneWidth,
                    height: section.gridFrame.height
                )
            ))
            zonesByWorkspace[section.workspaceId] = zones
        }
        layout.niriColumnDropZonesByWorkspace = zonesByWorkspace
    }
    func overviewInsertPositionToNiri(_ position: InsertPosition) -> InsertPosition {
        switch position {
        case .before:
            return .after
        case .after:
            return .before
        case .swap:
            return .swap
        }
    }
    func buildNiriColumnLayout(
        windowData: [WindowHandle: (entry: WindowModel.Entry, title: String, appName: String, appIcon: NSImage?, frame: CGRect)]
    ) {
        guard let wmController else { return }
        guard let controllerSnapshot = wmController.latestControllerSnapshot else {
            layout.niriColumnsByWorkspace = [:]
            return
        }
        var columnsByWorkspace: [WorkspaceDescriptor.ID: [OverviewNiriColumn]] = [:]
        for section in layout.workspaceSections {
            guard isNiriLayout(workspaceId: section.workspaceId) else { continue }
            let snapshotColumns = snapshotColumns(
                for: section.workspaceId,
                controllerSnapshot: controllerSnapshot
            )
            guard !snapshotColumns.isEmpty else { continue }
            let columnCount = snapshotColumns.count
            let spacing = OverviewLayoutMetrics.windowSpacing
            let totalSpacing = spacing * CGFloat(max(0, columnCount - 1))
            let rawWidth = (section.gridFrame.width - totalSpacing) / CGFloat(columnCount)
            let columnWidth = min(
                OverviewLayoutMetrics.maxThumbnailWidth,
                max(OverviewLayoutMetrics.minThumbnailWidth, rawWidth)
            )
            let totalWidth = CGFloat(columnCount) * columnWidth + totalSpacing
            let startX = section.gridFrame.minX + max(0, (section.gridFrame.width - totalWidth) / 2)
            let columnHeight = section.gridFrame.height
            var columns: [OverviewNiriColumn] = []
            for (idx, snapshotColumn) in snapshotColumns.enumerated() {
                let orderedHandles = snapshotColumn.windowHandles
                let columnX = startX + CGFloat(idx) * (columnWidth + spacing)
                let columnFrame = CGRect(
                    x: columnX,
                    y: section.gridFrame.minY,
                    width: columnWidth,
                    height: columnHeight
                )
                let visibleHandles = orderedHandles.filter { windowData[$0] != nil }
                guard !visibleHandles.isEmpty else { continue }
                let tileCount = max(1, visibleHandles.count)
                let innerSpacing: CGFloat = 6
                let totalInnerSpacing = innerSpacing * CGFloat(max(0, tileCount - 1))
                let tileHeight = max(30, (columnHeight - totalInnerSpacing) / CGFloat(tileCount))
                for (tileIdx, handle) in visibleHandles.enumerated() {
                    let tileY = columnFrame.maxY - CGFloat(tileIdx + 1) * tileHeight - CGFloat(tileIdx) * innerSpacing
                    let tileFrame = CGRect(
                        x: columnFrame.minX,
                        y: tileY,
                        width: columnFrame.width,
                        height: tileHeight
                    )
                    layout.updateWindowFrame(handle: handle, frame: tileFrame)
                }
                let columnEntry = OverviewNiriColumn(
                    workspaceId: section.workspaceId,
                    columnIndex: idx,
                    frame: columnFrame,
                    windowHandles: visibleHandles
                )
                columns.append(columnEntry)
            }
            columnsByWorkspace[section.workspaceId] = columns
        }
        layout.niriColumnsByWorkspace = columnsByWorkspace
    }

    private func snapshotColumns(
        for workspaceId: WorkspaceDescriptor.ID,
        controllerSnapshot: WMControllerControllerSnapshot
    ) -> [(columnIndex: Int, windowHandles: [WindowHandle])] {
        var columns: [(columnIndex: Int, windowHandles: [WindowHandle])] = []
        var columnIndexByKey: [UUID: Int] = [:]

        for window in controllerSnapshot.orderedWindows(in: workspaceId) {
            let key = window.columnId ?? window.handleId
            if let existingIndex = columnIndexByKey[key] {
                columns[existingIndex].windowHandles.append(window.handle)
                continue
            }

            columnIndexByKey[key] = columns.count
            columns.append(
                (columnIndex: window.columnIndex >= 0 ? window.columnIndex : columns.count, windowHandles: [window.handle])
            )
        }

        return columns.sorted { lhs, rhs in
            if lhs.columnIndex != rhs.columnIndex {
                return lhs.columnIndex < rhs.columnIndex
            }
            return lhs.windowHandles.first?.id.uuidString ?? "" < rhs.windowHandles.first?.id.uuidString ?? ""
        }
    }
}
