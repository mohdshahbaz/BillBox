package com.local.billbox.print

import android.graphics.Color
import android.graphics.RectF
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.balanceText
import kotlin.math.abs
import kotlin.math.max

// The "Marg style" bill design (Settings › Printing › Bill design), as PrintMarg.swift draws it on the Mac and iPhone:
// firm and party side by side, a band with GSTIN, the title box and the bill details, the item table with Box / Pcs /
// Free / Pack columns, the GST class table with the totals beside it, the amount in words, and Terms | Receiver |
// Authorised signatory at the bottom. Its own choices are the print_marg_* settings.

/** The design the company chose: "classic" (BillBox) or "marg". */
fun printStyle(co: J): String = if (co.str("print_style") == "marg") "marg" else "classic"

val margColours = listOf("blue" to "Marg blue", "mono" to "Black only (any printer)", "green" to "Green", "maroon" to "Maroon")
/** (name and headings, filled bands) */
private fun margInk(co: J): Pair<Int, Int> = when (co.str("print_marg_colour")) {
    "mono" -> Color.BLACK to Color.argb(23, 0, 0, 0)
    "green" -> Color.argb(255, 18, 94, 33) to Color.argb(255, 219, 240, 217)
    "maroon" -> Color.argb(255, 122, 31, 43) to Color.argb(255, 247, 222, 224)
    else -> Color.argb(255, 26, 26, 128) to Color.argb(255, 191, 242, 247)
}

/** key, heading, width (null = the rest), align 0 left / 1 centre / 2 right */
class MargColumn(val key: String, val head: String, val width: Float?, val align: Int)
val margColumns = listOf(
    MargColumn("sn", "Sn.", 18f, 1), MargColumn("box", "Box", 24f, 2), MargColumn("pcs", "Pcs", 22f, 2), MargColumn("free", "Free", 22f, 2),
    MargColumn("pack", "Pack", 28f, 1), MargColumn("item", "Product", null, 0), MargColumn("batch", "Batch", 40f, 0), MargColumn("mrp", "MRP", 36f, 2),
    MargColumn("exp", "Exp.", 30f, 1), MargColumn("hsn", "HSN", 40f, 1), MargColumn("rate", "Rate", 40f, 2), MargColumn("dis", "Dis %", 24f, 2),
    MargColumn("gst", "GST %", 24f, 2), MargColumn("sgst", "SGST", 25f, 2), MargColumn("cgst", "CGST", 25f, 2), MargColumn("igst", "IGST", 26f, 2),
    MargColumn("amount", "Amount", 50f, 2))
/** Columns that can be switched off: key, title, on when never set. */
val margOptionalColumns = listOf(Triple("free", "Free", true), Triple("pack", "Pack", true), Triple("batch", "Batch", false), Triple("mrp", "MRP", true),
    Triple("exp", "Expiry", true), Triple("hsn", "HSN", true), Triple("dis", "Disc %", true), Triple("tax", "SGST / CGST (IGST) %", true), Triple("gst", "GST %", false))
fun margShown(co: J): Set<String> {
    val raw = co.str("print_marg_cols")
    val set = raw.split(',').map { it.trim() }.toSet()
    return margOptionalColumns.filter { if (raw.isEmpty()) it.third else it.first in set }.map { it.first }.toSet()
}
fun margCols(co: J, inter: Boolean): List<MargColumn> {
    val on = margShown(co)
    val pcsOnly = co.str("print_qty") == "pcs"
    return margColumns.filter { c ->
        when (c.key) {
            "free", "pack", "batch", "mrp", "exp", "hsn", "dis", "gst" -> c.key in on
            "sgst", "cgst" -> "tax" in on && !inter
            "igst" -> "tax" in on && inter
            "box" -> !pcsOnly
            else -> true
        }
    }
}
fun margClasses(inv: J, co: J): List<Double> {
    val used = inv.list("lines").map { it.num("gst_rate") }.toSet()
    val all = (if (co.str("print_marg_classes") == "used") emptySet() else setOf(5.0, 12.0, 18.0, 28.0)) + used
    return if (all.isEmpty()) listOf(0.0) else all.sorted()
}
fun margSpec(base: Spec, inv: J, co: J): Spec {
    val f = base.fs
    // the bank details go under the GST classes, in room the totals beside them need anyway
    val bankH = if (bankLines(co).isEmpty()) 0f else bankLines(co).size * 8f * f + 4
    val classH = (margClasses(inv, co).size + 2) * 8.6f * f + 4
    val totals = max(classH + bankH, 9 * 8.6f * f) + 13 * f + 1.2f
    return base.copy(tableHead = 15 * f, foot = 36 * f, totals = totals, strip = 26 * f, sellerBand = 52 * f, buyerBand = 0f, headNext = 18 * f)
}
fun expText(d: String): String { val p = d.split('-'); return if (p.size >= 2 && p[0].length == 4) "${p[1]}/${p[0].takeLast(2)}" else "" }
fun addDays(d: String, n: Int): String = try { java.time.LocalDate.parse(d).plusDays(n.toLong()).toString() } catch (_: Exception) { d }

