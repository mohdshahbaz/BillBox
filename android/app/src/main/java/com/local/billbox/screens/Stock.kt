package com.local.billbox.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMerge
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddBox
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Redeem
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.ApiError
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.BulkOutcome
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Col
import com.local.billbox.ui.Confirm
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.RowAction
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SelectionBar
import com.local.billbox.ui.Warn
import com.local.billbox.ui.bulkDelete
import com.local.billbox.ui.rememberDebouncer

@Composable
fun StockScreen() {
    val app = LocalApp.current
    var items by remember { mutableStateOf(listOf<J>()) }
    var cats by remember { mutableStateOf(listOf<J>()) }
    var query by remember { mutableStateOf("") }
    var catId by remember { mutableIntStateOf(0) }
    val selection = remember { mutableStateListOf<Int>() }
    var selecting by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<J?>(null) }
    var creating by remember { mutableStateOf(false) }
    var stockFor by remember { mutableStateOf<J?>(null) }
    var setStockFor by remember { mutableStateOf<J?>(null) }
    var schemeFor by remember { mutableStateOf<J?>(null) }
    var sheet by remember { mutableStateOf("") }   // bulk, category, online, tidy, merge
    var mrpReport by remember { mutableStateOf<J?>(null) }
    var deleteTarget by remember { mutableStateOf<J?>(null) }
    var forceTarget by remember { mutableStateOf<Pair<J, String>?>(null) }
    var confirmBulk by remember { mutableStateOf(false) }
    var confirmZero by remember { mutableStateOf(false) }
    var catMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    val debounce = rememberDebouncer()
    val zero = items.filter { it.num("stock") <= 0.0 }

    suspend fun load() {
        app.guarded {
            items = Api.list("/items", mapOf("q" to query, "category_id" to if (catId == 0) null else catId))
            cats = Api.list("/categories")
        }
        loading = false
    }
    LaunchedEffect(catId) { load() }
    LaunchedEffect(app.dataVersion) { if (app.dataVersion > 0) load() }

    suspend fun delete(it: J, force: Boolean) {
        try {
            val r = Api.obj("DELETE", "/items/${it.id}", mapOf("force" to if (force) 1 else null))
            app.notify(if (r.str("result") == "archived") "${it.str("name")} archived (it has history)." else "${it.str("name")} deleted.")
            load()
        } catch (e: ApiError) { if (e.code == "HAS_STOCK" && !force) forceTarget = it to e.message else app.notify(e.message, true) }
    }
    suspend fun outcome(id: Int): BulkOutcome {
        val it = items.firstOrNull { x -> x.id == id } ?: return BulkOutcome.Failed("#$id", "not found")
        return try { if (Api.obj("DELETE", "/items/${it.id}").str("result") == "archived") BulkOutcome.Archived else BulkOutcome.Deleted }
        catch (e: ApiError) { BulkOutcome.Failed(it.str("name"), if (e.code == "HAS_STOCK") "still in stock" else e.message) }
    }

    ScreenScaffold("Stock", actions = {
        Box {
            IconButton(onClick = { catMenu = true }) { Icon(Icons.Default.FilterList, "Category", tint = if (catId == 0) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary) }
            DropdownMenu(catMenu, { catMenu = false }) {
                DropdownMenuItem(text = { Text("All categories") }, onClick = { catId = 0; catMenu = false })
                cats.forEach { c -> DropdownMenuItem(text = { Text(c.str("name")) }, onClick = { catId = c.id; catMenu = false }) }
            }
        }
        Box {
            IconButton(onClick = { moreMenu = true }) { Icon(Icons.Default.MoreVert, "More") }
            DropdownMenu(moreMenu, { moreMenu = false }) {
                fun item(t: String, enabled: Boolean = true, red: Boolean = false, run: () -> Unit) = Triple(t, enabled, red) to run
                listOf(
                    item("Auto categories (from item names)") { app.launch { val r = Api.obj("POST", "/items/auto-categorize", body = emptyMap<String, Any>()); app.notify("${r.int("categorised")} of ${r.int("checked")} items categorised" + if (r.int("from_internet") > 0) " (${r.int("from_internet")} found on the internet)." else "."); load() } },
                    item("Auto-fill missing MRPs") { app.launch { mrpReport = Api.obj("POST", "/items/auto-mrp", body = emptyMap<String, Any>()); load() } },
                    item("Set prices from MRP…") { sheet = "bulk" },
                    item("Items from the internet…") { sheet = "online" },
                    item("Tidy names & merge duplicates…") { sheet = "tidy" },
                    item("Merge selected items…", selection.size >= 2) { sheet = "merge" },
                    item("New category…") { sheet = "category" },
                    item("Delete items with zero/negative stock…", zero.isNotEmpty(), true) { confirmZero = true },
                ).forEachIndexed { i, (m, run) ->
                    if (i == 3 || i == 6 || i == 7) HorizontalDivider()
                    DropdownMenuItem(text = { Text(m.first, color = if (m.third) MaterialTheme.colorScheme.error else Color.Unspecified) }, enabled = m.second, onClick = { moreMenu = false; run() })
                }
            }
        }
    }, fab = { ExtendedFloatingActionButton(modifier = Modifier.padding(bottom = 32.dp), onClick = { creating = true }, icon = { Icon(Icons.Default.Add, null) }, text = { Text("New item") }) }) { mod ->
        Column(mod) {
            OutlinedTextField(query, { query = it; debounce.run { load() } }, Modifier.fillMaxWidth().padding(12.dp), singleLine = true,
                placeholder = { Text("Search item or HSN") }, leadingIcon = { Icon(Icons.Default.Search, null) }, shape = RoundedCornerShape(28.dp))
            SelectionBar(selection.size, items.size, selecting, { selecting = it; if (!it) selection.clear() },
                { if (selection.size == items.size) selection.clear() else { selection.clear(); selection.addAll(items.map { it.id }) } }, busy = busy) { confirmBulk = true }
            Box(Modifier.weight(1f)) {
                if (loading) Loading()
                else if (items.isEmpty()) EmptyState("No items", "Add an item, or scan a supplier bill in Purchases and items are created for you.", Icons.Default.Inventory2)
                else DataTable(items, "stock", phone = listOf("item", "stock", "mrp", "retail", "wholesale"), selected = selection.toSet(), keyOf = { it.id }, selecting = selecting,
                    onToggle = { r -> if (r.id in selection) selection.remove(r.id) else selection.add(r.id) }, onOpen = { editing = it },
                    menu = { it -> listOfNotNull(
                        RowAction("Edit…", Icons.Default.Edit) { editing = it },
                        RowAction("Add stock…", Icons.Default.AddBox) { stockFor = it },
                        RowAction("Set stock qty…", Icons.Default.Edit) { setStockFor = it },
                        RowAction("Add scheme…", Icons.Default.Redeem) { schemeFor = it },
                        RowAction("Delete…", Icons.Default.Delete, true) { deleteTarget = it },
                        if (selection.size > 1 && it.id in selection) RowAction("Merge ${selection.size} selected…", Icons.AutoMirrored.Filled.CallMerge) { sheet = "merge" } else null,
                        if (selection.size > 1 && it.id in selection) RowAction("Delete ${selection.size} selected…", Icons.Default.Delete, true) { confirmBulk = true } else null,
                    ) },
                    columns = listOf(
                        Col("Item", "item", 240) { it -> Cell(it.str("name"), lines = 2) },
                        Col("Category", "category", 130) { it -> Cell(it.str("category")) },
                        Col("HSN", "hsn", 80) { it -> Cell(it.str("hsn")) },
                        Col("Stock (box + pcs)", "stock", 140) { it -> Cell(Fmt.boxPcs(it.int("stock"), it.int("pcs_per_box")), if (it.num("stock") <= app.lowStockQty) Warn else Color.Unspecified, bold = true) },
                        Col("Pcs per box", "box", 90) { it -> Cell(if (it.int("pcs_per_box") > 1) "${it.int("pcs_per_box")}" else "–") },
                        Col("Total pcs", "pcs", 90, end = true, hidden = true) { it -> Cell(it.str("stock"), end = true) },
                        Col("MRP", "mrp", 90) { it -> Cell(Fmt.money(it, "mrp")) },
                        Col("Retail / pc (ex-GST)", "retail", 120, end = true) { it -> Cell(Fmt.rate(it.num("retail_price")), end = true) },
                        Col("Wholesale / pc (ex-GST)", "wholesale", 120, end = true) { it -> Cell(Fmt.rate(it.num("wholesale_price")), end = true) },
                        Col("Retail / box (incl. GST)", "retailbox", 150, end = true) { it -> Cell(if (it.int("pcs_per_box") > 1) Fmt.money(it.num("retail_price") * it.int("pcs_per_box") * (1 + it.num("gst_rate") / 100)) else "–", end = true) },
                        Col("Wholesale / box (incl. GST)", "wholesalebox", 160, end = true) { it -> Cell(if (it.int("pcs_per_box") > 1) Fmt.money(it.num("wholesale_price") * it.int("pcs_per_box") * (1 + it.num("gst_rate") / 100)) else "–", end = true) },
                        Col("Cost", "cost", 90) { it -> Cell(Fmt.money(it, "purchase_price")) },
                        Col("GST", "gst", 55) { it -> Cell("${Fmt.qty(it.num("gst_rate"))}%") },
                        Col("Your margin", "margin", 90) { it -> Cell("${it.str("dist_margin_pct")}%") },
                        Col("Retailer margin", "rmargin", 110) { it -> Cell("${it.str("retailer_margin_pct")}%") },
                    ))
            }
            Text("${items.size} items" + if (catId == 0) "" else " in ${cats.firstOrNull { it.id == catId }?.str("name") ?: ""}",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        }
    }

    if (creating) ItemForm(null, cats, { creating = false }) { load() }
    editing?.let { ItemForm(it, cats, { editing = null }) { load() } }
    stockFor?.let { AddStockForm(it, { stockFor = null }) { load() } }
    setStockFor?.let { SetStockForm(it, { setStockFor = null }) { load() } }
    schemeFor?.let { SchemeForm(it) { schemeFor = null } }
    when (sheet) {
        "bulk" -> BulkPriceForm(cats, catId, { sheet = "" }) { load() }
        "category" -> CategoryForm({ sheet = "" }) { load() }
        "online" -> OnlineItemsForm({ sheet = "" }) { load() }
        "tidy" -> TidyItemsForm({ sheet = "" }) { load() }
        "merge" -> MergeSelectedForm(items.filter { it.id in selection }, { sheet = "" }) { selection.clear(); load() }
    }
    mrpReport?.let { MrpReportDialog(it) { mrpReport = null } }
    deleteTarget?.let { t -> Confirm("Delete ${t.str("name")}?", "Items that were ever bought or sold are archived instead, so history stays intact.", "Delete", { app.launch { delete(t, false) } }, { deleteTarget = null }, destructive = true) }
    forceTarget?.let { (it, msg) ->
        AlertDialog(onDismissRequest = { forceTarget = null }, title = { Text("Still in stock") }, text = { Text("$msg\n\nDelete it anyway?") },
            confirmButton = { TextButton({ forceTarget = null; app.launch { delete(it, true) } }) { Text("Delete anyway", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ forceTarget = null }) { Text("Cancel") } })
    }
    if (confirmBulk) Confirm("Delete ${selection.size} selected item${if (selection.size == 1) "" else "s"}?", "Items that were ever bought or sold are archived instead, so history stays intact. An item still in stock is skipped.", "Delete ${selection.size}", {
        app.launch { busy = true; bulkDelete(selection.toList(), { m, e -> app.notify(m, e) }) { outcome(it) }; selection.clear(); selecting = false; busy = false; load() }
    }, { confirmBulk = false }, destructive = true)
    if (confirmZero) Confirm("Delete ${zero.size} item${if (zero.size == 1) "" else "s"} with zero or negative stock?", "Items that were ever bought or sold are archived instead, so history stays intact.", "Delete ${zero.size}", {
        app.launch { busy = true; bulkDelete(zero.map { it.id }, { m, e -> app.notify(m, e) }) { outcome(it) }; selection.clear(); busy = false; load() }
    }, { confirmZero = false }, destructive = true)
}
