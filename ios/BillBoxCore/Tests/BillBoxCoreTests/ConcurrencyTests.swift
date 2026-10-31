import XCTest
#if SWIFT_PACKAGE
@testable import BillBoxCore
#endif

/// Screens load several things at once (the billing screen asks for parties, salesmen, items and routes together).
/// Before requests were taken one at a time, this crashed the app on launch: two threads used one SQLite connection.
final class ConcurrencyTests: XCTestCase {
    func testManyRequestsAtOnceAreSafe() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BillBoxRace-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        Category.internetAllowed = false
        Backup.defaultDir = dir + "/backups"
        let r = try Router(dataDir: dir)
        for round in 0..<40 {
            await withTaskGroup(of: Void.self) { g in
                for p in ["/parties", "/salesmen", "/items", "/routes", "/companies", "/settings", "/fy", "/categories"] {
                    g.addTask { _ = await r.handle("GET", p, query: [:], body: [:], companyId: 1) }
                }
                g.addTask { _ = await r.handle("POST", "/items", query: [:], body: ["name": "Item \(round)", "gst_rate": 5], companyId: 1) }
                g.addTask { _ = await r.exclusive { r.backup.isDue() } }
            }
        }
        guard case .json(200, let body) = await r.handle("GET", "/items", query: [:], body: [:], companyId: 1) else { return XCTFail("items") }
        XCTAssertEqual((body as? [Any])?.count, 40)
    }
}
