import CoreGraphics
enum ColumnDisplay: Equatable {
    case normal
    case tabbed
}
enum SizingMode: Equatable {
    case normal
    case fullscreen
}
enum ProportionalSize: Equatable {
    case proportion(CGFloat)
    case fixed(CGFloat)
    var value: CGFloat {
        switch self {
        case let .proportion(p): p
        case let .fixed(f): f
        }
    }
    var isProportion: Bool {
        if case .proportion = self { return true }
        return false
    }
    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }
    static let `default` = ProportionalSize.proportion(1.0)
}
enum WeightedSize: Equatable {
    case auto(weight: CGFloat)
    case fixed(CGFloat)
    var weight: CGFloat {
        switch self {
        case let .auto(w): w
        case .fixed: 0
        }
    }
    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }
    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }
    static let `default` = WeightedSize.auto(weight: 1.0)
}
struct WindowSizeConstraints: Equatable {
    var minSize: CGSize
    var maxSize: CGSize
    var isFixed: Bool
    static let unconstrained = WindowSizeConstraints(
        minSize: CGSize(width: 1, height: 1),
        maxSize: .zero,
        isFixed: false
    )
    static func fixed(size: CGSize) -> WindowSizeConstraints {
        WindowSizeConstraints(
            minSize: size,
            maxSize: size,
            isFixed: true
        )
    }
    var hasMinWidth: Bool {
        minSize.width > 1
    }
    var hasMinHeight: Bool {
        minSize.height > 1
    }
    var hasMaxWidth: Bool {
        maxSize.width > 0
    }
    var hasMaxHeight: Bool {
        maxSize.height > 0
    }
    func clampHeight(_ height: CGFloat) -> CGFloat {
        var result = height
        if hasMinHeight {
            result = max(result, minSize.height)
        }
        if hasMaxHeight {
            result = min(result, maxSize.height)
        }
        return result
    }
    func clampWidth(_ width: CGFloat) -> CGFloat {
        var result = width
        if hasMinWidth {
            result = max(result, minSize.width)
        }
        if hasMaxWidth {
            result = min(result, maxSize.width)
        }
        return result
    }
}
struct PresetSize: Equatable {
    enum Kind: Equatable {
        case proportion(CGFloat)
        case fixed(CGFloat)
        var value: CGFloat {
            switch self {
            case let .proportion(p): p
            case let .fixed(f): f
            }
        }
    }
    let kind: Kind
    static func proportion(_ value: CGFloat) -> PresetSize {
        PresetSize(kind: .proportion(value))
    }
    static func fixed(_ value: CGFloat) -> PresetSize {
        PresetSize(kind: .fixed(value))
    }
    var asProportionalSize: ProportionalSize {
        switch kind {
        case let .proportion(p): .proportion(p)
        case let .fixed(f): .fixed(f)
        }
    }
}
