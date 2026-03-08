import Foundation

struct ViewportState {
    var activeColumnIndex: Int = 0
    var selectedNodeId: NodeId?
    var animationClock: AnimationClock?
    var displayRefreshRate: Double = 60.0
}
