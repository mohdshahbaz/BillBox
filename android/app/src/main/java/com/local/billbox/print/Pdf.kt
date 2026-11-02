package com.local.billbox.print

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.balanceText
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

// The bill layouts of the Mac and iPhone (Print.swift), drawn as vector PDF pages with Android's PdfDocument.

enum class PrintLayout(val id: String, val label: String) {
    HalfSheets("halfSheets", "Half sheets: Original on one A4 page, Duplicate on the next, each at the top of the page"),
    A4TwoUp("a4TwoUp", "A4 sheet: Original on top, Duplicate below"),
    Single("single", "Half sheet: Original copy only, at the top of an A4 page"),
    A4Full("a4Full", "Full A4 page: Original + Duplicate, one copy per page"),
    A4FullOriginal("a4FullOriginal", "Full A4 page: Original copy only");

    val isFullPage: Boolean get() = this == A4Full || this == A4FullOriginal
    companion object { fun parse(s: String) = entries.firstOrNull { it.id == s } ?: HalfSheets }
}

val copyLabels = listOf("ORIGINAL FOR RECIPIENT", "DUPLICATE FOR TRANSPORTER/SUPPLIER")
const val triplicateLabel = "TRIPLICATE FOR ASSESSEE"
/** The copy labels, as the company set them (Settings › Printing) or the standard ones; a third copy when switched on. */
fun copyLabelsFor(co: J): List<String> {
    val l = mutableListOf(co.str("print_copy1").let { if (it.isEmpty()) copyLabels[0] else it.uppercase() },
        co.str("print_copy2").let { if (it.isEmpty()) copyLabels[1] else it.uppercase() })
    if (co.str("print_triplicate") == "1") l.add(co.str("print_copy3").let { if (it.isEmpty()) triplicateLabel else it.uppercase() })
    return l
}

/** Settings › Printing › Text size: smaller, normal or larger print (rows grow with the text, so nothing is cut). */
fun printScale(co: J): Float = when (co.str("print_font")) { "small" -> 0.92f; "large" -> 1.1f; else -> 1f }

/** Columns that can be left off the printed bill (Settings › Printing): key, title, column index. */
val optionalColumns = listOf(Triple("hsn", "HSN", 2), Triple("mrp", "MRP", 4), Triple("disc", "Disc %", 6), Triple("taxable", "Taxable", 7), Triple("gst", "GST %", 8))

fun printedColumns(co: J): List<Int> {
    val hide = co.str("print_hide_cols").split(',').map { it.trim() }.toSet()
    val gone = optionalColumns.filter { it.first in hide }.map { it.third }.toSet()
    return (0 until 10).filter { it !in gone }
}

/** Page geometry in points (same numbers as the Mac): half sheet 210 x 148.5 mm, full page A4. */
data class Spec(val w: Float, val h: Float, val m: Float, val rowH: Float, val tableHead: Float, val foot: Float, val totals: Float,
                val strip: Float, val sellerBand: Float, val buyerBand: Float, val headNext: Float, val fs: Float, val cw: Float) {
    val headFirst get() = strip + sellerBand + buyerBand + 0.6f
    val inner get() = h - 2 * m - 2.4f
    /** The same page with text (and the rows holding it) made larger or smaller. */
    fun scaled(k: Float): Spec = if (k == 1f) this else copy(rowH = rowH * k, tableHead = tableHead * k, foot = foot * k, totals = totals * k,
        strip = strip * k, sellerBand = sellerBand * k, headNext = headNext * k, fs = fs * k)
    /** Room for the bank details under the GST table, when the bill prints them. */
    /** The bank details sit in the footer, in the room it already has. With compact totals (on unless switched off) the
     *  totals take only the height their lines need, and the rest goes to item rows. */
    fun withBank(co: J, inv: J = J()): Spec {
        if (!compactPrint(co)) return this
        fun on(k: String) = co.str(k).isEmpty() || co.str(k) != "0"
        val f = fs
        var n = 1
        if (inv.num("discount") > 0) n += 2
        if (inv.num("cgst") > 0) n += 2
        if (inv.num("igst") > 0) n += 1
        if (abs(inv.num("round_off")) > 0) n += 1
        if (inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005) n += 1
        val right = 4 + n * 9f * f + 4 + 19f * f
        var left = leftOther(co, inv, f)
        val bankH = bankTabHeight(co, f)
        if (bankH > 0f && left + bankH + 2 <= totals) left += bankH   // the bank block rides in this room when it fits
        return copy(totals = minOf(totals, ceil(maxOf(right, left) + 2)))
    }
    fun withBankBlock(co: J): Spec {
        val rows = bankRows(co)
        if (rows.isEmpty()) return this
        val extra = rows.size * 8.4f * fs + (if (rows.any { it.first == "ADDRESS" && it.second.length > 70 }) 8.4f * fs else 0f) + 4f
        return copy(totals = totals + extra)
    }
    fun cap(first: Boolean, last: Boolean): Int = floor((inner - (if (first) headFirst else headNext) - tableHead - foot - (if (last) totals else 0f)) / rowH).toInt()

    companion object {
        val half = Spec(595.276f, 420.945f, 20f, 12f, 15f, 26f, 91f, 15f, 56f, 0f, 18f, 1f, 1f)
        val full = Spec(595.276f, 841.89f, 34f, 16f, 20f, 32f, 112f, 19f, 68f, 0f, 24f, 1.15f, 1.0f)
    }
}

