import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal .xlsx writer (backend/src/utils/xlsx.js): several sheets, bold headers, number formats, column widths, frozen header row.
enum XLSX {
    struct Col { let h: String; let k: String; let w: Double; let t: String }
    struct Sheet { let name: String; let cols: [Col]; let rows: [Row]; var title: String? = nil; var total: Row? = nil }

    static func esc(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "&": out += "&amp;"
            case "\"": out += "&quot;"
            default:
                let v = ch.value
                if v <= 0x08 || v == 0x0b || v == 0x0c || (v >= 0x0e && v <= 0x1f) { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func colName(_ i: Int) -> String {
        var s = ""
        var n = i + 1
        while n > 0 { s = String(UnicodeScalar(UInt8(65 + (n - 1) % 26))) + s; n = (n - 1) / 26 }
        return s
    }

    // style ids: 0 normal, 1 bold header (grey fill, border), 2 number 0.00, 3 integer, 4 bold title, 5 bold number total, 6 bold text total
    static let STYLES = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts>
    <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE3EAF3"/></patternFill></fill></fills>
    <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF8A99AD"/></bottom><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="7">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
    <xf numFmtId="4" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyNumberFormat="1" applyBorder="1"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
    </cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """

    static func cell(_ c: String, _ v: Any?, _ s: Int) -> String {
        guard let u = unwrap(v) else { return "<c r=\"\(c)\" s=\"\(s)\"/>" }
        if let str = u as? String, str.isEmpty { return "<c r=\"\(c)\" s=\"\(s)\"/>" }
        if !(u is String), !(u is Bool), let d = numberValue(u), d.isFinite { return "<c r=\"\(c)\" s=\"\(s)\"><v>\(JS.numberString(d))</v></c>" }
        return "<c r=\"\(c)\" s=\"\(s)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(JS.string(u)))</t></is></c>"
    }

    static func numberValue(_ v: Any) -> Double? {
        switch v {
        case let i as Int: return Double(i)
        case let d as Double: return d
        case let i as Int64: return Double(i)
        default: return nil
        }
    }

    static func sheetXml(_ sh: Sheet) -> String {
        var rows: [String] = []
        var r = 0
        if let title = sh.title { r += 1; rows.append("<row r=\"\(r)\" ht=\"22\" customHeight=\"1\">\(cell("A\(r)", title, 4))</row>"); r += 1 }
        let headerRow = r + 1
        r += 1
        rows.append("<row r=\"\(r)\" ht=\"30\" customHeight=\"1\">" + sh.cols.enumerated().map { cell(colName($0.offset) + "\(r)", $0.element.h, 1) }.joined() + "</row>")
        for row in sh.rows {
            r += 1
            rows.append("<row r=\"\(r)\">" + sh.cols.enumerated().map { (i, c) in cell(colName(i) + "\(r)", row[c.k] ?? nil, c.t == "num" ? 2 : (c.t == "int" ? 3 : 0)) }.joined() + "</row>")
        }
        if let total = sh.total {
            r += 1
            rows.append("<row r=\"\(r)\">" + sh.cols.enumerated().map { (i, c) -> String in
                let v: Any? = (i == 0 && total[c.k] == nil) ? "Total" : (total[c.k] ?? nil)
                return cell(colName(i) + "\(r)", v, c.t == "num" || c.t == "int" ? 5 : 6)
            }.joined() + "</row>")
        }
        let widths = sh.cols.enumerated().map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\(JS.numberString($0.element.w))\" customWidth=\"1\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="\(headerRow)" topLeftCell="A\(headerRow + 1)" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols>\(widths)</cols><sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    static func build(_ sheets: [Sheet]) -> Data {
        let names = sheets.map { esc(String(rx("[\\\\\\/?*\\[\\]:]", "g").replace($0.name, " ").prefix(31))) }
        var files: [(String, String)] = [
            ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" + sheets.indices.map { "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined() + "</Types>"),
            ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            ("xl/workbook.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>" + names.enumerated().map { "<sheet name=\"\($0.element)\" sheetId=\"\($0.offset + 1)\" r:id=\"rId\($0.offset + 1)\"/>" }.joined() + "</sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + sheets.indices.map { "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>" }.joined() + "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"),
            ("xl/styles.xml", STYLES),
        ]
        for (i, s) in sheets.enumerated() { files.append(("xl/worksheets/sheet\(i + 1).xml", sheetXml(s))) }
        return Zip.make(files.map { ($0.0, Data($0.1.utf8)) })
    }
}

/// ZIP writer with CRC-32; deflate when the platform has it (Apple's Compression), stored otherwise.
enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    /// Raw deflate (no zlib header), or nil when not available.
    static func deflate(_ d: Data) -> Data? {
        #if canImport(Compression)
        if d.isEmpty { return nil }
        let cap = d.count + 1024
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          src.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        if n == 0 { return nil }
        out.count = n
        return out
        #else
        return nil
        #endif
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }

    static func make(_ files: [(String, Data)]) -> Data {
        var parts = Data(), central = Data()
        var off: UInt32 = 0
        for (name, raw) in files {
            let nm = Data(name.utf8)
            let crc = crc32(raw)
            let comp = deflate(raw)
            let method = comp == nil ? 0 : 8
            let body = comp ?? raw
            var lh: [UInt8] = le32(0x04034b50) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0)
            lh += le32(crc) + le32(UInt32(body.count)) + le32(UInt32(raw.count)) + le16(nm.count) + le16(0)
            parts.append(contentsOf: lh); parts.append(nm); parts.append(body)
            var ch: [UInt8] = le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(method) + le16(0) + le16(0)
            ch += le32(crc) + le32(UInt32(body.count)) + le32(UInt32(raw.count)) + le16(nm.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(off)
            central.append(contentsOf: ch); central.append(nm)
            off += UInt32(30 + nm.count + body.count)
        }
        var end: [UInt8] = le32(0x06054b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        end += le32(UInt32(central.count)) + le32(off) + le16(0)
        var out = parts
        out.append(central)
        out.append(contentsOf: end)
        return out
    }
}
