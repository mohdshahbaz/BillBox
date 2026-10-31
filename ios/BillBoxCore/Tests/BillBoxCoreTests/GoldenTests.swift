import XCTest
#if SWIFT_PACKAGE
@testable import BillBoxCore
import ParityKit
#endif

/// The iPhone engine must answer exactly as the Mac does.
/// The golden files are the Mac engine's own answers (Node, backend/src), recorded by ios/tests/parity/make_golden.py;
/// each test replays the same steps on BillBoxCore and compares every reply and every table, field by field.
final class GoldenTests: XCTestCase {

    // MARK: helpers

    static var golden: URL {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "Golden", withExtension: nil)!
        #else
        return Bundle(for: GoldenTests.self).url(forResource: "Golden", withExtension: nil)!
        #endif
    }

    var work: URL!

    override func setUpWithError() throws {
        // the Mac recorded these in India; "today", financial years and printed dates depend on the local day
        setenv("TZ", "Asia/Kolkata", 1); tzset()   // also for code that asks the system's zone (a simulator on a UTC machine)
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = TimeZone(identifier: "Asia/Kolkata")!
        Category.internetAllowed = false
        let meta = try ParityCompare.parse(String(contentsOf: Self.golden.appendingPathComponent("meta.json"), encoding: .utf8)) as! [String: Any]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        Clock.override = f.date(from: meta["recorded"] as! String)
        work = FileManager.default.temporaryDirectory.appendingPathComponent("BillBoxGolden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        Clock.override = nil
        try? FileManager.default.removeItem(at: work)
    }

    /// A copy of the Mac-made backup folder (restoring must not touch the bundled original).
    func macBackupCopy() throws -> String {
        let dst = work.appendingPathComponent("MacBackup-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: Self.golden.appendingPathComponent("MacBackup"), to: dst)
        return dst.path
    }

    /// Replays `<name>.json` on a fresh iPhone engine and compares each reply with `<name>.mac.jsonl`.
    @discardableResult
    func replay(_ name: String, substitutions: [String: String] = [:], file: StaticString = #filePath, line: UInt = #line) async throws -> (mac: [[String: Any]], phone: [[String: Any]]) {
        var text = try String(contentsOf: Self.golden.appendingPathComponent("\(name).json"), encoding: .utf8)
        var subs = substitutions
        subs["work"] = subs["work"] ?? work.path
        subs["engine"] = "ios"
        for (k, v) in subs { text = text.replacingOccurrences(of: "{\(k)}", with: v) }
        let steps = (try ParityCompare.parse(text) as! [Any]).map { $0 as! [String: Any] }
        let mac = try String(contentsOf: Self.golden.appendingPathComponent("\(name).mac.jsonl"), encoding: .utf8)
            .split(separator: "\n").map { try ParityCompare.parse(String($0)) as! [String: Any] }

        let data = work.appendingPathComponent("\(name)-data")
        Backup.defaultDir = work.appendingPathComponent("\(name)-home/DistributorProBackups").path
        let runner = ParityRunner(router: try Router(dataDir: data.path))
        // through JSON text, exactly as the Linux harness reads bbcheck's output
        let phone = try await runner.run(steps).map { try ParityCompare.parse(try JSONText.compact($0)) as! [String: Any] }

        XCTAssertEqual(mac.count, phone.count, "\(name): number of replies", file: file, line: line)
        var bad = 0
        for (m, p) in zip(mac, phone) {
            let i = m["step"] as! Int
            let st = steps[i]
            var diffs: [String] = []
            ParityCompare.diff(m, p, "step \(i) \((st["op"] as? String) ?? (st["method"] as? String) ?? "GET") \((st["path"] as? String) ?? "")",
                               loose: (st["loose"] as? Bool) ?? false, into: &diffs)
            if !diffs.isEmpty {
                bad += 1
                if bad <= 10 { XCTFail(diffs.prefix(8).joined(separator: "\n"), file: file, line: line) }
            }
        }
        XCTAssertEqual(bad, 0, "\(name): \(bad) of \(mac.count) replies differ from the Mac", file: file, line: line)
        return (mac, phone)
    }

    /// Company books keyed by company name (ids can differ between installs).
    static func byName(_ dump: [String: Any]) -> [String: [String: Any]] {
        var names: [String: String] = [:]
        for r in dump["registry"] as! [[String: Any]] { names[JS.string(r["id"] ?? nil)] = ((r["name"] as! String) + ((r["fy"] as? String).map { " " + $0 } ?? "")).split(separator: " ").joined(separator: " ").lowercased() }
        var out: [String: [String: Any]] = [:]
        for (id, tables) in dump["companies"] as! [String: Any] { out[names[id]!] = tables as? [String: Any] }
        return out
    }

    // MARK: calculations and screens' data

    /// One long working session: companies, items, schemes, parties, purchases, bills (cash, credit, discounts, schemes,
    /// inter-state), payments, ledgers, salesmen and routes, every report, edits, deletions and refused mistakes.
    func testWorkingSessionMatchesMac() async throws {
        let (mac, _) = try await replay("scenario")
        XCTAssertGreaterThan(mac.count, 200)
    }

    /// Real supplier bills (Golden/private, kept off GitHub): skipped where those files are not present.
    func needPrivate(_ name: String) throws {
        if !FileManager.default.fileExists(atPath: Self.golden.appendingPathComponent("private/\(name).json").path) {
            throw XCTSkip("private test files (real supplier bills) not present")
        }
    }

    func testSupplierBillParserMatchesMac() async throws { try needPrivate("parser"); try await replay("private/parser") }

    /// 1,600+ random bills: every rounding, tax split and scheme path.
    func testRandomBillsMatchMac() async throws { try await replay("fuzz") }

    /// Text of the three real supplier PDFs from their text runs, watermarks left out.
    func testPdfPageTextMatchesMacWithoutWatermarks() async throws {
        try needPrivate("pagetext")
        let (_, phone) = try await replay("private/pagetext")
        let jmd = ((phone[0]["text"] as? [String]) ?? []).joined(separator: "\n")
        XCTAssertFalse(jmd.isEmpty)
    }

    // MARK: backups between Mac and iPhone

    /// A backup made on the Mac restores on the iPhone (Replace) and every table of every company equals the Mac's books.
    func testMacBackupRestoresOnIPhone() async throws {
        let (_, phone) = try await replay("restore_replace", substitutions: ["macbackup": try macBackupCopy()])
        let macBooks = Self.byName(try ParityCompare.parse(String(contentsOf: Self.golden.appendingPathComponent("macbackup.dump.json"), encoding: .utf8)) as! [String: Any])
        let restored = Self.byName(phone.last!["dump"] as! [String: Any])
        for co in ["ak enterprises", "second traders", "ak enterprises 2027-28", "ak enterprises 2025-26"] {
            var diffs: [String] = []
            ParityCompare.diff(macBooks[co], restored[co], co, loose: false, into: &diffs)
            XCTAssert(diffs.isEmpty, "Mac backup restored on iPhone: \(co): " + diffs.prefix(5).joined(separator: "; "))
        }
    }

    func testMergingMacBackupMatchesMac() async throws { try await replay("restore_merge", substitutions: ["macbackup": try macBackupCopy()]) }

    func testSingleCompanyFileFromMacMatchesMac() async throws {
        let mb = try macBackupCopy()
        try await replay("restore_single", substitutions: ["macbackup": mb])
    }

    /// A backup made on the iPhone has the Mac's layout (manifest, checksums, intact databases) and restores into a fresh install unchanged.
    /// (The Mac restoring an iPhone backup is checked by ios/tests/parity/test_backup.py, which runs the Mac engine itself.)
    func testIPhoneBackupHasMacLayoutAndRestores() async throws {
        var text = try String(contentsOf: Self.golden.appendingPathComponent("scenario.json"), encoding: .utf8)
        text = text.replacingOccurrences(of: "{work}", with: work.path).replacingOccurrences(of: "{engine}", with: "ios")
        let steps = (try ParityCompare.parse(text) as! [Any]).map { $0 as! [String: Any] }.filter { ($0["op"] as? String) != "dump" }
        Backup.defaultDir = work.appendingPathComponent("a-home/DistributorProBackups").path
        let a = ParityRunner(router: try Router(dataDir: work.appendingPathComponent("a-data").path))
        let out = try await a.run(steps + [["op": "backup"], ["op": "dump"]]).map { try ParityCompare.parse(try JSONText.compact($0)) as! [String: Any] }
        let folder = out[out.count - 2]["folder"] as! String
        XCTAssertTrue((folder as NSString).lastPathComponent.hasPrefix("FMCG_Backup_"))

        let manifestText = try String(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("manifest.json"), encoding: .utf8)
        let manifest = try ParityCompare.parse(manifestText) as! [String: Any]
        // same key order as the Mac writes
        XCTAssertTrue(manifestText.range(of: "\"created\"")!.lowerBound < manifestText.range(of: "\"reason\"")!.lowerBound)
        XCTAssertTrue(manifestText.range(of: "\"reason\"")!.lowerBound < manifestText.range(of: "\"files\"")!.lowerBound)
        let files = manifest["files"] as! [[String: Any]]
        XCTAssertEqual(files.count, 5)
        for f in files {
            let path = (folder as NSString).appendingPathComponent(f["file"] as! String)
            XCTAssertEqual(SHA256.hex(try Data(contentsOf: URL(fileURLWithPath: path))), f["sha256"] as? String, "checksum of \(f["file"]!)")
            let db = try Database(path, readonly: true)
            XCTAssertEqual(try db.prepare("PRAGMA integrity_check").get()?["integrity_check"] as? String, "ok")
        }

        Backup.defaultDir = work.appendingPathComponent("b-home/DistributorProBackups").path
        let b = ParityRunner(router: try Router(dataDir: work.appendingPathComponent("b-data").path))
        let r = try await b.run([["method": "POST", "path": "/backup/restore", "body": ["folder": folder]], ["op": "dump"]])
            .map { try ParityCompare.parse(try JSONText.compact($0)) as! [String: Any] }
        XCTAssertEqual(r[0]["status"] as? Int, 200)
        let before = Self.byName(out.last!["dump"] as! [String: Any]), after = Self.byName(r[1]["dump"] as! [String: Any])
        for co in ["ak enterprises", "second traders", "ak enterprises 2027-28", "ak enterprises 2025-26"] {
            var diffs: [String] = []
            ParityCompare.diff(before[co], after[co], co, loose: false, into: &diffs)
            XCTAssert(diffs.isEmpty, "iPhone backup restored: \(co): " + diffs.prefix(5).joined(separator: "; "))
        }
    }
}