/** The bank details printed above the amount in words (Settings › Printing › Bank details), in this order; empty ones left out. */
val bankFields = listOf("bank_name" to "BANK NAME", "bank_ac_name" to "ACCOUNT NAME", "bank_ac_no" to "ACCOUNT NUMBER", "bank_ifsc" to "IFSC CODE",
    "bank_branch" to "BRANCH NAME", "bank_branch_code" to "BRANCH CODE", "bank_address" to "ADDRESS")
fun bankRows(co: J): List<Pair<String, String>> =
    if (co.str("print_bank_block") == "0") emptyList() else bankFields.mapNotNull { (k, label) -> co.str(k).trim().takeIf { it.isNotEmpty() }?.let { label to it } }

/** The bank details in at most three short lines of (label, value) pairs (Bank · A/c name / A/c no. · IFSC / Branch · address). */
/** Settings › Printing › Compact totals (on unless switched off): GST and bank details take less room, for more item rows. */
fun compactPrint(co: J): Boolean = co.str("print_compact") != "0"

fun bankLines(co: J): List<List<Pair<String, String>>> {
    if (co.str("print_bank_block") == "0") return emptyList()
    fun v(k: String) = co.str(k).trim()
    val code = v("bank_branch_code")
    val branch = v("bank_branch") + if (code.isEmpty()) "" else if (v("bank_branch").isEmpty()) "Code $code" else " ($code)"
    return listOf(listOf("Bank" to v("bank_name"), "A/c name" to v("bank_ac_name")), listOf("A/c no." to v("bank_ac_no"), "IFSC" to v("bank_ifsc")),
        listOf("Branch" to branch, "" to v("bank_address"))).map { l -> l.filter { it.second.isNotEmpty() } }.filter { it.isNotEmpty() }
}

/** Draws one line of bank details (bold labels) from x within width w; shrinks to fit. */
fun bankLine(pen: Pen, pairs: List<Pair<String, String>>, x: Float, top: Float, w: Float, h: Float, size: Float) {
    val parts = mutableListOf<Pair<String, Int>>()
    pairs.forEachIndexed { i, (k, v) -> if (i > 0) parts.add("  ·  " to 400); if (k.isNotEmpty()) parts.add("$k: " to 700); parts.add(v to 500) }
    val total = parts.sumOf { pen.width(it.first, size, it.second).toDouble() }.toFloat()
    val k = if (total > w) maxOf(0.6f, w / total) else 1f
    var cx = x
    for ((t, wt) in parts) { if (cx >= x + w) break; cx += pen.text(t, cx, top, x + w - cx, h, size * k, wt, minScale = 1f) }
}

/** The bank details as (label, value) rows for the aligned block above "Amount in words": Bank, A/c name, A/c no., IFSC, Branch, Address. */
fun bankTabRows(co: J): List<Pair<String, String>> = bankLines(co).flatten().map { (k, v) -> (if (k.isEmpty()) "Address" else k) to v }
/** Height of that block: a small heading and one line per row. */
fun bankTabHeight(co: J, fs: Float): Float = bankTabRows(co).let { if (it.isEmpty()) 0f else (it.size + 1) * 7.6f * fs + 3f }
/** Height the left side of the totals band already needs without the bank block (GST table, balance, amount in words). */
fun leftOther(co: J, inv: J, f: Float): Float {
    fun on(k: String) = co.str(k).isEmpty() || co.str(k) != "0"
    var left = 8f
    if (on("print_gst_table")) left += (maxOf(1, inv.list("gst_summary").size) + 1) * 8.5f * f + 1
    if (co.str("print_balance") == "1" && inv.has("party_prev_balance")) left += 10f * f
    if (on("print_words")) left += 8f * f + 18f * f
    return left
}
/** True when the bank block fits in the totals band of this page design (otherwise the bank lines stay in the footer). */
fun bankTabFits(co: J, inv: J, g: Spec): Boolean { val h = bankTabHeight(co, g.fs); return h > 0f && leftOther(co, inv, g.fs) + h + 2 <= g.totals + 0.5f }

/** Splits n item rows into pages (always at least one page). */
fun paginate(n: Int, g: Spec): List<IntRange> {
    if (n <= g.cap(true, true)) return listOf(0 until n)
    val pages = mutableListOf<IntRange>()
    var i = 0; var first = true
    while (true) {
        val remaining = n - i
        if (remaining <= g.cap(first, true)) { pages.add(i until n); break }
        val take = max(1, minOf(g.cap(first, false), remaining - 1))   // the totals never sit alone on an empty page
        pages.add(i until i + take); i += take; first = false
    }
    return pages
}

