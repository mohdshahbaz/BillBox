import Foundation
open class BGTask { public var identifier: String { "" }; open var expirationHandler: (() -> Void)?; open func setTaskCompleted(success: Bool) {} }
open class BGAppRefreshTask: BGTask {}
open class BGProcessingTask: BGTask {}
open class BGTaskRequest { public var identifier: String; public var earliestBeginDate: Date?; public init(identifier: String) { self.identifier = identifier } }
open class BGAppRefreshTaskRequest: BGTaskRequest {}
open class BGTaskScheduler {
    public static let shared = BGTaskScheduler()
    public func register(forTaskWithIdentifier: String, using: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool { true }
    public func submit(_ r: BGTaskRequest) throws {}
    public func cancel(taskRequestWithIdentifier: String) {}
}
