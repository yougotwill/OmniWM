import Foundation
import QuartzCore
enum WorkspaceSwitch {
    case animation(SpringAnimation)
    func currentIndex(at time: TimeInterval = CACurrentMediaTime()) -> Double {
        switch self {
        case let .animation(anim):
            anim.value(at: time)
        }
    }
    func isAnimating(at time: TimeInterval = CACurrentMediaTime()) -> Bool {
        switch self {
        case let .animation(anim):
            !anim.isComplete(at: time)
        }
    }
    mutating func tick(at time: TimeInterval) -> Bool {
        switch self {
        case let .animation(anim):
            !anim.isComplete(at: time)
        }
    }
}
