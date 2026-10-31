package com.local.billbox.screens

import android.util.Base64
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Calculate
import androidx.compose.material.icons.filled.ClearAll
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.MoveToInbox
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Subject
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.ApiError
import com.local.billbox.data.AppState
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.system.Platform
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Banner
import com.local.billbox.ui.Choice
import com.local.billbox.ui.DateField
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Pick
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SearchPicker
import com.local.billbox.ui.Segments
import com.local.billbox.ui.Warn
import com.local.billbox.ui.panel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlin.math.roundToInt

private val pIds = AtomicLong(1)

/** One row of a purchase bill. */
class PLine {
    val key = pIds.getAndIncrement()
    var itemId by mutableIntStateOf(0)
    var desc by mutableStateOf("")
    var hsn by mutableStateOf("")
    var qty by mutableStateOf("1")
    var unit by mutableStateOf("PCS")
    var rate by mutableStateOf("")
    var amount by mutableStateOf("")
    var amountManual by mutableStateOf(false)
    var matched by mutableStateOf(true)
    var created by mutableStateOf(false)
    val q get() = qty.trim().toDoubleOrNull() ?: 0.0
    val r get() = rate.trim().toDoubleOrNull() ?: 0.0
    fun autoAmount() { if (amountManual) return; val v = q * r; amount = if (v == 0.0) "" else String.format(java.util.Locale.US, "%.2f", v) }
}

/** The purchase bill being entered; kept while you visit other screens. */
class PurchaseState(app: AppState) {
    val lines = mutableStateListOf(PLine())
    var supplierId by mutableIntStateOf(0)
    var invoiceNo by mutableStateOf("")
    var date by mutableStateOf(app.dateInFY)
    var source by mutableStateOf("MANUAL")
    var paid by mutableStateOf("")
    var payMode by mutableStateOf("CASH")
    var disc by mutableStateOf("")
    var cgst by mutableStateOf("")
    var sgst by mutableStateOf("")
    var igst by mutableStateOf("")
    var roundOff by mutableStateOf("")
    var printedTotal by mutableStateOf<Double?>(null)
    var parsed by mutableStateOf<J?>(null)
    var warnings by mutableStateOf(listOf<String>())
    var pendingSupplier by mutableStateOf<J?>(null)
    var preview by mutableStateOf<J?>(null)
    var errorText by mutableStateOf<String?>(null)
    var editingId by mutableStateOf<Int?>(null)
    var editingNo by mutableStateOf("")

    val key: String get() = listOf(supplierId.toString(), invoiceNo, date, paid, payMode, disc, cgst, sgst, igst, roundOff, (printedTotal ?: -1.0).toString()).joinToString("|") + "#" +
        lines.joinToString(",") { "${it.itemId}:${it.hsn}:${it.qty}:${it.unit}:${it.rate}:${it.amount}" }

    fun payload(dup: Boolean = false): Map<String, Any?> {
        val d = mutableMapOf<String, Any?>("supplier_invoice_no" to invoiceNo.trim(), "date" to date, "source" to source, "pay_mode" to payMode,
            "discount" to disc, "cgst" to cgst, "sgst" to sgst, "igst" to igst, "round_off" to roundOff,
            "lines" to lines.map { mapOf("item_id" to (if (it.itemId == 0) null else it.itemId), "hsn" to it.hsn, "qty" to it.qty, "unit" to it.unit, "rate" to it.rate, "amount" to it.amount) })
        if (supplierId != 0) d["party_id"] = supplierId
        paid.trim().toDoubleOrNull()?.let { d["paid_amount"] = it }
        printedTotal?.let { d["printed_total"] = it }
        if (dup) d["allow_duplicate"] = true
        return d
    }

    fun reset(app: AppState) {
        invoiceNo = ""; paid = ""; disc = ""; cgst = ""; sgst = ""; igst = ""; roundOff = ""; supplierId = 0; date = app.dateInFY
        source = "MANUAL"; parsed = null; pendingSupplier = null; warnings = emptyList(); printedTotal = null; editingId = null; editingNo = ""
        lines.clear(); lines.add(PLine()); preview = null; errorText = null
    }
}

