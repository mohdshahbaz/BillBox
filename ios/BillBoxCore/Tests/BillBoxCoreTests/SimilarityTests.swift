import XCTest
#if SWIFT_PACKAGE
@testable import BillBoxCore
#endif

/// Supplier-bill names matched to items and suppliers: the same scores as the Mac (backend/src/services/pdfParser.js similarity).
final class SimilarityTests: XCTestCase {
    func testScoresMatchMac() {
        let cases: [(String, String, Double)] = [
            ("BIKANO BHUJIYA 200 GM", "Bikano Bhujia 200g", 1),
            ("BIKANO BUJIA 200GMS", "Bikano Bhujia 200g", 1),
            ("RATAN TRADERS PVT LTD", "Ratan Traders", 1),
            ("Aloo Bhujia 400g", "Bikano Bhujia 400g", 0.6666666666666666),
            ("NAMKIN MIX 5/-", "Namkeen Mix 5/-", 1),
            ("Haldiram Navratan", "Haldirams Navrattan Mixture", 0.6333333333333333),
            ("Kurkure Masala Munch 90gm", "KURKURE MASALA MUNCH 90 G", 1),
            ("Parle-G 800g", "Parle G Gold 1kg", 0.3333333333333333),
        ]
        for (a, b, want) in cases { XCTAssertEqual(PDFParser.similarity(a, b), want, accuracy: 1e-12, "\(a) | \(b)") }
    }
}
