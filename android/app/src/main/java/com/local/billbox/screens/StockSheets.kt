package com.local.billbox.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.Chip
import com.local.billbox.ui.Choice
import com.local.billbox.ui.DateField
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.SwitchRow
import com.local.billbox.ui.Warn
import com.local.billbox.ui.panel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

private fun num(s: String) = s.replace(",", "").trim().toDoubleOrNull()

/**
 * New or edit item. Prices are kept per piece (ex-GST); a box price (GST included, the way a box is quoted) can be typed
 * instead and the piece price follows to 8 decimals, so a box of 300 at 2500 bills as exactly 2500.
 */
@Composable
fun ItemForm(item: J?, cats: List<J>, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    val defaultGst = app.setting("item_default_gst").ifEmpty { "18" }
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    val boxText = remember { mutableStateMapOf<String, String>() }
    fun v(k: String, d: String = "") = f.value[k] ?: (if (item?.has(k) == true) item.str(k) else d)
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    fun factors(): Pair<Double, Double> {
        val typed = maxOf(1, v("pcs_per_box", "1").trim().toIntOrNull() ?: 1)
        val ppb = Fmt.packFromName(v("name")) ?: typed
        return ppb.toDouble() to 1 + (num(v("gst_rate", defaultGst)) ?: 0.0) / 100
    }
    fun exactPiece(k: String): String {
        val bt = boxText[k] ?: return v(k)
        if (bt.isBlank()) return ""
        val b = num(bt) ?: return bt
        val (ppb, gst) = factors()
        return String.format(Locale.US, "%.8f", b / ppb / gst)
    }
    fun pieceText(k: String): String = if (boxText[k] == null) v(k) else exactPiece(k).let { s -> s.toDoubleOrNull()?.let { Fmt.rate(it) } ?: s }
    fun boxShown(k: String): String {
        boxText[k]?.let { return it }
        val (ppb, gst) = factors()
        val p = num(v(k)) ?: return ""
        if (p <= 0) return ""
        return Fmt.qty((p * ppb * gst * 100).roundToLong() / 100.0)
    }
    FormDialog(if (item == null) "New item" else "Edit ${item.str("name")}", onDismiss, canSave = v("name").isNotBlank(), onSave = {
        val body = mutableMapOf<String, Any?>()
        for (k in listOf("name", "category_id", "hsn", "gst_rate", "pcs_per_box", "mrp", "retail_price", "wholesale_price", "purchase_price"))
            body[k] = v(k, if (k == "gst_rate") defaultGst else if (k == "pcs_per_box") "1" else "")
        for (k in listOf("retail_price", "wholesale_price")) if (boxText[k] != null) body[k] = exactPiece(k)
        if (item != null) Api.obj("PUT", "/items/${item.id}", body = body) else Api.obj("POST", "/items", body = body)
        app.notify(if (item == null) "Item added. Record a purchase (or add stock) to start selling it." else "Item saved.")
        done()
    }) {
        Field("Item name", v("name"), { set("name", it) }, singleLine = false)
        Choice("Category", listOf("" to "Choose automatically from the name") + cats.map { it.id.toString() to it.str("name") }, v("category_id"), { set("category_id", it) })
        Field("HSN code", v("hsn"), { set("hsn", it) }, kb = Kb.Number)
        Field("GST rate %", v("gst_rate", defaultGst), { set("gst_rate", it) }, kb = Kb.Decimal)
        Field("Pieces in one box (1 if sold loose only)", v("pcs_per_box", "1"), { set("pcs_per_box", it) }, kb = Kb.Number)
        Fmt.packFromName(v("name"))?.let { Hint("The name says 1 box = $it pieces. That is used automatically.") }
        SectionHeader("Prices")
        Hint("Stock and prices are kept per piece; bills show boxes and pieces.")
        Field("MRP per piece (incl. GST)", v("mrp"), { set("mrp", it) }, kb = Kb.Decimal)
        Field("Retail price per piece (ex-GST)", pieceText("retail_price"), { boxText.remove("retail_price"); set("retail_price", it) }, kb = Kb.Decimal)
        Field("Retail price per box (incl. GST)", boxShown("retail_price"), { boxText["retail_price"] = it }, kb = Kb.Decimal)
        Field("Wholesale price per piece (ex-GST)", pieceText("wholesale_price"), { boxText.remove("wholesale_price"); set("wholesale_price", it) }, kb = Kb.Decimal)
        Field("Wholesale price per box (incl. GST)", boxShown("wholesale_price"), { boxText["wholesale_price"] = it }, kb = Kb.Decimal)
        Hint("Type either the box price (with GST) or the piece price (ex-GST); the other follows. The box price uses the pieces per box from the name when it has one. Prices are kept to 8 decimals, so a box of 300 at 2500 is billed as exactly 2500.")
        Field("Purchase price per piece (ex-GST)", v("purchase_price"), { set("purchase_price", it) }, kb = Kb.Decimal)
    }
}

