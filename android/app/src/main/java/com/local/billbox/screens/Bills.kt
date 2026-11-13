package com.local.billbox.screens

import com.local.billbox.ui.StatusPill
import com.local.billbox.ui.SummaryCard
import com.local.billbox.ui.SummaryItem
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.AppState
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.data.Page
import com.local.billbox.data.PendingEdit
import com.local.billbox.print.Printing
import com.local.billbox.system.Platform
import com.local.billbox.system.WhatsApp
import com.local.billbox.ui.Bad
import com.local.billbox.ui.BulkOutcome
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Col
import com.local.billbox.ui.Confirm
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DateField
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.RowAction
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.SelectionBar
import com.local.billbox.ui.SwitchRow
import com.local.billbox.ui.Warn
import com.local.billbox.ui.bulkDelete
import com.local.billbox.ui.rememberDebouncer
import com.local.billbox.ui.Choice

fun billTypeName(r: J) = when (r.str("type")) { "SALE" -> "Sale"; "DEBIT_NOTE" -> "Debit note"; else -> "Purchase" }
fun billTypeColor(r: J) = when (r.str("type")) { "SALE" -> Color(0xFF00897B); "DEBIT_NOTE" -> Color(0xFF8E24AA); else -> Color(0xFFEF6C00) }
fun billPath(r: J) = when (r.str("type")) { "SALE" -> "/invoices"; "DEBIT_NOTE" -> "/debit-notes"; else -> "/purchases" }

/** Opens a bill, purchase or debit note for editing on its own screen. */
fun editBill(app: AppState, r: J) {
    val t = r.str("type")
    app.pendingEdit = PendingEdit(if (t == "SALE") "INVOICE" else if (t == "DEBIT_NOTE") "DEBIT_NOTE" else "PURCHASE", r.int("bill_id"))
    app.section = if (t == "SALE") Page.Billing else if (t == "DEBIT_NOTE") Page.DebitNotes else Page.Purchases
}

