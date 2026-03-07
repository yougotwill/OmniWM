import Foundation
enum LayoutReason: Codable, Equatable {
    case standard
    case macosHiddenApp
}
enum ParentKind: Codable, Equatable {
    case tilingContainer
}
