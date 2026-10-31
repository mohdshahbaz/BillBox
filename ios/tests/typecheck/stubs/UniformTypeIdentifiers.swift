// Type-check stub (Linux only). Mirrors the iOS 16 SDK surface BillBox uses.
import Foundation
public struct UTType: Hashable, Sendable {
    public init?(filenameExtension: String) {}
    public init(exportedAs: String) {}
    public static let pdf = UTType(exportedAs: "")
    public static let folder = UTType(exportedAs: "")
    public static let data = UTType(exportedAs: "")
    public static let zip = UTType(exportedAs: "")
    public static let json = UTType(exportedAs: "")
    public static let commaSeparatedText = UTType(exportedAs: "")
    public static let item = UTType(exportedAs: "")
    public static let image = UTType(exportedAs: "")
    public static let plainText = UTType(exportedAs: "")
    public static let spreadsheet = UTType(exportedAs: "")
    public static let database = UTType(exportedAs: "")
    public var preferredFilenameExtension: String? { nil }
}
