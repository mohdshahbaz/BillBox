package com.local.billbox.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.engine.Engine
import com.local.billbox.print.PrintLayout
import com.local.billbox.print.PrintPrefs
import com.local.billbox.print.optionalColumns
import com.local.billbox.system.Platform
import com.local.billbox.system.WhatsApp
import com.local.billbox.ui.Bad
import com.local.billbox.ui.Cell
import com.local.billbox.ui.Choice
import com.local.billbox.ui.Col
import com.local.billbox.ui.Confirm
import com.local.billbox.ui.DataTable
import com.local.billbox.ui.ErrorText
import com.local.billbox.ui.Field
import com.local.billbox.ui.FormDialog
import com.local.billbox.ui.Good
import com.local.billbox.ui.Hint
import com.local.billbox.ui.InfoLine
import com.local.billbox.ui.Kb
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.LocalBack
import com.local.billbox.ui.LocalUi
import com.local.billbox.ui.Loading
import com.local.billbox.ui.RowAction
import com.local.billbox.ui.ScreenScaffold
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.Segments
import com.local.billbox.ui.SelectionBar
import com.local.billbox.ui.SwitchRow
import com.local.billbox.ui.Themes
import com.local.billbox.ui.Warn
import com.local.billbox.ui.panel
import java.io.File

private data class SettingsPage(val id: String, val title: String, val icon: ImageVector, val color: Color)

private val pages = listOf(
    SettingsPage("appearance", "Appearance", Icons.Default.Palette, Color(0xFFE91E63)),
    SettingsPage("companies", "Companies", Icons.Default.Business, Color(0xFF1E88E5)),
    SettingsPage("printing", "Printing", Icons.Default.Print, Color(0xFF757575)),
    SettingsPage("whatsapp", "WhatsApp", Icons.Default.Chat, Color(0xFF43A047)),
    SettingsPage("billing", "Billing & Dashboard", Icons.Default.Speed, Color(0xFFFB8C00)),
    SettingsPage("parties", "Parties & Payments", Icons.Default.People, Color(0xFF8E24AA)),
    SettingsPage("stock", "Stock", Icons.Default.Inventory2, Color(0xFF795548)),
    SettingsPage("backup", "Backup", Icons.Default.Backup, Color(0xFF00897B)),
    SettingsPage("sync", "Sync", Icons.Default.Sync, Color(0xFF039BE5)),
    SettingsPage("update", "Updates", Icons.Default.SystemUpdate, Color(0xFF43A047)),
    SettingsPage("marg", "Import from Marg ERP", Icons.Default.Download, Color(0xFF3949AB)),
    SettingsPage("licence", "Licence", Icons.Default.Verified, Color(0xFFF9A825)),
)

/** The Mac's settings tabs as a list of sections, each opening its own page (system back returns to the list). */
@Composable
fun SettingsScreen() {
    var open by rememberSaveable { mutableStateOf<String?>(null) }
    val page = pages.firstOrNull { it.id == open }
    if (page == null) {
        ScreenScaffold("Settings") { mod ->
            Column(mod.verticalScroll(rememberScrollState())) {
                pages.forEach { p ->
                    ListItem(headlineContent = { Text(p.title) },
                        leadingContent = { Box(Modifier.size(34.dp).clip(RoundedCornerShape(8.dp)).background(p.color), contentAlignment = Alignment.Center) { Icon(p.icon, null, tint = Color.White, modifier = Modifier.size(20.dp)) } },
                        trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) }, modifier = Modifier.clickable { open = p.id })
                    HorizontalDivider()
                }
            }
        }
    } else {
        BackHandler { open = null }
        androidx.compose.runtime.CompositionLocalProvider(LocalBack provides { open = null }) {
            ScreenScaffold(page.title) { mod ->
                Box(mod) {
                    when (page.id) {
                        "appearance" -> AppearancePage()
                        "companies" -> CompaniesPage()
                        "printing" -> PrintingPage()
                        "whatsapp" -> WhatsAppPage()
                        "billing" -> BillingDashboardPage()
                        "parties" -> PartiesPaymentsPage()
                        "stock" -> StockPage()
                        "backup" -> BackupPage()
                        "sync" -> SyncPage()
                        "update" -> UpdatesPage()
                        "marg" -> MargImportPage()
                        "licence" -> LicencePage()
                    }
                }
            }
        }
    }
}

/** Settings › Licence: the trial or the licence of this phone, Buy (on the website) and the licence key (services/license.js). */
@Composable
private fun LicencePage() {
    val app = LocalApp.current
    var s by remember { mutableStateOf(J()) }
    var key by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { try { s = Api.get("/license") } catch (_: Exception) {} }
    fun run(path: String, body: Map<String, Any?>) = app.launch {
        busy = true
        try {
            s = Api.obj("POST", path, body = body)
            if (s.str("state") == "licensed") key = ""
            if (s.str("renew_error").isNotEmpty()) app.notify(s.str("renew_error"), true)
            else app.notify(if (s.str("state") == "licensed") "Licence checked: BillBox is licensed on this phone." else "Done.")
        } finally { busy = false }
    }
    val state = s.str("state")
    Page {
        SectionHeader("This phone")
        Text(when (state) {
            "licensed" -> if (s.str("plan") == "lifetime") "Licensed for life" else "Licensed"
            "trial" -> "Free trial: ${s.int("trial_days_left")} day${if (s.int("trial_days_left") == 1) "" else "s"} left"
            "expired" -> "The trial has ended"
            else -> "No licence needed"
        }, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium, color = if (state == "expired") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
        Hint(when (state) {
            "licensed" -> if (s.str("expires").isEmpty()) "Everything in BillBox, on this phone, with no end date." else "Everything in BillBox until ${s.str("expires")}."
            "trial" -> "Everything works during the ${s.int("trial_days")}-day trial. After it, your books stay safe and can be seen, printed and backed up; adding or changing anything needs a licence."
            "expired" -> (if (s.str("reason").isEmpty()) "" else s.str("reason") + ". ") + "Your books are safe: they can still be seen, printed, exported and backed up. Buy a licence or enter your key to add and change things again."
            else -> "This copy of BillBox is not limited."
        })
        if (s.str("edition") == "admin") Hint("Admin (test) edition: test licence keys only.", color = Color(0xFFEF6C00))
        if (state != "unlimited" && state.isNotEmpty()) {
            if (state != "licensed") {
                SectionHeader("Buy")
                DriveBtn("Buy a licence…", prominent = true) { com.local.billbox.system.Platform.openUrl(s.str("buy_url")) }
                Hint("Yearly ₹1,499 · Lifetime ₹3,999 by UPI or bank transfer. Send the reference on the buy page; your licence key is ready there once the payment is confirmed (usually within a few hours). Enter it below.")
            }
            SectionHeader("Licence")
            if (state == "licensed") {
                Hint("Plan: ${if (s.str("plan") == "lifetime") "Lifetime" else "Yearly"} · valid till ${s.str("expires").ifEmpty { "no end" }}" + (if (s.str("email").isNotEmpty()) " · ${s.str("email")}" else "") + " · checked online by ${s.str("renew_by")}")
                DriveBtn(if (busy) "Checking…" else "Check the licence now", enabled = !busy) { run("/license/renew", emptyMap()) }
                DriveBtn("Remove the licence from this phone", destructive = true, enabled = !busy) { run("/license/deactivate", emptyMap()) }
            } else {
                Field("Licence key (BB1.…)", key, { key = it })
                DriveBtn(if (busy) "Checking…" else "Use this licence key", prominent = true, enabled = !busy && key.isNotBlank()) { run("/license/activate", mapOf("key" to key)) }
            }
            Hint("Device ${s.str("device")}. One licence works on 2 devices (Mac, Windows, Linux, iPhone or Android). BillBox checks it online every few weeks and keeps working offline in between. To move it, remove it here first.")
            if (s.str("edition") == "admin") {
                SectionHeader("Testing")
                DriveBtn("Start the trial again", destructive = true, enabled = !busy) { run("/license/reset-trial", emptyMap()) }
            }
        }
    }
}

@Composable
private fun Page(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { content(); Spacer(Modifier.height(80.dp)) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AppearancePage() {
    val ui = LocalUi.current
    Page {
        SectionHeader("Theme")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), maxItemsInEachRow = 2) {
            Themes.forEach { t ->
                val on = ui.theme == t.id
                val a = Color(t.accentLight)
                Column(Modifier.weight(1f).widthIn(min = 140.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainer)
                    .border(BorderStroke(if (on) 2.dp else 1.dp, if (on) a else MaterialTheme.colorScheme.outlineVariant), RoundedCornerShape(12.dp))
                    .clickable { ui.set("theme", t.id) }.padding(10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(8.dp))) {
                        if (t.id == "dynamic") Box(Modifier.weight(1f).fillMaxSize().background(MaterialTheme.colorScheme.primaryContainer))
                        else Box(Modifier.weight(1f).fillMaxSize().background(a))
                        Box(Modifier.weight(1f).fillMaxSize().background(Color(t.pageLight)))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(t.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        if (on) Icon(Icons.Default.CheckCircle, null, tint = a)
                    }
                }
            }
        }
        Hint("“Your wallpaper” takes its colours from the phone's wallpaper (Android 12 and up). The theme applies at once and is remembered.")
        SectionHeader("Mode")
        Segments(listOf("auto" to "Automatic", "light" to "Light", "dark" to "Dark"), ui.appearance, { ui.set("appearance", it) })
        SectionHeader("Accent colour")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val own = Themes.firstOrNull { it.id == ui.theme } ?: Themes[0]
            Box(Modifier.size(34.dp).clip(RoundedCornerShape(17.dp)).background(Color(own.accentLight))
                .border(BorderStroke(if (ui.accentOverride.isEmpty()) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface), RoundedCornerShape(17.dp))
                .clickable { ui.set("accentOverride", "") }, contentAlignment = Alignment.Center) { Text("A", color = Color.White, fontWeight = FontWeight.Bold) }
            com.local.billbox.ui.AccentChoices.forEach { (id, light, _) ->
                Box(Modifier.size(34.dp).clip(RoundedCornerShape(17.dp)).background(Color(light))
                    .border(BorderStroke(if (ui.accentOverride == id) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface), RoundedCornerShape(17.dp))
                    .clickable { ui.set("accentOverride", id) })
            }
        }
        Hint("“A” is the theme's own colour; the others replace it on buttons, icons and totals.")
        SectionHeader("Background")
        Segments(listOf("" to "Theme", "plain" to "Plain", "tinted" to "Tinted"), ui.pageStyle, { ui.set("pageStyle", it) })
        SectionHeader("Panels")
        Segments(listOf("soft" to "Soft shadow", "outline" to "Outlined", "flat" to "Flat"), ui.cardStyle, { ui.set("cardStyle", it) })
        Segments(listOf("square" to "Square", "normal" to "Rounded", "round" to "Round"), ui.corners, { ui.set("corners", it) })
        SectionHeader("Table rows")
        Segments(listOf("compact" to "Compact", "regular" to "Regular", "roomy" to "Roomy"), ui.density, { ui.set("density", it) })
        SectionHeader("Letters")
        Segments(listOf("system" to "System", "serif" to "Serif", "mono" to "Mono"), ui.fontStyle, { ui.set("fontStyle", it) })
        Segments(listOf("light" to "Light", "regular" to "Regular", "medium" to "Medium", "bold" to "Bold"), ui.fontWeight, { ui.set("fontWeight", it) })
        SectionHeader("Text size")
        Segments(listOf("small" to "Smaller", "default" to "System", "large" to "Larger", "xlarge" to "Largest"), ui.textSize, { ui.set("textSize", it) })
        Hint("Panels, corners, row height and text size apply at once on this phone and are remembered.")
    }
}

