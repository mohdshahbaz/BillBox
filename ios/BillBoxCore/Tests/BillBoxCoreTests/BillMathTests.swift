import XCTest
#if SWIFT_PACKAGE
@testable import BillBoxCore
#endif

/// The billing screen works its totals out on the phone as each key is typed (BillMath, the Mac's own file, unchanged).
/// Golden: 3,000 random bills priced by the Mac's BillMath (its JavaScript twin, backend/test/billmath_port.js).
/// The saved bill itself is priced by the engine, which the GoldenTests check against the Mac's server.
final class BillMathTests: XCTestCase {
    func testLiveBillTotalsMatchMac() throws {
        let g = try ParityCompare.parse(String(contentsOf: GoldenTests.golden.appendingPathComponent("billmath.json"), encoding: .utf8)) as! [String: Any]
        let bills = g["bills"] as! [[String: Any]], mac = g["mac"] as! [[String: Any]]
        XCTAssertEqual(bills.count, mac.count)
        var bad: [String] = []
        for (n, (bill, m)) in zip(bills, mac).enumerated() {
            let num = { (x: [String: Any], k: String) -> Double in ParityCompare.number(x[k]) ?? 0 }
            let inputs = (bill["lines"] as! [[String: Any]]).map { l in
                BillMath.LineInput(boxes: Int(num(l, "boxes")), pcs: Int(num(l, "pcs")), ppb: Int(num(l, "ppb")), listRate: num(l, "listRate"),
                                   typedRate: ParityCompare.number(l["typedRate"]), discPct: num(l, "discPct"), gstRate: num(l, "gstRate"))
            }
            let r = BillMath.compute(inputs, intra: bill["intra"] as! Bool)
            func check(_ what: String, _ phone: Double, _ macValue: Double) {
                if phone != macValue { bad.append("bill \(n): \(what) phone \(phone) Mac \(macValue)") }
            }
            for (i, l) in (m["lines"] as! [[String: Any]]).enumerated() {
                check("line \(i + 1) pieces", Double(r.lines[i].totalPcs), num(l, "totalPcs"))
                check("line \(i + 1) rate", r.lines[i].rate, num(l, "rate"))
                check("line \(i + 1) gross", r.lines[i].gross, num(l, "gross"))
                check("line \(i + 1) discount", r.lines[i].discount, num(l, "discount"))
                check("line \(i + 1) taxable", r.lines[i].taxable, num(l, "taxable"))
                check("line \(i + 1) CGST", r.lines[i].cgst, num(l, "cgst"))
                check("line \(i + 1) SGST", r.lines[i].sgst, num(l, "sgst"))
                check("line \(i + 1) IGST", r.lines[i].igst, num(l, "igst"))
                check("line \(i + 1) amount", r.lines[i].amount, num(l, "amount"))
            }
            check("pieces", Double(r.pieces), num(m, "pieces"))
            for (k, v) in [("subtotal", r.subtotal), ("discount", r.discount), ("taxable", r.taxable), ("cgst", r.cgst), ("sgst", r.sgst),
                           ("igst", r.igst), ("roundOff", r.roundOff), ("total", r.total)] { check(k, v, num(m, k)) }
        }
        XCTAssert(bad.isEmpty, "\(bad.count) differences:\n" + bad.prefix(10).joined(separator: "\n"))
    }

    /// The rounding rule itself: JavaScript's Math.round(x * 100) / 100 with the server's epsilon.
    func testPaiseRoundingLikeMac() {
        XCTAssertEqual(BillMath.r2(1.005), 1.01)
        XCTAssertEqual(BillMath.r2(2.675), 2.68)
        XCTAssertEqual(BillMath.r2(-1.005), -1)
        XCTAssertEqual(BillMath.r2(0.125), 0.13)
        XCTAssertEqual(r2(1.005), BillMath.r2(1.005))
    }
}