private val widths: List<Float?> = listOf(18f, null, 42f, 82f, 32f, 40f, 28f, 48f, 26f, 54f)
private val headings = listOf("#", "Description of goods", "HSN", "Qty (box / pcs)", "MRP", "Rate", "Disc %", "Taxable", "GST %", "Amount")
private const val FRAME = 1.1f
private const val RULE = 0.6f
private val SHADE = Color.argb(23, 0, 0, 0)
private val MUTED = Color.argb(158, 0, 0, 0)

/** Text drawing in points: shrinks to fit (down to minScale), then cuts with "…". */
class Pen(val c: Canvas) {
    // linear + subpixel text: a PDF page is measured in points, and at 6-7 pt Android otherwise rounds every letter's width
    // to whole units, which squeezed small lines (address, terms, GST table) together
    private val p = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.LINEAR_TEXT_FLAG or Paint.SUBPIXEL_TEXT_FLAG)
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = Color.BLACK }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    /** Serif letters (the Marg design's "Classic serif" typeface). */
    var serif = false

    private fun font(size: Float, weight: Int, color: Int) {
        p.textSize = size; p.color = color
        p.typeface = if (serif) Typeface.create(Typeface.SERIF, if (weight >= 600) Typeface.BOLD else Typeface.NORMAL)
            else when { weight >= 700 -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD); weight >= 600 -> Typeface.create("sans-serif-medium", Typeface.NORMAL); else -> Typeface.DEFAULT }
    }

    /** One line in the box [x, x+w] centred on the band [top, top+h]. align: 0 left, 1 centre, 2 right. Returns the width used. */
    fun text(s: String, x: Float, top: Float, w: Float, h: Float, size: Float, weight: Int = 400, align: Int = 0, color: Int = Color.BLACK, minScale: Float = 0.75f, pad: Float = 0f): Float {
        if (s.isEmpty()) return 0f
        font(size, weight, color)
        val room = max(1f, w - 2 * pad)
        var tw = p.measureText(s)
        if (tw > room) { p.textSize = max(size * minScale, size * room / tw); tw = p.measureText(s) }
        val shown = if (tw > room) TextUtils.ellipsize(s, p, room, TextUtils.TruncateAt.END).toString() else s
        val sw = p.measureText(shown)
        val fm = p.fontMetrics
        val base = top + h / 2 - (fm.ascent + fm.descent) / 2
        val sx = when (align) { 1 -> x + (w - sw) / 2; 2 -> x + w - pad - sw; else -> x + pad }
        c.drawText(shown, sx, base, p)
        return sw
    }

    /** Text at a baseline-free top position, natural width (for runs laid out left to right). */
    fun run(s: String, x: Float, top: Float, h: Float, size: Float, weight: Int = 400, color: Int = Color.BLACK): Float =
        text(s, x, top, 10000f, h, size, weight, 0, color, 1f)

    fun width(s: String, size: Float, weight: Int = 400): Float { font(size, weight, Color.BLACK); return p.measureText(s) }

    /** Up to maxLines wrapped lines from the top; returns the height used. */
    fun para(s: String, x: Float, top: Float, w: Float, size: Float, maxLines: Int, weight: Int = 400, color: Int = Color.BLACK): Float {
        if (s.isBlank()) return 0f
        font(size, weight, color)
        val l = StaticLayout.Builder.obtain(s, 0, s.length, p, max(1, w.roundToInt())).setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setMaxLines(maxLines).setEllipsize(TextUtils.TruncateAt.END).setIncludePad(false).setLineSpacing(0f, 1f).build()
        c.save(); c.translate(x, top); l.draw(c); c.restore()
        return l.height.toFloat()
    }

    fun hLine(x1: Float, x2: Float, y: Float, w: Float = RULE, color: Int = Color.BLACK) { line.strokeWidth = w; line.color = color; line.pathEffect = null; c.drawLine(x1, y, x2, y, line) }
    fun vLine(x: Float, y1: Float, y2: Float, w: Float = RULE, color: Int = Color.BLACK) { line.strokeWidth = w; line.color = color; line.pathEffect = null; c.drawLine(x, y1, x, y2, line) }
    fun dashed(x1: Float, x2: Float, y: Float) { line.strokeWidth = 0.5f; line.color = Color.argb(115, 0, 0, 0); line.pathEffect = DashPathEffect(floatArrayOf(4f, 3f), 0f); c.drawLine(x1, y, x2, y, line); line.pathEffect = null }
    fun box(r: RectF, w: Float = FRAME) { line.strokeWidth = w; line.color = Color.BLACK; line.pathEffect = null; c.drawRect(r, line) }
    fun shade(r: RectF, color: Int = SHADE) { fill.color = color; c.drawRect(r, fill) }
}

