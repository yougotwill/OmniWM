import ApplicationServices
import CoreGraphics
import Foundation
final class WindowHandle: Hashable {
    let id: UUID
    let pid: pid_t
    let axElement: AXUIElement
    init(id: UUID, pid: pid_t, axElement: AXUIElement) {
        self.id = id
        self.pid = pid
        self.axElement = axElement
    }
    static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool {
        lhs === rhs
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
