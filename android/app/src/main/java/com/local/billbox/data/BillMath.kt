package com.local.billbox.data

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * The bill arithmetic, a line-for-line copy of the engine's buildInvoice (backend/src/services/billing.js) and the iPhone's
 * BillMath, so the total shown while typing is the total saved.
 */
object BillMath {
    private val EPS = Math.ulp(1.0)
    /** JavaScript's Math.round(x * 100) / 100 with the engine's epsilon. */
    fun r2(x: Double): Double = floor((x + EPS) * 100 + 0.5) / 100

    fun totalPcs(boxes: Int, ppb: Int, pcs: Int): Int = max(0, boxes) * max(1, ppb) + max(0, pcs)

    data class LineInput(val boxes: Int, val pcs: Int, val ppb: Int, val listRate: Double, val typedRate: Double?, val discPct: Double, val gstRate: Double)
    data class LineResult(val totalPcs: Int, val rate: Double, val gross: Double, val discount: Double, val taxable: Double,
                          val cgst: Double, val sgst: Double, val igst: Double, val amount: Double)
    data class Result(val lines: List<LineResult> = emptyList(), val pieces: Int = 0, val subtotal: Double = 0.0, val discount: Double = 0.0,
                      val taxable: Double = 0.0, val cgst: Double = 0.0, val sgst: Double = 0.0, val igst: Double = 0.0,
                      val roundOff: Double = 0.0, val total: Double = 0.0) {
        val gst: Double get() = cgst + sgst + igst
    }

    fun line(i: LineInput, intra: Boolean): LineResult {
        val tp = totalPcs(i.boxes, i.ppb, i.pcs)
        val rate = i.typedRate ?: i.listRate
        val pct = min(100.0, max(0.0, i.discPct))
        val gross = r2(rate * tp)
        val discount = r2(gross * pct / 100)
        val taxable = r2(gross - discount)
        val tax = r2(taxable * i.gstRate / 100)
        var cgst = 0.0; var sgst = 0.0; var igst = 0.0
        if (intra) { cgst = r2(tax / 2); sgst = r2(tax - cgst) } else igst = tax
        return LineResult(tp, rate, gross, discount, taxable, cgst, sgst, igst, r2(taxable + cgst + sgst + igst))
    }

    fun compute(inputs: List<LineInput>, intra: Boolean, roundTotal: Boolean = true): Result {
        val ls = inputs.map { line(it, intra) }
        var sub = 0.0; var disc = 0.0; var tax = 0.0; var c = 0.0; var s = 0.0; var ig = 0.0; var pcs = 0
        for (l in ls) { pcs += l.totalPcs; sub += l.gross; disc += l.discount; tax += l.taxable; c += l.cgst; s += l.sgst; ig += l.igst }
        sub = r2(sub); disc = r2(disc); tax = r2(tax); c = r2(c); s = r2(s); ig = r2(ig)
        val grand = r2(tax + c + s + ig)
        val total = if (roundTotal) floor(grand + 0.5) else grand
        return Result(ls, pcs, sub, disc, tax, c, s, ig, r2(total - grand), total)
    }

    /** The price-list rate per piece (ex-GST) for a party's tier: wholesale falls back to retail when none is set (as the engine). */
    fun listRate(item: J?, tier: String): Double {
        if (item == null) return 0.0
        val gst = item.num("gst_rate")
        var list = item.num("retail_price")
        if (tier == "WHOLESALE" && item.num("wholesale_price") > 0) list = item.num("wholesale_price")
        if (tier == "MRP") list = item.num("mrp") / (1 + gst / 100)
        return list
    }
}