/** Builds a PDF from page drawers, each page its own size. */
class PdfBuilder {
    private val doc = PdfDocument()
    private var n = 0
    fun page(w: Float, h: Float, draw: (Pen) -> Unit) {
        n++
        val pg = doc.startPage(PdfDocument.PageInfo.Builder(w.roundToInt(), h.roundToInt(), n).create())
        pg.canvas.drawColor(Color.WHITE)
        draw(Pen(pg.canvas))
        doc.finishPage(pg)
    }
    val pageCount get() = n
    fun bytes(): ByteArray { val out = ByteArrayOutputStream(); doc.writeTo(out); doc.close(); return out.toByteArray() }
}

/** One copy of a bill (or debit note) on one page, inside one ruled frame, at (ox, oy). */
class InvoiceSheet(val inv: J, val co: J, val rows: IntRange, val page: Int, val pages: Int, val copy: String, val g: Spec) {
    /** The bank details sit in the totals band, left of the totals, on the last page when they fit there. */
    private val bankTab = page == pages - 1 && bankTabFits(co, inv, g)
    private val first = page == 0
    private val last = page == pages - 1
    private val docTitle = inv.str("doc_title").ifEmpty { co.str("print_title").ifEmpty { "TAX INVOICE" }.uppercase() }
    private val noLabel = inv.str("doc_no_label").ifEmpty { "Invoice No." }
    private val companyName = co.str("company_name").ifEmpty { co.str("name") }
    private val cols = printedColumns(co)
    private fun on(k: String) = co.str(k) != "0"
    private val fs = g.fs

    private fun colWidths(total: Float): List<Float> {
        val ws = cols.map { widths[it] }
        val fixed = ws.filterNotNull().sum() * g.cw
        return ws.map { it?.let { v -> v * g.cw } ?: (total - fixed) }
    }

    fun draw(pen: Pen, ox: Float = 0f, oy: Float = 0f) {
        val x = ox + g.m; var y = oy + g.m; val w = g.w - 2 * g.m
        val head = if (first) g.headFirst else g.headNext
        val tableH = g.inner - head - g.foot - (if (last) g.totals else 0f)
        val frameTop = y
        if (first) firstHeader(pen, x, y, w) else nextHeader(pen, x, y, w)
        y += head
        pen.hLine(x, x + w, y + FRAME / 2, FRAME); y += FRAME
        table(pen, x, y, w, tableH)
        y += tableH
        if (last) { pen.hLine(x, x + w, y + FRAME / 2, FRAME); y += FRAME; totals(pen, x, y, w); y += g.totals }
        pen.box(RectF(x, frameTop, x + w, y))
        footer(pen, x, y, w)
    }

    private fun firstHeader(pen: Pen, x: Float, y: Float, w: Float) {
        // seller on the left, buyer on the right, compact (like a Marg bill)
        val half = w / 2
        var ly = y + 3
        val nameH = 14f * fs
        pen.text(hc(companyName), x + 5, ly, half - 10, nameH, 12 * fs, 700, minScale = 0.6f); ly += nameH
        if (co.str("print_tagline").isNotEmpty()) { pen.text(hc(co.str("print_tagline")), x + 5, ly, half - 10, 8f * fs, 6.5f * fs, color = MUTED, minScale = 0.7f); ly += 8f * fs }
        ly += pen.para(hc(co.str("company_address")), x + 5, ly, half - 10, 6.5f * fs, 2)
        val contact = listOf(co.str("company_phone").let { if (it.isEmpty()) "" else "Phone: $it" }, co.str("state_code").let { if (it.isEmpty()) "" else "State code: $it" }).filter { it.isNotEmpty() }.joinToString("   ")
        val small = 8.5f * fs
        if (contact.isNotEmpty()) { pen.text(hc(contact), x + 5, ly, half - 10, small, 6.5f * fs, minScale = 0.8f); ly += small }
        if (co.str("company_gstin").isNotEmpty()) pen.text(hc("GSTIN: ${co.str("company_gstin")}"), x + 5, ly, half - 10, small, 6.5f * fs, 600)
        pen.vLine(x + half, y, y + g.sellerBand)
        val bx = x + half + 5; val bw = half - 10
        var by = y + 3
        val lbl = hc(if (inv.str("doc_title") == "DEBIT NOTE") "Supplier:" else "Bill to:")
        // the buyer stands out: "Bill to" and the party in bold, larger than the seller's details
        val lw = pen.width(lbl, 7.5f * fs, 700)
        val rowH = 15f * fs
        pen.text(lbl, bx, by, lw + 1, rowH, 7.5f * fs, 700, minScale = 1f)
        pen.text(hc(inv.str("party_name").ifEmpty { "Cash customer" }), bx + lw + 4, by, bw - lw - 4, rowH, 11.5f * fs, 700, minScale = 0.6f)
        by += rowH
        val lineH = 9.5f * fs
        for (l in buyerLines()) {
            if (by + lineH > y + g.sellerBand) break
            pen.text(hc(l), bx, by, bw, lineH, 7.5f * fs, if (l.startsWith("GSTIN")) 700 else 600, minScale = 0.7f)
            by += lineH
        }
        pen.hLine(x, x + w, y + g.sellerBand + RULE / 2)
        infoRow(pen, x, y + g.sellerBand + RULE, w)
    }