class MargSheet(val inv: J, val co: J, val rows: IntRange, val page: Int, val pages: Int, val copy: String, val g: Spec) {
    private val first = page == 0
    private val last = page == pages - 1
    private val inter = inv.num("igst") > 0
    private val cols = margCols(co, inter)
    private val accent = margInk(co).first
    private val band = margInk(co).second
    private val isNote = inv.str("doc_title") == "DEBIT NOTE"
    private val fs = g.fs
    private fun on(k: String, d: Boolean = true) = if (co.str(k).isEmpty()) d else co.str(k) != "0"
    private fun hc(s: String) = if (co.str("print_caps_head") == "1") s.uppercase() else s
    private val companyName = co.str("company_name").ifEmpty { co.str("name") }
    private val docTitle = inv.str("doc_title").ifEmpty { co.str("print_title").ifEmpty { "GST INVOICE" }.uppercase() }
    private val noLabel = inv.str("doc_no_label").ifEmpty { "Invoice No." }
    private val perBox = co.str("print_marg_rate") != "pcs" && co.str("print_qty") != "pcs"
    private val L = 0.8f

    fun draw(pen: Pen, ox: Float = 0f, oy: Float = 0f) {
        pen.serif = co.str("print_marg_font") != "sans"
        val x = ox + g.m; var y = oy + g.m; val w = g.w - 2 * g.m
        val head = if (first) g.headFirst else g.headNext
        val tableH = g.inner - head - g.foot - (if (last) g.totals else 0f)
        val top = y
        if (first) header(pen, x, y, w) else nextHeader(pen, x, y, w)
        y += head; pen.hLine(x, x + w, y, L)
        table(pen, x, y, w, tableH); y += tableH
        if (last) { pen.hLine(x, x + w, y, L); totals(pen, x, y, w); y += g.totals }
        pen.hLine(x, x + w, y, L)
        footer(pen, x, y, w, g.foot); y += g.foot
        pen.box(RectF(x, top, x + w, y), 1.1f)
        pen.serif = false
    }

    // MARK: header