@Composable
private fun CompaniesPage() {
    val app = LocalApp.current
    var editing by remember { mutableStateOf<J?>(null) }
    var creating by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<J?>(null) }
    var yearStart by remember { mutableIntStateOf(app.currentFYStart + 1) }
    Page {
        app.companies.forEach { c ->
            Row(Modifier.fillMaxWidth().panel(10.dp).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(c.str("name") + if (c.str("fy").isEmpty()) "" else "  · FY ${c.str("fy")} file", fontWeight = FontWeight.Medium)
                    Hint(listOf(c.str("company_gstin"), c.str("company_address")).filter { it.isNotEmpty() }.joinToString(" · "))
                }
                if (c.id == app.companyId) Text("Open", color = Good, style = MaterialTheme.typography.labelMedium)
                else OutlinedButton(onClick = { app.launch { app.switchCompany(c.id) } }) { Text("Open") }
                TextButton(onClick = { editing = c }) { Text("Edit") }
                TextButton(onClick = { deleting = c }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
        }
        Hint("Each company has its own books (stock, parties, bills). Switch company from the menu under the screen title.")
        Button(onClick = { creating = true }) { Text("New company…") }
        SectionHeader("Financial years of ${app.companyName}")
        Choice("Financial year", ((app.currentFYStart - 6)..(app.currentFYStart + 1)).map { it to "FY " + app.fyLabelFor(it) }, yearStart, { yearStart = it })
        OutlinedButton(onClick = { app.launch { app.addYearBooks(app.fyLabelFor(yearStart), true) } }) { Text("Start FY ${app.fyLabelFor(yearStart)} as its own file, carrying forward") }
        OutlinedButton(onClick = { app.launch { app.addYearBooks(app.fyLabelFor(yearStart), false) } }) { Text("Add FY ${app.fyLabelFor(yearStart)} as an empty file (for Marg data)") }
        Hint("Like Marg, each year can be kept in its own file. “Carrying forward” copies items, parties, schemes, stock in hand and closing balances into the new year’s opening balances. An empty file is for an earlier year: open it, then Settings › Import from Marg ERP brings that year’s Marg data in. Years with their own file open that file.")
    }
    if (creating) CompanyForm(null) { creating = false }
    editing?.let { CompanyForm(it) { editing = null } }
    deleting?.let { DeleteCompanyDialog(it) { deleting = null } }
}

/** The company name has to be typed to confirm. The books are hidden, not erased: the file stays in the data folder and in backups. */
@Composable
private fun DeleteCompanyDialog(company: J, onDismiss: () -> Unit) {
    val app = LocalApp.current
    val name = company.str("name")
    var typed by remember { mutableStateOf("") }
    FormDialog("Delete $name" + if (company.str("fy").isEmpty()) "" else " · FY ${company.str("fy")}", onDismiss, saveLabel = "Delete company",
        canSave = typed.trim().equals(name.trim(), ignoreCase = true), onSave = {
            Api.obj("POST", "/companies/${company.id}/delete", body = mapOf("confirm" to typed))
            app.reloadCompanies(pick = true)
            app.notify("$name deleted")
        }) {
        Text("Its stock, parties, bills and accounts disappear from BillBox. Backups made before today still have them, so it can be brought back from Settings › Backup if needed.")
        Field("Type the company name to confirm", typed, { typed = it }, placeholder = name)
    }
}

@Composable
private fun CompanyForm(company: J?, onDismiss: () -> Unit) {
    val app = LocalApp.current
    val terms = "Goods once sold will not be taken back."
    val f = remember { mutableStateOf(mapOf<String, String>()) }
    fun v(k: String, d: String = "") = f.value[k] ?: (if (company?.has(k) == true) company.str(k) else d)
    fun set(k: String, x: String) { f.value = f.value + (k to x) }
    FormDialog(if (company == null) "New company" else "Edit ${company.str("name")}", onDismiss, canSave = v("name").isNotBlank(), onSave = {
        val body = listOf("name", "company_gstin", "state_code", "company_address", "company_phone", "invoice_terms").associateWith { v(it, if (it == "state_code") "09" else if (it == "invoice_terms") terms else "") }
        if (company != null) { Api.obj("PUT", "/companies/${company.id}", body = body); app.reloadCompanies() }
        else { val r = Api.obj("POST", "/companies", body = body); app.reloadCompanies(); app.switchCompany(r.int("id")) }
    }) {
        Field("Company / business name", v("name"), { set("name", it) })
        Field("GSTIN (blank if unregistered)", v("company_gstin"), { set("company_gstin", it.uppercase()) }, kb = Kb.Caps)
        Field("State code (09 = Uttar Pradesh, 07 = Delhi)", v("state_code", "09"), { set("state_code", it) }, kb = Kb.Number)
        Field("Address", v("company_address"), { set("company_address", it) }, singleLine = false, minLines = 2)
        Field("Phone", v("company_phone"), { set("company_phone", it) }, kb = Kb.Phone)
        Field("Terms printed on invoices", v("invoice_terms", terms), { set("invoice_terms", it) }, singleLine = false)
    }
}

