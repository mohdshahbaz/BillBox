package com.local.billbox.system

import android.content.ClipData
import android.content.Context
import android.content.Intent
import com.local.billbox.data.Api
import com.local.billbox.data.AppState
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.print.PdfBuilder
import com.local.billbox.print.Printing

/**
 * Sends the customer's copy of a bill on WhatsApp: WhatsApp opens on the customer's chat with the bill attached, ready to
 * send (Android lets an app hand a file to a chat; the final Send tap is WhatsApp's).
 */
object WhatsApp {
    const val defaultMessage = "Hello {name}, thank you for your purchase. Your bill {invoice} for {total} is attached. - {company}"

    /** Which WhatsApp to use on this phone: "com.whatsapp" or "com.whatsapp.w4b" (Business). */
    var appPackage: String
        get() = runCatching { Platform.context.getSharedPreferences("billbox_wa", Context.MODE_PRIVATE).getString("pkg", "") ?: "" }.getOrDefault("")
        set(v) { Platform.context.getSharedPreferences("billbox_wa", Context.MODE_PRIVATE).edit().putString("pkg", v).apply() }

    fun installed(pkg: String): Boolean = runCatching { Platform.context.packageManager.getPackageInfo(pkg, 0); true }.getOrDefault(false)

    private fun pkg(): String? {
        val chosen = appPackage
        if (chosen.isNotEmpty() && installed(chosen)) return chosen
        return listOf("com.whatsapp", "com.whatsapp.w4b").firstOrNull { installed(it) }
    }

    /** Digits only, with the country code. "98765 43210", "+91 98765-43210" and "098765 43210" all become 919876543210. */
    fun number(raw: String, countryCode: String): String? {
        var d = raw.filter { it.isDigit() }
        if (d.startsWith("00")) d = d.drop(2)
        if (d.startsWith("0") && d.length == 11) d = d.drop(1)
        if (d.length == 10) d = countryCode + d
        return if (d.length in 11..15) d else null
    }

    fun partyNumber(inv: J, cc: String): String? =
        (listOf(inv.str("party_phone")) + inv.str("party_mobiles").split(',', ';', '/')).firstNotNullOfOrNull { number(it, cc) }

    /** After a bill is saved (Settings › WhatsApp › send after saving). */
    suspend fun sendIfEnabled(id: Int, app: AppState) { if (app.setting("wa_auto") == "1") send(id, app, quiet = true) }

    suspend fun send(id: Int, app: AppState, quiet: Boolean = false) {
        val inv = try { Api.get("/invoices/$id") } catch (e: Exception) { if (!quiet) app.notify(e.message ?: "", true); return }
        val who = inv.str("party_name").ifEmpty { "the customer" }
        val cc = app.setting("wa_cc").ifEmpty { "91" }
        val phone = partyNumber(inv, cc) ?: run { if (!quiet) app.notify("$who has no mobile number on file.", true); return }
        val text = app.setting("wa_message").ifEmpty { defaultMessage }
            .replace("{name}", inv.str("party_name")).replace("{invoice}", inv.str("invoice_no"))
            .replace("{total}", Fmt.money(inv.num("total"))).replace("{company}", app.companyName)
        val bytes = Printing.invoiceBytes(inv, app)
        open(phone, "${inv.str("invoice_no").replace("/", "-")}.pdf", bytes, text, app)
    }

    /** A one-page PDF to try the whole route without a real bill. */
    fun sendTest(raw: String, app: AppState) {
        val phone = number(raw, app.setting("wa_cc").ifEmpty { "91" }) ?: run { app.notify("Enter a mobile number to send the test to.", true); return }
        val b = PdfBuilder()
        b.page(420f, 200f) { pen -> pen.para("BillBox test\nIf you can read this on WhatsApp, sending bills works.", 20f, 20f, 380f, 16f, 4) }
        open(phone, "BillBox-test.pdf", b.bytes(), "BillBox test", app)
    }

    private fun open(phone: String, file: String, pdf: ByteArray, caption: String, app: AppState) {
        val p = pkg() ?: run { app.notify("WhatsApp is not installed on this phone.", true); return }
        val f = Platform.cacheFile(file, pdf)
        val uri = Platform.uriOf(f)
        val i = Intent(Intent.ACTION_SEND).setPackage(p).setType("application/pdf")
            .putExtra(Intent.EXTRA_STREAM, uri).putExtra(Intent.EXTRA_TEXT, caption)
            .putExtra("jid", "$phone@s.whatsapp.net")   // opens this customer's chat directly
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        i.clipData = ClipData.newRawUri(file, uri)
        try { Platform.context.startActivity(i); app.notify("WhatsApp is open on the chat: tap Send.") }
        catch (e: Exception) { app.notify("WhatsApp could not be opened: ${e.message}", true) }
    }
}
