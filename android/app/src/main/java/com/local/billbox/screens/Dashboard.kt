package com.local.billbox.screens

import com.local.billbox.ui.DS
import com.local.billbox.ui.Info
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AddShoppingCart
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CurrencyRupee
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.data.Page
import com.local.billbox.data.PendingEdit
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Banner
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.Kpi
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.Loading
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.Segments
import com.local.billbox.ui.Warn
import com.local.billbox.ui.panel
import java.time.LocalTime
import kotlin.math.abs

private val Teal = Color(0xFF00897B)
private val Orange = Color(0xFFEF6C00)

/** The day's business at a glance: today, this month or the whole year; every card and row opens the screen behind it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DashboardScreen() {
    val app = LocalApp.current
    var d by remember { mutableStateOf<J?>(null) }
    var period by remember { mutableStateOf(app.setting("dash_period").takeIf { it in listOf("today", "month", "year") } ?: "month") }
    var metric by remember { mutableStateOf("sales") }
    var pickedMonth by remember { mutableStateOf<String?>(null) }
    var photo by remember { mutableStateOf(false) }
    val hidden = app.dashboardHidden
    suspend fun load() { app.guarded { d = Api.get("/reports/dashboard") } }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(app.dataVersion) { if (app.dataVersion > 0) load() }
    fun go(p: Page) { app.section = p }

    ScreenScaffold("Dashboard", actions = { IconButton(onClick = { app.launch { load() } }) { Icon(Icons.Default.Refresh, "Refresh") } }) { mod ->
        val x = d
        if (x == null) { Box(mod) { Loading() }; return@ScreenScaffold }
        Column(mod.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // hero
            val accent = MaterialTheme.colorScheme.primary
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Brush.linearGradient(listOf(accent, accent.copy(alpha = 0.72f)))).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val onA = MaterialTheme.colorScheme.onPrimary
                Row {
                    Column(Modifier.weight(1f)) {
                        val h = LocalTime.now().hour
                        Text(if (h < 12) "Good morning" else if (h < 17) "Good afternoon" else "Good evening", color = onA.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
                        Text(app.companyName, color = onA, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 2)
                        Text("FY ${x.str("fy")} · ${Fmt.dmy(x.str("as_of"))}", color = onA.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(if (x.bool("is_current")) "Sales today" else "Sales on the last day", color = onA.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall)
                        Text(Fmt.money(x.num("today_sales")), color = onA, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
                        Text("${x.int("today_bills")} bills · collected ${Fmt.money(x.num("today_collections"))}", color = onA.copy(alpha = 0.85f), style = MaterialTheme.typography.bodySmall, maxLines = 1)
                    }
                }
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickChip("New bill", Icons.Default.AddShoppingCart, onA) { go(Page.Billing) }
                    QuickChip("Payments from photo", Icons.Default.DocumentScanner, onA) { photo = true }
                    QuickChip("Purchase", Icons.Default.LocalShipping, onA) { go(Page.Purchases) }
                    QuickChip("All bills", Icons.AutoMirrored.Filled.ReceiptLong, onA) { go(Page.Bills) }
                    QuickChip("Stock", Icons.Default.Inventory2, onA) { go(Page.Stock) }
                    QuickChip("Parties", Icons.Default.People, onA) { go(Page.Parties) }
                }
            }
            if (!x.bool("is_current")) Banner("You are looking at a past financial year. Figures show that year only; \"today\" means its last day, ${Fmt.dmy(x.str("as_of"))}. Switch year from the company menu at the top.", Icons.Default.History)
            if ("alerts" !in hidden) {
                val chips = listOfNotNull(
                    if (x.int("unprinted_bills") > 0) Triple("${x.int("unprinted_bills")} bill${if (x.int("unprinted_bills") == 1) "" else "s"} to print", Icons.Default.Print, Info) to { app.openUnprinted = true; go(Page.Bills) } else null,
                    if (x.int("low_stock_count") > 0) Triple("${x.int("low_stock_count")} items low on stock", Icons.Default.Warning, Bad) to { go(Page.Stock) } else null,
                    if (x.int("expiring_30d") > 0) Triple("${x.int("expiring_30d")} ${if (x.int("expiring_30d") == 1) "batch expires" else "batches expire"} within ${if (x.has("expiry_days")) x.int("expiry_days") else 30} days", Icons.Default.EventBusy, Warn) to { go(Page.Reports) } else null,
                    if (x.int("expired_stock") > 0) Triple("${x.int("expired_stock")} expired batch${if (x.int("expired_stock") == 1) "" else "es"} in stock", Icons.Default.Cancel, Bad) to { go(Page.Reports) } else null,
                )
                // chips wrap onto a new line instead of running off the screen edge (docs/DESIGN_SYSTEM.md)
                if (chips.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(DS.space8), verticalArrangement = Arrangement.spacedBy(DS.space8)) {
                    chips.forEach { (c, run) ->
                        Row(Modifier.clip(CircleShape).background(c.third.copy(alpha = DS.tint)).clickable { run() }.heightIn(min = 40.dp).padding(horizontal = DS.space12, vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(c.second, null, Modifier.size(16.dp), tint = c.third); Text("  ${c.first}", color = c.third, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
            Segments(listOf("today" to if (x.bool("is_current")) "Today" else "Last day", "month" to "This month", "year" to "Whole year"), period, { period = it })
            // figures
            fun pick(t: Double, m: Double, y: Double) = if (period == "today") t else if (period == "month") m else y
            val word = if (period == "today") "today" else if (period == "month") "this month" else "this year"
            val todayPurchases = x.list("series").lastOrNull { it.str("date") == x.str("as_of") }?.num("purchases") ?: 0.0
            val sales = pick(x.num("today_sales"), x.num("month_sales"), x.num("fy_sales"))
            val bills = pick(x.int("today_bills").toDouble(), x.int("month_bills").toDouble(), x.int("fy_bills").toDouble())
            val profit = pick(x.num("today_profit"), x.num("month_profit"), x.num("fy_profit"))
            val purchases = pick(todayPurchases, x.num("month_purchases"), x.num("fy_purchases"))
            val collected = pick(x.num("today_collections"), x.num("month_collections"), x.num("fy_collections"))
            val gst = if (period == "year") x.num("fy_gst_liability") else x.num("gst_liability")
            // a fixed grid (2 across on a phone, 3 on a wide screen): every tile the same width, and the same height in a row
            val tiles: List<@Composable (Modifier) -> Unit> = listOf(
                { m -> Kpi("Sales", Fmt.money(sales), "${bills.toInt()} bills $word", Icons.Default.CurrencyRupee, Teal, m) { go(Page.Bills) } },
                { m -> Kpi("Profit", Fmt.money(profit), if (period == "year") "Margin ${Fmt.qty(x.num("fy_margin_pct"))}%" else "Before expenses, $word", Icons.AutoMirrored.Filled.TrendingUp, if (profit >= 0) Good else Bad, m) { go(Page.Reports) } },
                { m -> Kpi("Collections", Fmt.money(collected), "Payments received $word", Icons.Default.Payments, Good, m) { go(Page.Parties) } },
                { m -> Kpi("Purchases", Fmt.money(purchases), "Supplier bills $word", Icons.Default.LocalShipping, Orange, m) { go(Page.Purchases) } },
                { m -> Kpi("To receive", Fmt.money(x.num("receivable")), "You owe suppliers ${Fmt.money(x.num("payable"))}", Icons.Default.PersonSearch, Orange, m) { go(Page.Parties) } },
                { m -> Kpi(if (period == "year") "GST for the year" else "GST this month", Fmt.money(abs(gst)), if (gst >= 0) "To pay (output less input)" else "Credit carried forward", Icons.Default.AccountBalance, if (gst >= 0) Bad else Good, m) { go(Page.Reports) } }
            )
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
                val across = if (maxWidth >= 560.dp) 3 else 2
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    tiles.chunked(across).forEach { row ->
                        Row(Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            row.forEach { tile -> tile(Modifier.weight(1f).fillMaxHeight()) }
                            repeat(across - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            if ("charts" !in hidden) {
                val rows = x.list("monthly")
                val color = if (metric == "sales") Teal else if (metric == "purchases") Orange else Good
                val sel = pickedMonth ?: x.str("month")
                Column(Modifier.fillMaxWidth().panel(14.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Month by month", style = MaterialTheme.typography.titleMedium)
                    Segments(listOf("sales" to "Sales", "purchases" to "Purchases", "profit" to "Profit"), metric, { metric = it })
                    MonthBars(rows.map { Triple(it.str("month"), Fmt.monthName(it.str("month")), it.num(metric)) }, color, sel) { pickedMonth = it }
                    rows.firstOrNull { it.str("month") == sel }?.let { c ->
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(Fmt.monthName(c.str("month")) + " " + c.str("month").take(4), fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodySmall)
                            Text("Sales ${Fmt.money(c.num("sales"))}", color = Teal, style = MaterialTheme.typography.bodySmall)
                            Text("Purchases ${Fmt.money(c.num("purchases"))}", color = Orange, style = MaterialTheme.typography.bodySmall)
                            Text("Profit ${Fmt.money(c.num("profit"))}", color = if (c.num("profit") >= 0) Good else Bad, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            if ("daily" !in hidden) {
                Column(Modifier.fillMaxWidth().panel(14.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Last 14 days", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        Box(Modifier.size(8.dp).clip(CircleShape).background(Teal)); Hint(" Sales  ")
                        Box(Modifier.size(8.dp).clip(CircleShape).background(Orange)); Hint(" Purchases")
                    }
                    DailyBars(x.list("series"))
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), maxItemsInEachRow = 2) {
                val m = Modifier.weight(1f).widthIn(min = 280.dp)
                if ("items" !in hidden) ListCard("Best sellers this month", Icons.Default.Star, x.list("top_items").map { it.str("name") to Fmt.money(it.num("amount")) }, m) { go(Page.Stock) }
                if ("dues" !in hidden) ListCard("Top dues", Icons.Default.PersonSearch, x.list("top_dues").map { it.str("name") to Fmt.money(it.num("balance")) }, m) { go(Page.Parties) }
                if ("low" !in hidden) ListCard("Low stock", Icons.Default.Warning, x.list("low_stock").take(8).map { it.str("name") to Fmt.boxPcs(it.int("stock"), maxOf(1, it.int("pcs_per_box"))) }, m) { go(Page.Stock) }
                if ("recent" !in hidden) {
                    val bs = x.list("recent_bills")
                    ListCard("Latest bills", Icons.AutoMirrored.Filled.ReceiptLong, bs.map { "${it.str("invoice_no")} · ${it.str("party")}" + (if (it.bool("printed")) "" else " · not printed") to Fmt.money(it.num("total")) }, m) { i ->
                        app.pendingEdit = PendingEdit("INVOICE", bs[i].int("id")); go(Page.Billing)
                    }
                }
            }
        }
    }
    if (photo) PaymentPhotoDialog({ photo = false }) { load() }
}

@Composable
private fun QuickChip(title: String, icon: ImageVector, color: Color, onClick: () -> Unit) {
    Row(Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(16.dp), tint = color); Text("  $title", color = color, style = MaterialTheme.typography.labelLarge)
    }
}

/** A short list; tapping a row opens the screen behind it. */
@Composable
private fun ListCard(title: String, icon: ImageVector, rows: List<Pair<String, String>>, modifier: Modifier, open: (Int) -> Unit) {
    Column(modifier.panel(14.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Text("  $title", style = MaterialTheme.typography.titleMedium) }
        if (rows.isEmpty()) Hint("Nothing to show.")
        rows.forEachIndexed { i, (a, b) ->
            Row(Modifier.fillMaxWidth().clickable { open(i) }.padding(vertical = 4.dp)) {
                Text(a, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis); Text(b, fontWeight = FontWeight.Medium)
            }
            if (i < rows.size - 1) HorizontalDivider()
        }
    }
}

