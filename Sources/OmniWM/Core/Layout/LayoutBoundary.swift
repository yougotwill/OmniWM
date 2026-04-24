// SPDX-License-Identifier: GPL-2.0-only
import AppKit
import Foundation

struct LayoutWindowSnapshot {
    let token: WindowToken
    let constraints: WindowSizeConstraints
    let hiddenState: WindowModel.HiddenState?
    let layoutReason: LayoutReason
    let nativeFullscreenRestore: NativeFullscreenRestoreContext?

    var isNativeFullscreenSuspended: Bool {
        layoutReason == .nativeFullscreen
    }

    var isRestoringNativeFullscreen: Bool {
        nativeFullscreenRestore != nil
    }

    var restoreFrame: CGRect? {
        nativeFullscreenRestore?.restoreFrame
    }
}

struct NativeFullscreenRestoreContext: Equatable {
    let originalToken: WindowToken
    let currentToken: WindowToken
    let workspaceId: WorkspaceDescriptor.ID
    let restoreFrame: CGRect?
    let capturedTopologyProfile: TopologyProfile?
    let niriState: ManagedWindowRestoreSnapshot.NiriState?
    let replacementMetadata: ManagedReplacementMetadata?
}

struct LayoutMonitorSnapshot {
    let monitorId: Monitor.ID
    let displayId: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let workingFrame: CGRect
    let scale: CGFloat
    let orientation: Monitor.Orientation
}

struct WorkspaceRefreshInput {
    let workspaceId: WorkspaceDescriptor.ID
    let monitor: LayoutMonitorSnapshot
    let windows: [LayoutWindowSnapshot]
    let isActiveWorkspace: Bool
}

enum NiriRemovalRevealSide: Equatable {
    case left
    case right

    static func closestHorizontalEdge(
        to frame: CGRect,
        in viewport: CGRect
    ) -> NiriRemovalRevealSide {
        let viewportMidX = viewport.midX
        return frame.midX <= viewportMidX ? .left : .right
    }
}

enum NiriRemovalAnimationPolicy: Equatable {
    case ordinary
    case staticViewportPreserving

    var shouldStartCloseAnimation: Bool {
        self == .ordinary
    }

    var shouldStartSurvivorMoveAnimations: Bool {
        self == .ordinary
    }

    var shouldStartColumnAnimations: Bool {
        self == .ordinary
    }

    var shouldStartScrollAnimation: Bool {
        self == .ordinary
    }

    var shouldDeferFrameApplication: Bool {
        self == .ordinary
    }

    func merging(_ other: NiriRemovalAnimationPolicy) -> NiriRemovalAnimationPolicy {
        if self == .staticViewportPreserving || other == .staticViewportPreserving {
            return .staticViewportPreserving
        }
        return .ordinary
    }
}

enum NiriRemovalDiagnosticPhase: Equatable {
    case intake
    case topologyPlanning
    case animationDirectives
    case frameApplication
    case displayLinkTick
}

enum NiriRemovalViewportAction: Equatable {
    case none
    case staticPreserved
    case animated
}

struct NiriRemovalAnimationDiagnostic: Equatable {
    var phase: NiriRemovalDiagnosticPhase
    var workspaceId: WorkspaceDescriptor.ID
    var removedNodeId: NodeId?
    var removedWindow: WindowToken? = nil
    var recoveryTarget: WindowToken?
    var revealSide: NiriRemovalRevealSide?
    var activeColumnBefore: Int?
    var activeColumnAfter: Int?
    var currentOffset: CGFloat?
    var targetOffset: CGFloat?
    var stationaryOffset: CGFloat?
    var viewportAction: NiriRemovalViewportAction
    var animationPolicy: NiriRemovalAnimationPolicy
    var closeAnimation: Bool
    var survivorMoveAnimation: Bool
    var columnAnimation: Bool
    var viewportAnimation: Bool
    var startNiriScroll: Bool
    var skipFrameApplicationForAnimation: Bool

    func withPhase(
        _ phase: NiriRemovalDiagnosticPhase,
        closeAnimation: Bool? = nil,
        survivorMoveAnimation: Bool? = nil,
        columnAnimation: Bool? = nil,
        viewportAnimation: Bool? = nil,
        startNiriScroll: Bool? = nil,
        skipFrameApplicationForAnimation: Bool? = nil
    ) -> NiriRemovalAnimationDiagnostic {
        var diagnostic = self
        diagnostic.phase = phase
        if let closeAnimation {
            diagnostic.closeAnimation = closeAnimation
        }
        if let survivorMoveAnimation {
            diagnostic.survivorMoveAnimation = survivorMoveAnimation
        }
        if let columnAnimation {
            diagnostic.columnAnimation = columnAnimation
        }
        if let viewportAnimation {
            diagnostic.viewportAnimation = viewportAnimation
        }
        if let startNiriScroll {
            diagnostic.startNiriScroll = startNiriScroll
        }
        if let skipFrameApplicationForAnimation {
            diagnostic.skipFrameApplicationForAnimation = skipFrameApplicationForAnimation
        }
        return diagnostic
    }
}

struct NiriWindowRemovalSeed {
    let removedNodeIds: [NodeId]
    let oldFrames: [WindowToken: CGRect]
    var removedWindow: WindowToken?
    let selectedRemovalAnchorNodeId: NodeId?
    let revealSide: NiriRemovalRevealSide?
    let shouldRecoverFocus: Bool
    var animationPolicy: NiriRemovalAnimationPolicy = .ordinary
}

