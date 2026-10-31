import Foundation
import UIKit
open class VNObservation: NSObject {}
open class VNRecognizedText: NSObject { open var string: String { "" }; open var confidence: Float { 0 } }
open class VNRecognizedTextObservation: VNObservation {
    open func topCandidates(_ n: Int) -> [VNRecognizedText] { [] }
    open var boundingBox: CGRect { .zero }
}
open class VNRequest: NSObject {
    public typealias CompletionHandler = (VNRequest, Error?) -> Void
    open var results: [VNObservation]? { nil }
}
open class VNImageBasedRequest: VNRequest {}
public enum VNRequestTextRecognitionLevel: Int { case accurate, fast }
open class VNRecognizeTextRequest: VNImageBasedRequest {
    public init(completionHandler: CompletionHandler? = nil) {}
    public override init() {}
    open var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    open var usesLanguageCorrection = true
    open var recognitionLanguages: [String] = []
}
open class VNImageRequestHandler: NSObject {
    public init(cgImage: CGImage, options: [AnyHashable: Any] = [:]) {}
    public init(url: URL, options: [AnyHashable: Any] = [:]) {}
    open func perform(_ requests: [VNRequest]) throws {}
}
