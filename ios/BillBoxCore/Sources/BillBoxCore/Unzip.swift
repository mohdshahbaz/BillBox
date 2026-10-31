import Foundation

/// Reading .zip files: a Mac backup folder often reaches the iPhone zipped (Finder's Compress, Mail, WhatsApp, or the Files
/// app's own copy of a folder). Stored and deflated entries are supported; the inflater below is plain RFC 1951, so it behaves
/// the same on the phone and in the tests.
public enum Unzip {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Every file of the archive (folders and macOS resource-fork copies left out), in the archive's order.
    public static func entries(_ zip: Data) throws -> [(name: String, data: Data)] {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) | Int(b[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 3 < b.count ? u16(o) | u16(o + 2) << 16 : 0 }
        // end of central directory: the last "PK\5\6" within the final 64 KB
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65_557) {
            if b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 5 && b[i + 3] == 6 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure(description: "This is not a zip file.") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var out: [(name: String, data: Data)] = []
        for _ in 0..<count {
            guard u32(p) == 0x02014b50 else { throw Failure(description: "The zip file is damaged.") }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nlen = u16(p + 28), xlen = u16(p + 30), clen = u16(p + 32)
            let local = u32(p + 42)
            let nameBytes = Array(b[(p + 46)..<min(b.count, p + 46 + nlen)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            p += 46 + nlen + xlen + clen
            // skip macOS resource-fork copies and folders
            if name.hasPrefix("__MACOSX/") || name.hasSuffix("/") || name.isEmpty { continue }
            guard u32(local) == 0x04034b50 else { throw Failure(description: "The zip file is damaged.") }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + csize <= b.count else { throw Failure(description: "The zip file is incomplete.") }
            let raw = Array(b[start..<(start + csize)])
            switch method {
            case 0: out.append((name, Data(raw)))
            case 8: out.append((name, Data(try Inflate.run(raw, expected: usize))))
            default: throw Failure(description: "\(name) is packed with a method BillBox cannot read.")
            }
        }
        return out
    }

    /// Writes every file of the archive under `dir` (folders are created; names that try to leave `dir` are refused).
    /// Returns the relative paths written.
    @discardableResult
    public static func extract(_ zip: Data, to dir: String) throws -> [String] {
        let root = URL(fileURLWithPath: dir).standardizedFileURL.path
        var written: [String] = []
        for (name, data) in try entries(zip) {
            let dest = URL(fileURLWithPath: dir).appendingPathComponent(name).standardizedFileURL
            guard dest.path.hasPrefix(root + "/") else { throw Failure(description: "The zip file has an unsafe name: \(name)") }
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
            written.append(name)
        }
        return written
    }
}

/// RFC 1951 inflate (raw deflate, as inside zip files).
enum Inflate {
    struct Bits {
        let d: [UInt8]
        var pos = 0, bit = 0
        /// bits not used yet, lowest first (a 64-bit window over the stream)
        private var buf: UInt64 = 0, have = 0
        init(d: [UInt8]) { self.d = d }
        mutating func get(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            while have < n {
                guard pos < d.count else { throw Unzip.Failure(description: "The zip file is incomplete.") }
                buf |= UInt64(d[pos]) << UInt64(have)
                pos += 1
                have += 8
            }
            let v = Int(buf & ((1 << UInt64(n)) - 1))
            buf >>= UInt64(n)
            have -= n
            return v
        }
        /// Drops the rest of the current byte (stored blocks start on a byte boundary); `pos` is then the next unread byte.
        mutating func align() {
            let drop = have % 8
            buf >>= UInt64(drop)
            have -= drop
            // give whole unread bytes back to the stream
            pos -= have / 8
            buf = 0
            have = 0
        }
    }

    /// Canonical Huffman decoder: counts per length and symbols in code order.
    struct Huff {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []
        init(_ lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offs = [Int](repeating: 0, count: 16)
            for l in 1..<16 { offs[l] = offs[l - 1] + counts[l - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (s, l) in lengths.enumerated() where l != 0 { symbols[offs[l]] = s; offs[l] += 1 }
        }
        func decode(_ br: inout Bits) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= try br.get(1)
                let c = counts[len]
                if code - c < first { return symbols[index + (code - first)] }
                index += c
                first += c
                first <<= 1
                code <<= 1
            }
            throw Unzip.Failure(description: "The zip file is damaged.")
        }
    }

    static let lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let fixedLit: Huff = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        return Huff(l)
    }()
    static let fixedDist = Huff([Int](repeating: 5, count: 30))

    static func run(_ data: [UInt8], expected: Int = 0) throws -> [UInt8] {
        var br = Bits(d: data)
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        var last = 0
        repeat {
            last = try br.get(1)
            let type = try br.get(2)
            switch type {
            case 0:
                br.align()
                guard br.pos + 4 <= data.count else { throw Unzip.Failure(description: "The zip file is incomplete.") }
                let len = Int(data[br.pos]) | Int(data[br.pos + 1]) << 8
                br.pos += 4
                guard br.pos + len <= data.count else { throw Unzip.Failure(description: "The zip file is incomplete.") }
                out.append(contentsOf: data[br.pos..<(br.pos + len)])
                br.pos += len
            case 1:
                try codes(&br, &out, fixedLit, fixedDist)
            case 2:
                let hlit = try br.get(5) + 257, hdist = try br.get(5) + 1, hclen = try br.get(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var cl = [Int](repeating: 0, count: 19)
                for k in 0..<hclen { cl[order[k]] = try br.get(3) }
                let clh = Huff(cl)
                var lens: [Int] = []
                while lens.count < hlit + hdist {
                    let sym = try clh.decode(&br)
                    switch sym {
                    case 0...15: lens.append(sym)
                    case 16:
                        guard let prev = lens.last else { throw Unzip.Failure(description: "The zip file is damaged.") }
                        lens += [Int](repeating: prev, count: 3 + (try br.get(2)))
                    case 17: lens += [Int](repeating: 0, count: 3 + (try br.get(3)))
                    default: lens += [Int](repeating: 0, count: 11 + (try br.get(7)))
                    }
                }
                try codes(&br, &out, Huff(Array(lens[0..<hlit])), Huff(Array(lens[hlit..<(hlit + hdist)])))
            default:
                throw Unzip.Failure(description: "The zip file is damaged.")
            }
        } while last == 0
        return out
    }

    static func codes(_ br: inout Bits, _ out: inout [UInt8], _ lit: Huff, _ dist: Huff) throws {
        while true {
            let sym = try lit.decode(&br)
            if sym < 256 { out.append(UInt8(sym)); continue }
            if sym == 256 { return }
            let li = sym - 257
            guard li < lbase.count else { throw Unzip.Failure(description: "The zip file is damaged.") }
            let len = lbase[li] + (try br.get(lext[li]))
            let di = try dist.decode(&br)
            guard di < dbase.count else { throw Unzip.Failure(description: "The zip file is damaged.") }
            let d = dbase[di] + (try br.get(dext[di]))
            guard d <= out.count else { throw Unzip.Failure(description: "The zip file is damaged.") }
            let from = out.count - d
            for k in 0..<len { out.append(out[from + k]) }
        }
    }
}
