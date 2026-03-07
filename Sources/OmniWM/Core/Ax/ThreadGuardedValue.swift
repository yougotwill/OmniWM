import Foundation
@usableFromInline
final class ThreadGuardedValue<Value>: Sendable {
    @usableFromInline
    nonisolated(unsafe) var _value: Value?
    @usableFromInline
    let threadToken: AppThreadToken
    init(_ value: Value) {
        threadToken = appThreadToken!
        _value = value
    }
    @inlinable
    var value: Value {
        get {
            _value!
        }
        set(newValue) {
            _value = newValue
        }
    }
    @inlinable
    var valueIfExists: Value? {
        return _value
    }
    func destroy() {
        _value = nil
    }
    @inlinable
    subscript<K: Hashable, V>(key: K) -> V? where Value == [K: V] {
        get {
            return _value?[key]
        }
        set {
            _value?[key] = newValue
        }
    }
    @inlinable
    func contains<T: Hashable>(_ element: T) -> Bool where Value == Set<T> {
        return _value?.contains(element) ?? false
    }
    @inlinable
    func insert<T: Hashable>(_ element: T) where Value == Set<T> {
        _value?.insert(element)
    }
    @inlinable
    @discardableResult
    func remove<T: Hashable>(_ element: T) -> T? where Value == Set<T> {
        return _value?.remove(element)
    }
}
extension ThreadGuardedValue {
    @inlinable
    func forEachKey<K: Hashable, V>(_ body: (K) -> Void) where Value == [K: V] {
        _value?.keys.forEach(body)
    }
}