/** A row of small action buttons under a detail page (wraps on narrow phones). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActionRow(vararg actions: Triple<String, ImageVector, () -> Unit>, destructive: Set<String> = emptySet()) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        actions.forEach { (label, icon, run) ->
            OutlinedButton(onClick = run) {
                Icon(icon, null, Modifier.size(18.dp), tint = if (label in destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(6.dp))
                Text(label, color = if (label in destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BillsScreen() {
    val app = LocalApp.current
    var type by remember { mutableStateOf("ALL") }
    var from by remember { mutableStateOf(if (app.isCurrentFY) app.monthStartInFY else app.fyFrom) }
    var to by remember { mutableStateOf(if (app.isCurrentFY) app.dateInFY else app.fyTo) }
    var query by remember { mutableStateOf("") }
    var unpaid by remember { mutableStateOf(false) }
    var unprinted by remember { mutableStateOf(false) }
    var rows by remember { mutableStateOf(listOf<J>()) }
    var totals by remember { mutableStateOf(J()) }
    val selection = remember { mutableStateListOf<Int>() }
    var selecting by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<J?>(null) }
    var ewb by remember { mutableStateOf<J?>(null) }
    var deleting by remember { mutableStateOf<J?>(null) }
    var confirmBulk by remember { mutableStateOf(false) }
    val debounce = rememberDebouncer()

    suspend fun load() {
        app.guarded {
            val r = Api.get("/bills", mapOf("type" to type, "from" to from, "to" to to, "q" to query, "unpaid" to if (unpaid) 1 else 0, "unprinted" to if (unprinted) 1 else 0))
            // a sale, a purchase and a debit note can share an id, so rows get a unique table id
            rows = r.list("rows").map { x -> x.with("bill_id" to x.int("id"), "id" to when (x.str("type")) { "SALE" -> x.int("id"); "DEBIT_NOTE" -> 1_000_000_000 + x.int("id"); else -> -x.int("id") }) }
            totals = r.obj("totals")
        }
        loading = false
    }
    LaunchedEffect(Unit) {
        if (app.openUnprinted) { app.openUnprinted = false; from = app.fyFrom; to = app.dateInFY; unprinted = true }
    }
    LaunchedEffect(type, from, to, unpaid, unprinted) { load() }
    LaunchedEffect(app.dataVersion) { if (app.dataVersion > 0) load() }

    // sale bills to print: the selected ones, or with "Not printed" on and nothing selected, every bill listed; oldest first
    val printIds = run {
        val sales = rows.filter { it.str("type") == "SALE" }
        val picked = if (selection.isEmpty()) (if (unprinted) sales else emptyList()) else sales.filter { it.id in selection }
        picked.sortedWith(compareBy({ it.str("date") }, { it.int("bill_id") })).map { it.int("bill_id") }
    }

    ScreenScaffold("All Bills", actions = {
        TextButton(onClick = { app.launch { Printing.invoices(printIds, app) } }, enabled = printIds.isNotEmpty()) {
            Icon(Icons.Default.Print, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp))
            Text(if (printIds.isEmpty()) "Print" else "Print ${printIds.size}")
        }
    }) { mod ->
        Column(mod) {
            Column(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Segments(listOf("ALL" to "All", "SALE" to "Sales", "PURCHASE" to "Purchases", "DEBIT_NOTE" to "Debit notes"), type, { type = it })
                OutlinedTextField(query, { query = it; debounce.run { load() } }, Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("Search bill no or party") },
                    leadingIcon = { Icon(Icons.Default.Search, null) }, shape = RoundedCornerShape(28.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DateField("From", from, { from = it }, Modifier.weight(1f))
                    DateField("To", to, { to = it }, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(unpaid, { unpaid = !unpaid }, { Text("Unpaid only") })
                    FilterChip(unprinted, { unprinted = !unprinted }, { Text("Not printed") })
                }
            }
            SelectionBar(selection.size, rows.size, selecting, { selecting = it; if (!it) selection.clear() },
                { if (selection.size == rows.size) selection.clear() else { selection.clear(); selection.addAll(rows.map { it.id }) } },
                actionLabel = "Delete", busy = busy, extra = {
                    // the ticked sale bills, oldest first
                    val sales = rows.filter { it.id in selection && it.str("type") == "SALE" }.sortedWith(compareBy({ it.str("date") }, { it.int("bill_id") })).map { it.int("bill_id") }
                    IconButton(onClick = { app.launch { Printing.invoices(sales, app) } }, enabled = sales.isNotEmpty() && !busy) { Icon(Icons.Default.Print, "Print ${sales.size} bills") }
                    IconButton(onClick = { Printing.markPrinted(sales, app); app.notify("${sales.size} bills marked printed."); app.launch { kotlinx.coroutines.delay(400); load() } },
                        enabled = sales.isNotEmpty() && !busy) { Icon(Icons.Default.Verified, "Mark printed") }
                    if (sales.size == 1) IconButton(onClick = { app.launch { WhatsApp.send(sales[0], app) } }) { Icon(Icons.AutoMirrored.Filled.Send, "WhatsApp") }
                }) { confirmBulk = true }
            Box(Modifier.weight(1f)) {
                if (loading) Loading()
                else if (rows.isEmpty()) EmptyState("No bills match these filters", "", Icons.Default.FindInPage)
                else DataTable(rows, "bills", phone = listOf("party", "total", "due", "no", "date", "type"), selected = selection.toSet(), keyOf = { it.id }, selecting = selecting,
                    onToggle = { r -> if (r.id in selection) selection.remove(r.id) else selection.add(r.id) }, onOpen = { viewing = it },
                    menu = { r -> listOfNotNull(
                        RowAction("View", Icons.Default.ReceiptLong) { viewing = r },
                        RowAction("Edit…", Icons.Default.Edit) { editBill(app, r) },
                        if (r.str("type") == "SALE") RowAction("E-way bill…", Icons.Default.LocalShipping) { ewb = r } else null,
                        RowAction("Delete…", Icons.Default.Delete, true) { deleting = r },
                        if (selection.size > 1 && r.id in selection) RowAction("Delete ${selection.size} selected…", Icons.Default.Delete, true) { confirmBulk = true } else null,
                    ) },
                    columns = listOf(
                        Col("Date", "date", 96) { r -> Cell(Fmt.dmy(r.str("date"))) },
                        Col("Type", "type", 84) { r -> StatusPill(billTypeName(r), billTypeColor(r)) },
                        Col("Bill no", "no", 150) { r -> Cell(r.str("no")) },
                        Col("Supplier bill", "ref", 110) { r -> Cell(r.str("ref")) },
                        Col("Party", "party", 200) { r -> Cell(r.str("party"), lines = 2) },
                        Col("Total", "total", 110, end = true) { r -> Cell(Fmt.money(r, "total"), end = true) },
                        Col("Paid", "paid", 110, end = true) { r -> Cell(Fmt.money(r, "paid"), end = true) },
                        Col("Printed", "printed", 84) { r -> StatusPill(if (r.str("type") != "SALE") "" else if (r.int("printed") == 1) "Yes" else "Not yet", if (r.int("printed") == 1) MaterialTheme.colorScheme.onSurfaceVariant else Warn) },
                        Col("Due", "due", 110, end = true) { r -> val due = r.num("total") - r.num("paid"); Cell(Fmt.money(due), if (due > 0.5) Bad else Color.Unspecified, bold = true, end = true) },
                    ))
            }
            SummaryCard(listOfNotNull(
                SummaryItem("Bills", "${rows.size}"),
                SummaryItem("Sales", Fmt.money(totals, "sales")),
                SummaryItem("Purchases", Fmt.money(totals, "purchases")),
                if (totals.num("debit_notes") > 0) SummaryItem("Debit notes", Fmt.money(totals, "debit_notes")) else null,
                SummaryItem("Due", Fmt.money(totals, "due"), strong = true, tint = if (totals.num("due") > 0.5) Bad else null),
            ))
        }
    }

    viewing?.let { r ->
        if (r.str("type") == "DEBIT_NOTE") DebitNoteDetail(r.int("bill_id"), { viewing = null }, onEdit = { viewing = null; editBill(app, r) }, onDelete = { viewing = null; deleting = r })
        else BillDetail(r, { viewing = null }, onEdit = { viewing = null; editBill(app, r) }, onEway = { viewing = null; ewb = r }, onDelete = { viewing = null; deleting = r })
    }
    ewb?.let { r -> EwayBillForm(r.int("bill_id")) { ewb = null } }
    deleting?.let { r ->
        val sale = r.str("type") == "SALE"
        val what = if (sale) "bill" else if (r.str("type") == "DEBIT_NOTE") "debit note" else "purchase bill"
        Confirm("Delete $what ${r.str("no")}?",
            if (sale) "Its stock goes back on the shelf, and its ledger and receipt entries are removed. This cannot be undone."
            else if (r.str("type") == "DEBIT_NOTE") "The returned pieces go back into stock and its ledger entry is removed. This cannot be undone."
            else "The stock it brought in is taken out again and its ledger entries are removed. It is refused if some of that stock was already sold. This cannot be undone.",
            "Delete $what", {
                app.launch { Api.obj("DELETE", "${billPath(r)}/${r.int("bill_id")}"); app.notify("Deleted ${r.str("no")}."); selection.clear(); load() }
            }, { deleting = null }, destructive = true)
    }
    if (confirmBulk) Confirm("Delete ${selection.size} selected bill${if (selection.size == 1) "" else "s"}?",
        "A sale puts its stock back on the shelf and removes its ledger and receipt entries. A purchase takes its stock out again and is skipped if some of that stock was already sold. This cannot be undone.",
        "Delete ${selection.size}", {
            app.launch {
                busy = true
                bulkDelete(selection.toList(), { m, e -> app.notify(m, e) }) { id ->
                    val r = rows.firstOrNull { it.id == id } ?: return@bulkDelete BulkOutcome.Failed("#$id", "not found")
                    try { Api.obj("DELETE", "${billPath(r)}/${r.int("bill_id")}"); BulkOutcome.Deleted } catch (e: Exception) { BulkOutcome.Failed(r.str("no"), e.message ?: "") }
                }
                selection.clear(); selecting = false; busy = false; load()
            }
        }, { confirmBulk = false }, destructive = true)
}

@Composable
fun BillDetail(row: J, onDismiss: () -> Unit, onEdit: () -> Unit, onEway: () -> Unit, onDelete: () -> Unit) {
    val app = LocalApp.current
    val sale = row.str("type") == "SALE"
    var bill by remember { mutableStateOf<J?>(null) }
    LaunchedEffect(row.id) { app.guarded { bill = Api.get(if (sale) "/invoices/${row.int("bill_id")}" else "/purchases/${row.int("bill_id")}") } }
    val b = bill ?: J()
    InfoDialog("${if (sale) b.str("invoice_no") else b.str("purchase_no")} · ${b.str("party_name").ifEmpty { "Cash customer" }}", onDismiss, scroll = false) {
        Hint("${Fmt.dmy(b.str("date"))}${if (sale) "" else "   ·   Supplier bill ${b.str("supplier_invoice_no")}"}   ·   Total ${Fmt.money(b, "total")}   ·   Paid ${Fmt.money(b, "paid")}   ·   Due ${Fmt.money(b.num("total") - b.num("paid"))}")
        val acts = mutableListOf<Triple<String, ImageVector, () -> Unit>>()
        if (sale) {
            acts.add(Triple("WhatsApp", Icons.AutoMirrored.Filled.Send) { app.launch { WhatsApp.send(row.int("bill_id"), app) } })
            acts.add(Triple("Print", Icons.Default.Print) { onDismiss(); app.launch { Printing.invoice(row.int("bill_id"), app, forcePreview = true) } })
            acts.add(Triple("E-way bill", Icons.Default.LocalShipping) { onEway() })
        } else acts.add(Triple("Return goods", Icons.AutoMirrored.Filled.Undo) { onDismiss(); app.pendingEdit = PendingEdit("RETURN_PURCHASE", row.int("bill_id")); app.section = Page.DebitNotes })
        acts.add(Triple("Edit", Icons.Default.Edit) { onEdit() })
        acts.add(Triple("Delete", Icons.Default.Delete) { onDelete() })
        ActionRow(*acts.toTypedArray(), destructive = setOf("Delete"))
        Box(Modifier.weight(1f)) {
            if (bill == null) Loading() else DataTable(b.list("lines"), "billdetail", columns = listOf(
                Col("Item", "item", 220) { l -> Cell(l.str("item_name"), lines = 2) },
                Col("Qty (box + pcs)", "qty", 120, end = true) { l -> Cell(Fmt.boxPcs(if (l.has("pcs_qty")) l.int("pcs_qty") else l.int("qty"), l.int("pcs_per_box")), end = true) },   // purchase qty is in its unit; pcs_qty is pieces
                Col("Free pcs", "free", 60, end = true) { l -> Cell(l.str("free_qty"), end = true) },
                Col("Rate", "rate", 90, end = true) { l -> Cell(Fmt.money(l, "rate"), end = true) },
                Col("Taxable", "taxable", 100, end = true) { l -> Cell(Fmt.money(l, "taxable"), end = true) },
                Col("GST", "gst", 55, end = true) { l -> Cell("${l.str("gst_rate")}%", end = true) },
                Col("Amount", "amount", 110, end = true) { l -> Cell(Fmt.money(l, "amount"), bold = true, end = true) },
            ))
        }
    }
}

/**
 * E-way bill for one sale bill: BillBox makes the file the government portal takes (ewaybillgst.gov.in › e-Waybill ›
 * Generate Bulk). The portal gives back a 12-digit number, which is saved here and printed on the bill.
 */
