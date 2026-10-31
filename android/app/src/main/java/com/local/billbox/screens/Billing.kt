package com.local.billbox.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.NoteAdd
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.local.billbox.data.Api
import com.local.billbox.data.ApiError
import com.local.billbox.data.AppState
import com.local.billbox.data.BillMath
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.data.Page
import com.local.billbox.print.Printing
import com.local.billbox.system.WhatsApp
import com.local.billbox.ui.Banner
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Choice
import com.local.billbox.ui.Col
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DateField
import com.local.billbox.ui.EditCell
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoLine
import com.local.billbox.ui.IntCell
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Pick
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SearchPicker
import com.local.billbox.ui.Warn
import com.local.billbox.ui.panel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

private val lineIds = AtomicLong(1)

/** One line of the bill being typed. */
data class BillLine(val itemId: Int, val name: String, val ppb: Int, val stock: Double, val boxes: Int = 0, val pcs: Int = 1,
                    val disc: String = "", val rate: String = "", val id: Long = lineIds.getAndIncrement()) {
    val totalPcs: Int get() = BillMath.totalPcs(boxes, ppb, pcs)

    companion object {
        /** A new line starts as ONE BOX when the item is packed in boxes (Settings › Billing can make it one piece). */
        fun fresh(item: J, disc: String, unit: String): BillLine {
            val ppb = maxOf(1, item.int("pcs_per_box"))
            val box = ppb > 1 && unit != "piece"
            return BillLine(item.id, item.str("name"), ppb, item.num("stock"), boxes = if (box) 1 else 0, pcs = if (box) 0 else 1,
                disc = if ((disc.toDoubleOrNull() ?: 0.0) > 0) disc else "")
        }
    }
}

/** The bill being made; kept while you visit other screens (as on the iPhone). */
class BillingState(app: AppState) {
    val lines = mutableStateListOf<BillLine>()
    var partyId by mutableIntStateOf(0)
    var salesmanId by mutableIntStateOf(0)
    var saleType by mutableStateOf(app.defaultSaleType)
    var payMode by mutableStateOf(app.defaultPayMode)
    var billDate by mutableStateOf(app.dateInFY)
    var paid by mutableStateOf("")
    var editingId by mutableStateOf<Int?>(null)
    var editingNo by mutableStateOf("")
    var query by mutableStateOf("")
    var preview by mutableStateOf<J?>(null)
    var previewKey by mutableStateOf("")
    var errorText by mutableStateOf<String?>(null)
    /** The line whose Box (or Pcs) gets the cursor next: the one just added. */
    var focusLine by mutableStateOf<Long?>(null)

    val recalcKey: String get() = "$partyId|$billDate|$saleType|$payMode|$paid|" + lines.joinToString(",") { "${it.itemId}:${it.boxes}:${it.pcs}:${it.disc}:${it.rate}" }

    fun clear(app: AppState) {
        lines.clear(); preview = null; errorText = null; partyId = 0; paid = ""
        payMode = app.defaultPayMode; saleType = app.defaultSaleType; billDate = app.dateInFY
        editingId = null; editingNo = ""; query = ""
    }

    /** A bill is on credit unless money is entered. A walk-in customer has no account, so they always pay at the counter. */
    val effectiveMode: String get() {
        val amount = paid.trim().toDoubleOrNull() ?: 0.0
        return if (payMode == "CREDIT" && (partyId == 0 || amount > 0)) "CASH" else payMode
    }

    fun payload(override: Boolean = false): Map<String, Any?> {
        val d = mutableMapOf<String, Any?>("date" to billDate, "sale_type" to saleType, "pay_mode" to effectiveMode,
            "lines" to lines.map { l ->
                val m = mutableMapOf<String, Any?>("item_id" to l.itemId, "boxes" to l.boxes, "pcs" to l.pcs, "disc_pct" to (l.disc.toDoubleOrNull() ?: 0.0))
                l.rate.trim().toDoubleOrNull()?.let { if (it >= 0 && l.rate.isNotEmpty()) m["rate"] = it }
                m
            })
        if (partyId != 0) d["party_id"] = partyId
        if (salesmanId != 0) d["salesman_id"] = salesmanId
        paid.trim().toDoubleOrNull()?.let { d["paid_amount"] = it }
        if (override) d["override_credit"] = true
        return d
    }
}