    /** Settings › Printing › "Company and Bill to in CAPITALS" */
    private fun hc(t: String) = if (co.str("print_caps_head") == "1") t.uppercase() else t

    private fun buyerLines(): List<String> {
        if (!on("print_party")) return emptyList()   // Settings › Printing › party's address and numbers
        val mob = mutableListOf<String>()
        for (m in listOf(inv.str("party_phone")) + inv.str("party_mobiles").split(',', ';', '/')) { val t = m.trim(); if (t.isNotEmpty() && t !in mob) mob.add(t) }
        if (inv.str("party_tel").isNotEmpty()) mob.add(inv.str("party_tel"))
        fun join(vararg parts: Pair<String, String>) = parts.filter { it.second.isNotBlank() }.joinToString("   ") { "${it.first}: ${it.second}" }
        return listOf(inv.str("party_address"), join("GSTIN" to inv.str("party_gstin"), "State" to inv.str("party_state")), join("Phone" to mob.joinToString(", ")),
            join("PAN" to inv.str("party_pan"), "Email" to inv.str("party_email"), "FSSAI" to inv.str("party_fssai"))).filter { it.isNotBlank() }
    }

    private fun details(): List<Triple<String, String, Boolean>> {
        val out = mutableListOf(Triple(noLabel, inv.str("invoice_no"), true), Triple("Date", Fmt.dmy(inv.str("date")), true))
        if (inv.o.has("doc_line")) {
            if (inv.str("doc_line").isNotEmpty()) out.add(Triple("Ref", inv.str("doc_line"), false))
        } else {
            if (on("print_salesman")) out.add(Triple("Salesman", inv.str("salesman_name").ifEmpty { "-" }, false))
            val mode = inv.str("pay_mode").lowercase().replaceFirstChar { it.uppercase() }
            val type = inv.str("sale_type").lowercase().replaceFirstChar { it.uppercase() }
            if (on("print_payment")) out.add(Triple("Payment", listOf(mode, if (type.isEmpty()) "" else "$type sale").filter { it.isNotEmpty() }.joinToString(" · "), false))
            if (inv.str("ewb_no").isNotEmpty()) out.add(Triple("E-way bill", inv.str("ewb_no"), true))
        }
        return out
    }

    private fun infoRow(pen: Pen, x: Float, y: Float, w: Float) {
        pen.shade(RectF(x, y, x + w, y + g.strip))
        val copyW = pen.width(copy, 6 * fs, 700)
        val end = x + w - 5 - copyW - 4
        var cx = x + 5
        cx += pen.run(docTitle, cx, y, g.strip, 8.5f * fs, 700) + 10
        for ((k, v, b) in details()) {
            if (cx >= end) break
            cx += pen.text("$k:", cx, y, end - cx, g.strip, 6.5f * fs, color = MUTED, minScale = 1f) + 3
            if (cx >= end) break
            cx += pen.text(v, cx, y, minOf(end - cx, pen.width(v, 7.5f * fs, if (b) 700 else 400) + 1), g.strip, 7.5f * fs, if (b) 700 else 400, minScale = 0.6f) + 10
        }
        pen.text(copy, x + w - 5 - copyW - 2, y, copyW + 2, g.strip, 6 * fs, 700, align = 2, minScale = 1f)
    }

    private fun nextHeader(pen: Pen, x: Float, y: Float, w: Float) {
        pen.shade(RectF(x, y, x + w, y + g.headNext))
        val copyW = pen.width(copy, 6.5f * fs, 700)
        pen.text("$docTitle  ·  $noLabel ${inv.str("invoice_no")}  ·  ${Fmt.dmy(inv.str("date"))}  (continued)", x + 6, y, w - copyW - 18, g.headNext, 8.5f * fs, 700)
        pen.text(copy, x + w - 6 - copyW, y, copyW, g.headNext, 6.5f * fs, 700, align = 2, minScale = 1f)
    }