/** Twelve bars, April to March; tap one to read that month. A loss is drawn in red. */
@Composable
private fun MonthBars(values: List<Triple<String, String, Double>>, color: Color, selected: String, pick: (String) -> Unit) {
    val top = maxOf(1.0, values.maxOfOrNull { abs(it.third) } ?: 1.0)
    val loss = Bad   // read here: the drawing block below is not composable
    Row(Modifier.fillMaxWidth().height(200.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
        values.forEach { (id, label, v) ->
            val on = id == selected
            Column(Modifier.weight(1f).fillMaxSize().clickable { pick(id) }, horizontalAlignment = Alignment.CenterHorizontally) {
                if (on) Text(Fmt.money(v), fontSize = 8.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
                Canvas(Modifier.weight(1f).fillMaxWidth()) {
                    val h = maxOf(if (v != 0.0) 3f else 0f, size.height * (abs(v) / top).toFloat())
                    drawRoundRect((if (v < 0) loss else color).copy(alpha = if (on) 1f else 0.45f), Offset(0f, size.height - h), Size(size.width, h), CornerRadius(8f, 8f))
                }
                Text(label, fontSize = 10.sp, maxLines = 1, color = if (on) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Sales and purchases for each of the last 14 days; tap a day to read it. */
@Composable
private fun DailyBars(series: List<J>) {
    var picked by remember { mutableStateOf<String?>(null) }
    val top = maxOf(1.0, series.maxOfOrNull { maxOf(it.num("sales"), it.num("purchases")) } ?: 1.0)
    Row(Modifier.fillMaxWidth().height(150.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
        series.forEach { s ->
            val id = s.str("date")
            Column(Modifier.weight(1f).fillMaxSize().background(if (picked == id) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f) else Color.Transparent)
                .clickable { picked = if (picked == id) null else id }, horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(Modifier.weight(1f).fillMaxWidth()) {
                    val w = size.width / 2 - 1
                    val a = (size.height * s.num("sales") / top).toFloat(); val b = (size.height * s.num("purchases") / top).toFloat()
                    drawRect(Teal, Offset(0f, size.height - a), Size(w, a))
                    drawRect(Orange, Offset(w + 2, size.height - b), Size(w, b))
                }
                Text(Fmt.dmy(id).take(5), fontSize = 8.sp, maxLines = 1, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    picked?.let { p -> series.firstOrNull { it.str("date") == p }?.let { Hint("${Fmt.dmy(p)}: sales ${Fmt.money(it.num("sales"))}, purchases ${Fmt.money(it.num("purchases"))}") } }
}