private data class LineCalc(val rate: Double, val free: Double, val amount: Double, val schemes: List<String>)
private data class Totals(val subtotal: Double, val discount: Double, val taxable: Double, val gst: Double, val roundOff: Double, val total: Double, val lines: List<LineCalc>)

@Composable
fun BillingScreen() {
    val app = LocalApp.current
    val st = remember { app.keep("billing") { BillingState(app) } }
    val scope = rememberCoroutineScope()
    var parties by remember { mutableStateOf(listOf<J>()) }
    var salesmen by remember { mutableStateOf(listOf<J>()) }
    var routes by remember { mutableStateOf(listOf<J>()) }
    var items by remember { mutableStateOf(listOf<J>()) }
    var index by remember { mutableStateOf(listOf<Pair<String, J>>()) }
    var calculating by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var detailsOpen by remember { mutableStateOf(false) }
    var creditAlert by remember { mutableStateOf<String?>(null) }
    var askPrint by remember { mutableStateOf<J?>(null) }
    var newParty by remember { mutableStateOf(false) }
    var highlight by remember { mutableIntStateOf(0) }
    val searchFocus = remember { FocusRequester() }
    var calcGen by remember { mutableIntStateOf(0) }
    val wide = LocalConfiguration.current.screenWidthDp >= 720

    val party = parties.firstOrNull { it.id == st.partyId }.takeIf { st.partyId != 0 }

    // amounts worked out on the phone at once, with the engine's rules (the engine's answer replaces them when it knows schemes)
    val catalog = remember(items) { items.associateBy { it.id } }
    val myState = app.setting("state_code")
    val tier = party?.str("price_tier")?.ifEmpty { "RETAIL" } ?: "RETAIL"
    val intra = party == null || party.str("state_code").isEmpty() || party.str("state_code") == myState
    val local = BillMath.compute(st.lines.map { l ->
        val it = catalog[l.itemId]
        BillMath.LineInput(l.boxes, l.pcs, l.ppb, BillMath.listRate(it, tier), l.rate.trim().toDoubleOrNull()?.takeIf { v -> v >= 0 }, l.disc.toDoubleOrNull() ?: 0.0, it?.num("gst_rate") ?: 0.0)
    }, intra, app.setting("bill_round") != "0")
    val key = st.recalcKey
    val totals: Totals? = if (st.lines.isEmpty()) null else run {
        val p = st.preview
        if (p != null && st.previewKey == key) {
            val ls = p.list("lines").map { LineCalc(it.num("rate"), it.num("free_qty"), it.num("amount"), it.strings("schemes")) }
            if (ls.size == st.lines.size && ls.any { it.free > 0 || it.schemes.isNotEmpty() })
                return@run Totals(p.num("subtotal"), p.num("discount"), p.num("taxable"), p.num("cgst") + p.num("sgst") + p.num("igst"), p.num("round_off"), p.num("total"), ls)
        }
        Totals(local.subtotal, local.discount, local.taxable, local.gst, local.roundOff, local.total, local.lines.map { LineCalc(it.rate, 0.0, it.amount, emptyList()) })
    }
    val ready = st.preview != null && st.previewKey == key

    // same matching and order as the Mac: in stock first, then where the first word appears, then by name
    val suggestions = remember(st.query, index) {
        val q = st.query.trim().lowercase()
        val words = q.split(' ').filter { it.isNotEmpty() }
        if (words.isEmpty()) emptyList() else index.mapNotNull { (name, i) ->
            if (words.all { name.contains(it) } || i.str("barcode").lowercase() == q || i.str("hsn").startsWith(q)) Triple(maxOf(0, name.indexOf(words[0])), i.str("name"), i) else null
        }.sortedWith(compareBy({ if (it.third.num("stock") > 0) 0 else 1 }, { it.first }, { it.second })).take(8).map { it.third }
    }

    suspend fun reload() {
        app.guarded {
            parties = Api.list("/parties", mapOf("kind" to "CUSTOMER"))
            salesmen = Api.list("/salesmen")
            routes = Api.list("/routes")
            items = Api.list("/items", mapOf("all" to "1"))
            index = items.map { it.str("name").lowercase() to it }
        }
    }

    suspend fun recalc() {
        if (st.lines.isEmpty()) { st.preview = null; st.errorText = null; calculating = false; return }
        val mine = ++calcGen
        val k = st.recalcKey
        calculating = true
        try {
            val r = Api.obj("POST", "/invoices/preview", body = st.payload())
            if (mine != calcGen) return
            st.preview = r; st.previewKey = k; st.errorText = null
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) {
            if (mine != calcGen) return
            st.preview = null; st.previewKey = ""; st.errorText = e.message
        }
        calculating = false
    }

    suspend fun loadForEdit(id: Int) {
        app.guarded {
            val inv = Api.get("/invoices/$id")
            st.lines.clear()
            st.lines.addAll(inv.list("edit_lines").map { l ->
                val ppb = maxOf(1, l.int("pcs_per_box")); val q = l.num("qty").toInt()
                val md = l.num("manual_disc")
                BillLine(l.int("item_id"), l.str("item_name"), ppb, items.firstOrNull { it.id == l.int("item_id") }?.num("stock") ?: 0.0,
                    boxes = if (ppb > 1) q / ppb else 0, pcs = if (ppb > 1) q % ppb else q,
                    rate = if (l.has("rate")) Fmt.qty(l.num("rate")) else "", disc = if (md == 0.0) "" else Fmt.qty(md))
            })
            st.editingId = id; st.editingNo = inv.str("invoice_no")
            st.partyId = inv.optInt("party_id") ?: 0
            st.salesmanId = inv.optInt("salesman_id") ?: 0
            st.saleType = inv.str("sale_type").ifEmpty { "COUNTER" }
            st.payMode = inv.str("pay_mode").ifEmpty { "CASH" }
            st.paid = String.format(java.util.Locale.US, "%.2f", inv.num("paid"))
            st.billDate = inv.str("date").take(10).ifEmpty { app.dateInFY }
        }
    }

    fun add(item: J) {
        val i = st.lines.indexOfFirst { it.itemId == item.id }
        if (i >= 0) { val l = st.lines[i]; st.lines[i] = if (l.ppb > 1) l.copy(boxes = l.boxes + 1) else l.copy(pcs = l.pcs + 1) }
        else st.lines.add(BillLine.fresh(item, app.setting("bill_default_disc"), app.setting("bill_new_unit")))
        st.query = ""; highlight = 0
        // the cursor goes to the line's Box (Pcs for loose items); the keyboard's Next / Done goes on from there
        st.focusLine = st.lines.firstOrNull { it.itemId == item.id }?.id
    }

    fun submitSearch() {
        if (suggestions.isNotEmpty()) { add(suggestions[minOf(highlight, suggestions.size - 1)]); return }
        val q = st.query.trim(); if (q.isEmpty()) return
        st.query = ""
        app.launch {
            val r = Api.list("/items", mapOf("q" to q))
            if (r.size == 1) add(r[0]) else app.notify("No item matches \"$q\"", true)
        }
    }

    suspend fun save(override: Boolean = false) {
        if (busy || st.lines.isEmpty()) return
        busy = true
        try {
            recalc()
            if (st.preview == null || st.previewKey != st.recalcKey) return
            val wasEdit = st.editingId
            val ov = override || app.setting("bill_credit_check") == "0"
            val r = if (wasEdit != null) Api.obj("PUT", "/invoices/$wasEdit", body = st.payload(ov)) else Api.obj("POST", "/invoices", body = st.payload(ov))
            app.notify("${if (wasEdit != null) "Updated" else "Saved"} ${r.str("invoice_no")} · ${Fmt.money(r, "total")}")
            val kept = st.partyId
            st.clear(app)
            if (app.setting("bill_keep_party") == "1" && wasEdit == null) st.partyId = kept
            detailsOpen = false
            reload()
            WhatsApp.sendIfEnabled(r.int("id"), app)
            when (app.setting("bill_after_save")) {
                "later" -> app.notify("${r.str("invoice_no")} kept to print later (All Bills › Not printed).")
                "ask" -> askPrint = r
                else -> Printing.invoice(r.int("id"), app)
            }
        } catch (e: ApiError) {
            if (e.code == "CREDIT_LIMIT" && !override) creditAlert = e.message else app.notify(e.message, true)
        } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) {
            app.notify(e.message ?: "Could not save", true)
        } finally { busy = false }
    }

    LaunchedEffect(Unit) {
        reload()
        app.pendingEdit?.let { if (it.type == "INVOICE") { app.pendingEdit = null; loadForEdit(it.id) } }
    }
    LaunchedEffect(app.itemsVersion) { if (app.itemsVersion > 0) reload() }
    LaunchedEffect(key) { delay(200); recalc() }

    ScreenScaffold(if (st.editingId != null) "Editing ${st.editingNo}" else "Billing", actions = {
        IconButton(onClick = { runCatching { searchFocus.requestFocus() } }) { Icon(Icons.Default.Search, "Find item") }
        IconButton(onClick = { st.clear(app) }) { Icon(if (st.editingId != null) Icons.Default.Cancel else Icons.Default.NoteAdd, if (st.editingId != null) "Cancel edit" else "New bill") }
    }) { mod ->
        Column(mod) {
            Column(Modifier.weight(1f).padding(horizontal = 12.dp).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (st.editingId != null) Banner("Editing ${st.editingNo}. Saving replaces the old bill; stock and ledger are corrected automatically.", Icons.Default.Edit)
                OutlinedTextField(st.query, { st.query = it; highlight = 0 }, Modifier.fillMaxWidth().focusRequester(searchFocus),
                    placeholder = { Text("Type an item name or scan a barcode") }, singleLine = true, leadingIcon = { Icon(Icons.Default.Search, null) },
                    trailingIcon = { if (st.query.isNotEmpty()) IconButton({ st.query = "" }) { Icon(Icons.Default.Close, "Clear search") } },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { submitSearch() }),
                    shape = RoundedCornerShape(12.dp))
                Box(Modifier.weight(1f).fillMaxWidth()) {
                    if (st.lines.isEmpty()) EmptyState("Start a bill", "Search an item above and press Enter.", Icons.Default.ShoppingCart)
                    else BillTable(st, totals)
                    if (suggestions.isNotEmpty()) Surface(Modifier.fillMaxWidth().zIndex(2f), shape = RoundedCornerShape(12.dp), shadowElevation = 8.dp, tonalElevation = 3.dp) {
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                            suggestions.forEachIndexed { i, it ->
                                Row(Modifier.fillMaxWidth().background(if (i == highlight) MaterialTheme.colorScheme.primaryContainer else Color.Transparent)
                                    .clickable { add(it) }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(it.str("name"), maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Hint("Stock ${Fmt.boxPcs(it.int("stock"), maxOf(1, it.int("pcs_per_box")))}  ·  MRP ${Fmt.money(it, "mrp")}  ·  GST ${Fmt.qty(it.num("gst_rate"))}%")
                                    }
                                    if (it.num("stock") <= 0) Text("Out of stock", color = Bad, style = MaterialTheme.typography.labelSmall)
                                }
                            }
                        }
                    }
                }
                st.errorText?.let { Banner(it, Icons.Default.Warning, Bad) }
            }
            // party, payment, the working and the total with Save
            val customer: @Composable () -> Unit = {
                CustomerCard(st, parties, salesmen, items, party, onNewParty = { newParty = true })
            }
            val working: @Composable () -> Unit = {
                Column(Modifier.fillMaxWidth().panel(10.dp).padding(12.dp)) {
                    InfoLine("Items", totals?.let { Fmt.money(it.subtotal) } ?: "–")
                    InfoLine("Discount", totals?.let { "- " + Fmt.money(it.discount) } ?: "–")
                    InfoLine("Taxable", totals?.let { Fmt.money(it.taxable) } ?: "–")
                    InfoLine("GST", totals?.let { Fmt.money(it.gst) } ?: "–")
                    InfoLine("Round off", totals?.let { Fmt.money(it.roundOff) } ?: "–")
                }
            }
            val saveButton: @Composable () -> Unit = {
                Button(onClick = { scope.launch { save() } }, enabled = !busy && st.lines.isNotEmpty() && (ready || st.errorText == null)) {
                    Icon(Icons.Default.Print, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                    Text(if (st.editingId != null) "Update" else "Save & print", maxLines = 1)
                }
            }
            val pcs = st.lines.sumOf { it.totalPcs }
            Surface(color = MaterialTheme.colorScheme.surfaceContainer, tonalElevation = 2.dp) {
                if (wide) Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.weight(1f)) { customer() }
                    Box(Modifier.width(230.dp)) { working() }
                    Column(Modifier.width(250.dp).panel(10.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row { Text(if (st.editingId != null) "EDITING ${st.editingNo}" else "BILL TOTAL", style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f)); if (calculating) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp) }
                        Text(totals?.let { Fmt.money(it.total) } ?: "₹0.00", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, maxLines = 1)
                        Hint("${st.lines.size} item${if (st.lines.size == 1) "" else "s"} · $pcs pcs")
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { saveButton(); OutlinedButton({ st.clear(app) }) { Text(if (st.editingId != null) "Cancel" else "New") } }
                    }
                } else Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    AnimatedVisibility(detailsOpen) {
                        Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) { customer(); working() }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.weight(1f).clickable { detailsOpen = !detailsOpen }, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(party?.str("name") ?: "Walk-in cash customer", style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Hint("${payModeTitle(st.effectiveMode)} · ${st.lines.size} item${if (st.lines.size == 1) "" else "s"} · $pcs pcs")
                            }
                            Icon(if (detailsOpen) Icons.Default.ExpandMore else Icons.Default.ExpandLess, if (detailsOpen) "Hide party, payment and totals" else "Show party, payment and totals")
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            if (calculating) CircularProgressIndicator(Modifier.size(10.dp), strokeWidth = 1.5.dp)
                            Text(totals?.let { Fmt.money(it.total) } ?: "₹0.00", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, maxLines = 1)
                        }
                        saveButton()
                    }
                }
            }
        }
    }

    if (newParty) PartyForm(null, "RETAILER", routes, salesmen, onDismiss = { newParty = false }) {
        val before = parties.map { it.id }.toSet()
        reload()
        parties.filter { it.id !in before }.maxByOrNull { it.id }?.let { st.partyId = it.id }
    }
    askPrint?.let { r ->
        AlertDialog(onDismissRequest = { askPrint = null }, title = { Text("Print ${r.str("invoice_no")} now?") },
            confirmButton = { TextButton({ askPrint = null; app.launch { Printing.invoice(r.int("id"), app) } }) { Text("Print now") } },
            dismissButton = { TextButton({ askPrint = null }) { Text("Later (All Bills › Not printed)") } })
    }
    creditAlert?.let { msg ->
        AlertDialog(onDismissRequest = { creditAlert = null }, title = { Text("Credit limit exceeded") }, text = { Text(msg) },
            confirmButton = { TextButton({ creditAlert = null; scope.launch { save(override = true) } }) { Text("Bill anyway") } },
            dismissButton = { TextButton({ creditAlert = null }) { Text("Cancel") } })
    }
}

