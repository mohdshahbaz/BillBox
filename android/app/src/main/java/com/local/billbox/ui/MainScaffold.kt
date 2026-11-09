package com.local.billbox.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ReceiptLong
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.KeyboardReturn
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PointOfSale
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Business
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.local.billbox.data.AppState
import com.local.billbox.data.Page
import com.local.billbox.print.PrintPreviewDialog
import com.local.billbox.screens.BillingScreen
import com.local.billbox.screens.BillsScreen
import com.local.billbox.screens.DashboardScreen
import com.local.billbox.screens.DebitNotesScreen
import com.local.billbox.screens.PartiesScreen
import com.local.billbox.screens.PurchasesScreen
import com.local.billbox.screens.ReportsScreen
import com.local.billbox.screens.SalesmenScreen
import com.local.billbox.screens.SettingsScreen
import com.local.billbox.screens.StockScreen
import com.local.billbox.system.CrashCatcher
import com.local.billbox.system.Platform

val LocalApp = staticCompositionLocalOf<AppState> { error("AppState not provided") }
/** Back arrow for a screen opened from More (phones). */
val LocalBack = compositionLocalOf<(() -> Unit)?> { null }

val Page.icon: ImageVector get() = when (this) {
    Page.Dashboard -> Icons.Default.Dashboard
    Page.Billing -> Icons.Default.PointOfSale
    Page.Purchases -> Icons.Default.LocalShipping
    Page.Bills -> Icons.AutoMirrored.Filled.ReceiptLong
    Page.Stock -> Icons.Default.Inventory2
    Page.Parties -> Icons.Default.People
    Page.Salesmen -> Icons.Default.Badge
    Page.Reports -> Icons.Default.Assessment
    Page.Settings -> Icons.Default.Settings
    Page.DebitNotes -> Icons.Default.KeyboardReturn
}

private val tabs = listOf(Page.Billing, Page.Bills, Page.Stock, Page.Parties)
private val more = listOf(Page.Purchases, Page.DebitNotes, Page.Salesmen, Page.Dashboard, Page.Reports, Page.Settings)
/** The Mac's order (its ⌘1 … ⌘9, ⌘0). */
private val railOrder = listOf(Page.Dashboard, Page.Billing, Page.Purchases, Page.Bills, Page.Stock, Page.Parties, Page.Salesmen, Page.Reports, Page.Settings, Page.DebitNotes)

@Composable
fun MainScaffold(app: AppState) {
    CompositionLocalProvider(LocalApp provides app) {
        LaunchedEffect(Unit) { if (!app.ready) app.start() }
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.fillMaxSize()) {
                when {
                    !app.ready -> Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(); Text("Opening your books…", Modifier.padding(top = 16.dp))
                    }
                    app.startError != null -> Column(Modifier.fillMaxSize().padding(30.dp), verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.Warning, null, Modifier.size(44.dp), tint = Warn)
                        Text("The books could not be opened", style = MaterialTheme.typography.titleLarge)
                        Text(app.startError ?: "", textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onClick = { app.launch { app.start() } }) { Text("Try again") }
                    }
                    else -> key(app.companyId, app.fy) { Shell(app) }
                }
                ToastHost(app)
            }
        }
        val job = app.printJob
        if (job != null) PrintPreviewDialog(job) { app.printJob = null }
        var crash by remember { mutableStateOf(CrashCatcher.pendingReport()) }
        crash?.let { text ->
            AlertDialog(onDismissRequest = { crash = null; CrashCatcher.clear() },
                title = { Text("BillBox closed unexpectedly last time") },
                text = { Column(Modifier.verticalScroll(rememberScrollState())) { Hint("This is what happened. Share it so the problem can be fixed; nothing is sent unless you share it."); SelectionContainer { Text(text, style = MaterialTheme.typography.bodySmall) } } },
                confirmButton = { TextButton({ Platform.shareText(text, "Share crash report") }) { Text("Share") } },
                dismissButton = { TextButton({ crash = null; CrashCatcher.clear() }) { Text("Close") } })
        }
    }
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun Shell(app: AppState) {
    val wide = LocalConfiguration.current.screenWidthDp >= 600
    var moreList by rememberSaveable { mutableStateOf(app.section !in tabs && app.section !in more) }
    if (wide) {
        Row(Modifier.fillMaxSize().navigationBarsPadding()) {
            NavigationRail(Modifier.verticalScroll(rememberScrollState())) {
                railOrder.forEach { p ->
                    NavigationRailItem(selected = app.section == p, onClick = { app.section = p }, icon = { Icon(p.icon, null) },
                        label = { Text(p.title, maxLines = 1, style = MaterialTheme.typography.labelSmall) })
                }
            }
            Box(Modifier.weight(1f)) { PageContent(app.section) }
        }
    } else {
        val inMore = app.section in more
        // the tab bar steps aside while the keyboard is up, so the bill and its totals get the whole height above the keyboard
        val keyboard = WindowInsets.isImeVisible
        Scaffold(bottomBar = {
            if (!keyboard) NavigationBar {
                tabs.forEach { p ->
                    NavigationBarItem(selected = app.section == p, onClick = { app.section = p; moreList = false }, icon = { Icon(p.icon, null) }, label = { Text(p.title, maxLines = 1) })
                }
                NavigationBarItem(selected = inMore, onClick = { if (inMore) moreList = true else { moreList = true; app.section = Page.Dashboard } },
                    icon = { Icon(Icons.Default.MoreHoriz, null) }, label = { Text("More") })
            }
        }, contentWindowInsets = WindowInsets(0)) { pad ->
            Box(Modifier.fillMaxSize().padding(pad)) {
                if (inMore && moreList) MoreList { app.section = it; moreList = false }
                else if (inMore) {
                    BackHandler { moreList = true }
                    CompositionLocalProvider(LocalBack provides { moreList = true }) { PageContent(app.section) }
                } else PageContent(app.section)
            }
        }
        // system back on a tab other than the start screen goes to the start screen, as Android apps do
        val start = Page.of(LocalUi.current.startPage) ?: Page.Billing
        BackHandler(enabled = !inMore && app.section != start) { app.section = start }
    }
}