@Composable
private fun PrintingPage() {
    val app = LocalApp.current
    var layout by remember { mutableStateOf(PrintLayout.parse(app.setting("print_layout"))) }
    var afterSave by remember { mutableStateOf(app.setting("bill_after_save").ifEmpty { "print" }) }
    var title by remember { mutableStateOf(app.setting("print_title")) }
    val hidden = remember { mutableStateListOf(*app.setting("print_hide_cols").split(',').filter { it.isNotBlank() }.toTypedArray()) }
    var words by remember { mutableStateOf(app.setting("print_words") != "0") }
    var signature by remember { mutableStateOf(app.setting("print_signature") != "0") }
    var copy1 by remember { mutableStateOf(app.setting("print_copy1")) }
    var copy2 by remember { mutableStateOf(app.setting("print_copy2")) }
    var direct by remember { mutableStateOf(PrintPrefs.direct) }
    Page {
        Choice("Invoice layout", PrintLayout.entries.map { it to it.label }, layout, { layout = it })
        Choice("After saving a bill", listOf("print" to "Print it now", "ask" to "Ask: print now or later", "later" to "Keep it to print later"), afterSave, { afterSave = it })
        Hint("“Keep it to print later”: saved bills wait under All Bills › Not printed; select them and print them together.")
        SectionHeader("What the bill shows")
        Field("Bill title (blank = TAX INVOICE; GST INVOICE in Marg style)", title, { title = it })
        optionalColumns.forEach { (key, t, _) -> SwitchRow("Print the $t column", key !in hidden, { on -> if (on) hidden.remove(key) else hidden.add(key) }) }
        SwitchRow("Print the amount in words", words, { words = it })
        SwitchRow("Print “For company / Authorised Signatory”", signature, { signature = it })
        Field("First copy label (blank = ORIGINAL FOR RECIPIENT)", copy1, { copy1 = it })
        Field("Second copy label (blank = DUPLICATE FOR TRANSPORTER/SUPPLIER)", copy2, { copy2 = it })
        PrintOptions()
        SectionHeader("Printer (this phone)")
        SwitchRow("Skip BillBox's preview: open Android's print screen at once", direct, { direct = it },
            "Android shows its own print screen every time; it remembers the printer you used last. Add a printer in the phone's Settings › Connected devices › Printing (or install your printer's print service app).")
        Hint("“Half sheets”: cut A4 sheets in two (or use A5) and choose A5 paper in Android's print screen once; the Original prints on one sheet and the Duplicate on the next, across the sheet. “Original on top, Duplicate below” fits both copies on one uncut A4 sheet. “Full A4 page” prints each copy on its own A4 sheet, with room for many more item rows.")
        Button(onClick = {
            PrintPrefs.direct = direct
            app.launch {
                app.saveSettings(mapOf("print_layout" to layout.id, "bill_after_save" to afterSave, "print_title" to title.trim(),
                    "print_hide_cols" to optionalColumns.map { it.first }.filter { it in hidden }.joinToString(","),
                    "print_words" to if (words) "1" else "0", "print_signature" to if (signature) "1" else "0", "print_copy1" to copy1.trim(), "print_copy2" to copy2.trim()))
                app.notify("Print settings saved.")
            }
        }, Modifier.fillMaxWidth()) { Text("Save") }
    }
}

@Composable
private fun WhatsAppPage() {
    val app = LocalApp.current
    var auto by remember { mutableStateOf(app.setting("wa_auto") == "1") }
    var cc by remember { mutableStateOf(app.setting("wa_cc").ifEmpty { "91" }) }
    var message by remember { mutableStateOf(app.setting("wa_message")) }
    var test by remember { mutableStateOf("") }
    var pkg by remember { mutableStateOf(WhatsApp.appPackage) }
    suspend fun save(quiet: Boolean) { app.saveSettings(mapOf("wa_auto" to if (auto) "1" else "0", "wa_cc" to cc.filter { it.isDigit() }, "wa_message" to message)); if (!quiet) app.notify("WhatsApp settings saved.") }
    Page {
        val have = listOf("com.whatsapp" to "WhatsApp", "com.whatsapp.w4b" to "WhatsApp Business").filter { WhatsApp.installed(it.first) }
        if (have.isEmpty()) Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Default.Warning, null, tint = Warn); Text("  WhatsApp is not installed on this phone.") }
        else Choice("Send with", listOf("" to "Whichever is installed") + have, pkg, { pkg = it; WhatsApp.appPackage = it })
        SwitchRow("After saving a bill, open WhatsApp with the customer's copy", auto, { auto = it; app.launch { save(true) } })
        Field("Try it: send a test to this number", test, { test = it }, kb = Kb.Phone, placeholder = "10-digit mobile, e.g. your own")
        OutlinedButton(onClick = { WhatsApp.sendTest(test, app) }) { Text("Send test") }
        Field("Country code for 10-digit numbers", cc, { cc = it }, kb = Kb.Number)
        Field("Message sent with the bill", message, { message = it }, singleLine = false, placeholder = WhatsApp.defaultMessage)
        Hint("Each bill goes as one Original copy in PDF form to the customer's mobile number: WhatsApp opens on that customer's chat with the bill attached and the message filled in, and you tap Send. Customers without a number are skipped. Use {name}, {invoice}, {total} and {company} in the message.")
        Button(onClick = { app.launch { save(false) } }, Modifier.fillMaxWidth()) { Text("Save") }
    }
}

private val dashSections = listOf("alerts" to "Alerts (bills to print, low stock, expiry)", "charts" to "Month-by-month chart", "daily" to "Last 14 days chart",
    "items" to "Best sellers", "dues" to "Top dues", "low" to "Low stock list", "recent" to "Latest bills")
private val series = listOf("INV" to "Sale bill", "RCT" to "Receipt", "PUR" to "Purchase", "PAY" to "Payment", "DN" to "Debit note")

/** A setting saved as soon as it changes. */
@Composable
private fun settingChoice(k: String, dflt: String): Pair<String, (String) -> Unit> {
    val app = LocalApp.current
    return app.setting(k).ifEmpty { dflt } to { v: String -> app.launch { app.saveSettings(mapOf(k to v)) }; Unit }
}

/** A text or number setting with its own Save button (checked against a range when it is a number). */
@Composable
private fun SettingField(title: String, key: String, placeholder: String = "", range: ClosedFloatingPointRange<Double>? = null, maxLength: Int = 40) {
    val app = LocalApp.current
    var text by remember { mutableStateOf(app.setting(key)) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Field(title, text, { text = it }, Modifier.weight(1f), kb = if (range != null) Kb.Decimal else Kb.Text, placeholder = placeholder)
        TextButton(enabled = text != app.setting(key), onClick = {
            val t = text.trim().take(maxLength)
            if (range != null && t.isNotEmpty()) { val d = t.toDoubleOrNull(); if (d == null || d !in range) { app.notify("$title: enter a number from ${Fmt.qty(range.start)} to ${Fmt.qty(range.endInclusive)}.", true); return@TextButton } }
            text = t
            app.launch { app.saveSettings(mapOf(key to t)); app.notify("Saved.") }
        }) { Text("Save") }
    }
}

@Composable
private fun BillingDashboardPage() {
    val app = LocalApp.current
    val ui = LocalUi.current
    fun flag(k: String, d: Boolean) = if (app.setting(k).isEmpty()) d else app.setting(k) != "0"
    fun setFlag(k: String, v: Boolean) = app.launch { app.saveSettings(mapOf(k to if (v) "1" else "0")) }
    Page {
        SectionHeader("Billing")
        val (pay, setPay) = settingChoice("bill_pay_mode", "CREDIT")
        Choice("Payment on a new bill", listOf("CREDIT" to "Credit", "CASH" to "Cash", "UPI" to "UPI", "CARD" to "Card"), pay, setPay)
        val (st, setSt) = settingChoice("bill_sale_type", "COUNTER")
        Choice("Sale type on a new bill", listOf("COUNTER" to "Counter", "VAN" to "Van sale"), st, setSt)
        SwitchRow("Round the bill total to the rupee", app.setting("bill_round") != "0", { setFlag("bill_round", it) })
        SettingField("Discount % on every new line", "bill_default_disc", "0", 0.0..100.0)
        SettingField("GST % for new items", "item_default_gst", "18", 0.0..100.0)
        val (unit, setUnit) = settingChoice("bill_new_unit", "box")
        Choice("A new line starts as", listOf("box" to "One box", "piece" to "One piece"), unit, setUnit)
        SwitchRow("Keep the party for the next bill", flag("bill_keep_party", false), { setFlag("bill_keep_party", it) })
        SwitchRow("Ask before billing over a credit limit", flag("bill_credit_check", true), { setFlag("bill_credit_check", it) })
        Hint("Each bill can still be changed before saving. What happens after saving (print now or later) is under Printing.")
        SectionHeader("Dashboard")
        val (per, setPer) = settingChoice("dash_period", "month")
        Choice("Dashboard opens on", listOf("today" to "Today", "month" to "This month", "year" to "Whole year"), per, setPer)
        dashSections.forEach { (k, t) ->
            SwitchRow(t, k !in app.dashboardHidden, { on ->
                val h = app.dashboardHidden.toMutableSet(); if (on) h.remove(k) else h.add(k)
                app.launch { app.saveSettings(mapOf("dash_hide" to dashSections.map { it.first }.filter { it in h }.joinToString(","))) }
            })
        }
        Choice("Open BillBox on", listOf("billing" to "Billing", "dashboard" to "Dashboard", "bills" to "All Bills", "stock" to "Stock", "parties" to "Parties"), ui.startPage, { ui.set("startPage", it); app.prefs.edit().putString("startPage", it).apply() })
        NumberingBlock()
    }
}

