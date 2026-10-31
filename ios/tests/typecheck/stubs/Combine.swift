// Type-check stub (Linux only).
import Foundation
public final class ObservableObjectPublisher { public init() {}; public func send() {} }
public protocol ObservableObject: AnyObject {
    associatedtype ObjectWillChangePublisher = ObservableObjectPublisher
    var objectWillChange: ObjectWillChangePublisher { get }
}
extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    public var objectWillChange: ObservableObjectPublisher { ObservableObjectPublisher() }
}
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public struct Publisher {}
    public var projectedValue: Publisher { Publisher() }
}