@Composable
private fun PageContent(p: Page) {
    when (p) {
        Page.Dashboard -> DashboardScreen()
        Page.Billing -> BillingScreen()
        Page.Purchases -> PurchasesScreen()
        Page.Bills -> BillsScreen()
        Page.Stock -> StockScreen()
        Page.Parties -> PartiesScreen()
        Page.Salesmen -> SalesmenScreen()
        Page.Reports -> ReportsScreen()
        Page.Settings -> SettingsScreen()
        Page.DebitNotes -> DebitNotesScreen()
    }
}

@Composable
private fun MoreList(open: (Page) -> Unit) {
    ScreenScaffold("More") {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            more.forEach { p ->
                ListItem(headlineContent = { Text(p.title) }, leadingContent = { Icon(p.icon, null, tint = MaterialTheme.colorScheme.primary) },
                    trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null) }, modifier = Modifier.clickable { open(p) })
                HorizontalDivider()
            }
        }
    }
}

/**
 * A screen with Android's top app bar: the screen's title over the company and financial year (tap to switch), the
 * screen's actions on the right, and a floating action button when it has a main action.
 */
/** Room the lists leave free at their end so the last rows can scroll clear of a floating button (New item, New party…). */
val LocalFabSpace = staticCompositionLocalOf { 0.dp }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenScaffold(title: String, actions: @Composable RowScope.() -> Unit = {}, fab: (@Composable () -> Unit)? = null,
                   content: @Composable (Modifier) -> Unit) {
    val back = LocalBack.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { CompanyYearTitle(title) },
                navigationIcon = { if (back != null) IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = actions,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
            )
        },
        floatingActionButton = fab ?: {},
        contentWindowInsets = WindowInsets(0),
    ) { pad ->
        CompositionLocalProvider(LocalFabSpace provides if (fab != null) 120.dp else 0.dp) {
            Box(Modifier.fillMaxSize().padding(pad).imePadding()) { content(Modifier.fillMaxSize()) }
        }
    }
}

/** The screen title with the open company and financial year under it; tapping opens the company and year switcher. */
@Composable
fun CompanyYearTitle(title: String) {
    val app = LocalApp.current
    var open by remember { mutableStateOf(false) }
    Box {
        Column(Modifier.clickable { open = true }.padding(end = 8.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Business, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(" ${app.companyName} · FY ${app.fyLabel}" + if (app.isCurrentFY) "" else " · past year",
                    style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    color = if (app.isCurrentFY) MaterialTheme.colorScheme.onSurfaceVariant else Warn, modifier = Modifier.widthIn(max = 260.dp))
                Icon(Icons.Default.ArrowDropDown, null, Modifier.size(18.dp))
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            SmallLabel("  Company")
            app.companyGroups.forEach { c ->
                DropdownMenuItem(text = { Text(c.str("name")) }, leadingIcon = { if (app.isOpenGroup(c)) Icon(Icons.Default.Check, null) },
                    onClick = { open = false; if (!app.isOpenGroup(c)) app.launch { app.switchCompany(c.id) } })
            }
            HorizontalDivider()
            SmallLabel("  Financial year ${app.fyLabel} · " + if (app.isCurrentFY) "current year" else "past year · view and edit")
            app.yearChoices.forEach { y ->
                val t = y.title + if (y.bookId != app.companyId && y.label.isNotEmpty()) "  · own file" else ""
                DropdownMenuItem(text = { Text(t) }, leadingIcon = { if (y.bookId == app.companyId && y.label == app.fyLabel) Icon(Icons.Default.Check, null) },
                    onClick = { open = false; app.launch { app.chooseYear(y) } })
            }
        }
    }
}

/** Messages at the bottom (Android snackbar style): green tick for done, red for problems; tap × to close. */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.ToastHost(app: AppState) {
    val t = app.toast
    AnimatedVisibility(t != null, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 88.dp, start = 16.dp, end = 16.dp),
        enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
        val shown = t ?: return@AnimatedVisibility
        Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.inverseSurface, shadowElevation = 6.dp) {
            Row(Modifier.padding(start = 14.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(if (shown.error) Icons.Default.Error else Icons.Default.CheckCircle, null, tint = if (shown.error) Color(0xFFFF6B6B) else Color(0xFF5DD07A))
                Text(shown.text, color = MaterialTheme.colorScheme.inverseOnSurface, style = MaterialTheme.typography.bodyMedium, maxLines = 4, modifier = Modifier.weight(1f, fill = false))
                IconButton(onClick = { app.toast = null }) { Icon(Icons.Default.Close, "Dismiss", tint = MaterialTheme.colorScheme.inverseOnSurface) }
            }
        }
    }
}
