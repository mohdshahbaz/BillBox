import XCTest
#if SWIFT_PACKAGE
@testable import BillBoxCore
import ParityKit
#endif

/// Backups that reach the iPhone in other shapes than a plain folder: zipped (Finder, Mail, WhatsApp, the Files app),
/// a folder that holds the backup folder, or a single company file; and the backup folder after the app folder moved.
final class BackupFilesTests: XCTestCase {
    var work: URL!

    override func setUpWithError() throws {
        NSTimeZone.default = TimeZone(identifier: "Asia/Kolkata")!
        Category.internetAllowed = false
        work = FileManager.default.temporaryDirectory.appendingPathComponent("BillBoxFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    /// Stored, fast-deflated and best-deflated entries, an empty file and nested folders all come out byte for byte.
    func testUnzipStoredAndDeflated() throws {
        let zip = try Data(contentsOf: GoldenTests.golden.appendingPathComponent("mixed.zip"))
        let blob = try Data(contentsOf: GoldenTests.golden.appendingPathComponent("mixed.blob"))
        let names = try Unzip.extract(zip, to: work.path)
        XCTAssertEqual(Set(names), ["stored.bin", "fast.bin", "best.bin", "empty.txt", "sub/dir/tiny.txt"])
        for n in ["stored.bin", "fast.bin", "best.bin"] {
            XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent(n)), blob, n)
        }
        XCTAssertEqual(try Data(contentsOf: work.appendingPathComponent("empty.txt")).count, 0)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("sub/dir/tiny.txt"), encoding: .utf8), "a")
        XCTAssertThrowsError(try Unzip.extract(Data("not a zip".utf8), to: work.path))
    }

    /// A Mac backup zipped by Finder restores on the iPhone, and every table equals the Mac's books.
    func testZippedMacBackupRestores() async throws {
        Clock.override = nil
        let zip = try Data(contentsOf: GoldenTests.golden.appendingPathComponent("MacBackup.zip"))
        let unpacked = work.appendingPathComponent("picked")
        try Unzip.extract(zip, to: unpacked.path)
        let found = Backup.locate(in: unpacked.path)
        XCTAssertNotNil(found.folder)
        XCTAssertNil(found.file)

        Backup.defaultDir = work.appendingPathComponent("home/DistributorProBackups").path
        let r = ParityRunner(router: try Router(dataDir: work.appendingPathComponent("data").path))
        let out = try await r.run([["method": "POST", "path": "/backup/restore", "body": ["folder": found.folder!]], ["op": "dump"]])
            .map { try ParityCompare.parse(try JSONText.compact($0)) as! [String: Any] }
        XCTAssertEqual(out[0]["status"] as? Int, 200, "\(out[0])")
        let mac = GoldenTests.byName(try ParityCompare.parse(String(contentsOf: GoldenTests.golden.appendingPathComponent("macbackup.dump.json"), encoding: .utf8)) as! [String: Any])
        let got = GoldenTests.byName(out[1]["dump"] as! [String: Any])
        for co in ["ak enterprises", "second traders", "ak enterprises 2027-28", "ak enterprises 2025-26"] {
            var diffs: [String] = []
            ParityCompare.diff(mac[co], got[co], co, loose: false, into: &diffs)
            XCTAssert(diffs.isEmpty, co + ": " + diffs.prefix(5).joined(separator: "; "))
        }
    }

    /// A folder that only holds one company file is offered as that file.
    func testLocateSingleCompanyFile() throws {
        let d = work.appendingPathComponent("Downloads/x")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: GoldenTests.golden.appendingPathComponent("MacBackup/AK_Enterprises_1.db"), to: d.appendingPathComponent("AK_Enterprises_1.db"))
        let found = Backup.locate(in: work.path)
        XCTAssertNil(found.folder)
        XCTAssertEqual((found.file.map { ($0 as NSString).lastPathComponent }), "AK_Enterprises_1.db")
    }

    /// A backup folder saved inside the app's old folder (before the app was installed again) is moved to the same place in the new one;
    /// a folder elsewhere is left alone.
    func testBackupFolderFollowsTheAppFolder() async throws {
        let r = try Router(dataDir: work.appendingPathComponent("data").path)
        let old = "/var/mobile/Containers/Data/Application/OLD-UUID/Documents/DistributorProBackups"
        _ = await r.handle("PUT", "/backup/config", body: ["dir": old])
        let docs = work.appendingPathComponent("NEW/Documents").path
        try r.backup.followAppFolder(documents: docs)
        XCTAssertEqual(try r.backup.config()["dir"] as? String, docs + "/DistributorProBackups")
        _ = await r.handle("PUT", "/backup/config", body: ["dir": "/Volumes/USB/Backups"])
        try r.backup.followAppFolder(documents: docs)
        XCTAssertEqual(try r.backup.config()["dir"] as? String, "/Volumes/USB/Backups")
    }

    /// A failed backup says why (the Mac answered only "Server error").
    func testBackupFailureKeepsItsReason() async throws {
        let r = try Router(dataDir: work.appendingPathComponent("data").path)
        let file = work.appendingPathComponent("a-file").path
        FileManager.default.createFile(atPath: file, contents: Data("x".utf8))
        _ = await r.handle("PUT", "/backup/config", body: ["dir": file + "/sub"])
        guard case .json(500, let body) = await r.handle("POST", "/backup/run") else { return XCTFail("expected a failure") }
        let o = body as! [String: Any]
        XCTAssertEqual(o["error"] as? String, "Server error")
        XCTAssertTrue((o["detail"] as? String ?? "").hasPrefix("Cannot write to"), "\(o)")
    }
}