/** Only two units exist: BOX and PCS. Carton / case / dozen style units on a bill count as boxes. */
private fun normUnit(u: String) = if (Regex("^(BOX|CTN|CASE|CARTON|DOZ|DZN|BX)", RegexOption.IGNORE_CASE).containsMatchIn(u)) "BOX" else "PCS"

/**
 * Purchase bill entry. "Scan PDF bill" fills everything in: supplier, items (created with HSN, GST rate, MRP and pieces
 * per box), quantities, prices, discount, CGST/SGST, round off and the printed grand total.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PurchasesScreen() {
    val app = LocalApp.current
    val st = remember { app.keep("purchase") { PurchaseState(app) } }
    val scope = rememberCoroutineScope()
    var suppliers by remember { mutableStateOf(listOf<J>()) }
    var items by remember { mutableStateOf(listOf<J>()) }
    var scanning by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var showText by remember { mutableStateOf(false) }
    var newItemFor by remember { mutableStateOf<PLine?>(null) }
    var supplierSheet by remember { mutableStateOf(false) }
    var duplicate by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }
    var warningsOpen by remember { mutableStateOf(false) }

    suspend fun loadLists() { app.guarded { suppliers = Api.list("/parties", mapOf("kind" to "SUPPLIER")); items = Api.list("/items") } }
    val itemChoices = remember(items) { items.map { Pick(it.id, it.str("name"), it.str("hsn")) } }
    fun item(id: Int) = if (id == 0) null else items.firstOrNull { it.id == id }

    fun apply(r: J) {
        val sup = r.obj("supplier"); val t = r.obj("totals")
        fun num(k: String) = if (t.num(k) == 0.0) "" else t.str(k)
        val ls = r.list("lines").map { x ->
            PLine().apply {
                itemId = x.optInt("item_id") ?: 0; desc = x.str("description"); unit = normUnit(x.str("unit")); matched = x.has("item_id"); created = x.bool("created")
                amountManual = true   // the printed amount is the truth for a scanned bill
                hsn = x.str("hsn"); val q = x.num("qty"); qty = if (q == Math.rint(q)) q.toLong().toString() else x.str("qty"); rate = x.str("rate"); amount = x.str("amount")
            }
        }
        st.source = "PDF"; st.parsed = r
        val w = r.strings("warnings").toMutableList()
        st.invoiceNo = r.str("invoice_no"); if (r.has("date")) st.date = r.str("date")
        st.supplierId = sup.optInt("matched_party_id") ?: 0
        st.pendingSupplier = if (st.supplierId == 0 && sup.has("name")) sup else null
        st.disc = num("discount"); st.cgst = num("cgst"); st.sgst = num("sgst"); st.igst = num("igst")
        st.roundOff = if (t.has("round_off")) t.str("round_off") else ""
        st.printedTotal = if (t.has("grand_total")) t.num("grand_total") else null
        st.lines.clear(); st.lines.addAll(ls.ifEmpty { listOf(PLine()) })
        val skipped = r.obj("pages").list("skipped")
        if (skipped.isNotEmpty()) w.add(0, "Skipped page(s) " + skipped.joinToString(", ") { "${it.str("page")} (${it.str("kind")})" } + ".")
        st.warnings = w
    }

    suspend fun scanPdf() {
        val (_, bytes) = Platform.openFile("application/pdf") ?: return
        if (bytes.isEmpty()) { app.notify("That file could not be opened.", true); return }
        scanning = true
        try {
            app.guarded {
                // create_missing: the supplier and every new item (HSN, GST rate, pieces per box, MRP, category) are added automatically
                val r = Api.obj("POST", "/purchases/parse-pdf", body = mapOf("pdf_base64" to Base64.encodeToString(bytes, Base64.NO_WRAP), "create_missing" to true))
                loadLists(); apply(r)
                val c = r.obj("created")
                app.notify("Bill read: ${r.list("lines").size} items" + (if (c.int("items") > 0) ", ${c.int("items")} new items added to Stock" else "") + if (c.bool("supplier")) ", supplier added." else ".")
            }
        } finally { scanning = false }
    }

    suspend fun takeEdit() {
        val e = app.pendingEdit ?: return
        if (e.type != "PURCHASE") return
        app.pendingEdit = null
        app.guarded {
            val b = Api.get("/purchases/${e.id}")
            st.lines.clear()
            st.lines.addAll(b.list("lines").map { x -> PLine().apply { itemId = x.int("item_id"); unit = normUnit(x.str("unit")); amountManual = true; hsn = x.str("hsn"); qty = x.num("qty").toInt().toString(); rate = x.str("rate"); amount = x.str("amount") } }.ifEmpty { listOf(PLine()) })
            st.editingId = e.id; st.editingNo = b.str("purchase_no"); st.supplierId = b.int("party_id"); st.invoiceNo = b.str("supplier_invoice_no")
            st.date = b.str("date").take(10); st.payMode = b.str("pay_mode").ifEmpty { "CASH" }; st.paid = String.format(java.util.Locale.US, "%.2f", b.num("paid"))
            fun n(k: String) = if (b.num(k) == 0.0) "" else b.str(k)
            st.disc = n("discount"); st.cgst = n("cgst"); st.sgst = n("sgst"); st.igst = n("igst"); st.roundOff = b.str("round_off")
            st.source = b.str("source").ifEmpty { "MANUAL" }; st.parsed = null; st.warnings = emptyList(); st.printedTotal = null
        }
    }

    suspend fun save(dup: Boolean = false) {
        if (busy) return
        busy = true
        try {
            val was = st.editingId
            val r = if (was != null) Api.obj("PUT", "/purchases/$was", body = st.payload(dup)) else Api.obj("POST", "/purchases", body = st.payload(dup))
            app.notify("${if (was != null) "Updated" else "Saved"} ${r.str("purchase_no")} · ${Fmt.money(r, "total")}. Stock and ledger are up to date.")
            st.reset(app); loadLists()
        } catch (e: ApiError) { if (e.code == "DUPLICATE" && !dup) duplicate = e.message else app.notify(e.message, true) }
        catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { app.notify(e.message ?: "", true) }
        finally { busy = false }
    }

    LaunchedEffect(Unit) { loadLists(); takeEdit() }
    LaunchedEffect(st.key) {
        delay(250)
        try { st.preview = Api.obj("POST", "/purchases/preview", body = st.payload()); st.errorText = null }
        catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { st.preview = null; st.errorText = e.message }
    }

    ScreenScaffold(if (st.editingId != null) "Edit purchase ${st.editingNo}" else "Purchase bill", actions = {
        IconButton(onClick = { st.lines.add(PLine()) }) { Icon(Icons.Default.Add, "Add row") }
        if (st.editingId == null) IconButton(onClick = { scope.launch { scanPdf() } }, enabled = !scanning) { Icon(Icons.Default.DocumentScanner, "Scan PDF bill") }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "More") }
            DropdownMenu(menu, { menu = false }) {
                if (st.parsed != null) DropdownMenuItem(text = { Text("View PDF text") }, leadingIcon = { Icon(Icons.Default.Subject, null) }, onClick = { menu = false; showText = true })
                DropdownMenuItem(text = { Text(if (st.editingId != null) "Cancel edit" else "Clear", color = MaterialTheme.colorScheme.error) }, leadingIcon = { Icon(Icons.Default.ClearAll, null) }, onClick = { menu = false; st.reset(app) })
            }
        }
    }) { mod ->
        Box(mod) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (st.editingId != null) Banner("Editing a saved bill. Updating reverses the old stock and ledger entries and writes the corrected bill under the same number.", Icons.Default.Edit)
                if (st.source == "PDF" && st.parsed != null) {
                    val used = maxOf(1, st.parsed!!.obj("pages").o.optJSONArray("used")?.length() ?: 1)
                    Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Filled in from the PDF ($used Original page${if (used == 1) "" else "s"} read). Check every field against the paper bill before saving.", fontWeight = FontWeight.SemiBold, color = Warn, modifier = Modifier.weight(1f))
                            if (st.warnings.isNotEmpty()) IconButton(onClick = { warningsOpen = !warningsOpen }) { Icon(if (warningsOpen) Icons.Default.ExpandLess else Icons.Default.ExpandMore, "Warnings") }
                        }
                        if (warningsOpen) st.warnings.forEach { Text("• $it", color = Bad, style = MaterialTheme.typography.bodySmall) }
                    }
                }
                SearchPicker("Supplier", suppliers.map { Pick(it.id, it.str("name"), it.str("gstin")) }, st.supplierId, { st.supplierId = it }, placeholder = "Select supplier…")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Field("Supplier invoice no.", st.invoiceNo, { st.invoiceNo = it.uppercase() }, Modifier.weight(1f), kb = Kb.Caps)
                    DateField("Bill date", st.date, { st.date = it }, Modifier.weight(1f))
                }
                st.pendingSupplier?.let { ps -> OutlinedButton(onClick = { supplierSheet = true }) { Text("Create supplier “${ps.str("name")}”") } }

                st.lines.forEachIndexed { idx, l ->
                    androidx.compose.runtime.key(l.key) {
                        Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${idx + 1}", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(24.dp))
                                SearchPicker("Item", itemChoices, l.itemId, { picked ->
                                    l.itemId = picked
                                    val it = item(picked) ?: return@SearchPicker
                                    l.matched = true
                                    if (l.hsn.isEmpty()) l.hsn = it.str("hsn")
                                    if (l.rate.isEmpty() && it.num("purchase_price") > 0) l.rate = it.str("purchase_price")
                                    l.autoAmount()
                                }, Modifier.weight(1f), placeholder = "Select item…")
                                IconButton(onClick = { if (st.lines.size > 1) st.lines.remove(l) }, enabled = st.lines.size > 1) { Icon(Icons.Default.RemoveCircle, "Remove row", tint = if (st.lines.size > 1) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.outlineVariant) }
                            }
                            if (!l.matched && l.desc.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("“${l.desc}” is not in your stock list.", color = Bad, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
                                TextButton(onClick = { newItemFor = l }) { Text("Create this item") }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Field("HSN", l.hsn, { l.hsn = it }, Modifier.weight(1f), kb = Kb.Number)
                                Field("Qty", l.qty, { l.qty = it; l.autoAmount() }, Modifier.weight(0.7f), kb = Kb.Number)
                                Segments(listOf("BOX" to "Box", "PCS" to "Pcs"), l.unit, { l.unit = it }, Modifier.weight(1.1f))
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Field("Price (per unit)", l.rate, { l.rate = it; l.autoAmount() }, Modifier.weight(1f), kb = Kb.Decimal, placeholder = "0.00")
                                Field("Amount", l.amount, { l.amount = it; l.amountManual = true }, Modifier.weight(1f), kb = Kb.Decimal, placeholder = "0.00")
                            }
                            val parts = mutableListOf<String>()
                            if (l.created) parts.add("New item added")
                            if (l.desc.isNotEmpty()) parts.add("On the bill: ${l.desc}")
                            item(l.itemId)?.let { it ->
                                val perBox = it.int("pcs_per_box")
                                val isBox = Regex("^(BOX|CTN|CASE|CARTON|DOZ|DZN)", RegexOption.IGNORE_CASE).containsMatchIn(l.unit)
                                if (isBox && perBox > 1 && l.q > 0) parts.add("${l.qty} box × $perBox = ${(l.q * perBox).roundToInt()} pcs go into stock")
                                else if (perBox > 1) parts.add("1 box = $perBox pcs  ·  ${Fmt.boxPcs(l.q.roundToInt(), perBox)} in stock terms")
                            }
                            if (parts.isNotEmpty()) Text(parts.joinToString("   ·   "), style = MaterialTheme.typography.bodySmall, color = if (l.created) Color(0xFF00897B) else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                OutlinedButton(onClick = { st.lines.add(PLine()) }) { Icon(Icons.Default.Add, null); Text(" Add row") }

                // totals
                val p = st.preview
                val inter = p?.str("supply") == "INTER"
                val mismatch = p != null && abs(p.num("mismatch")) > 0
                Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Field("Discount", st.disc, { st.disc = it }, Modifier.widthIn(max = 150.dp), kb = Kb.Decimal, placeholder = p?.str("discount") ?: "")
                        if (!inter) {
                            Field("CGST", st.cgst, { st.cgst = it }, Modifier.widthIn(max = 150.dp), kb = Kb.Decimal, placeholder = p?.str("cgst") ?: "")
                            Field("SGST", st.sgst, { st.sgst = it }, Modifier.widthIn(max = 150.dp), kb = Kb.Decimal, placeholder = p?.str("sgst") ?: "")
                        } else Field("IGST", st.igst, { st.igst = it }, Modifier.widthIn(max = 150.dp), kb = Kb.Decimal, placeholder = p?.str("igst") ?: "")
                        Field("Rounded off", st.roundOff, { st.roundOff = it }, Modifier.widthIn(max = 150.dp), kb = Kb.Signed, placeholder = p?.str("round_off") ?: "")
                    }
                    TextButton(onClick = { st.cgst = ""; st.sgst = ""; st.igst = "" }) { Icon(Icons.Default.Calculate, null); Text("  Auto tax (from each item's GST rate)") }
                    if (p != null) Hint("Items ${Fmt.money(p, "subtotal")}  ·  Taxable ${Fmt.money(p, "taxable")}")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Field("Paid now", st.paid, { st.paid = it }, Modifier.weight(1f), kb = Kb.Decimal)
                        Choice("Mode", listOf("CASH", "UPI", "BANK", "CHEQUE").map { it to it }, st.payMode, { st.payMode = it }, Modifier.weight(1f))
                    }
                    st.printedTotal?.let { Text("Printed on bill: ${Fmt.money(it)}", color = if (mismatch) Bad else MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = if (mismatch) FontWeight.SemiBold else null) }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(p?.let { Fmt.money(it, "total") } ?: "", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = Color(0xFF00897B), modifier = Modifier.weight(1f))
                        Button(onClick = { scope.launch { save() } }, enabled = !busy && p != null) {
                            Icon(Icons.Default.MoveToInbox, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                            Text(if (st.editingId != null) "Update bill" else "Save and add to stock")
                        }
                    }
                    ErrorText(st.errorText)
                }
            }
            if (scanning) Surface(Modifier.align(Alignment.Center), shape = MaterialTheme.shapes.large, tonalElevation = 6.dp, shadowElevation = 8.dp) {
                Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(22.dp)); Text("  Reading the bill and adding items…") }
            }
        }
    }

    if (showText) InfoDialog("Text read from the PDF", { showText = false }) {
        SelectionContainer { Text(st.parsed?.str("raw_text") ?: "", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
    }
    if (supplierSheet) SupplierFromBill(st.pendingSupplier ?: J(), { supplierSheet = false }) { id -> st.supplierId = id; st.pendingSupplier = null; loadLists() }
    newItemFor?.let { l -> NewItemFromBill(l, { newItemFor = null }) { id -> l.itemId = id; l.matched = true; loadLists() } }
    duplicate?.let { m ->
        AlertDialog(onDismissRequest = { duplicate = null }, title = { Text("Possible duplicate") }, text = { Text("$m\n\nSave it again anyway?") },
            confirmButton = { TextButton({ duplicate = null; scope.launch { save(dup = true) } }) { Text("Save anyway") } },
            dismissButton = { TextButton({ duplicate = null }) { Text("Cancel") } })
    }
}

@Composable
private fun SupplierFromBill(supplier: J, onDismiss: () -> Unit, done: suspend (Int) -> Unit) {
    val app = LocalApp.current
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    fun v(k: String, d: String = ""): String = f.value[k] ?: (if (supplier.o.optJSONArray(k) != null) supplier.strings(k).joinToString(", ") else if (supplier.has(k)) supplier.str(k) else d)
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    FormDialog("Create supplier from the bill", onDismiss, onSave = {
        val body = mutableMapOf<String, Any?>("type" to "SUPPLIER", "price_tier" to "WHOLESALE")
        for (k in listOf("name", "address", "gstin", "state_code", "tel", "phone", "mobiles", "fssai", "pan", "email")) body[k] = v(k, if (k == "state_code") "09" else "")
        val r = Api.obj("POST", "/parties", body = body)
        app.notify("Supplier added.")
        done(r.int("id"))
    }) {
        Field("Supplier name", v("name"), { set("name", it) })
        Field("Address", v("address"), { set("address", it) }, singleLine = false, minLines = 2)
        Field("GSTIN", v("gstin"), { set("gstin", it.uppercase()) }, kb = Kb.Caps)
        Field("State code", v("state_code", "09"), { set("state_code", it) }, kb = Kb.Number)
        Field("Tel", v("tel"), { set("tel", it) }, kb = Kb.Phone)
        Field("Phone", v("phone"), { set("phone", it) }, kb = Kb.Phone)
        Field("Mobile numbers (comma separated)", v("mobiles"), { set("mobiles", it) }, kb = Kb.Phone)
        Field("FSSAI number", v("fssai"), { set("fssai", it) }, kb = Kb.Number)
        Field("PAN number", v("pan"), { set("pan", it.uppercase()) }, kb = Kb.Caps)
        Field("Email", v("email"), { set("email", it) }, kb = Kb.Email)
    }
}

@Composable
private fun NewItemFromBill(line: PLine, onDismiss: () -> Unit, done: suspend (Int) -> Unit) {
    val pack = (Fmt.packFromName(line.desc) ?: 1).toString()
    val cost = run { val r = line.rate.toDoubleOrNull() ?: 0.0; val n = (Fmt.packFromName(line.desc) ?: 1).toDouble(); if (line.unit == "BOX" && n > 1) String.format(java.util.Locale.US, "%.4f", r / n) else line.rate }
    val defaults = mapOf("name" to line.desc, "hsn" to line.hsn, "gst_rate" to "18", "pcs_per_box" to pack, "purchase_price" to cost)
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    fun v(k: String) = f.value[k] ?: defaults[k] ?: ""
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    FormDialog("Create item from the bill", onDismiss, onSave = {
        val body = listOf("name", "hsn", "gst_rate", "pcs_per_box", "purchase_price", "mrp", "retail_price", "wholesale_price").associateWith { v(it) }
        val r = Api.obj("POST", "/items", body = body)
        done(r.int("id"))
    }) {
        Field("Item name", v("name"), { set("name", it) })
        Field("HSN code", v("hsn"), { set("hsn", it) }, kb = Kb.Number)
        Field("GST rate %", v("gst_rate"), { set("gst_rate", it) }, kb = Kb.Decimal)
        Field("Pieces in one box", v("pcs_per_box"), { set("pcs_per_box", it) }, kb = Kb.Number)
        Field("Purchase price per piece (ex-GST)", v("purchase_price"), { set("purchase_price", it) }, kb = Kb.Decimal)
        Field("MRP per piece (incl. GST)", v("mrp"), { set("mrp", it) }, kb = Kb.Decimal)
        Field("Retail price (ex-GST)", v("retail_price"), { set("retail_price", it) }, kb = Kb.Decimal)
        Field("Wholesale price (ex-GST)", v("wholesale_price"), { set("wholesale_price", it) }, kb = Kb.Decimal)
    }
}
