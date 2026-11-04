package com.local.billbox.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.CurrencyRupee
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TextSnippet
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.engine.Ocr
import com.local.billbox.print.Printing
import com.local.billbox.system.Platform
import com.local.billbox.ui.Bad
import com.local.billbox.ui.BulkOutcome
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Choice
import com.local.billbox.ui.Col
import com.local.billbox.ui.Confirm
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DateField
import com.local.billbox.ui.DayPicker
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.LocalUi
import com.local.billbox.ui.Loading
import com.local.billbox.ui.RowAction
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.SelectionBar
import com.local.billbox.ui.Warn
import com.local.billbox.ui.balanceText
import com.local.billbox.ui.bulkDelete
import com.local.billbox.ui.cap
import com.local.billbox.ui.copyText
import com.local.billbox.ui.dayList
import com.local.billbox.ui.dayNames
import com.local.billbox.ui.panel
import com.local.billbox.ui.rememberDebouncer
import com.local.billbox.ui.tsv
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun PartiesScreen() {
    val app = LocalApp.current
    val ui = LocalUi.current
    var kind by remember { mutableStateOf("CUSTOMER") }
    var query by remember { mutableStateOf("") }
    var parties by remember { mutableStateOf(listOf<J>()) }
    var routes by remember { mutableStateOf(listOf<J>()) }
    var salesmen by remember { mutableStateOf(listOf<J>()) }
    var loading by remember { mutableStateOf(true) }
    val selection = remember { mutableStateListOf<Int>() }
    var selecting by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<J?>(null) }
    var creating by remember { mutableStateOf(false) }
    var ledgerFor by remember { mutableStateOf<J?>(null) }
    var voucherFor by remember { mutableStateOf<J?>(null) }
    // set when "Record receipt / payment" was started from the ledger: the ledger opens again afterwards, on the year of the new line
    var ledgerReturn by remember { mutableStateOf<J?>(null) }
    var ledgerYear by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<J?>(null) }
    var confirmBulk by remember { mutableStateOf(false) }
    val debounce = rememberDebouncer()
    val supplier = kind == "SUPPLIER"

    suspend fun load() {
        app.guarded {
            parties = Api.list("/parties", mapOf("q" to query, "kind" to kind))
            routes = Api.list("/routes")
            salesmen = Api.list("/salesmen")
        }
        loading = false
    }
    LaunchedEffect(kind) { selection.clear(); load() }
    LaunchedEffect(app.dataVersion) { if (app.dataVersion > 0) load() }

    ScreenScaffold("Parties", fab = {
        ExtendedFloatingActionButton(modifier = Modifier.padding(bottom = 32.dp), onClick = { creating = true }, icon = { Icon(Icons.Default.PersonAdd, null) }, text = { Text(if (supplier) "New supplier" else "New customer") })
    }) { mod ->
        Column(mod) {
            Segments(listOf("CUSTOMER" to "Customers", "SUPPLIER" to "Suppliers"), kind, { kind = it }, Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
            OutlinedTextField(query, { query = it; debounce.run { load() } }, Modifier.fillMaxWidth().padding(horizontal = 12.dp), singleLine = true,
                placeholder = { Text("Search name, phone or GSTIN") }, leadingIcon = { Icon(Icons.Default.Search, null) }, shape = RoundedCornerShape(28.dp))
            if (!supplier && ui.showPhotoCard) PhotoPaymentsCard(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { photo = true }
            SelectionBar(selection.size, parties.size, selecting, { selecting = it; if (!it) selection.clear() },
                { if (selection.size == parties.size) selection.clear() else { selection.clear(); selection.addAll(parties.map { it.id }) } }, busy = busy) { confirmBulk = true }
            Box(Modifier.weight(1f)) {
                if (loading) Loading()
                else if (parties.isEmpty()) EmptyState(if (supplier) "No suppliers" else "No customers", if (supplier) "Suppliers are added automatically when you scan their bill." else "Add your first customer.", Icons.Default.People)
                else DataTable(parties, "parties", phone = listOf("name", "balance", "contact", "type"), selected = selection.toSet(), keyOf = { it.id }, selecting = selecting,
                    onToggle = { p -> if (p.id in selection) selection.remove(p.id) else selection.add(p.id) },
                    onOpen = { ledgerYear = ""; ledgerFor = it },
                    menu = { p -> listOfNotNull(
                        RowAction("Ledger…", Icons.AutoMirrored.Filled.List) { ledgerYear = ""; ledgerFor = p },
                        RowAction(if (supplier) "Record payment…" else "Record receipt…", Icons.Default.CurrencyRupee) { voucherFor = p },
                        if (selection.size > 1 && p.id in selection) RowAction("Delete ${selection.size} selected…", Icons.Default.Delete, true) { confirmBulk = true } else null,
                        RowAction("Edit…", Icons.Default.Edit) { editing = p },
                        RowAction("Delete…", Icons.Default.Delete, true) { deleteTarget = p },
                    ) },
                    columns = listOf(
                        Col("Party", "name", 200) { p -> Cell(p.str("name"), bold = true, lines = 2) },
                        Col("Type", "type", 90) { p -> Cell(cap(p.str("type"))) },
                        Col("GSTIN", "gstin", 150) { p -> Cell(p.str("gstin")) },
                        Col("Route", "route", 130) { p -> Cell(p.str("route_name")) },
                        Col("Price tier", "tier", 90) { p -> Cell(cap(p.str("price_tier"))) },
                        Col("Contact", "contact", 140) { p -> Cell(p.str("mobiles").ifEmpty { p.str("phone").ifEmpty { p.str("tel") } }) },
                        Col("Credit limit", "limit", 110, end = true) { p -> Cell(if (p.num("credit_limit") > 0) Fmt.money(p, "credit_limit") else "–", end = true) },
                        Col("Balance", "balance", 130, end = true) { p ->
                            val b = p.num("balance")
                            Cell(balanceText(b), if (b > 0.5) Warn else if (b < -0.5) Bad else MaterialTheme.colorScheme.onSurfaceVariant, bold = true, end = true)
                        },
                    ))
            }
            Text("${parties.size} ${if (supplier) "suppliers" else "customers"}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        }
    }

    if (creating) PartyForm(null, if (supplier) "SUPPLIER" else "RETAILER", routes, salesmen, { creating = false }) { load() }
    editing?.let { p -> PartyForm(p, "RETAILER", routes, salesmen, { editing = null }) { load() } }
    ledgerFor?.let { p -> LedgerDialog(p, { ledgerFor = null }, ledgerYear, { load() }) { ledgerReturn = p; ledgerYear = ""; ledgerFor = null; voucherFor = p } }
    voucherFor?.let { p ->
        VoucherForm(p, { voucherFor = null; ledgerReturn?.let { r -> ledgerReturn = null; ledgerFor = r } }, { d -> ledgerYear = fyLabelOf(d) }) { load() }
    }
    if (photo) PaymentPhotoDialog({ photo = false }) { load() }
    deleteTarget?.let { t ->
        Confirm("Delete ${t.str("name")}?", "Parties with bills or ledger entries are archived instead.", "Delete", {
            app.launch { val r = Api.obj("DELETE", "/parties/${t.id}"); app.notify(if (r.str("result") == "archived") "${t.str("name")} archived (it has history)." else "${t.str("name")} deleted."); load() }
        }, { deleteTarget = null }, destructive = true)
    }
    if (confirmBulk) Confirm("Delete ${selection.size} selected part${if (selection.size == 1) "y" else "ies"}?", "Parties with bills or ledger entries are archived instead.", "Delete ${selection.size}", {
        app.launch {
            busy = true
            bulkDelete(selection.toList(), { m, e -> app.notify(m, e) }) { id ->
                val p = parties.firstOrNull { it.id == id } ?: return@bulkDelete BulkOutcome.Failed("#$id", "not found")
                try { if (Api.obj("DELETE", "/parties/${p.id}").str("result") == "archived") BulkOutcome.Archived else BulkOutcome.Deleted }
                catch (e: Exception) { BulkOutcome.Failed(p.str("name"), e.message ?: "") }
            }
            selection.clear(); selecting = false; busy = false; load()
        }
    }, { confirmBulk = false }, destructive = true)
}

/** Parties › Customers: the way into payments from a photo (Settings › Parties & Payments can hide it). */
@Composable
fun PhotoPaymentsCard(modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(modifier.fillMaxWidth().panel(12.dp).clickable(onClick = onClick).padding(10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Surface(color = MaterialTheme.colorScheme.primary, shape = RoundedCornerShape(10.dp)) { Icon(Icons.Default.DocumentScanner, null, Modifier.padding(9.dp).size(22.dp), tint = MaterialTheme.colorScheme.onPrimary) }
        Column(Modifier.weight(1f)) {
            Text("Payments from a photo", style = MaterialTheme.typography.titleSmall)
            Hint("Photograph the handwritten list: every party's payment is recorded together.")
        }
        FilledTonalButton(onClick = onClick) { Text("Start") }
    }
}

/** New or edit party (customer or supplier), with a new route and salesman made on the spot. */
@Composable
fun PartyForm(party: J?, defaultType: String, routes: List<J>, salesmen: List<J>, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    fun v(k: String, d: String = "") = f.value[k] ?: (if (party?.has(k) == true) party.str(k) else d)
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    var type by remember { mutableStateOf(if (party == null) defaultType else party.str("type").ifEmpty { "RETAILER" }) }
    val defTier = app.setting("party_default_tier").takeIf { it in listOf("RETAIL", "WHOLESALE", "MRP") } ?: "RETAIL"
    var tier by remember { mutableStateOf(party?.str("price_tier")?.ifEmpty { null } ?: defTier) }
    var route by remember { mutableStateOf(if (party?.has("route_id") == true) party.str("route_id") else "") }
    var newRoute by remember { mutableStateOf("") }
    var newSalesman by remember { mutableStateOf("") }
    var newDays by remember { mutableStateOf("1") }
    var personName by remember { mutableStateOf("") }
    var personPhone by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        if (party == null) {   // Settings › Parties & Payments › new customers start with
            if (app.setting("party_default_limit").isNotEmpty()) set("credit_limit", app.setting("party_default_limit"))
            if (app.setting("party_default_days").isNotEmpty()) set("credit_days", app.setting("party_default_days"))
        }
    }
    val isSupplier = type == "SUPPLIER"
    FormDialog(if (party == null) "New party" else "Edit ${party.str("name")}", onDismiss, canSave = v("name").isNotBlank(), onSave = {
        val body = mutableMapOf<String, Any?>()
        for (k in listOf("name", "gstin", "state_code", "phone", "address", "credit_limit", "credit_days", "tel", "mobiles", "email", "fssai", "pan"))
            body[k] = v(k, if (k == "state_code") "09" else if (k == "credit_limit" || k == "credit_days") "0" else "").trim()
        body["type"] = type; body["price_tier"] = tier; body["route_id"] = if (route == "__new__") "" else route
        if (party == null) body["opening_balance"] = v("opening_balance", "0")
        if (route == "__new__") {
            if (newRoute.isBlank()) throw Exception("Enter a name for the new route")
            var sid = newSalesman
            if (newSalesman == "__new__") {
                if (personName.isBlank()) throw Exception("Enter the new salesman's name")
                sid = Api.obj("POST", "/salesmen", body = mapOf("name" to personName, "phone" to personPhone, "monthly_target" to "0")).int("id").toString()
            }
            body["new_route"] = mapOf("name" to newRoute, "salesman_id" to sid, "days" to newDays)
        }
        if (party != null) Api.obj("PUT", "/parties/${party.id}", body = body) else Api.obj("POST", "/parties", body = body)
        app.notify("Party saved.")
        done()
    }) {
        Field("Party name", v("name"), { set("name", it) })
        Choice("Type", listOf("RETAILER" to "Retailer", "WHOLESALER" to "Wholesaler", "SUPPLIER" to "Supplier / vendor"), type, { type = it })
        Field("GSTIN (blank if unregistered)", v("gstin"), { x ->
            val g = x.uppercase(); set("gstin", g)
            if (g.length >= 2 && g.take(2).all { it.isDigit() }) set("state_code", g.take(2))
            if (g.length == 15 && v("pan").isEmpty()) set("pan", g.drop(2).take(10))
        }, kb = Kb.Caps)
        Field("State code (09 UP, 07 Delhi)", v("state_code", "09"), { set("state_code", it) }, kb = Kb.Number)
        Field("Address", v("address"), { set("address", it) }, singleLine = false, minLines = 2)
        if (isSupplier) {
            Field("Tel (landline)", v("tel"), { set("tel", it) }, kb = Kb.Phone)
            Field("Phone", v("phone"), { set("phone", it) }, kb = Kb.Phone)
            Field("Mobile numbers (comma separated)", v("mobiles"), { set("mobiles", it) }, kb = Kb.Phone)
            Field("Email", v("email"), { set("email", it) }, kb = Kb.Email)
            Field("FSSAI number (14 digits)", v("fssai"), { set("fssai", it) }, kb = Kb.Number)
            Field("PAN number", v("pan"), { set("pan", it) }, kb = Kb.Caps)
        } else {
            Field("Phone", v("phone"), { set("phone", it) }, kb = Kb.Phone)
            Choice("Price tier", listOf("RETAIL" to "Retail price", "WHOLESALE" to "Wholesale price", "MRP" to "MRP"), tier, { tier = it })
            Field("Credit limit (0 = no limit)", v("credit_limit", "0"), { set("credit_limit", it) }, kb = Kb.Decimal)
            Field("Credit days", v("credit_days", "0"), { set("credit_days", it) }, kb = Kb.Number)
            Choice("Delivery / sales route", listOf("" to "No route") + routes.map { r ->
                val days = dayList(r.str("days"))
                r.id.toString() to (r.str("name") + if (days.isNotEmpty()) " · $days" else if (r.has("day_of_week")) " · ${dayNames[r.int("day_of_week").coerceIn(0, 6)].take(3)}" else "")
            } + listOf("__new__" to "+ New route…"), route, { route = it })
            if (route == "__new__") {
                Field("New route name", newRoute, { newRoute = it })
                Choice("Salesman for this route", listOf("" to "Not assigned yet") + salesmen.map { it.id.toString() to it.str("name") } + listOf("__new__" to "+ New salesman…"), newSalesman, { newSalesman = it })
                if (newSalesman == "__new__") {
                    Field("New salesman name", personName, { personName = it })
                    Field("Salesman phone (optional)", personPhone, { personPhone = it }, kb = Kb.Phone)
                }
                Text("Visit days"); DayPicker(newDays) { newDays = it }
            }
        }
        if (party == null) Field(if (isSupplier) "Opening balance (negative = you owe them)" else "Opening balance (they owe you)", v("opening_balance", "0"), { set("opening_balance", it) }, kb = Kb.Signed)
    }
}

/** "2026-27" for a date like 2026-11-02 (the financial year runs 1 April to 31 March). */
private fun fyLabelOf(iso: String): String {
    val q = iso.split("-")
    val y = q.getOrNull(0)?.toIntOrNull() ?: return ""
    val m = q.getOrNull(1)?.toIntOrNull() ?: return ""
    val s = if (m >= 4) y else y - 1
    return "$s-${"%02d".format((s + 1) % 100)}"
}

@Composable
fun LedgerDialog(party: J, onDismiss: () -> Unit, initialYear: String = "", onChanged: suspend () -> Unit = {}, onVoucher: () -> Unit) {
    val app = LocalApp.current
    var data by remember { mutableStateOf<J?>(null) }
    // the financial year shown; earlier years too
    var year by remember { mutableStateOf(initialYear.ifEmpty { app.fyLabel }) }
    var reload by remember { mutableStateOf(0) }
    var deleteTarget by remember { mutableStateOf<J?>(null) }
    // receipts, payments and opening balances can be deleted here; a bill's own line is removed by deleting or editing the bill
    fun deletable(e: J) = e.str("type") in listOf("RECEIPT", "PAYMENT", "OPENING")
    fun askDelete(e: J) { if (deletable(e)) deleteTarget = e else app.notify("That line belongs to a bill. Delete or edit the bill to remove it.") }
    LaunchedEffect(party.id, year, reload) { data = null; app.guarded { data = try { app.ledger(party, year) } catch (e: Exception) { app.notify(e.message ?: "", true); J() } } }
    val entries = data?.list("entries") ?: emptyList()
    val bal = data?.num("balance") ?: 0.0
    InfoDialog("${party.str("name")} · ledger · FY $year", onDismiss, scroll = false, actions = {
        androidx.compose.material3.IconButton(onClick = {
            copyText(tsv(listOf("Date", "Type", "Reference", "Narration", "Debit", "Credit", "Balance"),
                entries.map { listOf(Fmt.dmy(it.str("date")), it.str("type"), it.str("ref_no"), it.str("narration"), it.str("debit"), it.str("credit"), it.str("balance")) }))
            app.notify("Ledger copied. Paste into Excel or Sheets.")
        }) { Icon(Icons.Default.ContentCopy, "Copy") }
    }) {
        Text(balanceText(bal) + if (bal > 0.005) "  (they owe you)" else if (bal < -0.005) "  (you owe them)" else "", style = MaterialTheme.typography.titleMedium,
            color = if (bal > 0.5) Warn else if (bal < -0.5) Bad else Good)
        Choice("Year", app.yearChoices.filter { it.label.isNotEmpty() }.map { it.label to "FY ${it.label}" }, year, { year = it })
        data?.let { d -> if (kotlin.math.abs(d.num("opening_balance")) > 0.005) Hint("Opening balance for FY $year, brought forward from earlier years: ${balanceText(d.num("opening_balance"))}") }
        OutlinedButton(onClick = onVoucher) { Icon(Icons.Default.CurrencyRupee, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Record receipt / payment") }
        Box(Modifier.weight(1f)) {
            if (data == null) Loading() else DataTable(entries, "ledger", onOpen = { askDelete(it) },
                menu = { e -> listOfNotNull(if (deletable(e)) RowAction("Delete this line…", Icons.Default.Delete, true) { askDelete(e) } else null) }, columns = listOf(
                Col("Date", "date", 95) { r -> Cell(Fmt.dmy(r.str("date"))) },
                Col("Type", "type", 90) { r -> Cell(r.str("type")) },
                Col("Reference", "ref", 120) { r -> Cell(r.str("ref_no")) },
                Col("Narration", "narration", 220) { r -> Cell(r.str("narration")) },
                Col("Debit", "debit", 100, end = true) { r -> Cell(if (r.num("debit") > 0) Fmt.money(r, "debit") else "", end = true) },
                Col("Credit", "credit", 100, end = true) { r -> Cell(if (r.num("credit") > 0) Fmt.money(r, "credit") else "", end = true) },
                Col("Balance", "balance", 120, end = true) { r -> Cell(balanceText(r.num("balance")), bold = true, end = true) },
            ))
        }
        Hint("Dr = they owe you. Cr = you owe them. Tap a receipt, payment or opening line to delete it.")
    }
    deleteTarget?.let { t ->
        val amt = if (t.num("credit") > 0) t.num("credit") else t.num("debit")
        Confirm("Delete ${t.str("type").lowercase()} ${t.str("ref_no")} · ${Fmt.money(amt)}?", "The voucher behind it is removed too and the balance is worked out again. This cannot be undone.", "Delete", {
            app.launch {
                val book = app.yearChoices.firstOrNull { it.label == year }?.bookId
                Api.obj("DELETE", "/ledger/${t.id}", company = if (book == app.companyId) null else book)
                app.notify("Deleted ${t.str("type").lowercase()} ${t.str("ref_no")}.")
                reload++
                onChanged()
            }
        }, { deleteTarget = null }, destructive = true)
    }
}

@Composable
fun VoucherForm(party: J, onDismiss: () -> Unit, saved: (String) -> Unit = {}, done: suspend () -> Unit) {
    val app = LocalApp.current
    val supplier = party.str("type") == "SUPPLIER"
    var direction by remember { mutableStateOf(if (supplier) "PAID" else "RECEIVED") }
    var amount by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(app.setting("pay_default_mode").ifEmpty { "CASH" }) }
    var date by remember { mutableStateOf(app.dateInFY) }
    var reference by remember { mutableStateOf("") }
    val printIt = app.setting("voucher_print") != "0"
    FormDialog("${if (supplier) "Payment to" else "Receipt from"} ${party.str("name")}", onDismiss, if (printIt) "Save and print" else "Save",
        canSave = (amount.toDoubleOrNull() ?: 0.0) > 0, onSave = {
            val r = Api.obj("POST", "/vouchers", body = mapOf("party_id" to party.id.toString(), "direction" to direction, "amount" to amount, "mode" to mode, "date" to date, "reference" to reference))
            app.notify("Saved ${r.str("voucher_no")}.")
            saved(date)
            done()
            val no = r.str("voucher_no")
            if (no.isNotEmpty() && printIt) Printing.voucher(no, app)
        }) {
        Choice("Direction", listOf("RECEIVED" to "Received from them (money in)", "PAID" to "Paid to them (money out)"), direction, { direction = it })
        Field("Amount", amount, { amount = it }, kb = Kb.Decimal)
        Choice("Mode", listOf("BANK" to "Bank transfer", "CARD" to "Card", "CASH" to "Cash", "CHEQUE" to "Cheque", "UPI" to "UPI"), mode, { mode = it })
        DateField("Date", date, { date = it })
        Field("Reference / cheque no. (optional)", reference, { reference = it })
    }
}

/** One line of a handwritten payment list, as read and matched by the engine, ready to be checked and changed. */
private class PayLine(r: J) {
    val line = r.int("line")
    val text = r.str("text")
    var partyId by mutableStateOf(r.optInt("party_id"))
    var amount by mutableStateOf(if (r.num("amount") > 0) Fmt.plainNumber(r.num("amount")) else "")
    val reference = r.str("reference")
    val problems = r.strings("problems")
    var include by mutableStateOf(problems.isEmpty())
    val candidates = r.list("candidates")
    val bills = r.list("bills").joinToString(", ") { b -> if (b.str("invoice_no").isEmpty()) Fmt.money(b.num("amount")) + " (no bill found)" else "${b.str("invoice_no")} ${Fmt.money(b.num("amount"))}" }
    val ready get() = include && partyId != null && (amount.toDoubleOrNull() ?: 0.0) > 0
}

/**
 * Payments from a photo of a handwritten list. Each line: party name, the bill amounts separated by commas, then the
 * payment (when it differs from the bills' total). The photo is read on this phone (ML Kit); every line can be checked
 * and corrected before anything is saved, and all the payments are saved together.
 */
@Composable
fun PaymentPhotoDialog(onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var text by remember { mutableStateOf("") }
    val lines = remember { mutableStateListOf<PayLine>() }
    var parties by remember { mutableStateOf(listOf<J>()) }
    var date by remember { mutableStateOf(app.dateInFY) }
    var mode by remember { mutableStateOf(app.setting("pay_default_mode").takeIf { it in listOf("CASH", "UPI", "CHEQUE", "BANK", "CARD") } ?: "CASH") }
    var reading by remember { mutableStateOf(false) }
    var readError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { app.guarded { parties = Api.list("/parties", mapOf("kind" to "CUSTOMER")) } }
    val ready = lines.filter { it.ready }
    val total = ready.sumOf { it.amount.toDoubleOrNull() ?: 0.0 }

    suspend fun parse() { app.guarded { val r = Api.obj("POST", "/receipts/sheet/parse", body = mapOf("text" to text)); lines.clear(); lines.addAll(r.list("rows").map(::PayLine)) } }
    fun read(camera: Boolean) = app.launch {
        readError = null
        val bmp = (if (camera) Platform.takePhoto() else Platform.pickPhoto()) ?: return@launch
        reading = true
        try {
            val got = withContext(Dispatchers.Default) { Ocr.linesOf(bmp) }
            if (got.isEmpty()) readError = "No writing was found in the photo. Take it again in good light, with the page filling the picture."
            else { text = got.joinToString("\n"); parse() }
        } catch (e: Exception) { readError = e.message } finally { reading = false }
    }

    FormDialog("Payments from a photo", onDismiss, if (ready.isEmpty()) "Save" else "Save ${ready.size} payment${if (ready.size == 1) "" else "s"}", canSave = ready.isNotEmpty(), onSave = {
        val rows = ready.map { mapOf("party_id" to it.partyId, "amount" to (it.amount.toDoubleOrNull() ?: 0.0), "reference" to it.reference) }
        val r = Api.obj("POST", "/receipts/sheet", body = mapOf("date" to date, "mode" to mode, "rows" to rows))
        app.notify("Saved ${r.int("count")} payment${if (r.int("count") == 1) "" else "s"}, total ${Fmt.money(r.num("total"))}.")
        done()
    }) {
        SectionHeader("1. Photo of the list")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (Platform.hasCamera) PhotoTile("Take photo", "Use the camera", Icons.Default.CameraAlt, true, Modifier.weight(1f), !reading) { read(true) }
            PhotoTile("Choose photo", "From your photos", Icons.Default.PhotoLibrary, false, Modifier.weight(1f), !reading) { read(false) }
        }
        if (reading) Row(verticalAlignment = Alignment.CenterVertically) { androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Text("  Reading the writing…") }
        ErrorText(readError)
        Hint("Write one party per line: name, the bill amounts separated by commas, then the payment. “Gupta Store 1200, 850 - 2000” records 2,000 against bills of 1,200 and 850; “Gupta Store 1200, 850” records 2,050.")
        SectionHeader("2. Text read from the photo")
        OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), minLines = 4, textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace))
        Hint("Fix anything read wrongly here, or type the list yourself.")
        OutlinedButton(onClick = { app.launch { parse() } }, enabled = text.isNotBlank()) { Icon(Icons.Default.TextSnippet, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Read these lines") }
        if (lines.isNotEmpty()) {
            SectionHeader("3. Check each payment")
            lines.forEach { l ->
                Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(l.include, { l.include = it })
                        Text(l.text, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                    }
                    val near = l.candidates.map { it.id }
                    Choice("Party", listOf<Pair<Int?, String>>(null to "Choose party…") + l.candidates.map { it.id to "${it.str("name")}  · ${(it.num("score") * 100).toInt()}% match" } +
                        parties.filter { it.id !in near }.map { it.id to it.str("name") }, l.partyId, { l.partyId = it; if (it != null && (l.amount.toDoubleOrNull() ?: 0.0) > 0) l.include = true })
                    Field("Amount", l.amount, { l.amount = it }, kb = Kb.Decimal)
                    if (l.bills.isNotEmpty()) Hint("Bills: " + l.bills)
                    if (l.problems.isNotEmpty() && !l.ready) Text(l.problems.joinToString(" · "), color = Warn, style = MaterialTheme.typography.bodySmall)
                }
            }
            Hint("${ready.size} of ${lines.size} ready · total ${Fmt.money(total)}. Lines with a problem are left out until you choose the party and amount.")
            DateField("Date", date, { date = it })
            Choice("Mode", listOf("CASH" to "Cash", "UPI" to "UPI", "CHEQUE" to "Cheque", "BANK" to "Bank transfer", "CARD" to "Card"), mode, { mode = it })
        }
    }
}

@Composable
private fun PhotoTile(title: String, detail: String, icon: androidx.compose.ui.graphics.vector.ImageVector, prominent: Boolean, modifier: Modifier, enabled: Boolean, onClick: () -> Unit) {
    val accent = MaterialTheme.colorScheme.primary
    Surface(onClick = onClick, enabled = enabled, modifier = modifier, shape = RoundedCornerShape(14.dp), color = accent.copy(alpha = 0.06f),
        border = androidx.compose.foundation.BorderStroke(1.dp, accent.copy(alpha = 0.25f))) {
        Column(Modifier.padding(vertical = 14.dp, horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Surface(shape = CircleShape, color = if (prominent) accent else accent.copy(alpha = 0.14f)) {
                Icon(icon, null, Modifier.padding(13.dp).size(26.dp), tint = if (prominent) MaterialTheme.colorScheme.onPrimary else accent)
            }
            Text(title, style = MaterialTheme.typography.titleSmall)
            Hint(detail)
        }
    }
}