private fun payModeTitle(m: String) = mapOf("CASH" to "Cash", "UPI" to "UPI", "CARD" to "Card", "CREDIT" to "Credit")[m] ?: m

@Composable
private fun BillTable(st: BillingState, totals: Totals?) {
    val calc = st.lines.mapIndexed { i, l -> l.id to totals?.lines?.getOrNull(i) }.toMap()
    fun upd(l: BillLine, f: (BillLine) -> BillLine) { val i = st.lines.indexOfFirst { it.id == l.id }; if (i >= 0) st.lines[i] = f(st.lines[i]) }
    // a phone shows the item (with its amount under the name), boxes and pieces; the rest is a swipe to the right
    val phone = LocalConfiguration.current.screenWidthDp < 600
    val cols =
        listOf(
            Col<BillLine>("Item", "item", if (phone) 150 else 200) { l ->
                Column {
                    Text(l.name, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                    if (phone) calc[l.id]?.let { Text(Fmt.money(it.amount), fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
                    val schemes = calc[l.id]?.schemes ?: emptyList()
                    Hint((listOfNotNull(if (l.ppb > 1) "${l.ppb} pcs / box" else null, "Stock ${Fmt.boxPcs(l.stock.toInt(), l.ppb)}") + schemes).joinToString("  ·  "))
                }
            },
            Col("Box", "box", if (phone) 60 else 66) { l -> if (l.ppb > 1) IntCell(l.boxes, { v -> upd(l) { it.copy(boxes = v) } }, focusNow = st.focusLine == l.id, onFocused = { st.focusLine = null }) else Cell("–") },
            Col("Pcs", "pcs", if (phone) 64 else 70) { l -> IntCell(l.pcs, { v -> upd(l) { it.copy(pcs = v) } }, focusNow = st.focusLine == l.id && l.ppb <= 1, onFocused = { st.focusLine = null }) },
            Col("Total pcs", "total", 70, end = true) { l -> Cell("${l.totalPcs}", MaterialTheme.colorScheme.onSurfaceVariant, end = true) },
            Col("Disc %", "disc", 66) { l -> EditCell(l.disc, { v -> upd(l) { it.copy(disc = v) } }, placeholder = "0") },
            Col("Rate / pc (ex-GST)", "rate", 112, end = true) { l ->
                EditCell(l.rate, { v -> upd(l) { it.copy(rate = v) } }, placeholder = calc[l.id]?.let { Fmt.rate(it.rate) } ?: "rate",
                    color = if (l.rate.isEmpty()) Color.Unspecified else Warn)
            },
            Col("Rate / box", "boxrate", 104, end = true) { l ->
                if (l.ppb > 1) {
                    val shown = l.rate.toDoubleOrNull() ?: (calc[l.id]?.rate ?: 0.0)
                    val text = if (l.rate.isEmpty()) "" else Fmt.qty(Math.round((l.rate.toDoubleOrNull() ?: 0.0) * l.ppb * 100) / 100.0)
                    EditCell(text, { v ->
                        val d = v.trim().toDoubleOrNull()
                        upd(l) { it.copy(rate = if (d != null && d >= 0) String.format(java.util.Locale.US, "%.8f", d / l.ppb) else "") }
                    }, placeholder = Fmt.amount(shown * l.ppb), color = if (l.rate.isEmpty()) Color.Unspecified else Warn)
                } else Cell("–")
            },
            Col("Free", "free", 90) { l -> val f = calc[l.id]?.free ?: 0.0; Cell(if (f > 0) "+${Fmt.qty(f)} pcs free" else "", Good, bold = true) },
            Col("Amount", "amount", 104, end = true) { l -> Cell(calc[l.id]?.let { Fmt.money(it.amount) } ?: "", bold = true, end = true) },
            Col("", "remove", 44) { l -> IconButton({ st.lines.removeAll { it.id == l.id } }, Modifier.size(32.dp)) { Icon(Icons.Default.Cancel, "Remove ${l.name}", tint = MaterialTheme.colorScheme.onSurfaceVariant) } },
        )
    // every row stays alive while typing: the number pad never closes when the bill gets longer than the screen
    DataTable(st.lines.toList(), "billing", rowHeight = 48, lazy = false, keyOf = { it.id }, columns = cols,
        phone = listOf("item", "box", "pcs", "remove", "amount", "disc", "rate", "boxrate", "free", "total"))
}


@Composable
private fun CustomerCard(st: BillingState, parties: List<J>, salesmen: List<J>, items: List<J>, party: J?, onNewParty: () -> Unit) {
    Column(Modifier.fillMaxWidth().panel(10.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            SearchPicker("Party", listOf(Pick(0, "Walk-in cash customer")) + parties.map { Pick(it.id, it.str("name"), it.str("route_name")) },
                st.partyId, { st.partyId = it }, Modifier.weight(1f), placeholder = "Walk-in cash customer")
            IconButton(onClick = onNewParty) { Icon(Icons.Default.PersonAdd, "Create a new party without leaving the bill") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            DateField("Date", st.billDate, { st.billDate = it }, Modifier.weight(1f))
            Choice("Salesman", listOf(0 to "No salesman (counter)") + salesmen.map { it.id to it.str("name") }, st.salesmanId, { st.salesmanId = it }, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Choice("Sale type", listOf("COUNTER" to "Counter", "VAN" to "Van sale"), st.saleType, { st.saleType = it }, Modifier.weight(1f))
            Choice("Payment", listOf("CASH" to "Cash", "UPI" to "UPI", "CARD" to "Card", "CREDIT" to "Credit"), st.payMode, { st.payMode = it }, Modifier.weight(1f))
        }
        com.local.billbox.ui.Field("Paid now", st.paid, { st.paid = it }, kb = com.local.billbox.ui.Kb.Decimal,
            placeholder = if (st.partyId == 0 && st.payMode == "CREDIT") "Walk-in: paid in full" else if (st.payMode == "CREDIT") "Blank = on credit" else "Blank = paid in full")
        tierNote(party, st, items)?.let { Text(it, color = Warn, style = MaterialTheme.typography.bodySmall) }
        val limit = party?.num("credit_limit") ?: 0.0
        val over = party != null && limit > 0 && party.num("balance") > limit
        Text(if (party == null) "Walk-in customer · retail price · paid in full"
            else "Dues ${Fmt.money(party, "balance")}${if (limit > 0) " of ${Fmt.money(limit)} limit" else ""} · ${party.str("price_tier").lowercase().replaceFirstChar { it.uppercase() }} price",
            style = MaterialTheme.typography.bodySmall, color = if (over) Bad else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A wholesale customer, but items on the bill have no wholesale price of their own (Marg backups carry one sale rate), so they bill at retail. */
private fun tierNote(party: J?, st: BillingState, items: List<J>): String? {
    if (party == null || party.str("price_tier") != "WHOLESALE") return null
    val ids = st.lines.map { it.itemId }.toSet()
    val same = items.filter { it.id in ids && (it.num("wholesale_price") <= 0 || abs(it.num("wholesale_price") - it.num("retail_price")) < 0.000001) }
    if (same.isEmpty()) return null
    val n = same.size
    return "$n item${if (n == 1) " has" else "s have"} no separate wholesale price, so ${if (n == 1) "it is" else "they are"} billed at the retail price. Set wholesale prices in Stock › More › Set prices from MRP."
}