    private fun header(pen: Pen, x: Float, y: Float, w: Float) {
        val lw = w * 0.55f
        var ly = y + 3
        pen.text(hc(companyName), x + 6, ly, lw - 12, 18 * fs, 15 * fs, 700, color = accent, minScale = 0.55f); ly += 18 * fs
        if (co.str("print_tagline").isNotEmpty()) { pen.text(hc(co.str("print_tagline")), x + 6, ly, lw - 12, 8 * fs, 6.5f * fs, color = accent, minScale = 0.7f); ly += 8 * fs }
        ly += pen.para(hc(co.str("company_address")), x + 6, ly, lw - 12, 7.5f * fs, 2, color = accent)
        if (co.str("company_phone").isNotEmpty()) pen.text("Phone : ${co.str("company_phone")}", x + 6, ly, lw - 12, 9.5f * fs, 7.5f * fs, color = accent)
        pen.vLine(x + lw, y, y + g.sellerBand, L)
        val rx = x + lw + 6; val rw = w - lw - 12
        var ry = y + 3
        val pageTxt = if (on("print_marg_page")) "Page ${page + 1}" + (if (pages > 1) " of $pages" else "") else ""
        val pw = if (pageTxt.isEmpty()) 0f else pen.width(pageTxt, 6.5f * fs, 700) + 4
        pen.text(hc(partyTitle()), rx, ry, rw - pw, 13 * fs, 10.5f * fs, 700, minScale = 0.6f)
        if (pageTxt.isNotEmpty()) pen.text(pageTxt, rx + rw - pw, ry, pw, 13 * fs, 6.5f * fs, 700, 2, minScale = 1f)
        ry += 13 * fs
        val lh = 8.8f * fs
        for ((t, b) in partyLines()) {
            if (ry + lh > y + g.sellerBand) break
            pen.text(hc(t), rx, ry, rw, lh, 7.5f * fs, if (b) 700 else 400, minScale = 0.65f); ry += lh
        }
        // second band: GSTIN | title box | bill details
        val by = y + g.sellerBand
        pen.hLine(x, x + w, by, L)
        val bh = g.strip
        val tw = 150 * g.cw
        val leftW = w * 0.34f
        var gy = by + 2
        val ids = mutableListOf<Pair<String, Boolean>>()
        if (on("print_marg_email", false) && co.str("company_email").isNotEmpty()) ids.add("E-Mail : ${co.str("company_email")}" to false)
        if (co.str("company_gstin").isNotEmpty()) ids.add("GSTIN : ${co.str("company_gstin")}" to true)
        if (co.str("state_code").isNotEmpty()) ids.add("State code : ${co.str("state_code")}" to false)
        // labels and colons lined up, all the same size; only the GSTIN in bold
        val ih = minOf(8.6f * fs, (bh - 3) / max(1, ids.size))
        gy = by + (bh - ih * ids.size) / 2
        val labs = ids.map { it.first.substringBefore(" : ") to it.first.substringAfter(" : ") }
        val labW = labs.maxOfOrNull { pen.width(it.first, 7.5f * fs) } ?: 0f
        labs.forEachIndexed { i, (k, v) ->
            pen.text(k, x + 6, gy, labW + 1, ih, 7.5f * fs, color = accent, minScale = 1f)
            pen.text(":", x + 6 + labW + 3, gy, 4f, ih, 7.5f * fs, color = accent, minScale = 1f)
            pen.text(v, x + 6 + labW + 9, gy, leftW - labW - 21, ih, 7.5f * fs, if (ids[i].second) 700 else 400, color = accent, minScale = 0.6f)
            gy += ih
        }
        pen.vLine(x + leftW, by, by + bh, L)
        pen.shade(RectF(x + leftW, by, x + leftW + tw, by + bh), band)
        pen.text(docTitle, x + leftW, by + 1, tw, bh * 0.66f, 12.5f * fs, 700, 1, minScale = 0.6f)
        pen.text(copy, x + leftW, by + bh * 0.62f, tw, bh * 0.34f, 5.5f * fs, 700, 1, minScale = 0.6f)
        pen.vLine(x + leftW + tw, by, by + bh, L)
        val dx = x + leftW + tw + 6; val dw = w - leftW - tw - 12
        val (left, right) = detailLists()
        val rowsN = max(left.size, right.size)
        val dh = (bh - 3) / max(1, rowsN)
        fun group(kv: List<Pair<String, String>>, gx: Float, gw: Float) {
            val labW = kv.maxOfOrNull { pen.width(it.first, 7.5f * fs) } ?: 0f
            kv.forEachIndexed { i, (k, v) ->
                val yy = by + 1.5f + i * dh
                pen.text(k, gx, yy, labW + 1, dh, 7.5f * fs, minScale = 1f)
                pen.text(":", gx + labW + 3, yy, 4f, dh, 7.5f * fs, minScale = 1f)
                pen.text(v, gx + labW + 9, yy, gw - labW - 9, dh, 7.5f * fs, 700, minScale = 0.6f)
            }
        }
        group(left, dx, dw * 0.55f)
        group(right, dx + dw * 0.57f, dw * 0.43f)
    }

    private fun partyTitle(): String {
        val name = inv.str("party_name").ifEmpty { "Cash customer" }
        if (isNote) return "Supplier: $name"
        return (if (inv.str("party_name").isEmpty() || co.str("print_marg_ms") == "0") "" else "M/s ") + name
    }