@Composable
fun AddStockForm(item: J, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var boxes by remember { mutableStateOf("") }
    var pcs by remember { mutableStateOf("") }
    var price by remember { mutableStateOf("") }
    val perBox = maxOf(1, item.int("pcs_per_box"))
    val total = (boxes.toIntOrNull() ?: 0) * perBox + (pcs.toIntOrNull() ?: 0)
    FormDialog("Add stock · ${item.str("name")}", onDismiss, canSave = total > 0, onSave = {
        Api.obj("POST", "/batches", body = mapOf("item_id" to item.id, "qty" to total, "purchase_price" to price.ifEmpty { item.str("purchase_price") }))
        app.notify("Added ${Fmt.boxPcs(total, perBox)} of ${item.str("name")}.")
        done()
    }) {
        if (perBox > 1) Field("Boxes (1 box = $perBox pcs)", boxes, { boxes = it }, kb = Kb.Number)
        Field(if (perBox > 1) "Loose pieces" else "Pieces", pcs, { pcs = it }, kb = Kb.Number)
        if (total > 0) Hint("Total $total pcs = ${Fmt.boxPcs(total, perBox)}")
        Field("Purchase price per piece (ex-GST)", price, { price = it }, kb = Kb.Decimal, placeholder = item.str("purchase_price"))
    }
}

@Composable
fun SetStockForm(item: J, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var qty by remember { mutableStateOf("") }
    val n = qty.trim().toIntOrNull()
    FormDialog("Set stock · ${item.str("name")}", onDismiss, canSave = n != null, onSave = {
        Api.obj("POST", "/items/${item.id}/set-stock", body = mapOf("qty" to n))
        app.notify("Stock of ${item.str("name")} set to $n pcs.")
        done()
    }) {
        Hint("Now ${item.str("stock")} pcs")
        Field("New stock (total pieces)", qty, { qty = it }, kb = Kb.Signed, placeholder = item.str("stock"))
        Hint("Total pieces, not boxes. Zero and negative numbers are allowed.")
    }
}

@Composable
fun SchemeForm(item: J, onDismiss: () -> Unit) {
    val app = LocalApp.current
    var type by remember { mutableStateOf("FREE_QTY") }
    var buy by remember { mutableStateOf("10") }
    var free by remember { mutableStateOf("1") }
    var percent by remember { mutableStateOf("0") }
    var from by remember { mutableStateOf("") }
    var to by remember { mutableStateOf("") }
    FormDialog("Scheme · ${item.str("name")}", onDismiss, onSave = {
        Api.obj("POST", "/schemes", body = mapOf("item_id" to item.id, "type" to type, "buy_qty" to buy, "free_qty" to free, "percent" to percent,
            "valid_from" to from.ifEmpty { null }, "valid_to" to to.ifEmpty { null }))
        app.notify("Scheme saved.")
    }) {
        Choice("Scheme type", listOf("FREE_QTY" to "Buy X get Y free", "PERCENT" to "Percent off from a minimum quantity"), type, { type = it })
        Field("Buy quantity / minimum quantity (pieces)", buy, { buy = it }, kb = Kb.Number)
        if (type == "FREE_QTY") Field("Free pieces", free, { free = it }, kb = Kb.Number) else Field("Discount %", percent, { percent = it }, kb = Kb.Decimal)
        DateField("Valid from (optional)", from, { from = it }, allowClear = true)
        DateField("Valid to (optional)", to, { to = it }, allowClear = true)
    }
}

