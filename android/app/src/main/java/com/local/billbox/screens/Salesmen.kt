package com.local.billbox.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AltRoute
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Choice
import com.local.billbox.ui.Col
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.DayPicker
import com.local.billbox.ui.EmptyState
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.Warn
import com.local.billbox.ui.dayNames
import com.local.billbox.ui.panel
import java.time.LocalDate

/** A figure in a card. */
@Composable
fun StatCard(title: String, value: String, modifier: Modifier = Modifier, tint: Color = MaterialTheme.colorScheme.primary) {
    Column(modifier.panel(10.dp).padding(14.dp)) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.headlineSmall, color = tint, maxLines = 1)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SalesmenScreen() {
    val app = LocalApp.current
    var people by remember { mutableStateOf(listOf<J>()) }
    var sel by remember { mutableStateOf<Int?>(null) }
    var perf by remember { mutableStateOf<J?>(null) }
    var beat by remember { mutableStateOf<J?>(null) }
    var day by remember { mutableIntStateOf(LocalDate.now().dayOfWeek.value % 7) }
    var newSalesman by remember { mutableStateOf(false) }
    var newRoute by remember { mutableStateOf(false) }

    suspend fun load() { app.guarded { people = Api.list("/salesmen"); if (sel == null) sel = people.firstOrNull()?.id } }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(sel, day) {
        val s = sel ?: run { perf = null; beat = null; return@LaunchedEffect }
        app.guarded { perf = Api.get("/salesmen/$s/performance"); beat = Api.get("/salesmen/$s/beat", mapOf("day" to day)) }
    }

    ScreenScaffold("Salesmen and routes", actions = {
        IconButton(onClick = { newRoute = true }, enabled = people.isNotEmpty()) { Icon(Icons.Default.AltRoute, "New route") }
        IconButton(onClick = { newSalesman = true }) { Icon(Icons.Default.PersonAdd, "New salesman") }
    }) { mod ->
        Column(mod.verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            if (people.isNotEmpty()) Choice("Salesman", people.map { it.id to (it.str("name") + if (it.str("phone").isEmpty()) "" else " · ${it.str("phone")}") }, sel ?: 0, { sel = it })
            val p = perf
            if (p == null) EmptyState("No salesman selected", "Add a salesman to start tracking targets, beats and collections.", Icons.Default.Person)
            else {
                val ach: Double? = if (p.has("achievement_pct")) p.num("achievement_pct") else null
                FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp), maxItemsInEachRow = 2) {
                    val m = Modifier.weight(1f).widthIn(min = 150.dp)
                    StatCard("Target for ${p.str("month")}", Fmt.money(p, "target"), m)
                    StatCard("Sales (${p.int("invoices")} bills)", Fmt.money(p, "sales"), m, Color(0xFF00897B))
                    StatCard("Achievement", ach?.let { "${Fmt.qty(it)}%" } ?: "No target set", m, if ((ach ?: 0.0) >= 100) Good else Warn)
                    StatCard("Collections this month", Fmt.money(p, "collections"), m, Good)
                }
                if (ach != null) LinearProgressIndicator(progress = { (ach / 100).coerceIn(0.0, 1.0).toFloat() }, Modifier.fillMaxWidth())
                if (p.has("day")) {
                    val d = p.obj("day")
                    SectionHeader("Today")
                    val modes = d.list("collected_by_mode")
                    Text("${d.int("bills")} bills · ${Fmt.money(d, "sales")} sold · ${Fmt.money(d, "credit_given")} given on credit · collected: " +
                        if (modes.isEmpty()) "nothing yet" else modes.joinToString(", ") { "${it.str("mode")} ${Fmt.money(it, "amount")}" })
                }
                SectionHeader("Beat plan")
                Segments((0..6).map { it to dayNames[it].take(3) }, day, { day = it })
                val outlets = beat?.list("outlets") ?: emptyList()
                if (outlets.isEmpty()) Hint("No outlets on ${dayNames[day]}. Create a route for this day and assign parties to it.")
                else {
                    Box(Modifier.fillMaxWidth().height((outlets.size * 44 + 48).coerceAtMost(460).dp)) {
                        DataTable(outlets, "beat", columns = listOf(
                            Col("Outlet", "outlet", 220) { o -> Cell(o.str("name"), lines = 2) },
                            Col("Route", "route", 150) { o -> Cell(o.str("route_name")) },
                            Col("Last order", "last", 110) { o -> Cell(if (o.has("last_order")) Fmt.dmy(o.str("last_order")) else "Never") },
                            Col("Outstanding to collect", "outstanding", 170, end = true) { o -> Cell(Fmt.money(o, "outstanding"), if (o.num("outstanding") > 0) Warn else Color.Unspecified, bold = true, end = true) },
                        ))
                    }
                    Hint("To collect on this beat: ${Fmt.money(beat?.num("total_outstanding") ?: 0.0)}")
                }
            }
        }
    }

    if (newSalesman) {
        var name by remember { mutableStateOf("") }
        var phone by remember { mutableStateOf("") }
        var target by remember { mutableStateOf("0") }
        FormDialog("New salesman", { newSalesman = false }, canSave = name.isNotBlank(), onSave = {
            Api.obj("POST", "/salesmen", body = mapOf("name" to name, "phone" to phone, "monthly_target" to target)); load()
        }) {
            Field("Name", name, { name = it })
            Field("Phone", phone, { phone = it }, kb = Kb.Phone)
            Field("Monthly sales target (₹)", target, { target = it }, kb = Kb.Decimal)
        }
    }
    if (newRoute) {
        var name by remember { mutableStateOf("") }
        var salesman by remember { mutableStateOf(people.firstOrNull()?.id?.toString() ?: "") }
        var days by remember { mutableStateOf("1") }
        FormDialog("New route", { newRoute = false }, canSave = name.isNotBlank(), onSave = {
            Api.obj("POST", "/routes", body = mapOf("name" to name, "salesman_id" to salesman, "days" to days)); app.notify("Route added.")
        }) {
            Field("Route name", name, { name = it })
            Choice("Salesman", people.map { it.id.toString() to it.str("name") }, salesman, { salesman = it })
            Text("Visit days"); DayPicker(days) { days = it }
        }
    }
}
