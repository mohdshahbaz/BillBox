package com.local.billbox.screens

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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
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
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.data.Page
import com.local.billbox.print.Printing
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Choice
import com.local.billbox.ui.Col
import com.local.billbox.ui.Confirm
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DateField
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.InfoLine
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.Pick
import com.local.billbox.ui.RowAction
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SearchPicker
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.panel
import com.local.billbox.ui.rememberDebouncer
import kotlinx.coroutines.delay
import java.util.concurrent.atomic.AtomicLong

private val dnIds = AtomicLong(1)

/** One row of a debit note being written (batch 0 = the earliest-expiring batches). */
private class DNLine(itemId: Int = 0, qty: String = "1", unit: String = "PCS", rate: String = "", batchId: Int = 0) {
    val key = dnIds.getAndIncrement()
    var itemId by mutableIntStateOf(itemId)
    var qty by mutableStateOf(qty)
    var unit by mutableStateOf(unit)
    var rate by mutableStateOf(rate)
    var batchId by mutableIntStateOf(batchId)
}

/** What the editor opens with: a saved note to edit, or a purchase bill to return goods from. */
private data class DNEdit(val noteId: Int? = null, val purchaseId: Int? = null)

/**
 * Debit notes: goods sent back to a supplier. Each note takes the pieces out of stock, debits the supplier's ledger
 * (you owe them that much less) and takes its GST off the month's input tax credit.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DebitNotesScreen() {
    val app = LocalApp.current
    var query by remember { mutableStateOf("") }
    var rows by remember { mutableStateOf(listOf<J>()) }
    var totals by remember { mutableStateOf(J()) }
    var loading by remember { mutableStateOf(true) }
    var viewing by remember { mutableStateOf<J?>(null) }
    var editing by remember { mutableStateOf<DNEdit?>(null) }
    var deleting by remember { mutableStateOf<J?>(null) }
    val debounce = rememberDebouncer()

    suspend fun load() {
        app.guarded { val r = Api.get("/debit-notes", mapOf("q" to query)); rows = r.list("rows"); totals = r.obj("totals") }
        loading = false
    }
    LaunchedEffect(Unit) {
        load()
        // "Return goods…" on a purchase bill, or Edit in All Bills, lands here
        app.pendingEdit?.let { e ->
            if (e.type == "DEBIT_NOTE") { app.pendingEdit = null; editing = DNEdit(noteId = e.id) }
            else if (e.type == "RETURN_PURCHASE") { app.pendingEdit = null; editing = DNEdit(purchaseId = e.id) }
        }
    }

    ScreenScaffold("Debit Notes", fab = {
        ExtendedFloatingActionButton(onClick = { editing = DNEdit() }, icon = { Icon(Icons.Default.Add, null) }, text = { Text("New debit note") })
    }) { mod ->
        Column(mod) {
            OutlinedTextField(query, { query = it; debounce.run { load() } }, Modifier.fillMaxWidth().padding(12.dp), singleLine = true,
                placeholder = { Text("Search note no, supplier or bill") }, leadingIcon = { Icon(Icons.Default.Search, null) }, shape = RoundedCornerShape(28.dp))
            Box(Modifier.weight(1f)) {
                if (loading) Loading()
                else if (rows.isEmpty()) EmptyState("No debit notes in ${app.fy}", "", Icons.AutoMirrored.Filled.Undo)
                else DataTable(rows, "debitnotes", onOpen = { viewing = it }, menu = { r -> listOf(
                    RowAction("View", Icons.Default.ReceiptLong) { viewing = r },
                    RowAction("Print…", Icons.Default.Print) { app.launch { Printing.debitNote(r.id, app) } },
                    RowAction("Edit…", Icons.Default.Edit) { editing = DNEdit(noteId = r.id) },
                    RowAction("Delete…", Icons.Default.Delete, true) { deleting = r },
                ) }, columns = listOf(
                    Col("Date", "date", 96) { r -> Cell(Fmt.dmy(r.str("date"))) },
                    Col("Note no", "no", 140) { r -> Cell(r.str("note_no")) },
                    Col("Supplier", "party", 200) { r -> Cell(r.str("party"), lines = 2) },
                    Col("Against bill", "ref", 120) { r -> Cell(r.str("against_bill")) },
                    Col("Reason", "reason", 140) { r -> Cell(r.str("reason"), lines = 2) },
                    Col("Taxable", "taxable", 110, end = true) { r -> Cell(Fmt.money(r, "taxable"), end = true) },
                    Col("GST", "gst", 100, end = true) { r -> Cell(Fmt.money(r.num("cgst") + r.num("sgst") + r.num("igst")), end = true) },
                    Col("Total", "total", 110, end = true) { r -> Cell(Fmt.money(r, "total"), bold = true, end = true) },
                ))
            }
            Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                FlowRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("${totals.int("count")} notes", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Taxable ${Fmt.money(totals, "taxable")}")
                    Text("GST reversed ${Fmt.money(totals.num("cgst") + totals.num("sgst") + totals.num("igst"))}")
                    Text("Total ${Fmt.money(totals, "total")}", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
    viewing?.let { r -> DebitNoteDetail(r.id, { viewing = null }, onEdit = { viewing = null; editing = DNEdit(noteId = r.id) }, onDelete = { viewing = null; deleting = r }) }
    editing?.let { e -> DebitNoteEditor(e.noteId, e.purchaseId, { editing = null }) { load() } }
    deleting?.let { r ->
        Confirm("Delete debit note ${r.str("note_no")}?", "The returned pieces go back into stock and its ledger entry is removed. This cannot be undone.", "Delete debit note", {
            app.launch { Api.obj("DELETE", "/debit-notes/${r.id}"); app.notify("Deleted ${r.str("note_no")}."); load() }
        }, { deleting = null }, destructive = true)
    }
}

private val reasons = listOf("Damaged", "Expired / near expiry", "Short supply", "Wrong item sent", "Rate difference", "Excess supply")

@Composable
private fun DebitNoteEditor(editId: Int?, fromPurchase: Int?, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var suppliers by remember { mutableStateOf(listOf<J>()) }
    var items by remember { mutableStateOf(listOf<J>()) }
    var bills by remember { mutableStateOf(listOf<J>()) }
    val batches = remember { mutableStateMapOf<Int, List<J>>() }
    var partyId by remember { mutableIntStateOf(0) }
    var date by remember { mutableStateOf(app.dateInFY) }
    var purchaseId by remember { mutableIntStateOf(0) }
    var against by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var discount by remember { mutableStateOf("") }
    val lines = remember { mutableStateListOf(DNLine()) }
    var noteNo by remember { mutableStateOf("") }
    var preview by remember { mutableStateOf<J?>(null) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var printAfter by remember { mutableStateOf(false) }

    fun payload(): Map<String, Any?> {
        val b = mutableMapOf<String, Any?>("party_id" to partyId, "date" to date, "against_bill" to against, "reason" to reason, "notes" to notes, "discount" to discount)
        if (purchaseId > 0) b["purchase_id"] = purchaseId
        b["lines"] = lines.filter { it.itemId > 0 }.map { l -> mutableMapOf<String, Any?>("item_id" to l.itemId, "qty" to l.qty, "unit" to l.unit, "rate" to l.rate).also { if (l.batchId > 0) it["batch_id"] = l.batchId } }
        return b
    }
    val key = "$partyId|$date|$discount|" + lines.joinToString(",") { "${it.itemId}:${it.qty}:${it.unit}:${it.rate}:${it.batchId}" }

    suspend fun loadBills() {
        val name = suppliers.firstOrNull { it.id == partyId }?.str("name") ?: run { bills = emptyList(); return }
        app.guarded {
            val r = Api.get("/bills", mapOf("type" to "PURCHASE", "q" to name, "from" to "2000-01-01", "to" to "2100-12-31"))
            bills = r.list("rows").filter { it.str("party") == name }.map { it.with("bill_id" to it.int("id")) }
        }
    }
    suspend fun loadBatches(itemId: Int) {
        if (itemId <= 0 || batches.containsKey(itemId)) return
        runCatching { batches[itemId] = Api.list("/items/$itemId/batches").filter { it.int("qty") > 0 } }
    }
    suspend fun fillFromPurchase(id: Int) {
        app.guarded {
            val p = Api.get("/purchases/$id")
            val ls = p.list("lines").map { x ->
                val box = Regex("^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$", RegexOption.IGNORE_CASE).matches(x.str("unit"))
                DNLine(x.int("item_id"), x.num("qty").toInt().toString(), if (box) "BOX" else "PCS", x.str("rate"), x.int("batch_id"))
            }
            lines.clear(); lines.addAll(ls.ifEmpty { listOf(DNLine()) })
            for (l in lines) loadBatches(l.itemId)
        }
    }

    LaunchedEffect(Unit) {
        app.guarded { suppliers = Api.list("/parties", mapOf("kind" to "SUPPLIER")); items = Api.list("/items") }
        if (editId != null) app.guarded {
            val d = Api.get("/debit-notes/$editId")
            noteNo = d.str("note_no"); partyId = d.int("party_id"); date = d.str("date")
            loadBills()
            purchaseId = d.int("purchase_id")
            against = if (purchaseId > 0) "" else d.str("against_bill")
            reason = d.str("reason"); notes = d.str("notes"); discount = if (d.num("discount") == 0.0) "" else d.str("discount")
            lines.clear(); lines.addAll(d.list("lines").map { x -> DNLine(x.int("item_id"), x.num("qty").toInt().toString(), if (x.str("unit") == "BOX") "BOX" else "PCS", x.str("rate"), x.int("batch_id")) }.ifEmpty { listOf(DNLine()) })
            for (l in lines) loadBatches(l.itemId)
        } else if (fromPurchase != null) {
            app.guarded { val p = Api.get("/purchases/$fromPurchase"); partyId = p.int("party_id"); loadBills(); purchaseId = fromPurchase }
            fillFromPurchase(fromPurchase)
        }
    }
    LaunchedEffect(key) {
        delay(250)
        if (partyId <= 0 || lines.none { it.itemId > 0 }) { preview = null; errorText = null; return@LaunchedEffect }
        try { preview = Api.obj("POST", "/debit-notes/preview", body = payload()); errorText = null }
        catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { preview = null; errorText = e.message }
    }
    val itemChoices = remember(items) { items.map { Pick(it.id, it.str("name"), "${it.str("hsn")}  ·  stock ${Fmt.boxPcs(it.int("stock"), it.int("pcs_per_box"))}") } }

    FormDialog(if (editId == null) "New debit note" else "Edit $noteNo", onDismiss, if (editId == null) "Save" else "Update", canSave = preview != null, onSave = {
        val r = if (editId == null) Api.obj("POST", "/debit-notes", body = payload()) else Api.obj("PUT", "/debit-notes/$editId", body = payload())
        app.notify("${if (editId == null) "Saved" else "Updated"} debit note ${r.str("note_no")} for ${Fmt.money(r, "total")}. The pieces are out of stock.")
        done()
        if (printAfter) Printing.debitNote(r.int("id"), app)
    }) {
        SearchPicker("Supplier", suppliers.map { Pick(it.id, it.str("name"), it.str("gstin")) }, partyId, { partyId = it; purchaseId = 0; app.launch { loadBills() } }, placeholder = "Select supplier…")
        DateField("Date", date, { date = it })
        Choice("Against purchase bill", listOf(0 to "None") + bills.map { b -> b.int("bill_id") to "${b.str("ref").ifEmpty { b.str("no") }}  ·  ${Fmt.dmy(b.str("date"))}  ·  ${Fmt.money(b, "total")}" }, purchaseId, { purchaseId = it })
        if (purchaseId > 0) TextButton(onClick = { app.launch { fillFromPurchase(purchaseId) } }) { Icon(Icons.Default.FileDownload, null); Text("  Fill the rows from this bill") }
        Field("Supplier's bill no. (if not picked above)", against, { against = it.uppercase() }, kb = Kb.Caps)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Field("Reason", reason, { reason = it }, Modifier.weight(1f))
            var open by remember { mutableStateOf(false) }
            Box {
                IconButton(onClick = { open = true }) { Icon(Icons.Default.List, "Pick a reason") }
                DropdownMenu(open, { open = false }) { reasons.forEach { r -> DropdownMenuItem(text = { Text(r) }, onClick = { reason = r; open = false }) } }
            }
        }
        if (noteNo.isNotEmpty()) Hint("Editing $noteNo. Saving puts the old pieces back first, then takes the corrected rows out of stock.")

        SectionHeader("Goods returned")
        lines.forEach { l ->
            androidx.compose.runtime.key(l.key) {
                val it = items.firstOrNull { x -> x.id == l.itemId }
                Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SearchPicker("Item", itemChoices, l.itemId, { picked ->
                            l.itemId = picked; l.batchId = 0
                            val x = items.firstOrNull { y -> y.id == picked }
                            if (l.rate.isEmpty() && x != null && x.num("purchase_price") > 0) l.rate = Fmt.rate(x.num("purchase_price") * (if (l.unit == "BOX") maxOf(1, x.int("pcs_per_box")).toDouble() else 1.0))
                            app.launch { loadBatches(picked) }
                        }, Modifier.weight(1f), placeholder = "Select item…")
                        IconButton(onClick = { if (lines.size > 1) lines.remove(l) }, enabled = lines.size > 1) { Icon(Icons.Default.RemoveCircle, "Remove row", tint = if (lines.size > 1) Bad else MaterialTheme.colorScheme.outline) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Field("Qty", l.qty, { v -> l.qty = v }, Modifier.weight(0.8f), kb = Kb.Number)
                        Segments(listOf("PCS" to "Pcs", "BOX" to "Box"), l.unit, { v -> l.unit = v }, Modifier.weight(1f))
                        Field(if (l.unit == "BOX") "Rate / box" else "Rate / pc", l.rate, { v -> l.rate = v }, Modifier.weight(1.1f), kb = Kb.Decimal)
                    }
                    if (it != null) {
                        val ppb = maxOf(1, it.int("pcs_per_box"))
                        val q = l.qty.trim().toIntOrNull() ?: 0
                        val pcs = if (l.unit == "BOX") q * ppb else q
                        Choice("Batch", listOf(0 to "Earliest expiry first") + (batches[it.id] ?: emptyList()).map { b ->
                            b.id to "${b.str("batch_no")}  ·  ${Fmt.boxPcs(b.int("qty"), ppb)}${if (b.str("exp_date") < "2099-01-01") "  ·  exp ${Fmt.dmy(b.str("exp_date"))}" else ""}"
                        }, l.batchId, { v -> l.batchId = v })
                        Text("${Fmt.boxPcs(pcs, ppb)} out of stock  ·  in stock ${Fmt.boxPcs(it.int("stock"), ppb)}  ·  GST ${Fmt.qty(it.num("gst_rate"))}%",
                            style = MaterialTheme.typography.bodySmall, color = if (pcs > it.int("stock")) Bad else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        OutlinedButton(onClick = { lines.add(DNLine()) }) { Icon(Icons.Default.Add, null); Text(" Add row") }
        Hint("Rate is ex-GST, per box for a row in boxes. Pieces come out of the batch you pick, or the earliest-expiring batches.")

        SectionHeader("Totals")
        Field("Discount", discount, { discount = it }, kb = Kb.Decimal, placeholder = "0")
        preview?.let { p ->
            InfoLine("Items", Fmt.money(p.num("subtotal")))
            InfoLine("Taxable", Fmt.money(p.num("taxable")))
            if (p.str("supply") == "INTER") InfoLine("IGST", Fmt.money(p.num("igst"))) else { InfoLine("CGST", Fmt.money(p.num("cgst"))); InfoLine("SGST", Fmt.money(p.num("sgst"))) }
            if (p.num("round_off") != 0.0) InfoLine("Round off", Fmt.money(p.num("round_off")))
            InfoLine("Debit note total", Fmt.money(p, "total"), bold = true)
        }
        Field("Notes", notes, { notes = it }, singleLine = false, minLines = 2)
        ErrorText(errorText)
        com.local.billbox.ui.SwitchRow("Print after saving", printAfter, { printAfter = it })
    }
}

/** A saved debit note: its rows and totals, with Print, Edit and Delete. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DebitNoteDetail(id: Int, onDismiss: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    val app = LocalApp.current
    var d by remember { mutableStateOf<J?>(null) }
    LaunchedEffect(id) { app.guarded { d = Api.get("/debit-notes/$id") } }
    val n = d ?: J()
    InfoDialog("${n.str("note_no")} · ${n.str("party_name")}", onDismiss, scroll = false) {
        Hint(listOf(Fmt.dmy(n.str("date")), if (n.str("against_bill").isEmpty()) "" else "Against bill ${n.str("against_bill")}", n.str("reason"), "Total ${Fmt.money(n, "total")}").filter { it.isNotEmpty() }.joinToString("   ·   "))
        ActionRow(Triple("Print", Icons.Default.Print) { onDismiss(); app.launch { Printing.debitNote(id, app) } }, Triple("Edit", Icons.Default.Edit, onEdit), Triple("Delete", Icons.Default.Delete, onDelete), destructive = setOf("Delete"))
        Box(Modifier.weight(1f)) {
            if (d == null) Loading() else DataTable(n.list("lines"), "debitnotedetail", columns = listOf(
                Col("Item", "item", 220) { l -> Cell(l.str("item_name"), lines = 2) },
                Col("Qty", "qty", 120, end = true) { l -> Cell(Fmt.boxPcs(l.int("pcs_qty"), l.int("pcs_per_box")), end = true) },
                Col("Rate", "rate", 110, end = true) { l -> Cell("${Fmt.money(l, "rate")} / ${if (l.str("unit") == "BOX") "box" else "pc"}", end = true) },
                Col("Batch", "batch", 110) { l -> Cell(l.str("batch_no"), lines = 2) },
                Col("Taxable", "taxable", 100, end = true) { l -> Cell(Fmt.money(l, "taxable"), end = true) },
                Col("GST", "gst", 55, end = true) { l -> Cell("${Fmt.qty(l.num("gst_rate"))}%", end = true) },
                Col("Tax", "tax", 90, end = true) { l -> Cell(Fmt.money(l.num("cgst") + l.num("sgst") + l.num("igst")), end = true) },
            ))
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Taxable ${Fmt.money(n, "taxable")}")
            if (n.num("igst") > 0) Text("IGST ${Fmt.money(n, "igst")}") else { Text("CGST ${Fmt.money(n, "cgst")}"); Text("SGST ${Fmt.money(n, "sgst")}") }
            Text("Total ${Fmt.money(n, "total")}", fontWeight = FontWeight.Bold)
        }
    }
}
