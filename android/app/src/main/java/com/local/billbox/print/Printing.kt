package com.local.billbox.print

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.local.billbox.data.Api
import com.local.billbox.data.AppState
import com.local.billbox.data.PrintJob
import com.local.billbox.system.Platform
import com.local.billbox.ui.Hint
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Printing on this phone (kept on the device, like the iPhone's printer setting). */
object PrintPrefs {
    private fun p() = Platform.context.getSharedPreferences("billbox_print", Context.MODE_PRIVATE)
    /** Open Android's print screen at once instead of BillBox's preview. */
    var direct: Boolean
        get() = runCatching { p().getBoolean("direct", false) }.getOrDefault(false)
        set(v) { p().edit().putBoolean("direct", v).apply() }
}

object Printing {
    private fun safe(s: String) = s.replace("/", "-")

    private fun show(app: AppState, title: String, file: String, b: PdfBuilder, invoiceIds: List<Int> = emptyList(), forcePreview: Boolean = false) {
        val f = Platform.cacheFile(file, b.bytes())
        val job = PrintJob(title, file, f, invoiceIds)
        if (PrintPrefs.direct && !forcePreview) send(job, app) else app.printJob = job
    }

    /** Sends the PDF to Android's print service; bills in it count as printed. */
    fun send(job: PrintJob, app: AppState) {
        Platform.print(job.pdf, job.title)
        markPrinted(job.invoiceIds, app)
    }

    /** Remembers which bills have been printed (All Bills › Not printed lists the rest). */
    fun markPrinted(ids: List<Int>, app: AppState) {
        if (ids.isEmpty()) return
        app.scope.launch { runCatching { Api.obj("POST", "/invoices/printed", body = mapOf("ids" to ids)) } }
    }

    suspend fun invoice(id: Int, app: AppState, forcePreview: Boolean = false) = app.guarded {
        val inv = Api.get("/invoices/$id")
        val b = withContext(Dispatchers.Default) { invoicePdf(inv, app.settings, PrintLayout.parse(app.setting("print_layout"))) }
        show(app, "Invoice ${inv.str("invoice_no")}", "${safe(inv.str("invoice_no"))}.pdf", b, listOf(id), forcePreview)
    }

    /** Several bills in one job, in the order given, each with its copies (the bills kept to print later). */
    suspend fun invoices(ids: List<Int>, app: AppState) {
        if (ids.isEmpty()) return
        if (ids.size == 1) { invoice(ids[0], app, true); return }
        app.guarded {
            val layout = PrintLayout.parse(app.setting("print_layout"))
            val b = PdfBuilder(); val nos = mutableListOf<String>()
            for (id in ids) { val inv = Api.get("/invoices/$id"); withContext(Dispatchers.Default) { invoicePdf(inv, app.settings, layout, b) }; nos.add(inv.str("invoice_no")) }
            if (b.pageCount == 0) throw Exception("Could not prepare the bills for printing")
            show(app, "${nos.size} bills (${nos.first()} … ${nos.last()})", "Bills-${nos.size}.pdf", b, ids, true)
        }
    }

    suspend fun debitNote(id: Int, app: AppState) = app.guarded {
        val d = Api.get("/debit-notes/$id")
        val b = withContext(Dispatchers.Default) { debitNotePdf(d, app.settings, PrintLayout.parse(app.setting("print_layout"))) }
        show(app, "Debit note ${d.str("note_no")}", "${safe(d.str("note_no"))}.pdf", b)
    }

    suspend fun voucher(no: String, app: AppState) = app.guarded {
        val v = Api.get("/vouchers/${Api.seg(no)}")
        show(app, "Receipt $no", "${safe(no)}.pdf", withContext(Dispatchers.Default) { voucherPdf(v) })
    }

    /** A bill's PDF bytes for sending (one copy). */
    suspend fun invoiceBytes(inv: com.local.billbox.data.J, app: AppState): ByteArray {
        val layout = PrintLayout.parse(app.setting("print_layout"))
        val single = if (layout.isFullPage) PrintLayout.A4FullOriginal else PrintLayout.Single
        return withContext(Dispatchers.Default) { invoicePdf(inv, app.settings, single).bytes() }
    }
}

/** Pages of a PDF as pictures (for the preview). */
private suspend fun renderPages(f: File, widthPx: Int): List<Bitmap> = withContext(Dispatchers.IO) {
    val out = mutableListOf<Bitmap>()
    ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
        PdfRenderer(fd).use { r ->
            for (i in 0 until minOf(r.pageCount, 60)) {
                r.openPage(i).use { pg ->
                    val k = widthPx.toFloat() / pg.width
                    val bmp = Bitmap.createBitmap(widthPx, (pg.height * k).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(android.graphics.Color.WHITE)
                    pg.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    out.add(bmp)
                }
            }
        }
    }
    out
}

/** BillBox's print preview: the pages, Print (Android print service), Share and Save PDF. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrintPreviewDialog(job: PrintJob, onDismiss: () -> Unit) {
    val app = LocalApp.current
    var pages by remember(job.stamp) { mutableStateOf<List<Bitmap>?>(null) }
    LaunchedEffect(job.stamp) { pages = runCatching { renderPages(job.pdf, 1400) }.getOrDefault(emptyList()) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Scaffold(topBar = {
            TopAppBar(title = { Text(job.title, maxLines = 1) },
                navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Close") } },
                actions = {
                    IconButton(onClick = { app.launch { if (Platform.saveFile(job.fileName, "application/pdf", job.pdf.readBytes())) app.notify("Saved ${job.fileName}") } }) { Icon(Icons.Default.Download, "Save PDF") }
                    IconButton(onClick = { Platform.share(job.pdf, "application/pdf", title = job.title) }) { Icon(Icons.Default.Share, "Share PDF") }
                    IconButton(onClick = { Printing.send(job, app); onDismiss() }) { Icon(Icons.Default.Print, "Print") }
                })
        }) { pad ->
            val ps = pages
            if (ps == null) Box(Modifier.padding(pad)) { Loading() }
            else LazyColumn(Modifier.fillMaxSize().padding(pad).background(MaterialTheme.colorScheme.surfaceContainerHigh), verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp)) {
                item { Hint("${ps.size} page${if (ps.size == 1) "" else "s"} · tap the printer to print (or Save as PDF from Android's print screen)") }
                items(ps) { bmp -> Image(bmp.asImageBitmap(), null, Modifier.fillMaxWidth().background(Color.White), contentScale = ContentScale.FillWidth) }
            }
        }
    }
}
