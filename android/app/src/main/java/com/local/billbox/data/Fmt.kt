package com.local.billbox.data

import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/** Money, quantities and dates as the Mac and iPhone show them (Indian grouping, ₹, dd-MM-yyyy). */
object Fmt {
    private val inLocale = Locale("en", "IN")
    private val money = NumberFormat.getCurrencyInstance(inLocale).apply { maximumFractionDigits = 2; minimumFractionDigits = 2; currency = java.util.Currency.getInstance("INR") }
    private val plain = NumberFormat.getNumberInstance(inLocale).apply { maximumFractionDigits = 2; minimumFractionDigits = 2 }

    fun money(v: Double): String = money.format(v).replace("Rs.", "₹").replace("INR", "₹")
    fun money(j: J, k: String) = money(j.num(k))
    fun amount(v: Double): String = plain.format(v)

    /** 12 → "12", 12.5 → "12.5" (no grouping), for numbers typed back into fields. */
    fun plainNumber(v: Double): String = if (v == v.roundToLong().toDouble() && abs(v) < 1e15) v.roundToLong().toString() else v.toBigDecimal().stripTrailingZeros().toPlainString()
    fun qty(v: Double) = plainNumber(v)

    /** A per-piece rate with up to 4 decimals, never fewer than 2. */
    fun rate(v: Double): String {
        var s = String.format(Locale.US, "%.4f", v)
        while (s.endsWith("0") && s.length - s.indexOf('.') > 3) s = s.dropLast(1)
        return s
    }

    fun boxPcs(q: Int, perBox: Int): String {
        if (perBox <= 1) return "$q pcs"
        val b = q / perBox; val p = q % perBox
        return when {
            b == 0 -> "$p pcs"
            p == 0 -> "$b box"
            else -> "$b box $p pcs"
        }
    }

    val today: String get() = LocalDate.now().toString()
    fun monthStart(): String = today.take(7) + "-01"

    /** "2026-09-30" (or with time) → "30-09-2026" (time kept). */
    fun dmy(iso: String): String {
        if (iso.length < 10) return iso
        val d = "${iso.substring(8, 10)}-${iso.substring(5, 7)}-${iso.substring(0, 4)}"
        return if (iso.length > 10) d + iso.substring(10).replace("T", " ").take(6) else d
    }

    fun monthName(ym: String): String {
        val names = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
        val m = ym.takeLast(2).toIntOrNull() ?: 1
        return names[(m - 1).coerceIn(0, 11)]
    }

    /** Backup / system timestamps (UTC ISO from the engine) as Indian date and time: 27-10-2026, 04:43 PM. */
    fun ist(s: String): String = try {
        java.time.Instant.parse(s).atZone(java.time.ZoneId.of("Asia/Kolkata")).format(DateTimeFormatter.ofPattern("dd-MM-yyyy, hh:mm a", Locale.US))
    } catch (_: Exception) { dmy(s) }

    fun cut(s: String, n: Int) = if (s.length <= n) s else s.take(n - 2) + ".."

    /** "(1X144)", "(1X240 PKT)", "1X300" in an item name → pieces in one box. */
    fun packFromName(name: String): Int? {
        val pats = listOf("\\(\\s*(?:\\d+\\s*[xX*]\\s*)?(\\d{1,5})\\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\\s*\\)", "\\b\\d+\\s*[xX]\\s*(\\d{2,5})\\b")
        for (p in pats) {
            val m = Regex(p, RegexOption.IGNORE_CASE).find(name) ?: continue
            val n = m.groupValues[1].toIntOrNull() ?: continue
            if (n >= 1) return n
        }
        return null
    }

    fun parseIso(s: String): LocalDate? = runCatching { LocalDate.parse(s.take(10)) }.getOrNull()
    fun longDate(iso: String): String = parseIso(iso)?.format(DateTimeFormatter.ofPattern("d MMM yyyy", inLocale)) ?: iso
}