    private fun partyLines(): List<Pair<String, Boolean>> {
        if (!on("print_party")) return emptyList()
        val mob = mutableListOf<String>()
        for (m in listOf(inv.str("party_phone")) + inv.str("party_mobiles").split(',', ';', '/')) { val t = m.trim(); if (t.isNotEmpty() && t !in mob) mob.add(t) }
        if (inv.str("party_tel").isNotEmpty()) mob.add(inv.str("party_tel"))
        val out = mutableListOf<Pair<String, Boolean>>()
        inv.str("party_address").trim().takeIf { it.isNotEmpty() }?.let { out.add(it to false) }
        if (inv.str("party_state").isNotEmpty()) out.add("State code : ${inv.str("party_state")}" to false)
        if (mob.isNotEmpty()) out.add("Ph.No. : ${mob.joinToString(", ")}" to false)
        out.add("GSTIN : ${inv.str("party_gstin").ifEmpty { "Unregistered" }}" to true)
        val more = listOf("PAN" to inv.str("party_pan"), "FSSAI" to inv.str("party_fssai")).filter { it.second.isNotEmpty() }.joinToString("   ") { "${it.first} : ${it.second}" }
        if (more.isNotEmpty()) out.add(more to false)
        return out.take(5)
    }

    private fun detailLists(): Pair<List<Pair<String, String>>, List<Pair<String, String>>> {
        val left = mutableListOf(noLabel to inv.str("invoice_no"))
        val right = mutableListOf("Date" to Fmt.dmy(inv.str("date")))
        if (inv.o.has("doc_line")) {
            if (inv.str("doc_line").isNotEmpty()) left.add("Ref" to inv.str("doc_line"))
        } else {
            if (on("print_salesman")) left.add("Sales Man" to inv.str("salesman_name").ifEmpty { "-" }.uppercase())
            if (on("print_marg_due") && inv.str("pay_mode") == "CREDIT") right.add("Due Date" to Fmt.dmy(addDays(inv.str("date"), inv.int("party_credit_days"))))
            else if (on("print_payment")) right.add("Payment" to inv.str("pay_mode").lowercase().replaceFirstChar { it.uppercase() })
            if (inv.str("ewb_no").isNotEmpty()) left.add("E-way bill" to inv.str("ewb_no"))
        }
        return left to right
    }

    private fun nextHeader(pen: Pen, x: Float, y: Float, w: Float) {
        pen.shade(RectF(x, y, x + w, y + g.headNext), band)
        val pt = "Page ${page + 1} of $pages"
        val pw = pen.width(pt, 6.5f * fs, 700)
        pen.text("${hc(companyName)}  ·  $docTitle  ·  $noLabel ${inv.str("invoice_no")}  ·  ${Fmt.dmy(inv.str("date"))}  (continued)", x + 6, y, w - pw - 18, g.headNext, 8 * fs, 700)
        pen.text(pt, x + w - 6 - pw, y, pw, g.headNext, 6.5f * fs, 700, 2, minScale = 1f)
    }

    // MARK: items

    private fun cellText(c: MargColumn, i: Int, l: J): String {
        val ppb = max(1, l.int("pcs_per_box"))
        val qty = l.int("qty")
        val k = if (perBox && ppb > 1) ppb.toDouble() else 1.0
        return when (c.key) {
            "sn" -> "${i + 1}."
            "box" -> "${qty / ppb}"
            "pcs" -> if (co.str("print_qty") == "pcs") "$qty" else "${qty % ppb}"
            "free" -> "${l.int("free_qty")}"
            "pack" -> "$ppb*1"
            "item" -> Fmt.cut(if (co.str("print_caps") == "1") l.str("item_name").uppercase() else l.str("item_name"), 60)
            "batch" -> l.str("batch_no")
            "mrp" -> if (l.num("mrp") > 0) Fmt.amount(l.num("mrp") * k) else ""
            "exp" -> expText(l.str("exp_date"))
            "hsn" -> l.str("hsn")
            "rate" -> Fmt.amount(l.num("rate") * k)
            "dis" -> Fmt.amount(l.num("disc_pct"))
            "gst", "igst" -> Fmt.amount(l.num("gst_rate"))
            "sgst", "cgst" -> Fmt.amount(l.num("gst_rate") / 2)
            "amount" -> Fmt.amount(l.num("amount"))
            else -> ""
        }
    }