@Composable
private fun PartiesPaymentsPage() {
    val app = LocalApp.current
    val ui = LocalUi.current
    Page {
        SectionHeader("New customers start with")
        val (tier, setTier) = settingChoice("party_default_tier", "RETAIL")
        Choice("Price tier", listOf("RETAIL" to "Retail price", "WHOLESALE" to "Wholesale price", "MRP" to "MRP"), tier, setTier)
        SettingField("Credit limit (0 = no limit)", "party_default_limit", "0", 0.0..100_000_000.0)
        SettingField("Credit days", "party_default_days", "0", 0.0..365.0)
        SectionHeader("Payments")
        val (mode, setMode) = settingChoice("pay_default_mode", "CASH")
        Choice("Payment mode", listOf("CASH" to "Cash", "UPI" to "UPI", "CHEQUE" to "Cheque", "BANK" to "Bank transfer", "CARD" to "Card"), mode, setMode)
        SwitchRow("Print the receipt after saving a payment", app.setting("voucher_print") != "0", { v -> app.launch { app.saveSettings(mapOf("voucher_print" to if (v) "1" else "0")) } })
        SwitchRow("Show “Payments from a photo” on Parties", ui.showPhotoCard, { ui.setPhotoCard(it) })
    }
}

@Composable
private fun StockPage() {
    val app = LocalApp.current
    var low by remember { mutableStateOf(Fmt.qty(app.lowStockQty)) }
    Page {
        Field("Low-stock warning at or below (pieces)", low, { low = it }, kb = Kb.Decimal)
        SettingField("Warn about expiry this many days ahead", "expiry_days", "30", 1.0..365.0)
        Button(onClick = { app.launch { app.saveSettings(mapOf("low_stock_qty" to low.trim())); app.notify("Saved.") } }, Modifier.fillMaxWidth()) { Text("Save") }
    }
}

/** "FAILED 2026-10-27T11:13:00.000Z: reason" → the time part in Indian format. */
private fun istStatus(s: String): String {
    if (!s.startsWith("FAILED ")) return s
    val body = s.drop(7); val i = body.indexOf("Z: "); if (i < 0) return s
    return "FAILED " + Fmt.ist(body.take(i) + "Z") + ": " + body.drop(i + 3)
}

private data class RestoreTarget(val name: String? = null, val folder: String? = null, val file: String? = null, val label: String)

/**
 * Settings › Backup › Google Drive: every backup also goes into "BillBox Backups" in the user's Google Drive. Sign-in is
 * Google's code sign-in (a short code entered at google.com/device); the engine does the rest (services/drive.js).
 */
/** The one button style of the Google Drive section: full width, same height. */
@Composable
private fun DriveBtn(title: String, prominent: Boolean = false, destructive: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val m = Modifier.fillMaxWidth().height(48.dp)
    if (prominent) Button(onClick = onClick, enabled = enabled, modifier = m) { Text(title) }
    else OutlinedButton(onClick = onClick, enabled = enabled, modifier = m) {
        if (destructive) Text(title, color = MaterialTheme.colorScheme.error) else Text(title)
    }
}