    private fun table(pen: Pen, x: Float, y: Float, w: Float, h: Float) {
        val ws = colWidths(w)
        val lines = inv.list("lines")
        fun row(v: List<String>, top: Float, rh: Float, bold: Boolean) {
            var cx = x
            cols.forEachIndexed { k, i ->
                val align = if (i == 0) 1 else if (i in 3..9) 2 else 0
                pen.text(v[i], cx, top, ws[k], rh, 7 * fs, if (bold) 600 else 400, align, pad = 3f)
                cx += ws[k]
            }
        }
        pen.shade(RectF(x, y, x + w, y + g.tableHead))
        row(headings, y, g.tableHead, true)
        var ry = y + g.tableHead
        for (i in rows) {
            val l = lines.getOrNull(i) ?: continue
            var q = if (co.str("print_qty") == "pcs") "${l.int("qty")} pcs" else Fmt.boxPcs(l.int("qty"), l.int("pcs_per_box"))
            val f = l.int("free_qty"); if (f > 0) q += " +$f free"
            val name = if (co.str("print_caps") == "1") l.str("item_name").uppercase() else l.str("item_name")
            row(listOf("${i + 1}", Fmt.cut(name, if (fs > 1) 52 else 56), l.str("hsn"), q,
                if (l.num("mrp") > 0) Fmt.qty(l.num("mrp")) else "", Fmt.amount(l.num("rate")),
                if (l.num("disc_pct") > 0) Fmt.qty(l.num("disc_pct")) else "", Fmt.amount(l.num("taxable")),
                Fmt.qty(l.num("gst_rate")), Fmt.amount(l.num("amount"))), ry, g.rowH, false)
            ry += g.rowH
        }
        // column lines to the bottom, a light rule under every item, the heading rule
        var cx = x
        for (k in 0 until ws.size - 1) { cx += ws[k]; pen.vLine(cx, y, y + h, 0.5f, Color.argb(140, 0, 0, 0)) }
        for (k in 1..rows.count()) { val yy = y + g.tableHead + k * g.rowH; pen.hLine(x, x + w, yy, 0.4f, Color.argb(56, 0, 0, 0)) }
        pen.hLine(x, x + w, y + g.tableHead)
    }

    private fun totals(pen: Pen, x: Float, y: Float, w: Float) {
        val rightW = 186 * g.cw
        val lx = x + 6; var ly = y + 4
        val rowH = 8.5f * fs
        if (on("print_gst_table")) {
            val heads = listOf("GST %", "Items", "Taxable", "CGST", "SGST", "IGST")
            var cx = lx
            for (hd in heads) { val cw = (if (hd == "Items") 32f else 50f) * g.cw; pen.text(hd, cx, ly, cw, rowH, 6.5f * fs, 700, 2); cx += cw }
            ly += rowH + 1
            pen.hLine(lx, cx, ly - 0.5f, 0.4f, MUTED)
            for (s in inv.list("gst_summary")) {
                cx = lx
                val vals = listOf(Fmt.qty(s.num("rate")), "${s.num("rows").toInt()}", Fmt.amount(s.num("taxable")), Fmt.amount(s.num("cgst")), Fmt.amount(s.num("sgst")), Fmt.amount(s.num("igst")))
                vals.forEachIndexed { i, v -> val cw = (if (i == 1) 32f else 50f) * g.cw; pen.text(v, cx, ly, cw, rowH, 6.5f * fs, align = 2); cx += cw }
                ly += rowH
            }
        }
        if (bankTab) {
            // the bank details as a small table: labels in one column, a tab, the values in the next, lined up under each other
            val lh = 7.6f * fs; val labW = 38f * g.cw
            var by = ly + (if (on("print_gst_table")) 3f else 0f)
            pen.text("BANK DETAILS", lx, by, 120f, lh, 6f * fs, 700, color = MUTED, minScale = 1f); by += lh
            for ((k, v) in bankTabRows(co)) {
                pen.text("$k:", lx, by, labW, lh, 6.5f * fs, 700, minScale = 0.7f)
                pen.text(v, lx + labW + 4f, by, w - rightW - 12 - labW - 4f, lh, 7f * fs, 600, minScale = 0.6f)
                by += lh
            }
        }
        val wordsTop = y + g.totals - 4 - 8f * fs - 18f * fs
        if (co.str("print_balance") == "1" && inv.has("party_prev_balance")) {
            val by = if (on("print_words")) wordsTop - 10f * fs else y + g.totals - 14f * fs
            pen.text("Previous balance ${balanceText(inv.num("party_prev_balance"))}   ·   This bill ${Fmt.money(inv.num("total") - inv.num("paid"))}   ·   Now due ${balanceText(inv.num("party_balance_after"))}",
                lx, maxOf(ly + 1, by), w - 186 * g.cw - 12, 9f * fs, 6.5f * fs, 600, minScale = 0.6f)
            ly = maxOf(ly + 1, by) + 9f * fs
        }
        if (on("print_words")) {
            val wy = maxOf(ly + 2, wordsTop)
            pen.text("Amount in words", lx, wy, w - rightW - 12, 8f * fs, 6 * fs, 700, color = MUTED)
            pen.para(inv.str("amount_words"), lx, wy + 8f * fs, w - rightW - 12, 7.5f * fs, 2, 600)
        }
        val rx = x + w - rightW
        var ry = y + 4
        val sh = 9f * fs
        fun sum(a: String, v: Double) { pen.text(a, rx + 6, ry, rightW - 12, sh, 7 * fs, color = MUTED); pen.text(Fmt.amount(v), rx + 6, ry, rightW - 12, sh, 7.5f * fs, align = 2); ry += sh }
        sum("Items total", inv.num("subtotal"))
        if (inv.num("discount") > 0) sum("Less discount", -inv.num("discount"))
        if (!compactPrint(co) || inv.num("discount") > 0 || abs(inv.num("taxable") - inv.num("subtotal")) > 0.005) sum("Taxable value", inv.num("taxable"))
        if (inv.num("cgst") > 0) { sum("CGST", inv.num("cgst")); sum("SGST", inv.num("sgst")) }
        if (inv.num("igst") > 0) sum("IGST", inv.num("igst"))
        if (abs(inv.num("round_off")) > 0) sum("Round off", inv.num("round_off"))
        if (inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005) sum("Paid", inv.num("paid"))
        val gh = 19f * fs
        val gy = y + g.totals - gh
        pen.hLine(rx, x + w, gy)
        pen.shade(RectF(rx, gy, x + w, y + g.totals))
        pen.text(if (inv.str("doc_title") == "DEBIT NOTE") "NOTE TOTAL" else "GRAND TOTAL", rx + 6, gy, rightW / 2, gh, 8.5f * fs, 700)
        pen.text("₹ " + Fmt.amount(inv.num("total")), rx + rightW / 2, gy, rightW / 2 - 6, gh, 11 * fs, 700, 2)
        // the line between "Amount in words" and the totals, down beside GRAND TOTAL: drawn last so the shading can't cover it
        pen.vLine(rx, y, y + g.totals, FRAME)
    }