    private fun table(pen: Pen, x: Float, y: Float, w: Float, h: Float) {
        val fixed = cols.mapNotNull { it.width }.sum() * g.cw
        val ws = cols.map { it.width?.let { v -> v * g.cw } ?: (w - fixed) }
        val lines = inv.list("lines")
        pen.shade(RectF(x, y, x + w, y + g.tableHead), band)
        var cx = x
        cols.forEachIndexed { k, c -> pen.text(c.head, cx, y, ws[k], g.tableHead, 8 * fs, 700, c.align, minScale = 0.7f, pad = 2.5f); cx += ws[k] }
        var ry = y + g.tableHead
        for (i in rows) {
            val l = lines.getOrNull(i) ?: continue
            cx = x
            cols.forEachIndexed { k, c -> pen.text(cellText(c, i, l), cx, ry, ws[k], g.rowH, 7.5f * fs, 400, c.align, minScale = 0.7f, pad = 2.5f); cx += ws[k] }
            ry += g.rowH
        }
        cx = x
        for (k in 0 until ws.size - 1) { cx += ws[k]; pen.vLine(cx, y, y + h, 0.6f) }
        pen.hLine(x, x + w, y + g.tableHead, L)
    }

    // MARK: totals

    private class ClassRow(val label: String, val taxable: Double, val disc: Double, val sgst: Double, val cgst: Double, val igst: Double) {
        val gst get() = sgst + cgst + igst
        val total get() = taxable + gst
    }

    private fun totals(pen: Pen, x: Float, y: Float, w: Float) {
        val lines = inv.list("lines")
        val rows = margClasses(inv, co).map { r ->
            val ls = lines.filter { abs(it.num("gst_rate") - r) < 0.001 }
            fun sum(k: String) = ls.sumOf { it.num(k) }
            ClassRow("GST ${Fmt.amount(r)}", sum("taxable"), sum("disc_amt"), sum("sgst"), sum("cgst"), sum("igst"))
        }
        val tot = ClassRow("TOTAL", rows.sumOf { it.taxable }, rows.sumOf { it.disc }, rows.sumOf { it.sgst }, rows.sumOf { it.cgst }, rows.sumOf { it.igst })
        val heads = if (inter) listOf("CLASS", "TAXABLE", "DISC.", "IGST", "TOTAL GST", "AMOUNT") else listOf("CLASS", "TAXABLE", "DISC.", "SGST", "CGST", "TOTAL GST", "AMOUNT")
        fun vals(r: ClassRow) = if (inter) listOf(r.label, Fmt.amount(r.taxable), Fmt.amount(r.disc), Fmt.amount(r.igst), Fmt.amount(r.gst), Fmt.amount(r.total))
            else listOf(r.label, Fmt.amount(r.taxable), Fmt.amount(r.disc), Fmt.amount(r.sgst), Fmt.amount(r.cgst), Fmt.amount(r.gst), Fmt.amount(r.total))
        val rh = 8.6f * fs
        val bank = bankLines(co)
        val wordsH = 13 * fs
        val upperH = g.totals - wordsH - 1.2f
        val sumW = 172 * g.cw
        val tw = w - sumW
        val cw = tw / heads.size
        fun line(v: List<String>, top: Float, h: Float, bold: Boolean, size: Float = 7f) {
            v.forEachIndexed { i, s -> pen.text(s, x + i * cw, top, cw, h, size * fs, if (bold) 700 else 400, if (i == 0) 0 else 2, minScale = 0.6f, pad = 3f) }
        }
        pen.shade(RectF(x, y, x + tw, y + rh + 1), band)
        line(heads, y, rh + 1, true, 7.5f)
        var ty = y + rh + 1
        for (r in rows) { line(vals(r), ty, rh, false); ty += rh }
        pen.hLine(x, x + tw, ty, 0.6f)
        line(vals(tot), ty, rh, true)
        val tableEnd = ty + rh
        for (k in 1 until heads.size) pen.vLine(x + k * cw, y, tableEnd, 0.5f, Color.argb(178, 0, 0, 0))
        if (bank.isNotEmpty()) {
            // the bank details in the room under the GST classes
            pen.hLine(x, x + tw, tableEnd, 0.6f)
            var by = tableEnd + 1.5f
            for (l in bank) { bankLine(pen, l, x + 4, by, tw - 8, 8f * fs, 6.8f * fs); by += 8f * fs }
        }
        pen.vLine(x + tw, y, y + upperH, L)
        // the totals beside it, ending in the grand total
        val sx = x + tw
        val sums = mutableListOf("SUB TOTAL" to inv.num("subtotal"))
        if (inv.num("discount") > 0) sums.add("LESS DISCOUNT" to -inv.num("discount"))
        if (inv.num("discount") > 0 || abs(inv.num("taxable") - inv.num("subtotal")) > 0.005) sums.add("TAXABLE VALUE" to inv.num("taxable"))
        if (inter) sums.add("IGST PAYABLE" to inv.num("igst")) else { sums.add("SGST PAYABLE" to inv.num("sgst")); sums.add("CGST PAYABLE" to inv.num("cgst")) }
        sums.add("ROUND OFF" to inv.num("round_off"))
        if (inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005) sums.add("PAID" to inv.num("paid"))
        val gh = 17 * fs
        var sy = y + 2
        val sh = minOf(9f * fs, (upperH - gh - 4) / sums.size)
        val ss = minOf(7.5f * fs, sh * 0.85f)
        for ((a, v) in sums) { pen.text(a, sx + 6, sy, sumW - 12, sh, ss); pen.text(Fmt.amount(v), sx + 6, sy, sumW - 12, sh, ss, align = 2); sy += sh }
        val gy = y + upperH - gh
        pen.shade(RectF(sx, gy, x + w, y + upperH), band)
        pen.hLine(sx, x + w, gy, 0.6f)
        pen.text(if (isNote) "NOTE TOTAL" else "GRAND TOTAL", sx + 6, gy, sumW / 2, gh, 9.5f * fs, 700)
        pen.text(Fmt.amount(inv.num("total")), sx + sumW / 2, gy, sumW / 2 - 6, gh, 11 * fs, 700, 2)
        // amount in words (and the party's balance)
        val wy = y + upperH
        pen.hLine(x, x + w, wy, 0.6f)
        if (co.str("print_words") != "0") pen.text("Rs. " + inv.str("amount_words").replace("Rupees ", ""), x + 6, wy, w * 0.6f, wordsH, 7.5f * fs, 600, minScale = 0.6f)
        if (co.str("print_balance") == "1" && inv.has("party_prev_balance"))
            pen.text("Old balance ${balanceText(inv.num("party_prev_balance"))}  ·  Now due ${balanceText(inv.num("party_balance_after"))}", x + w * 0.6f, wy, w * 0.4f - 6, wordsH, 7 * fs, 700, 2, minScale = 0.6f)
    }