@Composable
private fun DriveSection(onRestore: (String) -> Unit = {}) {
    val app = LocalApp.current
    var status by remember { mutableStateOf(J()) }
    var clientId by remember { mutableStateOf("") }
    var secret by remember { mutableStateOf("") }
    var editing by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("https://www.google.com/device") }
    var every by remember { mutableIntStateOf(5) }
    var until by remember { mutableStateOf(0L) }
    var busy by remember { mutableStateOf(false) }
    var driveList by remember { mutableStateOf<List<J>?>(null) }
    var keysSaved by remember { mutableStateOf(false) }
    var fetching by remember { mutableStateOf("") }
    suspend fun load() { try { status = Api.get("/backup/drive") } catch (_: Exception) {} }
    LaunchedEffect(Unit) { load() }
    LaunchedEffect(code) {
        if (code.isEmpty()) return@LaunchedEffect
        while (System.currentTimeMillis() < until) {
            kotlinx.coroutines.delay(every * 1000L)
            try {
                if (Api.obj("POST", "/backup/drive/poll", body = emptyMap<String, Any>()).bool("connected")) {
                    code = ""; load(); app.notify("Google Drive connected. Backups now also go to Drive › BillBox Backups."); return@LaunchedEffect
                }
            } catch (e: Exception) {
                if ((e as? com.local.billbox.data.ApiError)?.code == "OFFLINE") continue
                code = ""; app.notify(e.message ?: "Google did not connect.", true); load(); return@LaunchedEffect
            }
        }
        code = ""; app.notify("The code ran out. Press Connect Google Drive again.", true)
    }
    val connected = status.bool("connected")
    val hasKeys = keysSaved || (status.str("client_id").isNotEmpty() && status.bool("has_secret"))
    SectionHeader("Google Drive")
    Text(if (connected) "Connected: backups also go to Google Drive › BillBox Backups" else if (code.isEmpty()) "Not connected" else "Waiting for Google…", fontWeight = FontWeight.Medium,
        color = if (connected) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurface)
    if (connected && status.str("last_upload").isNotEmpty()) Hint("Last upload: ${status.str("last_upload")} · ${if (status.str("last_status") == "ok") "done" else status.str("last_status")}")
    else if (connected && status.str("last_status").startsWith("failed")) Hint(status.str("last_status"), color = MaterialTheme.colorScheme.error)
    if (code.isNotEmpty()) {
        Text("1. Open google.com/device on any phone or computer.\n2. Enter this code and allow BillBox:")
        Text(code, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineMedium, modifier = Modifier.fillMaxWidth())
        DriveBtn("Open google.com/device", prominent = true) { com.local.billbox.system.Platform.openUrl(link) }
        DriveBtn("Copy code") { com.local.billbox.ui.copyText(code); app.notify("Code copied.") }
        DriveBtn("Cancel") { code = "" }
    } else if (connected) {
        DriveBtn(if (busy) "Uploading…" else "Upload the newest backup now", prominent = true, enabled = !busy) { app.launch {
            busy = true
            try { val r = Api.obj("POST", "/backup/drive/upload", body = emptyMap<String, Any>()); app.notify("Uploaded ${r.str("folder")} to Google Drive (${r.int("files")} files).") }
            finally { busy = false; load() }
        } }
        DriveBtn("Restore from Google Drive…", enabled = !busy) { app.launch {
            driveList = emptyList(); busy = true
            try { driveList = Api.list("/backup/drive/list") } catch (e: Exception) { driveList = null; throw e } finally { busy = false }
        } }
        DriveBtn("Disconnect Google Drive", destructive = true, enabled = !busy) { app.launch {
            status = Api.obj("POST", "/backup/drive/disconnect", body = emptyMap<String, Any>())
            app.notify("Google Drive disconnected. Backups stay on this phone; the copies already in Drive are not touched.")
        } }
    } else if (hasKeys && !editing) {
        DriveBtn(if (busy) "Connecting…" else "Connect Google Drive", prominent = true, enabled = !busy) { app.launch {
            busy = true
            try {
                val r = Api.obj("POST", "/backup/drive/connect", body = emptyMap<String, Any>())
                if (r.str("verification_url").isNotEmpty()) link = r.str("verification_url")
                every = maxOf(5, r.int("interval")); until = System.currentTimeMillis() + maxOf(60, r.int("expires_in")) * 1000L
                code = r.str("user_code")
            } finally { busy = false }
        } }
        Hint("Client ID: " + status.str("client_id").substringBefore(".apps.googleusercontent.com").let { if (it.length > 22) it.take(10) + "…" + it.takeLast(8) else it })
        DriveBtn("Change Google keys…", enabled = !busy) { editing = true; clientId = status.str("client_id") }
    } else {
        DriveBtn("Import the downloaded JSON file…", prominent = true, enabled = !busy) { app.launch {
            val (dir, name) = com.local.billbox.system.Platform.importPicked(false, "application/json", "*/*") ?: return@launch
            val text = java.io.File(dir, name).takeIf { it.exists() }?.readText() ?: ""
            if (text.isBlank()) { app.notify("That file could not be read. Download the JSON again in Google Cloud (Credentials › your client › Download JSON).", true); return@launch }
            status = Api.obj("PUT", "/backup/drive/client", body = mapOf("json" to text))
            editing = false; secret = ""; clientId = ""; keysSaved = true
            load()
            app.notify("Google keys imported. Now press Connect Google Drive.")
        } }
        Hint("or paste the two keys:")
        Field("Client ID (…apps.googleusercontent.com)", clientId, { clientId = it })
        Field("Client secret", secret, { secret = it })
        DriveBtn("Save keys", enabled = clientId.isNotBlank() && secret.isNotBlank()) { app.launch {
            status = Api.obj("PUT", "/backup/drive/client", body = mapOf("client_id" to clientId, "client_secret" to secret))
            editing = false; secret = ""; keysSaved = true; load(); app.notify("Google keys saved. Now press Connect Google Drive.")
        } }
        DriveBtn(if (busy) "Connecting…" else "Connect Google Drive", enabled = !busy) { app.launch {
            busy = true
            try {
                val r = Api.obj("POST", "/backup/drive/connect", body = emptyMap<String, Any>())
                if (r.str("verification_url").isNotEmpty()) link = r.str("verification_url")
                every = maxOf(5, r.int("interval")); until = System.currentTimeMillis() + maxOf(60, r.int("expires_in")) * 1000L
                code = r.str("user_code")
            } finally { busy = false }
        } }
        if (hasKeys) DriveBtn("Cancel") { editing = false }
    }
    driveList?.let { list ->
        AlertDialog(onDismissRequest = { if (fetching.isEmpty()) driveList = null }, title = { Text("Restore from Google Drive") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    if (busy) Text("Asking Google Drive…") else if (list.isEmpty()) Text("No backups in Google Drive › BillBox Backups yet.")
                    list.forEach { b ->
                        Column(Modifier.fillMaxWidth().clickable(enabled = fetching.isEmpty()) { app.launch {
                            fetching = b.str("name")
                            try {
                                val r = Api.obj("POST", "/backup/drive/download", body = mapOf("id" to b.str("id"), "name" to b.str("name")))
                                driveList = null
                                if (r.int("downloaded") > 0) app.notify("Brought ${r.str("name")} from Google Drive (${r.int("downloaded")} files).")
                                onRestore(r.str("name"))
                            } finally { fetching = "" }
                        } }.padding(vertical = 10.dp)) {
                            Text(b.str("name"), fontFamily = FontFamily.Monospace)
                            Hint(if (fetching == b.str("name")) "Downloading…" else if (b.bool("on_device")) "Also on this phone" else "Only in Google Drive")
                        }
                        HorizontalDivider()
                    }
                }
            },
            confirmButton = { TextButton({ driveList = null }, enabled = fetching.isEmpty()) { Text("Close") } })
    }
    Hint(if (connected) "Every backup (Back up now, the daily backup and the backup on leaving) is also uploaded to your Google Drive, into a folder with the backup's name inside BillBox Backups. The copy on this phone stays as well. BillBox can see only the files it made itself in your Drive."
        else "One-time setup (about 5 minutes, free): in console.cloud.google.com make a project, turn on the Google Drive API, set up the consent screen (External; add your Gmail as a test user), then Credentials › Create credentials › OAuth client ID › type “TVs and Limited Input devices”. Download its JSON and import it here (or paste the Client ID and secret), then Connect. A client made a minute ago can take a few minutes before Google knows it. The same keys work on the Mac, iPhone and Android.")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BackupPage() {
    val app = LocalApp.current
    var dir by remember { mutableStateOf("") }
    var enabled by remember { mutableStateOf(false) }
    var onExit by remember { mutableStateOf(false) }
    var time by remember { mutableStateOf("22:00") }
    var lastRun by remember { mutableStateOf("") }
    var lastStatus by remember { mutableStateOf("") }
    var backups by remember { mutableStateOf(listOf<J>()) }
    var busy by remember { mutableStateOf(false) }
    val sel = remember { mutableStateListOf<String>() }
    var selecting by remember { mutableStateOf(false) }
    var restoreTarget by remember { mutableStateOf<RestoreTarget?>(null) }
    var deleteNames by remember { mutableStateOf(listOf<String>()) }
    var pickTime by remember { mutableStateOf(false) }
    val inside = File(Engine.homeDir, "DistributorProBackups").absolutePath
    val usb = Platform.context.getExternalFilesDir(null)?.let { File(it, "DistributorProBackups").absolutePath }

    fun fill(r: J) {
        val c = r.obj("config")
        dir = c.str("dir"); enabled = c.bool("enabled"); onExit = c.bool("on_exit"); time = c.str("time").ifEmpty { "22:00" }
        lastRun = c.str("last_run"); lastStatus = c.str("last_status"); backups = r.list("backups")
    }
    suspend fun load() = app.guarded { fill(Api.get("/backup")) }
    LaunchedEffect(Unit) { load() }
    suspend fun setFolder(path: String, label: String) = app.guarded { Api.obj("PUT", "/backup/config", body = mapOf("dir" to path)); fill(Api.get("/backup")); app.notify("Backups will be saved in “$label”.") }

    suspend fun restore(t: RestoreTarget, mode: String) {
        busy = true
        app.guarded {
            Api.obj("PUT", "/backup/config", body = mapOf("dir" to dir.trim()))
            val r = Api.obj("POST", "/backup/restore", body = mapOf("name" to t.name, "folder" to t.folder, "file" to t.file, "company_id" to if (t.file != null) app.companyId else null, "mode" to mode))
            listOfNotNull(t.folder, t.file).forEach { f -> if (f.startsWith(Platform.context.cacheDir.absolutePath)) runCatching { File(f).let { x -> generateSequence(x) { it.parentFile }.firstOrNull { it.parentFile?.absolutePath == Platform.context.cacheDir.absolutePath }?.deleteRecursively() } } }
            app.reloadCompanies(pick = true)
            fill(Api.get("/backup"))
            if (mode == "merge") {
                var added = 0; val conflicts = mutableListOf<String>()
                for (m in r.list("merged")) { val a = m.obj("added"); a.o.keys().forEach { k -> added += a.int(k) }; conflicts += m.strings("conflicts") }
                app.notify("Merged $added new record${if (added == 1) "" else "s"} into " + r.strings("restored").joinToString(", ") + if (conflicts.isEmpty()) "." else ". ${conflicts.size} bill number${if (conflicts.size == 1) "" else "s"} clashed and were left as they are.")
            } else app.notify("Restored: " + r.strings("restored").joinToString(", ") + ".")
        }
        busy = false
    }
    suspend fun restoreFromFiles(single: Boolean, folder: Boolean) {
        val (root, name) = (if (folder) Platform.importPicked(true) else Platform.importPicked(false, "application/zip", "application/octet-stream", "*/*")) ?: return
        busy = true
        try {
            val (f, db) = Platform.locateBackup(root)
            restoreTarget = when {
                f != null && !single -> RestoreTarget(folder = f.absolutePath, label = name)
                db != null -> RestoreTarget(file = db.absolutePath, label = db.name)
                f != null -> RestoreTarget(folder = f.absolutePath, label = name)
                else -> { app.notify("“$name” has no BillBox backup in it (no manifest.json and no company .db file).", true); null }
            }
        } finally { busy = false }
    }

    Page {
        Text("Backup folder", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if (dir == inside) "On this phone (BillBox's own storage)" else if (dir == usb) "On this phone, visible over USB: Android › data › ${Platform.context.packageName} › files › DistributorProBackups" else dir, fontWeight = FontWeight.Medium)
        if (dir != inside) OutlinedButton(onClick = { app.launch { setFolder(inside, "BillBox's own storage") } }, enabled = !busy) { Text("Use BillBox's own storage") }
        if (usb != null && dir != usb) OutlinedButton(onClick = { app.launch { setFolder(usb, "phone storage, visible over USB") } }, enabled = !busy) { Text("Use a folder visible over USB") }
        SwitchRow("Back up automatically every day", enabled, { enabled = it })
        SwitchRow("Also back up whenever I leave the app", onExit, { onExit = it })
        Row(verticalAlignment = Alignment.CenterVertically) { Text("Time", Modifier.weight(1f)); OutlinedButton(onClick = { pickTime = true }) { Text(time) } }
        if (lastRun.isNotEmpty()) Hint("Last backup: ${Fmt.ist(lastRun)} · ${istStatus(lastStatus)}")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { app.launch {
                Api.obj("PUT", "/backup/config", body = mapOf("dir" to dir.trim(), "enabled" to enabled, "on_exit" to onExit, "time" to time))
                app.notify(if (enabled) "Saved. A backup will run every day at $time." else "Saved. Automatic backup is off.")
            } }) { Text("Save settings") }
            Button(onClick = { app.launch {
                busy = true
                try { app.guarded { Api.obj("PUT", "/backup/config", body = mapOf("dir" to dir.trim())); val r = Api.obj("POST", "/backup/run", body = emptyMap<String, Any>()); app.notify("Backup complete: " + r.str("folder").substringAfterLast('/')) }; load() }
                finally { busy = false }
            } }, enabled = !busy) { Text(if (busy) "Backing up…" else "Back up now") }
        }
        Hint("Every backup is kept for good; nothing is deleted automatically. While BillBox is open the daily backup runs at its time; when BillBox is closed Android runs it within about an hour of the time. Leaving the app counts as quitting. To keep a copy off the phone, select a backup below and use Save a copy (Drive, a USB drive, Downloads…).")

        DriveSection(onRestore = { n -> restoreTarget = RestoreTarget(name = n, label = n); app.launch { load() } })

        SectionHeader("Restore")
        val picked = backups.firstOrNull { it.str("name") in sel }
        OutlinedButton(onClick = { picked?.let { restoreTarget = RestoreTarget(name = it.str("name"), label = it.str("name")) } }, enabled = picked != null && !busy) { Text("Restore selected backup…") }
        OutlinedButton(onClick = { app.launch { restoreFromFiles(single = false, folder = true) } }, enabled = !busy) { Text("Restore from a backup folder…") }
        OutlinedButton(onClick = { app.launch { restoreFromFiles(single = false, folder = false) } }, enabled = !busy) { Text("Restore from a .zip of a backup…") }
        OutlinedButton(onClick = { app.launch { restoreFromFiles(single = true, folder = false) } }, enabled = !busy) { Text("Restore one company file (.db)…") }

        SectionHeader("Backups")
        SelectionBar(sel.size, backups.size, selecting, { selecting = it; if (!it) sel.clear() }, { if (sel.size == backups.size) sel.clear() else { sel.clear(); sel.addAll(backups.map { it.str("name") }) } },
            actionLabel = "Delete", busy = busy) { deleteNames = backups.filter { it.str("name") in sel }.map { it.str("name") } }
        Box(Modifier.fillMaxWidth().height(minOf(440, maxOf(backups.size, 3) * 44 + 60).dp)) {
            DataTable(backups, "backups", selected = sel.toSet(), keyOf = { it.str("name") }, selecting = selecting,
                onToggle = { b -> val n = b.str("name"); if (n in sel) sel.remove(n) else sel.add(n) },
                onOpen = { b -> sel.clear(); sel.add(b.str("name")) },
                menu = { b -> listOf(
                    RowAction("Restore this backup…") { restoreTarget = RestoreTarget(name = b.str("name"), label = b.str("name")) },
                    RowAction("Save a copy to…") { app.launch {
                        val folder = File(dir, b.str("name"))
                        if (Platform.saveFolder(b.str("name"), folder.listFiles()?.filter { it.isFile } ?: emptyList())) app.notify("Copied ${b.str("name")}.")
                    } },
                    RowAction("Delete this backup…", destructive = true) { deleteNames = listOf(b.str("name")) },
                ) },
                columns = listOf(
                    Col("Backup", "name", 250) { b -> Cell(b.str("name"), bold = b.str("name") in sel && !selecting) },
                    Col("Companies", "companies", 220) { b -> Cell(b.strings("companies").joinToString(", "), lines = 2) },
                    Col("Created", "created", 170) { b -> Cell(Fmt.ist(b.str("created"))) },
                    Col("Company files", "files", 100, end = true) { b -> Cell(b.str("files"), end = true) },
                    Col("Size", "size", 100, end = true) { b -> Cell(android.text.format.Formatter.formatShortFileSize(Platform.context, b.num("bytes").toLong()), end = true) },
                ))
        }
        Hint("Each backup is a new folder named FMCG_Backup_YYYYMMDD_HHMMSS holding a verified copy of every company's database — the same backup the Mac and iPhone make, so it restores on any of them. Each company is restored into the company with the same name (it is created if missing); other companies are not touched. The files are checked first, and a safety backup of today's data is made before anything is replaced. Long-press a backup for Save a copy, Restore or Delete.")
    }

    if (pickTime) {
        val p = time.split(":").mapNotNull { it.toIntOrNull() }
        val st = rememberTimePickerState(p.getOrElse(0) { 22 }, p.getOrElse(1) { 0 }, is24Hour = false)
        AlertDialog(onDismissRequest = { pickTime = false }, text = { TimePicker(st) },
            confirmButton = { TextButton({ time = String.format(java.util.Locale.US, "%02d:%02d", st.hour, st.minute); pickTime = false }) { Text("OK") } },
            dismissButton = { TextButton({ pickTime = false }) { Text("Cancel") } })
    }
    restoreTarget?.let { t ->
        AlertDialog(onDismissRequest = { restoreTarget = null }, title = { Text("Restore ${t.label}?") },
            text = { Text((if (t.file != null) "This goes into the company that file belongs to (matched by name). " else "Each company goes into the company with the same name here (it is created if missing). ") +
                "\n\nReplace: the current books of that company are replaced by the backup.\nMerge: only what is missing is added from the backup (parties, items, bills, receipts and so on); nothing that already exists is changed or removed.\n\nA safety backup of the current data is made first either way.") },
            confirmButton = { Row {
                TextButton({ restoreTarget = null; app.launch { restore(t, "merge") } }) { Text("Merge") }
                TextButton({ restoreTarget = null; app.launch { restore(t, "replace") } }) { Text("Replace", color = MaterialTheme.colorScheme.error) }
            } },
            dismissButton = { TextButton({ restoreTarget = null }) { Text("Cancel") } })
    }
    if (deleteNames.isNotEmpty()) {
        val names = deleteNames
        Confirm(if (names.size == 1) "Delete backup ${names[0]}?" else "Delete ${names.size} selected backups?",
            if (names.size == 1) "The backup folder is removed for good. Your current books are not affected." else "The backup folders are removed for good. Your current books are not affected.", "Delete", {
                app.launch {
                    busy = true; var deleted = 0
                    for (n in names) app.guarded { Api.obj("DELETE", "/backup/${Api.seg(n)}"); deleted++ }
                    load(); sel.clear(); busy = false
                    if (names.size == 1 && deleted == 1) app.notify("Deleted ${names[0]}.") else if (deleted > 0) app.notify("Deleted $deleted backup${if (deleted == 1) "" else "s"}.")
                }
            }, { deleteNames = emptyList() }, destructive = true)
    }
}

