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
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.local.billbox.ui.Confirm
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
import androidx.compose.foundation.layout.Row
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import com.local.billbox.ui.InfoDialog
import com.local.billbox.ui.Loading
import com.local.billbox.ui.dayList
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
    var showRoutes by remember { mutableStateOf(false) }
    var routes by remember { mutableStateOf<List<J>?>(null) }
    var editRoute by remember { mutableStateOf<J?>(null) }
    var deleteRoute by remember { mutableStateOf<J?>(null) }
    var menu by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<J?>(null) }
    var merging by remember { mutableStateOf<J?>(null) }
    var deleting by remember { mutableStateOf<J?>(null) }
    val current = people.firstOrNull { it.id == sel }

    suspend fun load() { app.guarded { people = Api.list("/salesmen"); if (sel == null) sel = people.firstOrNull()?.id } }
    suspend fun loadRoutes() { app.guarded { routes = Api.list("/routes") } }
    suspend fun reloadBeat() { val s = sel ?: return; app.guarded { beat = Api.get("/salesmen/$s/beat", mapOf("day" to day)) } }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(app.dataVersion) { if (app.dataVersion > 0) load() }
    LaunchedEffect(sel, day) {
        val s = sel ?: run { perf = null; beat = null; return@LaunchedEffect }
        app.guarded { perf = Api.get("/salesmen/$s/performance"); beat = Api.get("/salesmen/$s/beat", mapOf("day" to day)) }
    }

    ScreenScaffold("Salesmen and routes", actions = {
        IconButton(onClick = { showRoutes = true; app.launch { loadRoutes() } }) { Icon(Icons.AutoMirrored.Filled.List, "Routes") }
        IconButton(onClick = { newRoute = true }, enabled = people.isNotEmpty()) { Icon(Icons.Default.AltRoute, "New route") }
        IconButton(onClick = { newSalesman = true }) { Icon(Icons.Default.PersonAdd, "New salesman") }
        androidx.compose.foundation.layout.Box {
            IconButton(onClick = { menu = true }, enabled = current != null) { Icon(Icons.Default.MoreVert, "Salesman") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Edit salesman…") }, onClick = { menu = false; editing = current })
                DropdownMenuItem(text = { Text("Merge into another…") }, enabled = people.size > 1, onClick = { menu = false; merging = current })
                DropdownMenuItem(text = { Text("Delete salesman…", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; deleting = current })
            }
        }
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
    editing?.let { e ->
        var name by remember(e.id) { mutableStateOf(e.str("name")) }
        var phone by remember(e.id) { mutableStateOf(e.str("phone")) }
        var target by remember(e.id) { mutableStateOf(Fmt.qty(e.num("monthly_target"))) }
        FormDialog("Edit salesman", { editing = null }, canSave = name.isNotBlank(), onSave = {
            Api.obj("PUT", "/salesmen/${e.id}", body = mapOf("name" to name.trim(), "phone" to phone, "monthly_target" to target, "active" to true)); load()
        }) {
            Field("Name", name, { name = it })
            Field("Phone", phone, { phone = it }, kb = Kb.Phone)
            Field("Monthly sales target (₹)", target, { target = it }, kb = Kb.Decimal)
        }
    }
    merging?.let { m ->
        val others = people.filter { it.id != m.id }
        var into by remember(m.id) { mutableStateOf(others.firstOrNull()?.id?.toString() ?: "") }
        FormDialog("Merge ${m.str("name")}", { merging = null }, saveLabel = "Merge", canSave = into.isNotEmpty(), onSave = {
            val r = Api.obj("POST", "/salesmen/${m.id}/merge", body = mapOf("into" to into))
            val mv = r.obj("moved")
            app.notify("Merged: ${mv.int("invoices")} bills, ${mv.int("receipts")} receipts and ${mv.int("routes")} routes moved.")
            sel = into.toIntOrNull(); load()
        }) {
            Choice("Keep", others.map { it.id.toString() to it.str("name") }, into, { into = it })
            Hint("All of ${m.str("name")}'s bills, receipts and routes move to the salesman you keep; ${m.str("name")} is then removed.")
        }
    }
    deleting?.let { d ->
        Confirm("Delete ${d.str("name")}?", "Their routes are left without a salesman. Bills and receipts keep the name. To move their bills to someone else, use Merge instead.",
            "Delete", onConfirm = {
                deleting = null
                app.launch { app.guarded { Api.obj("DELETE", "/salesmen/${d.id}"); if (sel == d.id) sel = null; app.notify("${d.str("name")} deleted."); load() } }
            }, onDismiss = { deleting = null }, destructive = true)
    }
    if (showRoutes) {
        InfoDialog("Routes", { showRoutes = false }) {
            val list = routes
            when {
                list == null -> Loading()
                list.isEmpty() -> Hint("No routes yet. Add one with New route.")
                else -> list.forEach { r ->
                    val days = dayList(r.str("days"))
                    val d = days.ifEmpty { if (r.has("day_of_week")) dayNames[r.int("day_of_week").coerceIn(0, 6)].take(3) else "no visit day" }
                    val n = r.int("outlets")
                    Row(Modifier.fillMaxWidth().panel(10.dp).padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
                            Text(r.str("name"), fontWeight = FontWeight.Medium)
                            Hint("${r.str("salesman_name").ifEmpty { "no salesman" }} · $d · $n outlet${if (n == 1) "" else "s"}")
                        }
                        IconButton(onClick = { editRoute = r }) { Icon(Icons.Default.Edit, "Edit ${r.str("name")}") }
                        IconButton(onClick = { deleteRoute = r }) { Icon(Icons.Default.Delete, "Delete ${r.str("name")}", tint = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
    deleteRoute?.let { d ->
        Confirm("Delete ${d.str("name")}?", "Its outlets stay: those on other routes too keep them, the others are left without a route.",
            "Delete", onConfirm = {
                deleteRoute = null
                app.launch { app.guarded { Api.obj("DELETE", "/routes/${d.id}"); app.notify("${d.str("name")} deleted."); loadRoutes(); reloadBeat() } }
            }, onDismiss = { deleteRoute = null }, destructive = true)
    }
    if (newRoute) RouteForm(people, null, { newRoute = false }) { reloadBeat() }
    editRoute?.let { r -> RouteForm(people, r, { editRoute = null }) { loadRoutes(); reloadBeat() } }
}

/** New route, or edit one (`existing`): name, salesman, visit days (PUT /routes/:id). Its outlets stay on it. */
@Composable
fun RouteForm(people: List<J>, existing: J?, onDismiss: () -> Unit, done: suspend () -> Unit) {
    val app = LocalApp.current
    var name by remember(existing?.id) { mutableStateOf(existing?.str("name") ?: "") }
    var salesman by remember(existing?.id) {
        mutableStateOf(if (existing == null) people.firstOrNull()?.id?.toString() ?: "" else if (existing.has("salesman_id")) existing.int("salesman_id").toString() else "")
    }
    var days by remember(existing?.id) {
        mutableStateOf(if (existing == null) "1" else existing.str("days").ifEmpty { if (existing.has("day_of_week")) existing.int("day_of_week").toString() else "" })
    }
    FormDialog(if (existing == null) "New route" else "Edit route", onDismiss, canSave = name.isNotBlank(), onSave = {
        val body = mapOf("name" to name.trim(), "salesman_id" to salesman, "days" to days)
        if (existing != null) { Api.obj("PUT", "/routes/${existing.id}", body = body); app.notify("Route saved.") }
        else { Api.obj("POST", "/routes", body = body); app.notify("Route added.") }
        done()
    }) {
        Field("Route name", name, { name = it })
        Choice("Salesman", listOf("" to "Not assigned") + people.map { it.id.toString() to it.str("name") }, salesman, { salesman = it })
        Text("Visit days"); DayPicker(days) { days = it }
        if (existing != null) Hint("A route's name lists its places, separated by commas (e.g. Qazipara, Mandi, Mandawar Road): Parties › Assign routes uses them. Its outlets stay on it.")
    }
}
