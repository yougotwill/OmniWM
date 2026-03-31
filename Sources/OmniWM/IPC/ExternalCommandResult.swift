import Foundation

enum ExternalCommandResult: Equatable, Sendable, Error {
    case executed
    case ignoredDisabled
    case ignoredOverview
    case ignoredLayoutMismatch
    case staleWindowId
    case notFound
    case invalidArguments
}
