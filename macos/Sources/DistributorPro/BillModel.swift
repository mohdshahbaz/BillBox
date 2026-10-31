import Foundation

/// The bill being typed. Every change to a line (a box, a piece, a rate, a discount, a new or removed item) re-runs the arithmetic
/// at once, on this Mac, and publishes the result, so everything that shows an amount redraws on the same keystroke.
@MainActor final class BillModel: ObservableObject {
    @Published var lines: [BillLine] = [] {
        didSet { recompute() }
    }
    /// Amounts of the bill exactly as it stands now (total pieces x per-piece rate, discount, GST, round off).
    @Published private(set) var local = BillMath.Result()

    private var catalog: [Int: JSON] = [:]
    private var tier = "RETAIL"
    private var intra = true
    /// Settings › Billing & Dashboard: round the bill total to the rupee.
    var roundTotal = true

    /// Tells the model which prices and tax rules apply: the item list, the party (price tier, state) and the shop's own state.
    func configure(items: [JSON], party: JSON?, myState: String) {
        catalog = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        tier = party?.str("price_tier") ?? "RETAIL"
        let theirs = party?.str("state_code") ?? ""
        intra = party == nil || theirs.isEmpty || theirs == myState
        recompute()
    }

    var supply: String { intra ? "INTRA" : "INTER" }

    func recompute() { local = currentResult() }

    /// The amounts worked out right now from the lines, never from a saved copy.
    func currentResult() -> BillMath.Result {
        let inputs = lines.map { l -> BillMath.LineInput in
            let item = catalog[l.itemId]
            let gst = item?.num("gst_rate") ?? 0
            var list = item?.num("retail_price") ?? 0
            if tier == "WHOLESALE", let w = item?.num("wholesale_price"), w > 0 { list = w }   // none set: the retail price (as the engine)
            if tier == "MRP" { list = (item?.num("mrp") ?? 0) / (1 + gst / 100) }
            var typed: Double?
            let t = l.rate.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, let r = Double(t), r >= 0 { typed = r }
            return BillMath.LineInput(boxes: l.boxes, pcs: l.pcs, ppb: l.ppb, listRate: list, typedRate: typed,
                                      discPct: Double(l.disc) ?? 0, gstRate: gst)
        }
        return BillMath.compute(inputs, intra: intra, roundTotal: roundTotal)
    }
}