/**
 * Settings › Import from Marg ERP: reads a Marg CSV backup (the .zip, or the folder it unzips to), shows what it holds and
 * checks it against Marg's own figures, then imports items, parties with opening balances, bills, debit notes, receipts and
 * payments into the open company. Importing the same backup again adds nothing twice.
 */
@Composable
private fun MargImportPage() {
    val app = LocalApp.current
    var path by remember { mutableStateOf<String?>(null) }
    var picked by remember { mutableStateOf("") }
    var report by remember { mutableStateOf<J?>(null) }
    var result by remember { mutableStateOf<J?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirm by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    suspend fun choose(folder: Boolean) {
        val (root, name) = (if (folder) Platform.importPicked(true) else Platform.importPicked(false, "application/zip", "application/octet-stream")) ?: return
        picked = name; busy = true; errorText = null; report = null; result = null
        try { report = Api.obj("POST", "/import/marg/preview", body = mapOf("path" to root.absolutePath)); path = root.absolutePath } catch (e: Exception) { errorText = e.message } finally { busy = false }
    }
    Page {
        Hint("In Marg: Reports › Management Report › Data Transfer Utility › Export All Data › CSV. Pick the folder Marg wrote the CSV files to (or a .zip of it). Nothing is changed until you press Import.")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { app.launch { choose(false) } }, enabled = !busy) { Text("Choose a .zip…") }
            OutlinedButton(onClick = { app.launch { choose(true) } }, enabled = !busy) { Text("Choose a folder…") }
        }
        if (picked.isNotEmpty()) Hint(picked)
        if (busy) Loading()
        ErrorText(errorText)
        val r = result ?: report
        if (r != null) {
            val f = r.obj("found"); val t = r.obj("totals"); val per = r.obj("period")
            SectionHeader(if (per.str("from").isEmpty()) "In the backup" else "In the backup: ${Fmt.dmy(per.str("from"))} to ${Fmt.dmy(per.str("to"))}")
            InfoLine("Items", "${f.int("items")}"); InfoLine("Customers", "${f.int("customers")}"); InfoLine("Suppliers", "${f.int("suppliers")}")
            InfoLine("Sale bills", "${f.int("sales")}  ·  ${Fmt.money(t, "sales")}"); InfoLine("Purchase bills", "${f.int("purchases")}  ·  ${Fmt.money(t, "purchases")}")
            InfoLine("Debit notes", "${f.int("debit_notes")}  ·  ${Fmt.money(t, "debit_notes")}"); InfoLine("Receipts", "${f.int("receipts")}  ·  ${Fmt.money(t, "receipts")}")
            InfoLine("Payments", "${f.int("payments")}  ·  ${Fmt.money(t, "payments")}")
            InfoLine("Opening: customers owe", Fmt.money(t, "opening_receivable")); InfoLine("Opening: you owe suppliers", Fmt.money(t, "opening_payable"))
            SectionHeader("Checked against Marg")
            val c = r.obj("checks")
            listOf("Bill totals" to c.obj("bills"), "Party closing balances" to c.obj("party_balances"), "Item closing stock" to c.obj("stock")).forEach { (title, x) ->
                val problems = x.strings("problems")
                var open by remember { mutableStateOf(false) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (problems.isEmpty()) Icons.Default.CheckCircle else Icons.Default.Warning, null, tint = if (problems.isEmpty()) Good else Warn)
                    Text("  $title", Modifier.weight(1f)); Hint("${x.int("ok")} of ${x.int("checked")} match")
                }
                if (problems.isNotEmpty()) {
                    TextButton(onClick = { open = !open }) { Text("${problems.size} differ") }
                    if (open) problems.take(50).forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
            }
            val cleaning = r.strings("cleaning"); val warnings = r.strings("warnings")
            if (cleaning.isNotEmpty() || warnings.isNotEmpty()) {
                SectionHeader("Cleaned up")
                cleaning.forEach { Text(it) }; warnings.forEach { Text(it, color = Warn) }
            }
            val done = result != null
            val a = r.obj(if (done) "added" else "would_add"); val h = r.obj("already_here")
            SectionHeader(if (done) "Imported into ${app.companyName}" else "Importing adds to ${app.companyName}")
            InfoLine("Items", "${a.int("items")}" + if (h.int("items") > 0) "  (${h.int("items")} already here)" else "")
            InfoLine("Categories", "${a.int("categories")}")
            InfoLine("Customers / suppliers", "${a.int("customers")} / ${a.int("suppliers")}" + if (h.int("parties") > 0) "  (${h.int("parties")} already here)" else "")
            InfoLine("Sale / purchase bills", "${a.int("sales")} / ${a.int("purchases")}" + if (h.int("bills") > 0) "  (${h.int("bills")} already here)" else "")
            InfoLine("Debit notes", "${a.int("debit_notes")}")
            InfoLine("Receipts / payments", "${a.int("receipts")} / ${a.int("payments")}" + if (h.int("vouchers") > 0) "  (${h.int("vouchers")} already here)" else "")
            if (!done) Button(onClick = { confirm = true }, enabled = !busy && path != null) { Text("Import into ${app.companyName}") }
            else {
                Hint("Done. Stock, ledgers, All Bills and the GST books now include the Marg data.")
                val nb = r.obj("numbering")
                val parts = listOf("sale bill" to "INV", "purchase" to "PUR", "debit note" to "DN").filter { nb.str(it.second).isNotEmpty() }.map { "next ${it.first} ${nb.str(it.second)}" }
                if (parts.isNotEmpty()) Text("New bills carry on Marg's numbering: ${parts.joinToString(", ")}. Change it in Settings › Billing & Dashboard › Numbering.")
            }
        }
        path?.let { MargPriceFix(it) }
    }
    if (confirm) Confirm("Import this Marg backup into ${app.companyName}?", "Items, parties, bills, debit notes, receipts and payments that are not already here are added. Anything with the same name or number is left as it is.", "Import", {
        val p = path ?: return@Confirm
        app.launch {
            busy = true
            try {
                val r = Api.obj("POST", "/import/marg", body = mapOf("path" to p)); result = r
                val a = r.obj("added")
                app.notify("Imported from Marg: ${a.int("items")} items, ${a.int("customers") + a.int("suppliers")} parties, ${a.int("sales") + a.int("purchases")} bills, ${a.int("debit_notes")} debit notes.")
            } catch (e: Exception) { errorText = e.message } finally { busy = false }
        }
    }, { confirm = false })
}