@Composable
fun CategoryForm(onDismiss: () -> Unit, existing: J? = null, done: suspend () -> Unit) {
    var name by remember { mutableStateOf(existing?.str("name") ?: "") }
    FormDialog(if (existing == null) "New category" else "Rename category", onDismiss, canSave = name.isNotBlank(), onSave = {
        if (existing != null) Api.obj("PUT", "/categories/${existing.id}", body = mapOf("name" to name.trim()))
        else Api.obj("POST", "/categories", body = mapOf("name" to name))
        done()
    }) {
        Field("Category name", name, { name = it })
    }
}

/**
 * Retail / wholesale prices for many items at once, from the MRP: a % below MRP, or a price for each MRP. The preview
 * shows what one box will come to on a bill, worked out exactly as billing does.
 */
@Composable
fun BulkPriceForm(cats: List<J>, initialCat: Int, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var mode by remember { mutableStateOf("percent") }
    var cat by remember { mutableIntStateOf(initialCat) }
    var retailOff by remember { mutableStateOf("") }
    var wholesaleOff by remember { mutableStateOf("") }
    var round by remember { mutableStateOf("auto") }
    var groups by remember { mutableStateOf(listOf<J>()) }
    val retailBy = remember { mutableStateMapOf<String, String>() }
    val wholeBy = remember { mutableStateMapOf<String, String>() }
    var perBox by remember { mutableStateOf(true) }
    var inclGst by remember { mutableStateOf(true) }
    var result by remember { mutableStateOf<J?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    var loaded by remember { mutableStateOf(false) }
    fun key(g: J) = Fmt.qty((g.num("mrp") * 100).roundToLong() / 100.0)
    val tiers = groups.mapNotNull { g ->
        val r = (retailBy[key(g)] ?: "").trim(); val w = (wholeBy[key(g)] ?: "").trim()
        if (r.isEmpty() && w.isEmpty()) null else mutableMapOf<String, Any?>("mrp" to g.num("mrp")).also { if (r.isNotEmpty()) it["retail"] = r; if (w.isNotEmpty()) it["wholesale"] = w }
    }
    val ready = if (mode == "percent") !(retailOff.isBlank() && wholesaleOff.isBlank()) else tiers.isNotEmpty()
    fun request(preview: Boolean): Map<String, Any?> {
        val b = mutableMapOf<String, Any?>("mode" to mode, "preview" to preview, "round" to round)
        if (cat != 0) b["category_id"] = cat
        if (mode == "percent") { if (retailOff.isNotBlank()) b["retail_off"] = retailOff.trim(); if (wholesaleOff.isNotBlank()) b["wholesale_off"] = wholesaleOff.trim() }
        else { b["tiers"] = tiers; b["per"] = if (perBox) "box" else "piece"; b["include_gst"] = inclGst }
        return b
    }
    val inputs = "$mode|$cat|$retailOff|$wholesaleOff|$round|$perBox|$inclGst|" + tiers.joinToString(",") { "${it["mrp"]}=${it["retail"]}/${it["wholesale"]}" }
    LaunchedEffect(cat) { retailBy.clear(); wholeBy.clear(); app.guarded { groups = Api.list("/items/mrp-table", mapOf("category_id" to if (cat == 0) null else cat)) }; loaded = true }
    LaunchedEffect(inputs) {
        if (!ready) { result = null; problem = null; return@LaunchedEffect }
        delay(300)
        try { result = Api.obj("POST", "/items/set-prices", body = request(true)); problem = null }
        catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { result = null; problem = e.message }
    }
    val n = result?.int("would_update") ?: 0
    FormDialog("Set prices from MRP", onDismiss, if (n > 0) "Update $n items" else "Update prices", canSave = ready && problem == null && n > 0, onSave = {
        val r = Api.obj("POST", "/items/set-prices", body = request(false))
        app.notify("Prices set for ${r.int("updated")} items. New bills use them straight away.")
        done()
    }) {
        Segments(listOf("percent" to "% below MRP", "table" to "Price for each MRP"), mode, { mode = it })
        Choice("Items", listOf(0 to "Every category") + cats.map { it.id to it.str("name") }, cat, { cat = it })
        if (mode == "percent") {
            Field("Retail: % below MRP", retailOff, { retailOff = it }, kb = Kb.Decimal, placeholder = "e.g. 16.67")
            Field("Wholesale: % below MRP", wholesaleOff, { wholesaleOff = it }, kb = Kb.Decimal, placeholder = "e.g. 20")
            Choice("Round the box price (GST included)", listOf("auto" to "To the rupee (under ₹50: to the paisa)", "5" to "To ₹5", "10" to "To ₹10", "none" to "Do not round"), round, { round = it })
            Hint("MRP includes GST, so the price is worked out with GST included and GST is then taken out for billing: 16.67% below a ₹3,000 box is a ₹2,500 box, and a bill for that box comes to exactly ₹2,500. Leave a field empty to keep that price.")
        } else {
            Segments(listOf(true to "A whole box", false to "One piece"), perBox, { perBox = it })
            SwitchRow("Typed prices include GST", inclGst, { inclGst = it })
            if (groups.isEmpty()) Hint(if (loaded) "No items with an MRP here yet. Use Auto-fill missing MRPs first." else "Loading…")
            val unit = if (perBox) "box" else "piece"
            groups.forEach { g ->
                fun today(k: String): String { val x = g.num(k + if (perBox) "_box" else "_piece"); return if (x > 0 && inclGst) Fmt.qty(x) else "" }
                Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row {
                        Text("MRP ${Fmt.money(g.num("mrp"))}" + if (g.num("mrp_box") > 0 && perBox) " · box ${Fmt.money(g.num("mrp_box"))}" else "", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        Hint("${g.int("items")} item${if (g.int("items") == 1) "" else "s"}")
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Field("Retail / $unit", retailBy[key(g)] ?: "", { retailBy[key(g)] = it }, Modifier.weight(1f), kb = Kb.Decimal, placeholder = today("retail"))
                        Field("Wholesale / $unit", wholeBy[key(g)] ?: "", { wholeBy[key(g)] = it }, Modifier.weight(1f), kb = Kb.Decimal, placeholder = today("wholesale"))
                    }
                }
            }
            Hint("Every item whose MRP (per piece) matches gets the price. Greyed numbers are today's prices in the same units. Leave a field empty to keep that price.")
        }
        SectionHeader("Preview: what one box will come to on a bill")
        ErrorText(problem)
        val r = result
        if (r != null) {
            Text("${r.int("would_update")} items will change" + (if (r.int("skipped_no_mrp") > 0) " · ${r.int("skipped_no_mrp")} without an MRP left as they are" else "") + ".", fontWeight = FontWeight.Medium)
            val list = r.list("items")
            list.take(150).forEach { it ->
                Column(Modifier.padding(vertical = 3.dp)) {
                    Text(it.str("name"), maxLines = 1)
                    Hint("MRP " + if (it.int("pcs_per_box") > 1) "${Fmt.money(it.num("mrp_box"))} (${it.int("pcs_per_box")} × ${Fmt.money(it.num("mrp"))})" else Fmt.money(it.num("mrp")))
                    for (k in listOf("retail", "wholesale")) if (it.has(k + "_bill")) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(if (k == "retail") "Retail" else "Wholesale", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (it.num(k + "_old_bill") > 0 && abs(it.num(k + "_old_bill") - it.num(k + "_bill")) >= 0.5)
                            Text(Fmt.money(it.num(k + "_old_bill")), style = MaterialTheme.typography.bodySmall, textDecoration = TextDecoration.LineThrough, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(Fmt.money(it.num(k + "_bill")), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold, color = if (k == "retail") Color(0xFF00897B) else Warn)
                        Text("(${Fmt.qty(it.num(k + "_below_pct"))}% below)", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (list.size > 150) Hint("…and ${list.size - 150} more.")
        } else if (ready && problem == null) Loading()
        else if (problem == null) Hint("Enter a percentage or a price to see every item's new price and bill total.")
    }
}

@Composable
fun MrpReportDialog(report: J, onDismiss: () -> Unit) {
    val by = report.obj("by_category")
    val names = by.o.keys().asSequence().sorted().toList()
    InfoDialog("MRP read from item names", onDismiss) {
        Text("${report.int("found")} of ${report.int("checked")} items without an MRP were filled in. ${report.int("still_missing")} have no price in their name.")
        Row { Text("Category", Modifier.weight(1f), fontWeight = FontWeight.SemiBold); Text("Found", Modifier.width(70.dp), fontWeight = FontWeight.SemiBold); Text("Missing", Modifier.width(70.dp), fontWeight = FontWeight.SemiBold) }
        names.forEach { n ->
            val c = by.obj(n)
            Row { Text(n, Modifier.weight(1f)); Text(c.str("found"), Modifier.width(70.dp)); Text(c.str("missing"), Modifier.width(70.dp), color = if (c.int("missing") > 0) Warn else Color.Unspecified) }
        }
        val missing = report.list("missing")
        if (missing.isNotEmpty()) {
            SectionHeader("Items still needing an MRP (first ${missing.size}) – open each item and type it in:")
            missing.forEach { Text("• ${it.str("name")}  ·  ${it.str("category")}") }
        }
    }
}

/** An item found in a price list, ready to be checked before it is added. */
private class FoundItem(r: J) {
    var name by mutableStateOf(r.str("name"))
    var mrp by mutableStateOf(if (r.num("mrp") > 0) Fmt.rate(r.num("mrp")) else "")
    val exists: String? = r.str("exists_name").ifEmpty { null }
    var include by mutableStateOf(exists == null)
}

/**
 * Items of one company (and category) from its price list on the internet: search, pick the page or PDF, check the tidied
 * names (the same item listed twice is kept once, items you already have are marked) and add them together.
 */
@Composable
fun OnlineItemsForm(onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var company by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }
    var results by remember { mutableStateOf(listOf<J>()) }
    var link by remember { mutableStateOf("") }
    var pasted by remember { mutableStateOf("") }
    var nameCase by remember { mutableStateOf("title") }
    val found = remember { mutableStateListOf<FoundItem>() }
    var summary by remember { mutableStateOf("") }
    var gst by remember { mutableStateOf("18") }
    var working by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    val chosen = found.filter { it.include && it.name.isNotBlank() }

    fun show(r: J) {
        val list = r.list("items")
        found.clear(); found.addAll(list.map(::FoundItem))
        summary = "${r.int("found")} items found, ${r.int("new")} new" + (if (r.int("duplicates_merged") > 0) ", ${r.int("duplicates_merged")} listed twice kept once" else "") + "."
        if (list.isEmpty()) problem = "No items with a pack size or MRP were found on that page. Try another result, or paste the list."
    }
    fun run(label: String, work: suspend () -> Unit) = app.scope.launchRun(label, { working = it }, { problem = it }, work)

    FormDialog("Items from the internet", onDismiss, if (chosen.isEmpty()) "Add" else "Add ${chosen.size} item${if (chosen.size == 1) "" else "s"}", canSave = chosen.isNotEmpty(), onSave = {
        val r = Api.obj("POST", "/items/bulk-add", body = mapOf("category" to category, "gst_rate" to gst, "items" to chosen.map { mapOf("name" to it.name, "mrp" to (it.mrp.toDoubleOrNull() ?: 0.0)) }))
        val skipped = r.list("skipped").size
        app.notify("Added ${r.list("added").size} items" + if (skipped > 0) " ($skipped skipped: already in your items)." else ".")
        done()
    }) {
        SectionHeader("1. Find the company's price list")
        Field("Company / brand (e.g. Bikano)", company, { company = it })
        Field("Category (e.g. Namkeen)", category, { category = it })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { run("Searching…") { results = Api.obj("POST", "/items/online/search", body = mapOf("company" to company, "category" to category)).list("results"); if (results.isEmpty()) problem = "Nothing found. Try other words, or paste the address of the company's price list." } },
                enabled = company.isNotBlank() && working.isEmpty()) { Icon(Icons.Default.Search, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Search online") }
            if (working.isNotEmpty()) { Spacer(Modifier.width(10.dp)); CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Text("  $working", style = MaterialTheme.typography.bodySmall) }
        }
        ErrorText(problem)
        Hint("Searches the web for “company category price list MRP”. Pick the company's own page or PDF where you can.")
        val open: (String) -> Unit = { url -> run("Reading the page…") { show(Api.obj("POST", "/items/online/fetch", body = mapOf("url" to url, "company" to company, "case" to nameCase))) } }
        results.forEach { r ->
            Column(Modifier.fillMaxWidth().clickable(enabled = working.isEmpty()) { open(r.str("url")) }.padding(vertical = 6.dp)) {
                Text((if (r.bool("pdf")) "PDF · " else "") + r.str("title"), color = MaterialTheme.colorScheme.primary, maxLines = 2)
                Hint(r.str("url"))
            }
        }
        SectionHeader("…or give the page yourself")
        Field("Web address of a price list page or PDF", link, { link = it })
        TextButton(onClick = { open(link) }, enabled = link.isNotBlank() && working.isEmpty()) { Text("Read this page") }
        OutlinedTextField(pasted, { pasted = it }, Modifier.fillMaxWidth(), minLines = 3, placeholder = { Text("Or paste the list here: one item per line, MRP after the name") })
        TextButton(onClick = { run("Reading…") { show(Api.obj("POST", "/items/online/extract", body = mapOf("text" to pasted, "company" to company, "case" to nameCase))) } }, enabled = pasted.isNotBlank() && working.isEmpty()) { Text("Read the pasted list") }
        Choice("Names", listOf("title" to "Title Case (Bikano Bhujia 200g)", "upper" to "CAPITALS (BIKANO BHUJIA 200G)", "keep" to "As written"), nameCase, { nameCase = it })
        if (found.isNotEmpty()) {
            SectionHeader("2. Check the items")
            found.forEach { fi ->
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Checkbox(fi.include, { fi.include = it })
                        Field("Name", fi.name, { fi.name = it }, Modifier.weight(1f))
                        Field("MRP", fi.mrp, { fi.mrp = it }, Modifier.width(100.dp), kb = Kb.Decimal)
                    }
                    fi.exists?.let { Text("Already in your items as $it", color = Warn, style = MaterialTheme.typography.bodySmall) }
                }
            }
            Hint(summary)
            SectionHeader("3. Add them")
            Field("Category to put them in", category, { category = it })
            Field("GST %", gst, { gst = it }, kb = Kb.Decimal)
            Hint("Prices other than the MRP, HSN codes and stock can be filled in later under Stock.")
        }
    }
}

/** Runs one step of a sheet with a "working" label and its failure shown in the sheet. */
private fun kotlinx.coroutines.CoroutineScope.launchRun(label: String, setWorking: (String) -> Unit, setProblem: (String?) -> Unit, work: suspend () -> Unit) =
    launch {
        setProblem(null); setWorking(label)
        try { work() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { setProblem(e.message) } finally { setWorking("") }
    }

/**
 * Tidy item names (pack sizes, spacing, capitals) and merge items entered more than once — the same name, or similar names.
 * Different pack sizes, MRPs and boxes are never grouped. A merged item's bills, purchases, batches and schemes move to the
 * item kept, and the merged item is archived.
 */
@Composable
fun TidyItemsForm(onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var nameCase by remember { mutableStateOf("keep") }
    var match by remember { mutableStateOf("similar") }
    var data by remember { mutableStateOf<J?>(null) }
    val keepFor = remember { mutableStateMapOf<String, Int>() }
    val leaveOut = remember { mutableStateListOf<Int>() }
    val skip = remember { mutableStateListOf<Int>() }
    var working by remember { mutableStateOf(false) }
    val renames = data?.list("renames") ?: emptyList()
    val groups = data?.list("groups") ?: emptyList()
    suspend fun load() { app.guarded { data = Api.get("/items/clean-preview", mapOf("case" to nameCase, "match" to match)) } }
    LaunchedEffect(nameCase, match) { load() }
    fun members(g: J) = listOf(g.obj("keep")) + g.list("merge")
    fun keepId(g: J): Int {
        val c = keepFor[g.str("key")] ?: g.obj("keep").int("id")
        return if (c in leaveOut) members(g).firstOrNull { it.int("id") !in leaveOut }?.int("id") ?: c else c
    }
    fun mergeIds(g: J) = members(g).map { it.int("id") }.filter { it != keepId(g) && it !in leaveOut }

    FormDialog("Tidy names & merge duplicates", onDismiss, "Done", onSave = { done() }) {
        Segments(listOf("exact" to "Same name", "similar" to "Similar", "loose" to "Loosely similar"), match, { match = it })
        Hint("Similar: Bhujia / Bhujiya, “Bikano Bhujia” / “Bhujia Bikano”, “Parle G” / “Parle-G Biscuit”. Loosely similar also groups names that share most words (check those). Different pack sizes (200g / 400g), MRPs or box sizes are never grouped.")
        SectionHeader(if (groups.isEmpty()) "Duplicates" else "${groups.size} groups")
        if (data == null) Loading() else if (groups.isEmpty()) Hint("No duplicates found.")
        groups.forEach { g ->
            val k = keepId(g)
            Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val same = g.str("match") == "same"
                    Chip(if (same) "Same name" else "Similar (${(g.num("score") * 100).toInt()}% words alike)", if (same) Good else Warn)
                    if (g.strings("warnings").isNotEmpty()) Text(g.strings("warnings").joinToString(" · "), color = Warn, style = MaterialTheme.typography.bodySmall)
                }
                members(g).forEach { m ->
                    val id = m.int("id")
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (id in leaveOut) Icons.Default.RadioButtonUnchecked else Icons.Default.CheckCircle, null,
                            Modifier.clickable { if (id in leaveOut) leaveOut.remove(id) else leaveOut.add(id) }.padding(6.dp),
                            tint = if (id in leaveOut) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary)
                        Column(Modifier.weight(1f)) {
                            Text(m.str("name"), maxLines = 2, color = if (id in leaveOut) MaterialTheme.colorScheme.onSurfaceVariant else Color.Unspecified)
                            Hint("MRP ${if (m.num("mrp") > 0) Fmt.money(m.num("mrp")) else "–"} · ${maxOf(1, m.int("pcs_per_box"))} per box · ${m.int("used")} bill lines · ${m.int("stock")} pcs")
                        }
                        if (id == k) Chip("Keep", MaterialTheme.colorScheme.primary)
                        else if (id !in leaveOut) TextButton(onClick = { keepFor[g.str("key")] = id }) { Text("Keep this") }
                    }
                }
                val ids = mergeIds(g)
                Button(onClick = {
                    app.launch {
                        working = true
                        try { val r = Api.obj("POST", "/items/merge", body = mapOf("keep_id" to keepId(g), "merge_ids" to ids)); app.notify("Merged ${r.list("merged").size} item(s) into ${r.str("name")}.") }
                        finally { working = false }
                        load()
                    }
                }, enabled = !working && ids.isNotEmpty(), modifier = Modifier.align(Alignment.End)) { Text(if (ids.isEmpty()) "Nothing to merge" else "Merge ${ids.size} into the kept item") }
            }
        }
        if (groups.size > 1) OutlinedButton(onClick = {
            app.launch {
                working = true; var n = 0
                try { for (g in groups) if (mergeIds(g).isNotEmpty()) { Api.obj("POST", "/items/merge", body = mapOf("keep_id" to keepId(g), "merge_ids" to mergeIds(g))); n++ } }
                finally { working = false }
                app.notify("Merged $n groups of duplicates."); load()
            }
        }, enabled = !working) { Text("Merge all ${groups.size} groups as shown") }
        Hint("Untick an item to leave it out of its group. Bills, purchases, stock batches and schemes move to the item kept; the others are archived. This cannot be undone, so take a backup first if unsure.")

        SectionHeader("Tidier names")
        Choice("Names", listOf("keep" to "Pack sizes and spacing", "title" to "Title Case", "upper" to "CAPITALS"), nameCase, { nameCase = it })
        if (renames.isEmpty()) Hint("All names are already tidy.")
        renames.forEach { r ->
            val id = r.int("id")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(id !in skip, { on -> if (on) skip.remove(id) else skip.add(id) })
                Column { Text(r.str("clean")); Hint("was " + r.str("name")) }
            }
        }
        if (renames.isNotEmpty()) {
            val n = renames.count { it.int("id") !in skip }
            OutlinedButton(onClick = {
                app.launch {
                    working = true
                    try {
                        val r = Api.obj("POST", "/items/clean-names", body = mapOf("case" to nameCase, "ids" to renames.map { it.int("id") }.filter { it !in skip }))
                        val sk = r.list("skipped").size
                        app.notify("Renamed ${r.int("renamed")} items" + if (sk > 0) "; $sk left as they are because another item has that name (merge them)." else ".")
                    } finally { working = false }
                    skip.clear(); load()
                }
            }, enabled = !working && n > 0) { Text("Rename $n items") }
        }
        Hint("“200 GM”, “200gms” and “200 grams” all become 200g (200G in capitals); extra spaces go.")
    }
}