@Composable
fun EwayBillForm(billId: Int, onDismiss: () -> Unit) {
    val app = LocalApp.current
    var d by remember { mutableStateOf<J?>(null) }
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    fun v(k: String) = f.value[k] ?: ""
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    var mode by remember { mutableIntStateOf(1) }
    var oversize by remember { mutableStateOf(false) }
    var warnings by remember { mutableStateOf(listOf<String>()) }
    var made by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    LaunchedEffect(billId) {
        app.guarded {
            val r = Api.get("/invoices/$billId/ewaybill")
            d = r
            val m = mutableMapOf<String, String>()
            for (k in listOf("from_pincode", "to_pincode", "vehicle_no", "transporter_id", "transporter_name", "trans_doc_no", "trans_doc_date", "ewb_no", "ewb_date", "ewb_valid")) m[k] = r.str(k)
            m["distance"] = if (r.has("distance") && r.str("distance").isNotEmpty()) Fmt.qty(r.num("distance")) else ""
            if (m["ewb_date"].isNullOrEmpty()) m["ewb_date"] = Fmt.today
            f.value = m
            mode = r.int("mode").coerceIn(1, 4)
            oversize = r.str("vehicle_type") == "O"
        }
    }
    FormDialog("E-way bill · ${d?.str("invoice_no") ?: ""}", onDismiss, "Save number", canSave = d != null, onSave = {
        val r = Api.obj("PUT", "/invoices/$billId/ewaybill", body = mapOf("ewb_no" to v("ewb_no"), "ewb_date" to v("ewb_date"), "ewb_valid" to v("ewb_valid")))
        app.notify(if (r.str("ewb_no").isEmpty()) "E-way bill number cleared." else "E-way bill ${r.str("ewb_no")} saved on the bill.")
    }) {
        val dd = d
        if (dd == null) { Loading(); return@FormDialog }
        Row { Text(dd.str("party").ifEmpty { "Cash customer" }, Modifier.weight(1f)); Text(Fmt.money(dd.num("total")), fontWeight = FontWeight.SemiBold) }
        if (!dd.bool("needed")) Hint("This bill is under ₹50,000, so an e-way bill is usually not needed (some states ask for one for goods moved within the state).")
        if (dd.str("ewb_no").isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CheckCircle, null, tint = Good); Text("  E-way bill ${dd.str("ewb_no")}" + if (dd.str("ewb_valid").isEmpty()) "" else " · valid until ${Fmt.dmy(dd.str("ewb_valid"))}", color = Good)
        }
        SectionHeader("1. Transport")
        Field("Your PIN code", v("from_pincode"), { set("from_pincode", it) }, kb = Kb.Number, placeholder = "246701")
        Field("Party's PIN code", v("to_pincode"), { set("to_pincode", it) }, kb = Kb.Number, placeholder = "246725")
        Field("Distance (km)", v("distance"), { set("distance", it) }, kb = Kb.Number, placeholder = "0 = portal works it out")
        Choice("Mode", listOf(1 to "Road", 2 to "Rail", 3 to "Air", 4 to "Ship"), mode, { mode = it })
        if (mode == 1) {
            Field("Vehicle number", v("vehicle_no"), { set("vehicle_no", it.uppercase()) }, kb = Kb.Caps, placeholder = "UP20AB1234")
            SwitchRow("Over-dimensional cargo", oversize, { oversize = it })
        } else {
            Field("RR / airway bill / B/L no.", v("trans_doc_no"), { set("trans_doc_no", it) })
            DateField("Document date", v("trans_doc_date"), { set("trans_doc_date", it) }, allowClear = true)
        }
        Field("Transporter name", v("transporter_name"), { set("transporter_name", it) }, placeholder = "optional")
        Field("Transporter ID (GSTIN)", v("transporter_id"), { set("transporter_id", it.uppercase()) }, kb = Kb.Caps, placeholder = "optional")
        Hint("PIN codes are read from the two addresses when they contain one. For road transport give the vehicle number, or the transporter ID if the transporter will add the vehicle on the portal.")
        SectionHeader("2. File for the portal")
        Button(enabled = !working, onClick = {
            app.launch {
                problem = null; warnings = emptyList(); working = true
                try {
                    val body = mutableMapOf<String, Any?>("mode" to mode, "vehicle_type" to if (oversize) "O" else "R")
                    for (k in listOf("from_pincode", "to_pincode", "distance", "vehicle_no", "transporter_id", "transporter_name", "trans_doc_no", "trans_doc_date")) body[k] = v(k)
                    if (mode == 1) { body["trans_doc_no"] = ""; body["trans_doc_date"] = "" } else body["vehicle_no"] = ""
                    val r = Api.obj("POST", "/invoices/$billId/ewaybill", body = body)
                    warnings = r.strings("warnings")
                    if (Platform.saveFile(r.str("file_name"), "application/json", r.obj("ewaybill").pretty().toByteArray())) made = r.str("file_name")
                } catch (e: Exception) { problem = e.message } finally { working = false }
            }
        }) { Icon(Icons.Default.UploadFile, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Make the e-way bill file") }
        ErrorText(problem)
        warnings.forEach { Text(it, color = Warn, style = MaterialTheme.typography.bodySmall) }
        if (made.isNotEmpty()) Text("Saved $made.")
        TextButton(onClick = { Platform.openUrl("https://ewaybillgst.gov.in") }) { Icon(Icons.Default.OpenInBrowser, null); Text("  Open the e-way bill portal") }
        Hint("On the portal: log in › e-Waybill › Generate Bulk › choose this file › Upload › Generate. The portal shows the 12-digit e-way bill number.")
        SectionHeader("3. Number from the portal")
        Field("E-way bill number", v("ewb_no"), { set("ewb_no", it) }, kb = Kb.Number, placeholder = "12 digits")
        DateField("E-way bill date", v("ewb_date"), { set("ewb_date", it) }, allowClear = true)
        DateField("Valid until", v("ewb_valid"), { set("ewb_valid", it) }, allowClear = true)
        Hint("It is printed on the bill. Clear the number and save if the e-way bill was cancelled.")
    }
}
