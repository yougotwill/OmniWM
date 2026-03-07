import Foundation
enum RefreshSessionEvent {
    case axWindowCreated
    case axWindowChanged
    case appHidden
    case appUnhidden
    case timerRefresh
    var requiresFullEnumeration: Bool {
        switch self {
        case .timerRefresh:
            true
        default:
            false
        }
    }
    var debounceInterval: UInt64 {
        switch self {
        case .axWindowChanged:
            8_000_000
        case .axWindowCreated:
            4_000_000
        default:
            0
        }
    }
}