/** Stock › select items › Merge selected: choose the item to keep; the others' bills, purchases, batches and schemes move to it. */
@Composable
fun MergeSelectedForm(items: List<J>, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var keep by remember { mutableStateOf(items.firstOrNull()?.id) }
    FormDialog("Merge ${items.size} items", onDismiss, "Merge", canSave = items.size >= 2, onSave = {
        val k = keep ?: items.first().id
        val r = Api.obj("POST", "/items/merge", body = mapOf("keep_id" to k, "merge_ids" to items.map { it.id }.filter { it != k }))
        app.notify("Merged ${r.list("merged").size} item(s) into ${r.str("name")}.")
        done()
    }) {
        SectionHeader("Keep which one?")
        items.forEach { it ->
            Row(Modifier.fillMaxWidth().clickable { keep = it.id }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(keep == it.id, { keep = it.id })
                Column {
                    Text(it.str("name"))
                    Hint("MRP ${if (it.num("mrp") > 0) Fmt.money(it.num("mrp")) else "–"} · ${maxOf(1, it.int("pcs_per_box"))} per box · stock ${Fmt.qty(it.num("stock"))}")
                }
            }
        }
        Hint("The others are archived after their bills, purchases, stock batches and schemes move to the item kept. Prices or HSN the kept item lacks are taken from the others. This cannot be undone.")
    }
}