    private fun footer(pen: Pen, x: Float, y: Float, w: Float) {
        val top = y + 3
        val bankL = if (bankTab) emptyList() else bankLines(co)
        val sigW = if (bankL.isEmpty()) w / 3 else 130 * g.cw
        val leftW = if (bankL.isEmpty()) w / 3 * 1.3f else (w - sigW) * 0.42f
        val pay = co.str("print_bank")
        var ty = top
        if (on("print_terms") && co.str("invoice_terms").isNotEmpty()) {
            pen.text("Terms", x + 2, ty, leftW, 7f * fs, 6 * fs, 700, color = MUTED)
            ty += 7f * fs + pen.para(co.str("invoice_terms"), x + 2, ty + 7f * fs, leftW, 6.5f * fs, if (pay.isEmpty()) 2 else 1)
        }
        if (pay.isNotEmpty()) { pen.text(pay, x + 2, ty, leftW, 8f * fs, 6.5f * fs, 600, minScale = 0.7f); ty += 8f * fs }
        if (bankL.isEmpty()) {
            val third = w / 3
            var my = top
            if (co.str("print_note").isNotEmpty()) { pen.text(co.str("print_note"), x + third, my, third, 9f * fs, 7f * fs, 700, align = 1, minScale = 0.7f); my += 9f * fs }
            if (pages > 1) pen.text("Page ${page + 1} of $pages", x + third, my, third, 8f * fs, 6.5f * fs, align = 1, color = MUTED)
        } else {
            if (co.str("print_note").isNotEmpty() && ty + 8f * fs <= y + g.foot) pen.text(co.str("print_note"), x + 2, ty, leftW, 8f * fs, 6.5f * fs, 700, minScale = 0.7f)
            // the bank details, three short lines in the middle of the footer: no room is taken from the items
            val bx = x + leftW + 8; val bw = w - sigW - leftW - 14
            var by = top
            val lh = 7.4f * fs
            for (l in bankL) { bankLine(pen, l, bx, by, bw, lh, 6.3f * fs); by += lh }
            if (pages > 1) pen.text("Page ${page + 1} of $pages", bx, by, bw, 7f * fs, 6 * fs, color = MUTED)
        }
        if (on("print_signature")) {
            pen.text(hc("For $companyName"), x + w - sigW, top, sigW - 2, 9f * fs, 7 * fs, 700, 2, minScale = 0.7f)
            pen.text("Authorised Signatory", x + w - sigW, y + g.foot - 9f * fs, sigW - 2, 8f * fs, 6.5f * fs, align = 2, color = MUTED)
        }
    }
}

