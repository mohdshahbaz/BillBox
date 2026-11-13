package com.local.billbox.screens

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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.system.Platform
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Col
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DateField
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.Warn
import com.local.billbox.ui.copyText
import com.local.billbox.ui.tsv
import kotlin.math.abs

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ReportsScreen() {
    var tab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Sales Book", "Purchase Book", "Debit Notes", "GST Outward")
    ScreenScaffold("Books & GST") { mod ->
        Column(mod) {
            PrimaryScrollableTabRow(selectedTabIndex = tab, edgePadding = 8.dp) {
                tabs.forEachIndexed { i, t -> Tab(selected = tab == i, onClick = { tab = i }, text = { Text(t) }) }
            }
            when (tab) {
                0 -> androidx.compose.runtime.key("sales") { Book("sales") }
                1 -> androidx.compose.runtime.key("purchase") { Book("purchase") }
                2 -> androidx.compose.runtime.key("debit") { Book("debit") }
                else -> Gst()
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun androidx.compose.foundation.layout.ColumnScope.Book(type: String) {
    val app = LocalApp.current
    var from by remember { mutableStateOf(if (app.isCurrentFY) app.monthStartInFY else app.fyFrom) }
    var to by remember { mutableStateOf(if (app.isCurrentFY) app.dateInFY else app.fyTo) }
    var data by remember { mutableStateOf<J?>(null) }
    LaunchedEffect(from, to) { app.guarded { data = Api.get("/reports/book/$type", mapOf("from" to from, "to" to to)) } }
    val rows = data?.list("rows") ?: emptyList()
    val tot = data?.obj("totals") ?: J()
    val sales = type == "sales"
    Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        DateField("From", from, { from = it }, Modifier.weight(1f))
        DateField("To", to, { to = it }, Modifier.weight(1f))
        IconButton(onClick = {
            copyText(tsv(listOf("Date", "No", "Supplier bill", "Party", "GSTIN", "Taxable", "CGST", "SGST", "IGST", "Round off", "Total"),
                rows.map { listOf(Fmt.dmy(it.str("date")), it.str("no"), it.str("ref"), it.str("party"), it.str("gstin"), it.str("taxable"), it.str("cgst"), it.str("sgst"), it.str("igst"), it.str("round_off"), it.str("total")) }))
            app.notify("Copied. Paste into Excel or Sheets.")
        }) { Icon(Icons.Default.ContentCopy, "Copy") }
    }
    Box(Modifier.weight(1f)) {
        if (data == null) Loading()
        else if (rows.isEmpty()) EmptyState("No entries in this period", "", Icons.Default.MenuBook)
        else DataTable(rows, "book-$type", phone = listOf("party", "total", "no", "date", "taxable"), columns = listOf(
            Col("Date", "date", 95) { r -> Cell(Fmt.dmy(r.str("date"))) },
            Col(if (sales) "Invoice" else if (type == "debit") "Note no" else "Our ref", "no", 120) { r -> Cell(r.str("no")) },
            Col(if (type == "debit") "Against bill" else "Supplier bill", "ref", 110) { r -> Cell(r.str("ref")) },
            Col("Party", "party", 220) { r -> Cell(r.str("party"), lines = 2) },
            Col("GSTIN", "gstin", 150) { r -> Cell(r.str("gstin")) },
            Col("Taxable", "taxable", 110, end = true) { r -> Cell(Fmt.money(r, "taxable"), end = true) },
            Col("CGST", "cgst", 100, end = true) { r -> Cell(Fmt.money(r, "cgst"), end = true) },
            Col("SGST", "sgst", 100, end = true) { r -> Cell(Fmt.money(r, "sgst"), end = true) },
            Col("IGST", "igst", 100, end = true) { r -> Cell(Fmt.money(r, "igst"), end = true) },
            Col("Round off", "round", 90, end = true) { r -> Cell(Fmt.money(r, "round_off"), end = true) },
            Col("Total", "total", 110, end = true) { r -> Cell(Fmt.money(r, "total"), bold = true, end = true) },
        ))
    }
    SummaryCard(listOf(
        SummaryItem("Entries", "${tot.int("count")}"),
        SummaryItem("Taxable", Fmt.money(tot, "taxable")), SummaryItem("CGST", Fmt.money(tot, "cgst")), SummaryItem("SGST", Fmt.money(tot, "sgst")),
        SummaryItem("IGST", Fmt.money(tot, "igst")), SummaryItem("Total", Fmt.money(tot, "total"), strong = true, tint = MaterialTheme.colorScheme.primary),
    ))
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Gst() {
    val app = LocalApp.current
    var month by remember { mutableStateOf(app.dateInFY.take(7)) }
    var d by remember { mutableStateOf<J?>(null) }
    var exporting by remember { mutableStateOf(false) }
    LaunchedEffect(month) { d = null; app.guarded { d = Api.get("/reports/gst-outward", mapOf("month" to month)) } }
    fun shift(by: Int) {
        val y = month.take(4).toIntOrNull() ?: 2026; val m = month.takeLast(2).toIntOrNull() ?: 1
        val n = y * 12 + (m - 1) + by
        val next = String.format(java.util.Locale.US, "%04d-%02d", n / 12, n % 12 + 1)
        if (next >= app.fyFrom.take(7) && next <= app.fyTo.take(7)) month = next   // stay inside the open financial year
    }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { shift(-1) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous month") }
            Text("${month.takeLast(2)}-${month.take(4)}", style = MaterialTheme.typography.titleLarge)
            IconButton(onClick = { shift(1) }) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next month") }
            Spacer(Modifier.weight(1f))
            Button(onClick = {
                app.launch {
                    exporting = true
                    try { val (_, bytes) = Api.file("/reports/gst-outward.xlsx", mapOf("month" to month)); Platform.saveFile("GST-Outward-$month.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", bytes) }
                    finally { exporting = false }
                }
            }, enabled = d != null && !exporting) { Icon(Icons.Default.TableChart, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text(if (exporting) "Preparing…" else "Export to Excel") }
        }
        val x = d
        if (x == null) Loading() else {
            val rows = x.list("rows"); val tot = x.obj("totals")
            val all = rows + J(mapOf("rate" to "Total", "taxable" to tot.num("taxable"), "cgst" to tot.num("cgst"), "sgst" to tot.num("sgst"), "igst" to tot.num("igst"), "tax" to tot.num("tax"), "value" to tot.num("value"), "is_total" to true))
            Box(Modifier.fillMaxWidth().height(((rows.size + 1) * 42 + 50).dp)) {
                DataTable(all, "gst-rates", numbered = false, lazy = false, columns = listOf(
                    Col("GST rate", "rate", 80) { r -> Cell(if (r.bool("is_total")) "Total" else "${r.str("rate")}%", bold = true) },
                    Col("Taxable value", "taxable", 120, end = true) { r -> Cell(Fmt.money(r, "taxable"), end = true) },
                    Col("CGST", "cgst", 100, end = true) { r -> Cell(Fmt.money(r, "cgst"), end = true) },
                    Col("SGST", "sgst", 100, end = true) { r -> Cell(Fmt.money(r, "sgst"), end = true) },
                    Col("IGST", "igst", 110, end = true) { r -> Cell(Fmt.money(r, "igst"), end = true) },
                    Col("Total tax", "tax", 100, end = true) { r -> Cell(Fmt.money(r, "tax"), end = true) },
                    Col("Invoice value", "value", 120, end = true) { r -> Cell(Fmt.money(r, "value"), bold = true, end = true) },
                ))
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), maxItemsInEachRow = 2) {
                val m = Modifier.weight(1f).widthIn(min = 150.dp)
                val ic = x.obj("input_credit")
                StatCard("Invoices in ${x.str("month")}", "${x.int("invoices")}", m)
                StatCard("B2B (party has GSTIN)", Fmt.money(x.obj("b2b").num("taxable")), m, Good)
                StatCard("B2C (no GSTIN)", Fmt.money(x.obj("b2c").num("taxable")), m, Warn)
                StatCard(if (ic.num("debit_notes") > 0) "Input tax credit (purchases less ${Fmt.money(ic.num("debit_notes"))} on debit notes)" else "Input tax credit (purchases)", Fmt.money(ic.num("total")), m, Good)
                StatCard(if (x.num("net_payable") >= 0) "Net GST payable (estimate)" else "Credit carried forward", Fmt.money(abs(x.num("net_payable"))), m, if (x.num("net_payable") >= 0) Bad else Good)
            }
            Hint("The Excel file has four sheets: Summary, B2B Bills, B2C Bills and Rate-wise Summary. Rates are taken from each invoice line. Round-off is excluded from taxable value. The net figure is an estimate; check it with your accountant.")
        }
    }
}
