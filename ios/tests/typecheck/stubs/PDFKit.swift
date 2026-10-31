import Foundation
import UIKit
public enum PDFDisplayBox: Int { case mediaBox, cropBox, bleedBox, trimBox, artBox }
open class PDFSelection: NSObject { open var string: String? { nil } }
open class PDFPage: NSObject {
    public override init() {}
    public init?(image: UIImage) {}
    open var string: String? { nil }
    open var attributedString: NSAttributedString? { nil }
    open var numberOfCharacters: Int { 0 }
    open var rotation: Int = 0
    open func bounds(for box: PDFDisplayBox) -> CGRect { .zero }
    open func draw(with box: PDFDisplayBox, to context: CGContext) {}
    open func characterBounds(at index: Int) -> CGRect { .zero }
    open func selection(for range: NSRange) -> PDFSelection? { nil }
    open func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> UIImage { UIImage() }
    open var document: PDFDocument? { nil }
}
open class PDFDocument: NSObject {
    public override init() {}
    public init?(url: URL) {}
    public init?(data: Data) {}
    open var pageCount: Int { 0 }
    open var string: String? { nil }
    open var isEncrypted: Bool { false }
    open var isLocked: Bool { false }
    open func page(at index: Int) -> PDFPage? { nil }
    open func insert(_ page: PDFPage, at index: Int) {}
    open func dataRepresentation() -> Data? { nil }
    open func write(to url: URL) -> Bool { true }
    open func unlock(withPassword: String) -> Bool { false }
}
public enum PDFDisplayMode: Int { case singlePage, singlePageContinuous, twoUp, twoUpContinuous }
open class PDFView: UIView {
    open var document: PDFDocument?
    open var autoScales = false
    open var displayMode: PDFDisplayMode = .singlePageContinuous
    open var displayDirection: PDFDisplayDirection = .vertical
    open var pageShadowsEnabled = true
    open var minScaleFactor: CGFloat = 0
    open var maxScaleFactor: CGFloat = 0
    open var scaleFactorForSizeToFit: CGFloat { 1 }
    open var scaleFactor: CGFloat = 1
}
public enum PDFDisplayDirection: Int { case vertical, horizontal }