/** Items already in the books whose price is far off the Marg backup (an earlier BillBox worked some out per box instead of
 *  per piece): listed, then put right on Correct. */
@Composable
private fun MargPriceFix(path: String) {
    val app = LocalApp.current
    var check by remember { mutableStateOf<J?>(null) }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    fun run(apply: Boolean) = app.launch {
        busy = true; err = null
        try {
            check = Api.obj("POST", "/import/marg/prices", body = mapOf("path" to path, "apply" to apply))
            if (apply) app.notify("Corrected the prices of ${check?.int("changed") ?: 0} items.")
        } catch (e: Exception) { err = e.message } finally { busy = false }
    }
    SectionHeader("Prices of items already here")
    OutlinedButton(onClick = { run(false) }, enabled = !busy) { Text("Check item prices against this backup") }
    ErrorText(err)
    check?.let { c ->
        val rows = c.list("items")
        when {
            c.bool("applied") -> Text("Corrected the prices of ${c.int("changed")} items.")
            rows.isEmpty() -> Hint("All ${c.int("checked")} items already here match the backup.")
            else -> {
                Text("${rows.size} of ${c.int("checked")} items have a price far off the backup (per piece, ex-GST):")
                rows.take(40).forEach { r -> InfoLine(r.str("name"), "${Fmt.rate(r.num("retail_old"))} → ${Fmt.rate(r.num("retail_new"))}") }
                if (rows.size > 40) Hint("…and ${rows.size - 40} more")
                Button(onClick = { run(true) }, enabled = !busy) { Text("Correct ${rows.size} prices") }
            }
        }
    }
    Hint("Only prices at least twice or half of what Marg says are changed (an earlier BillBox read some Marg rates per box instead of per piece). Prices you changed by a little are kept.")
}

