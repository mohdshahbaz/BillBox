import Foundation
import PDFKit
import Vision
import UIKit

/// Reads the text of each page of a supplier PDF, the Mac's way.
///   Text PDFs: the Mac's own reader runs inside the app (PDFReaderWeb: pdf.js 1.10.100, as in pdf-parse, plus the Mac's
///              pdfExtract.js line joining and watermark removal), so every page reads exactly as on the Mac.
///   Scans (no text layer): Apple's on-device Vision text recognition, at most 12 pages (decision D5).
enum PDFText {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    static func read(_ data: Data) async throws -> (pages: [String], method: String) {
        let pages: [String]
        do {
            pages = try await PDFReaderWeb.shared.pages(data)
        } catch {
            throw HttpError(422, "This file could not be read as a PDF.")
        }
        // the Mac: pages.join('').replace(/\s/g, '').length >= 40
        if pages.joined().unicodeScalars.filter({ !CharacterSet.whitespacesAndNewlines.contains($0) }).count >= 40 { return (pages, "text") }
        guard let doc = PDFDocument(data: data) else { throw HttpError(422, "This file could not be read as a PDF.") }
        let ocr = try await recognise(doc)
        if ocr.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw HttpError(422, "No text could be recognised in this scanned PDF.") }
        return (ocr, "ocr")
    }

    /// Vision OCR, one string per page, lines top to bottom.
    static func recognise(_ doc: PDFDocument) async throws -> [String] {
        var out: [String] = []
        for i in 0..<min(doc.pageCount, 12) {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let scale: CGFloat = 200.0 / 72.0
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            let img = page.thumbnail(of: size, for: .mediaBox)
            guard let cg = img.cgImage else { out.append(""); continue }
            let lines = try await textLines(cg)
            out.append(lines.joined(separator: "\n"))
        }
        return out
    }

    /// Vision OCR of one picture (a page or a photo), lines top to bottom, words left to right. Handwriting is read too.
    static func textLines(_ cg: CGImage, languageCorrection: Bool = false) async throws -> [String] {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String], Error>) in
            let once = Once()
            let req = VNRecognizeTextRequest { r, e in
                guard once.first() else { return }
                if let e { c.resume(throwing: e); return }
                let obs = (r.results as? [VNRecognizedTextObservation]) ?? []
                // group observations into lines by their vertical position, then left to right
                var rows: [(y: CGFloat, items: [(x: CGFloat, s: String)])] = []
                for o in obs {
                    guard let s = o.topCandidates(1).first?.string else { continue }
                    let y = o.boundingBox.midY, x = o.boundingBox.minX
                    if let k = rows.firstIndex(where: { abs($0.y - y) < o.boundingBox.height * 0.5 }) { rows[k].items.append((x, s)) } else { rows.append((y, [(x, s)])) }
                }
                rows.sort { $0.y > $1.y }
                c.resume(returning: rows.map { $0.items.sorted { $0.x < $1.x }.map { $0.s }.joined(separator: " ") })
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = languageCorrection
            // recognition takes a moment: keep it off the threads Swift uses for everything else
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req]) } catch { if once.first() { c.resume(throwing: error) } }
            }
        }
    }
}

/// True the first time only (a continuation must be resumed exactly once).
final class Once {
    private var used = false
    private let lock = NSLock()
    func first() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
