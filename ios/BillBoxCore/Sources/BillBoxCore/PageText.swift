import Foundation

/// One run of text on a PDF page, in PDF coordinates (origin bottom-left): x and y of the baseline start, width, letter size and slant.
public struct TextRun {
    public var str: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var size: Double
    public var angle: Double   // degrees, 0 = horizontal
    public init(str: String, x: Double, y: Double, width: Double, size: Double, angle: Double) {
        self.str = str; self.x = x; self.y = y; self.width = width; self.size = size; self.angle = angle
    }
}

/// Page text exactly as the Mac builds it from pdf.js runs (backend/src/services/pdfExtract.js pageTextFromItems):
/// watermarks dropped, runs on the same visual row joined, a visible gap becomes a space.
public enum PageText {
    public static let watermarkScale = 3.0

    static func folded(_ a: Double) -> Double {
        var x = abs(a).truncatingRemainder(dividingBy: 180)
        if x > 90 { x = 180 - x }
        return x
    }

    public static func dropWatermarks(_ runs: [TextRun]) -> [TextRun] {
        var sizes: [Double] = []
        for r in runs {
            let n = r.str.filter { !$0.isWhitespace }.utf16.count
            for _ in 0..<n { sizes.append(r.size) }
        }
        if sizes.isEmpty { return runs }
        sizes.sort()
        let median = sizes[sizes.count / 2]
        return runs.filter { r in
            if JS.trim(r.str).isEmpty { return true }   // spaces stay where they are
            if median > 0 && r.size >= median * watermarkScale { return false }
            let a = folded(r.angle)
            if a >= 15 && a <= 75 { return false }
            return true
        }
    }

    public static func fromRuns(_ runs: [TextRun]) -> String {
        struct Cell { let x: Double; let w: Double; let s: String }
        var rows: [(y: Double, cells: [Cell])] = []
        for it in dropWatermarks(runs) {
            let y = JS.round(it.y)
            if let i = rows.firstIndex(where: { abs($0.y - y) <= 2 }) { rows[i].cells.append(Cell(x: it.x, w: it.width, s: it.str)) } else { rows.append((y, [Cell(x: it.x, w: it.width, s: it.str)])) }
        }
        rows = stableSorted(rows) { $0.y > $1.y }
        func joinRow(_ cells: [Cell]) -> String {
            var out = ""
            var prevEnd: Double?
            for c in stableSorted(cells, by: { $0.x < $1.x }) {
                if let p = prevEnd, c.x - p > 1.2 { out += " " }
                out += c.s
                prevEnd = c.x + c.w
            }
            return out
        }
        return rows.map { JS.trim(rx("\\s+", "g").replace(joinRow($0.cells), " ")) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// pdf.js-style items (`str`, `transform` [a b c d e f], `width`) -> runs. Used by the tests and kept beside the iOS reader.
    public static func runs(fromPdfJsItems items: [Row]) -> [TextRun] {
        items.compactMap { it in
            guard let s = it["str"] as? String, let t = it["transform"] as? [Any], t.count == 6 else { return nil }
            let n = t.map { JS.number($0) }
            var size = (n[2] * n[2] + n[3] * n[3]).squareRoot()
            if size == 0 { size = (n[0] * n[0] + n[1] * n[1]).squareRoot() }
            return TextRun(str: s, x: n[4], y: n[5], width: JS.number(it["width"] ?? nil).isFinite ? JS.number(it["width"] ?? nil) : 0, size: size,
                           angle: atan2(n[1], n[0]) * 180 / Double.pi)
        }
    }
}