/** Settings › Printing: what else the bill shows, its size, a third copy and lines of your own (saved as you change them). */
@Composable
private fun PrintOptions() {
    val app = LocalApp.current
    fun flag(k: String, d: Boolean) = if (app.setting(k).isEmpty()) d else app.setting(k) != "0"
    fun setFlag(k: String, v: Boolean) = app.launch { app.saveSettings(mapOf(k to if (v) "1" else "0")) }
    SectionHeader("Bill design")
    val (style, setStyle) = settingChoice("print_style", "classic")
    Choice("Bill design", com.local.billbox.print.billDesigns, style, setStyle)
    OutlinedButton(onClick = { app.launch {
        val r = Api.obj("GET", "/bills", query = mapOf("type" to "SALE", "from" to "2000-01-01", "to" to "2100-12-31"))
        val id = r.list("rows").firstOrNull()?.int("id")
        if (id == null) app.notify("There is no sale bill yet to show.", true) else com.local.billbox.print.Printing.invoice(id, app, true)
    } }) { Text("Preview on my latest bill") }
    Hint("Every design uses the paper layout, copies, text size and everything else on this page. Marg, Busy and Bizom styles share the choices below (colour, typeface, columns…).")
    if (style !in setOf("marg", "busy", "bizom")) {
        SectionHeader("BillBox design")
        val (face, setFace) = settingChoice("print_marg_font", "serif")
        Choice("Typeface", listOf("serif" to "Classic serif (like Marg)", "sans" to "Modern"), face, setFace)
        SwitchRow("“M/s” before the party's name", flag("print_marg_ms", true), { setFlag("print_marg_ms", it) })
        Hint("Bill to prints as on a Marg bill; the tax summary is HSN-wise, with Total GST (or IGST for another state).")
    }
    if (style in setOf("marg", "busy", "bizom")) {
        SectionHeader(when (style) { "busy" -> "Busy style"; "bizom" -> "Bizom style"; else -> "Marg style" })
        val (colour, setColour) = settingChoice("print_marg_colour", "blue")
        Choice("Colour", com.local.billbox.print.margColours, colour, setColour)
        val (face, setFace) = settingChoice("print_marg_font", if (style == "marg") "serif" else "sans")
        Choice("Typeface", listOf("serif" to "Classic serif (like Marg)", "sans" to "Modern"), face, setFace)
        val (per, setPer) = settingChoice("print_marg_rate", "box")
        Choice("Rate and MRP per", listOf("box" to "Box (like Marg)", "pcs" to "Piece"), per, setPer)
        val (cls, setCls) = settingChoice("print_marg_classes", "all")
        Choice("GST classes at the bottom", listOf("all" to "5, 12, 18 and 28 always (like Marg)", "used" to "Only the rates on the bill"), cls, setCls)
        val shown = com.local.billbox.print.margShown(app.settings)
        com.local.billbox.print.margOptionalColumns.forEach { (k, title, _) ->
            SwitchRow("$title column", k in shown, { v ->
                val on = shown.toMutableSet(); if (v) on.add(k) else on.remove(k)
                val list = com.local.billbox.print.margOptionalColumns.map { it.first }.filter { it in on }.joinToString(",")
                app.launch { app.saveSettings(mapOf("print_marg_cols" to list.ifEmpty { "none" })) }
            })
        }
        SwitchRow("“M/s” before the party's name", flag("print_marg_ms", true), { setFlag("print_marg_ms", it) })
        SwitchRow("Due date on credit bills (party's credit days)", flag("print_marg_due", true), { setFlag("print_marg_due", it) })
        SwitchRow("Receiver's signature box", flag("print_marg_receiver", true), { setFlag("print_marg_receiver", it) })
        SwitchRow("Page number", flag("print_marg_page", true), { setFlag("print_marg_page", it) })
        SwitchRow("Company e-mail", flag("print_marg_email", false), { setFlag("print_marg_email", it) })
        if (app.setting("print_marg_email") == "1") SettingField("E-mail", "company_email", "you@example.com", maxLength = 80)
        Hint("Title: “Bill title” on the Printing page (blank = GST INVOICE). A bill to another state shows IGST instead of SGST and CGST. “Black only” suits printers without colour.")
    }
    SectionHeader("More on the bill")
    SwitchRow("Party's address, GSTIN and phone", flag("print_party", true), { setFlag("print_party", it) })
    SwitchRow("Salesman", flag("print_salesman", true), { setFlag("print_salesman", it) })
    SwitchRow("Payment mode and sale type", flag("print_payment", true), { setFlag("print_payment", it) })
    SwitchRow("GST rate-wise table", flag("print_gst_table", true), { setFlag("print_gst_table", it) })
    SwitchRow("Terms", flag("print_terms", true), { setFlag("print_terms", it) })
    SwitchRow("Party's previous balance and total due", flag("print_balance", false), { setFlag("print_balance", it) },
        "Prints “Previous balance · This bill · Now due” above the amount in words, from the party's ledger.")
    SwitchRow("Item names in CAPITALS", flag("print_caps", false), { setFlag("print_caps", it) })
    SwitchRow("Company and Bill to in CAPITALS", flag("print_caps_head", false), { setFlag("print_caps_head", it) })
    val (qty, setQty) = settingChoice("print_qty", "boxpcs")
    Choice("Quantity as", listOf("boxpcs" to "Boxes and pieces (6 box 6 pcs)", "pcs" to "Pieces only (150 pcs)"), qty, setQty)
    SectionHeader("Size and copies")
    val (font, setFont) = settingChoice("print_font", "normal")
    Choice("Text size", listOf("small" to "Smaller (more rows on a page)", "normal" to "Normal", "large" to "Larger (easier to read)"), font, setFont)
    SwitchRow("Print ORIGINAL / DUPLICATE on each copy", flag("print_copy_label", true), { setFlag("print_copy_label", it) })
    SwitchRow("Print a third copy", flag("print_triplicate", false), { setFlag("print_triplicate", it) }, "Half-sheet and full-A4 layouts; two-on-A4 keeps its two copies.")
    if (app.setting("print_triplicate") == "1") SettingField("Third copy label", "print_copy3", "TRIPLICATE FOR ASSESSEE")
    SectionHeader("Your own lines")
    SettingField("Line under the company name", "print_tagline", "e.g. Distributor of Parle, Bikano", maxLength = 80)
    SettingField("Payment line at the bottom", "print_bank", "e.g. UPI ak@upi", maxLength = 120)
    SettingField("Note at the bottom", "print_note", "e.g. Thank you for your business", maxLength = 60)
    Hint("Leave a line empty to leave it off the bill.")
    SectionHeader("Bank details")
    SwitchRow("Print the bank details", flag("print_bank_block", true), { setFlag("print_bank_block", it) })
    SwitchRow("Compact totals (more item rows on each page)", flag("print_compact", true), { setFlag("print_compact", it) })
    val (bankSz, setBankSz) = settingChoice("print_bank_size", "m")
    Choice("Bank details size", listOf("s" to "Small", "m" to "Normal", "l" to "Large", "xl" to "Extra large"), bankSz, setBankSz)
    listOf("bank_name" to "Bank name", "bank_ac_name" to "Account name", "bank_ac_no" to "Account number", "bank_ifsc" to "IFSC code",
        "bank_branch" to "Branch name", "bank_branch_code" to "Branch code", "bank_address" to "Branch address").forEach { (k, title) ->
        SettingField(title, k, "", maxLength = if (k == "bank_address") 200 else 60)
    }
    Hint("Printed in three short lines (Bank · A/c name / A/c no. · IFSC / Branch · address) where the bill has room anyway: in the footer of the BillBox design, under the GST classes of the Marg style. Item rows are not reduced. Empty ones are left out.")
}

/**
 * Settings › Billing & Dashboard › Numbering: prefix and digits for each series, the year in the number or not, the last
 * number used and the next one (it carries on after the last bill, Marg's imported bills included), and Marg's pattern.
 */
@Composable
private fun NumberingBlock() {
    val app = LocalApp.current
    var rows by remember { mutableStateOf(listOf<J>()) }
    val next = remember { androidx.compose.runtime.mutableStateMapOf<String, String>() }
    suspend fun load() { app.guarded { rows = Api.get("/numbering").list("series") } }
    LaunchedEffect(app.settings) { load() }
    fun flag(k: String, d: Boolean) = if (app.setting(k).isEmpty()) d else app.setting(k) != "0"
    SectionHeader("Numbering")
    OutlinedButton(onClick = {
        app.launch {
            app.saveSettings(mapOf("num_fy" to "0", "num_INV_prefix" to "A", "num_INV_digits" to "6", "num_PUR_prefix" to "P", "num_PUR_digits" to "6", "num_DN_prefix" to "DNB", "num_DN_digits" to "5"))
            load(); rows.firstOrNull { it.str("series") == "INV" }?.let { app.notify("Marg numbering on: the next sale bill is ${it.str("next_no")}.") }
        }
    }) { Text("Use Marg's numbering (A000001, P000001, DNB00001)") }
    SwitchRow("Put the financial year in the number", flag("num_fy", true), { v -> app.launch { app.saveSettings(mapOf("num_fy" to if (v) "1" else "0")) } })
    val (dg, setDg) = settingChoice("num_digits", "5")
    Choice("Digits (series without their own)", listOf("3", "4", "5", "6").map { it to it }, dg, setDg)
    Hint("A new number always carries on after the highest one already used with the same prefix — including bills imported from Marg — so numbers never clash. After a Marg import BillBox takes Marg's pattern by itself, unless you chose your own numbering here first.")
    series.forEach { (k, t) ->
        val r = rows.firstOrNull { it.str("series") == k }
        Column(Modifier.fillMaxWidth().panel(10.dp).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(t, style = MaterialTheme.typography.titleSmall)
            SettingField("Prefix", "num_${k}_prefix", k, maxLength = 8)
            val (d, setD) = settingChoice("num_${k}_digits", "")
            Choice("Digits", listOf("" to "Same as above") + listOf("3", "4", "5", "6", "7", "8").map { it to it }, d, setD)
            if (r != null) {
                InfoLine("Last used", r.str("last_no").ifEmpty { "none yet" })
                InfoLine("Next", r.str("next_no"), bold = true)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Field("Start the next one at (number)", next[k] ?: "", { next[k] = it }, Modifier.weight(1f), kb = Kb.Number)
                    TextButton(enabled = !(next[k] ?: "").isBlank(), onClick = {
                        app.launch {
                            val x = Api.obj("PUT", "/numbering", body = mapOf("series" to k, "next" to (next[k] ?: "").trim()))
                            next[k] = ""; app.notify("The next one will be ${x.str("next_no")}."); load()
                        }
                    }) { Text("Set") }
                }
            }
        }
    }
}
