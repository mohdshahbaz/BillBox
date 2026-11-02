import Foundation

/// The bill arithmetic, kept free of any screen code so it can be checked on its own.
/// It is a line-for-line copy of the server's buildInvoice (backend/src/services/billing.js); backend/test/billmath.js runs the same
/// steps against the real server engine for thousands of random bills and fails on any difference of even one paisa.
///
///   total pieces  = boxes x pieces-per-box + loose pieces
///   gross         = per-piece rate x total pieces         (rounded to paise)
///   discount      = gross x disc% / 100                   (rounded)
///   taxable       = gross - discount
///   GST           = taxable x gst% / 100, split half CGST / half SGST (or all IGST for another state)
///   total         = nearest whole rupee of (taxable + GST); round off = total - that
enum BillMath {
    /// Same as JavaScript's Math.round(x * 100) / 100 with the server's epsilon, so both sides round alike.
    static func r2(_ x: Double) -> Double {
        ((x + Double.ulpOfOne) * 100 + 0.5).rounded(.down) / 100
    }

    static func totalPcs(boxes: Int, ppb: Int, pcs: Int) -> Int {
        max(0, boxes) * max(1, ppb) + max(0, pcs)
    }

    struct LineInput {
        var boxes = 0
        var pcs = 0
        var ppb = 1
        /// Price-list rate per piece, ex-GST, for this party's tier.
        var listRate = 0.0
        /// A rate typed on the bill (per piece, ex-GST). nil = use the price list.
        var typedRate: Double?
        var discPct = 0.0
        var gstRate = 0.0
    }

    struct LineResult {
        var totalPcs = 0
        var rate = 0.0
        var gross = 0.0
        var discount = 0.0
        var taxable = 0.0
        var cgst = 0.0
        var sgst = 0.0
        var igst = 0.0
        var amount = 0.0
    }

    struct Result {
        var lines: [LineResult] = []
        var pieces = 0
        var subtotal = 0.0
        var discount = 0.0
        var taxable = 0.0
        var cgst = 0.0
        var sgst = 0.0
        var igst = 0.0
        var roundOff = 0.0
        var total = 0.0
        var gst: Double { cgst + sgst + igst }
    }

    static func line(_ i: LineInput, intra: Bool) -> LineResult {
        var r = LineResult()
        r.totalPcs = totalPcs(boxes: i.boxes, ppb: i.ppb, pcs: i.pcs)
        r.rate = i.typedRate ?? i.listRate
        let pct = min(100, max(0, i.discPct))
        r.gross = r2(r.rate * Double(r.totalPcs))
        r.discount = r2(r.gross * pct / 100)
        r.taxable = r2(r.gross - r.discount)
        let tax = r2(r.taxable * i.gstRate / 100)
        if intra {
            r.cgst = r2(tax / 2)
            r.sgst = r2(tax - r.cgst)
        } else {
            r.igst = tax
        }
        r.amount = r2(r.taxable + r.cgst + r.sgst + r.igst)
        return r
    }

    static func compute(_ inputs: [LineInput], intra: Bool, roundTotal: Bool = true) -> Result {
        var out = Result()
        for i in inputs {
            let l = line(i, intra: intra)
            out.lines.append(l)
            out.pieces += l.totalPcs
            out.subtotal += l.gross
            out.discount += l.discount
            out.taxable += l.taxable
            out.cgst += l.cgst
            out.sgst += l.sgst
            out.igst += l.igst
        }
        out.subtotal = r2(out.subtotal)
        out.discount = r2(out.discount)
        out.taxable = r2(out.taxable)
        out.cgst = r2(out.cgst)
        out.sgst = r2(out.sgst)
        out.igst = r2(out.igst)
        let grand = r2(out.taxable + out.cgst + out.sgst + out.igst)
        out.total = roundTotal ? (grand + 0.5).rounded(.down) : grand
        out.roundOff = r2(out.total - grand)
        return out
    }
}