struct NiriWorkspaceSnapshot {
    let workspaceId: WorkspaceDescriptor.ID
    let monitor: LayoutMonitorSnapshot
    let windows: [LayoutWindowSnapshot]
    let viewportState: ViewportState
    let preferredFocusToken: WindowToken?
    let confirmedFocusedToken: WindowToken?
    let pendingFocusedToken: WindowToken?
    let pendingFocusedWorkspaceId: WorkspaceDescriptor.ID?
    let isNonManagedFocusActive: Bool
    let hasCompletedInitialRefresh: Bool
    let useScrollAnimationPath: Bool
    let removalSeed: NiriWindowRemovalSeed?
    let gap: CGFloat
    let outerGaps: LayoutGaps.OuterGaps
    let displayRefreshRate: Double
    let isActiveWorkspace: Bool
    let isInteractionWorkspace: Bool
}

struct DwindleWorkspaceSnapshot {
    let workspaceId: WorkspaceDescriptor.ID
    let monitor: LayoutMonitorSnapshot
    let windows: [LayoutWindowSnapshot]
    let preferredFocusToken: WindowToken?
    let confirmedFocusedToken: WindowToken?
    let selectedToken: WindowToken?
    let settings: ResolvedDwindleSettings
    let displayRefreshRate: Double
    let isActiveWorkspace: Bool
}

struct LayoutFrameChange {
    let token: WindowToken
    let frame: CGRect
    let forceApply: Bool
}

struct LayoutRestoreChange {
    let token: WindowToken
    let hiddenState: WindowModel.HiddenState
}

struct LayoutHideRequest {
    let token: WindowToken
    let side: HideSide
    let hiddenFrame: CGRect
}

enum LayoutVisibilityChange {
    case show(WindowToken)
    case hide(LayoutHideRequest)
}

struct LayoutFocusedFrame {
    let token: WindowToken
    let frame: CGRect
}

enum BorderUpdateMode {
    case coordinated
    case direct
    case none
}



struct WorkspaceLayoutDiff {
    var frameChanges: [LayoutFrameChange] = []
    var visibilityChanges: [LayoutVisibilityChange] = []
    var restoreChanges: [LayoutRestoreChange] = []
    var focusedFrame: LayoutFocusedFrame?
    var borderMode: BorderUpdateMode = .coordinated
}

struct WorkspaceSessionPatch {
    let workspaceId: WorkspaceDescriptor.ID
    var viewportState: ViewportState?
    var rememberedFocusToken: WindowToken?
}

struct WorkspaceSessionTransfer {
    var sourcePatch: WorkspaceSessionPatch?
    var targetPatch: WorkspaceSessionPatch?
}

enum AnimationDirective {
    case none
    case startNiriScroll(workspaceId: WorkspaceDescriptor.ID)
    case startDwindleAnimation(workspaceId: WorkspaceDescriptor.ID, monitorId: Monitor.ID)
    case activateWindow(token: WindowToken)
    case updateTabbedOverlays
}

enum LayoutFocusIntent {
    case focusWindow(token: WindowToken)
    case completeFocusedRemovalRecovery(workspaceId: WorkspaceDescriptor.ID, target: WindowToken?)
}

struct RefreshVisibilityEffect {
    let activeWorkspaceIds: Set<WorkspaceDescriptor.ID>
}

struct RefreshExecutionEffects {
    var visibility: RefreshVisibilityEffect?
    var requestWorkspaceBarRefresh: Bool = false
    var workspaceBarProjectionInvalidatedWorkspaceIds: Set<WorkspaceDescriptor.ID> = []
    var updateTabbedOverlays: Bool = false
    var refreshFocusedBorderForVisibilityState: Bool = false
    var focusValidationWorkspaceIds: [WorkspaceDescriptor.ID] = []
    var nativeFullscreenRestoreWorkspaceIds: [WorkspaceDescriptor.ID] = []
    var markInitialRefreshComplete: Bool = false
    var drainDeferredCreatedWindows: Bool = false
    var subscribeManagedWindows: Bool = false
}

struct ManagedRestoreMaterialStateChange {
    let token: WindowToken
    let reason: ManagedRestoreTriggerReason
}

struct WorkspaceLayoutPlan {
    let workspaceId: WorkspaceDescriptor.ID
    let monitor: LayoutMonitorSnapshot
    var sessionPatch: WorkspaceSessionPatch
    var diff: WorkspaceLayoutDiff
    var animationDirectives: [AnimationDirective] = []
    var focusIntents: [LayoutFocusIntent] = []
    var nativeFullscreenRestoreFinalizeTokens: [WindowToken] = []
    var managedRestoreMaterialStateChanges: [ManagedRestoreMaterialStateChange] = []
    var persistManagedRestoreSnapshots: Bool = true
    var skipFrameApplicationForAnimation: Bool = false
    var niriRemovalAnimationDiagnostic: NiriRemovalAnimationDiagnostic?
}

typealias RefreshPostLayoutAction = @MainActor () -> Void

struct RefreshExecutionPlan {
    var workspacePlans: [WorkspaceLayoutPlan] = []
    var effects: RefreshExecutionEffects = .init()
    var postLayoutActions: [RefreshPostLayoutAction] = []
}