/** A bill as PDF in the chosen layout (A4 two-up falls back to half sheets when the bill is longer than one page). */
/** [topOfA4]: for printing, a half-sheet copy goes at the TOP of its own A4 page (lower half blank): original on one page, duplicate on the next. */
fun invoicePdf(inv: J, co: J, layout: PrintLayout, into: PdfBuilder = PdfBuilder(), topOfA4: Boolean = false): PdfBuilder {
    val n = inv.list("lines").size
    val base = (if (layout.isFullPage) Spec.full else Spec.half).scaled(printScale(co))
    val marg = printStyle(co) != "classic"   // Marg, Busy and Bizom are drawn by MargSheet
    val g = if (marg) margSpec(base, inv, co) else base.withBank(co, inv)
    // one copy of one page, in the company's bill design (Settings › Printing › Bill design)
    fun sheet(pen: Pen, r: IntRange, i: Int, n2: Int, label: String, oy: Float = 0f) {
        val c = if (co.str("print_copy_label") == "0") "" else label   // Settings › Printing › ORIGINAL / DUPLICATE on each copy
        if (marg) MargSheet(inv, co, r, i, n2, c, g).draw(pen, 0f, oy) else InvoiceSheet(inv, co, r, i, n2, c, g).draw(pen, 0f, oy)
    }
    val labels = copyLabelsFor(co)
    if (layout == PrintLayout.A4TwoUp && paginate(n, g).size == 1) {
        into.page(g.w, g.h * 2) { pen ->
            sheet(pen, 0 until n, 0, 1, labels[0])
            sheet(pen, 0 until n, 0, 1, labels[1], g.h)
            pen.dashed(0f, g.w, g.h + 0.5f)
        }
        return into
    }
    val copies = if (layout == PrintLayout.Single || layout == PrintLayout.A4FullOriginal) listOf(labels[0]) else labels
    val ranges = paginate(n, g)
    val pageH = if (topOfA4 && !layout.isFullPage) g.h * 2 else g.h
    for (c in copies) ranges.forEachIndexed { i, r -> into.page(g.w, pageH) { pen -> sheet(pen, r, i, ranges.size, c) } }
    return into
}

/** A debit note on the bill layouts, headed DEBIT NOTE, its rows in pieces like a sale bill. */
fun debitNotePdf(d: J, co: J, layout: PrintLayout): PdfBuilder {
    val raw = org.json.JSONObject(d.o.toString())
    raw.put("lines", d.o.optJSONArray("print_lines") ?: org.json.JSONArray())
    return invoicePdf(J(raw), co, layout, topOfA4 = true)
}

/** A receipt or payment voucher: one copy per A4 page, each at the top of the page. */
fun voucherPdf(v: J): PdfBuilder {
    val b = PdfBuilder()
    val g = Spec.half
    val co = v.obj("company"); val party = v.obj("party")
    val received = v.str("direction") == "RECEIVED"
    for (copy in copyLabels) b.page(g.w, g.h * 2) { pen ->
        val x = g.m; val w = g.w - 2 * g.m; var y = g.m
        val top = y
        val cw = pen.width(copy, 7f, 700) + 8
        pen.text(co.str("name"), x + 8, y + 6, w - cw - 24, 16f, 13f, 700)
        pen.box(RectF(x + w - 8 - cw, y + 6, x + w - 8, y + 18), 0.6f)
        pen.text(copy, x + w - 8 - cw, y + 6, cw, 12f, 7f, 700, 1, minScale = 1f)
        var yy = y + 22
        yy += pen.para(co.str("address"), x + 8, yy, w - cw - 24, 7f, 2)
        val idLine = (if (co.str("gstin").isEmpty()) "" else "GSTIN: ${co.str("gstin")}   ") + (if (co.str("phone").isEmpty()) "" else "Ph: ${co.str("phone")}")
        if (idLine.isNotBlank()) { pen.text(idLine, x + 8, yy, w - 16, 9f, 7f); yy += 9f }
        yy += 4
        pen.shade(RectF(x, yy, x + w, yy + 20), Color.argb(64, 128, 128, 128))
        pen.text(v.str("title").uppercase(), x, yy, w, 20f, 11f, 700, 1)
        yy += 28
        pen.text("Voucher No: ${v.str("no")}", x + 10, yy, w / 2, 12f, 9f, 700)
        pen.text("Date: ${Fmt.dmy(v.str("date"))}", x + w / 2, yy, w / 2 - 10, 12f, 9f, 700, 2)
        yy += 17
        fun line(a: String, b2: String) {
            pen.text("$a:", x + 10, yy, 90f, 12f, 9f, 700, minScale = 1f)
            val hgt = pen.para(b2, x + 100, yy + 1, w - 110, 9f, 2)
            yy += maxOf(12f, hgt) + 5
        }
        line(if (received) "Received from" else "Paid to", party.str("name"))
        if (party.str("address").isNotEmpty()) line("Address", party.str("address"))
        if (party.str("gstin").isNotEmpty()) line("GSTIN", party.str("gstin"))
        line("Payment mode", v.str("mode") + if (v.str("reference").isEmpty()) "" else "   Ref: ${v.str("reference")}")
        line("Amount", "₹ " + Fmt.amount(v.num("amount")))
        line("In words", v.str("amount_words"))
        line("Balance after", balanceText(v.num("balance")))
        val bottom = g.h - g.m
        pen.text("Receiver's signature", x + 10, bottom - 18, w / 2, 10f, 7f)
        pen.text("Authorised signatory", x + w / 2, bottom - 18, w / 2 - 10, 10f, 7f, align = 2)
        pen.box(RectF(x, top, x + w, bottom))
    }
    return b
}
