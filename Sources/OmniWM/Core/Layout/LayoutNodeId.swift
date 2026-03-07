import Foundation
struct NodeId: Hashable, Equatable {
    let uuid: UUID
    init() {
        uuid = UUID()
    }
    init(uuid: UUID) {
        self.uuid = uuid
    }
}
