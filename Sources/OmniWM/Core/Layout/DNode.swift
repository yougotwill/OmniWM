import ApplicationServices
import CoreGraphics
import Foundation
struct WindowHandle: Hashable, Sendable {
    let id: UUID
    let pid: pid_t
}