    // MARK: footer

    private fun footer(pen: Pen, x: Float, y: Float, w: Float, h: Float) {
        val sigW = if (on("print_signature")) 150 * g.cw else 0f
        val recW = if (on("print_marg_receiver")) 140 * g.cw else 0f
        val tw = w - sigW - recW
        var ty = y + 3
        if (on("print_terms") && co.str("invoice_terms").isNotEmpty()) {
            val tt = "Terms & Conditions"
            pen.text(tt, x + 6, ty, tw - 12, 10 * fs, 8 * fs, 700, minScale = 1f)
            pen.hLine(x + 6, x + 6 + pen.width(tt, 8 * fs, 700), ty + 9.3f * fs, 0.5f)
            ty += 10 * fs
            ty += pen.para(co.str("invoice_terms"), x + 6, ty, tw - 12, 6.5f * fs, 3)
        }
        if (co.str("print_bank").isNotEmpty()) { pen.text(co.str("print_bank"), x + 6, ty, tw - 12, 8 * fs, 6.5f * fs, 600, minScale = 0.7f); ty += 8 * fs }
        if (co.str("print_note").isNotEmpty() && ty + 8 * fs <= y + h) pen.text(co.str("print_note"), x + 6, ty, tw - 12, 8 * fs, 7 * fs, 700, minScale = 0.7f)
        var cx = x + tw
        if (recW > 0) {
            pen.vLine(cx, y, y + h, L)
            pen.text("Receiver", cx, y + 3, recW, 10 * fs, 8 * fs, 700, 1)
            pen.text("(signature and stamp)", cx, y + h - 9 * fs, recW, 8 * fs, 5.5f * fs, align = 1, color = Color.argb(140, 0, 0, 0))
            cx += recW
        }
        if (sigW > 0) {
            pen.vLine(cx, y, y + h, L)
            pen.text(hc("For $companyName"), cx + 6, y + 3, sigW - 12, 9 * fs, 7 * fs, 700, minScale = 0.6f)
            pen.text("Authorised signatory", cx + 6, y + h - 11 * fs, sigW - 12, 10 * fs, 8 * fs, 700)
        }
    }
}
