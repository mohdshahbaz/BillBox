package com.local.billbox.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.ViewColumn
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject

/** One column of a table: its heading, starting width, alignment and cell. */
class Col<R>(val title: String, val id: String = title, val width: Int = 100, val end: Boolean = false, val hidden: Boolean = false,
             val minWidth: Int = 44, val cell: @Composable (R) -> Unit) {
    var isIndex = false
}

/** A text cell (one line, cut with "…"). */
@Composable
fun Cell(text: String, color: Color = Color.Unspecified, bold: Boolean = false, end: Boolean = false, lines: Int = 1) {
    Text(text, color = color, fontWeight = if (bold) FontWeight.SemiBold else null, maxLines = lines, overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.bodyMedium, textAlign = if (end) TextAlign.End else TextAlign.Start, modifier = Modifier.fillMaxWidth())
}

/** A row's long-press menu entry. */
data class RowAction(val label: String, val icon: ImageVector? = null, val destructive: Boolean = false, val enabled: Boolean = true, val run: () -> Unit)

/** What the user changed about one table (order, hidden, widths); kept per table in the same form as the Mac and iPhone. */
class TableLayout(private val ctx: Context, key: String) {
    private val k = "grid.$key"
    private val p = ctx.getSharedPreferences("billbox_grid", Context.MODE_PRIVATE)
    val order = mutableStateListOf<String>()
    val hidden = mutableStateListOf<String>()
    val widths = mutableStateMapOf<String, Float>()
    var touched by mutableStateOf(false)

    init {
        p.getString(k, null)?.let { s ->
            runCatching {
                val o = JSONObject(s)
                o.optJSONArray("order")?.let { a -> for (i in 0 until a.length()) order.add(a.getString(i)) }
                o.optJSONArray("hidden")?.let { a -> for (i in 0 until a.length()) hidden.add(a.getString(i)) }
                o.optJSONObject("widths")?.let { w -> w.keys().forEach { widths[it] = w.getDouble(it).toFloat() } }
                touched = true
            }
        }
    }

    fun save() {
        val w = JSONObject(); widths.forEach { (a, b) -> w.put(a, b.toDouble()) }
        p.edit().putString(k, JSONObject().put("order", JSONArray(order.toList())).put("hidden", JSONArray(hidden.toList())).put("widths", w).toString()).apply()
    }

    fun reset() { order.clear(); hidden.clear(); widths.clear(); touched = false; p.edit().remove(k).apply() }

    fun <R> ordered(cols: List<Col<R>>): List<Col<R>> {
        val byId = cols.associateBy { it.id }
        val out = order.mapNotNull { byId[it] }.toMutableList()
        cols.firstOrNull { it.isIndex }?.let { if (it.id !in order) out.add(0, it) }
        val have = out.map { it.id }.toSet()
        out += cols.filter { it.id !in have }
        return out
    }

    fun <R> isHidden(c: Col<R>) = if (touched) c.id in hidden else c.hidden

    fun <R> materialise(cols: List<Col<R>>) {
        if (!touched) { hidden.clear(); hidden.addAll(cols.filter { it.hidden }.map { it.id }); order.clear(); order.addAll(cols.map { it.id }); touched = true }
    }

    fun <R> toggle(c: Col<R>, cols: List<Col<R>>) {
        materialise(cols)
        val visible = ordered(cols).count { !isHidden(it) }
        if (c.id in hidden) hidden.remove(c.id) else if (visible > 1) hidden.add(c.id)
        save()
    }

    fun <R> move(c: Col<R>, by: Int, cols: List<Col<R>>) {
        materialise(cols)
        val ids = ordered(cols).map { it.id }.toMutableList()
        val i = ids.indexOf(c.id); val j = (i + by).coerceIn(0, ids.size - 1)
        if (i < 0 || i == j) return
        ids.removeAt(i); ids.add(j, c.id)
        order.clear(); order.addAll(ids); save()
    }
}

/**
 * The Mac's adjustable table on Android: every column kept, sideways scrolling with the heading pinned, drag a heading's
 * right edge to resize, the columns button to show / hide / reorder, long press a row for its menu, tap to open or select.
 * lazy = false keeps every row alive (the bill being typed), so editing never loses the keyboard.
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun <R> DataTable(
    rows: List<R>, layoutKey: String, modifier: Modifier = Modifier, rowHeight: Int = 40, lazy: Boolean = true, numbered: Boolean = true,
    selected: Set<Any>? = null, keyOf: (R) -> Any = { it as Any }, selecting: Boolean = false, onToggle: ((R) -> Unit)? = null,
    onOpen: ((R) -> Unit)? = null, menu: ((R) -> List<RowAction>)? = null, footer: (@Composable () -> Unit)? = null,
    phone: List<String> = emptyList(),
    columns: List<Col<R>>,
) {
    val ctx = LocalContext.current
    val ui = LocalUi.current
    val layout = remember(layoutKey) { TableLayout(ctx, layoutKey) }
    val cols = run {
        if (numbered && columns.none { it.id == "sno" }) listOf(Col<R>("S.No", "sno", 48, end = true) {}.also { it.isIndex = true }) + columns else columns
    }
    // On a phone (narrower than 600 dp), until the columns are arranged by hand: the columns that matter first (`phone`),
    // without the S.No column, so the party and the amount are on screen instead of off to the right.
    val compact = androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp < 600
    val shown = layout.ordered(cols).filter { !layout.isHidden(it) }
    val visible = if (compact && !layout.touched && phone.isNotEmpty()) {
        phone.mapNotNull { id -> shown.firstOrNull { it.id == id } } + shown.filter { it.id !in phone && !it.isIndex }
    } else shown
    val h = rememberScrollState()
    var showColumns by remember { mutableStateOf(false) }
    val rh = (rowHeight * ui.rowFactor).dp
    val density = LocalDensity.current
    fun w(c: Col<R>): Dp = (layout.widths[c.id] ?: c.width.toFloat()).dp

    val header: @Composable () -> Unit = {
        // the heading band: the card colour tinted with 6% of the accent (docs/DESIGN_SYSTEM.md, Table)
        Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.06f)),
            verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).horizontalScroll(h)) {
                visible.forEach { c ->
                    Box(Modifier.width(w(c)).heightIn(min = 34.dp)) {
                        Text(c.title.uppercase(), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = if (c.isIndex || c.id == "sno") 1 else 2,
                            textAlign = if (c.end) TextAlign.End else TextAlign.Start,
                            modifier = Modifier.fillMaxWidth().align(Alignment.CenterStart).padding(horizontal = 8.dp, vertical = 6.dp))
                        // the resize grip takes the heading's own height (matchParentSize), never the space left on screen: with
                        // fillMaxHeight the heading of a non-lazy table (the bill being typed) grew to fill the screen and hid every row
                        Box(Modifier.matchParentSize()) {
                            Box(Modifier.align(Alignment.CenterEnd).width(14.dp).fillMaxHeight().pointerInput(c.id) {
                                detectHorizontalDragGestures(onDragEnd = { layout.save() }) { _, dx ->
                                    layout.materialise(cols)
                                    val cur = layout.widths[c.id] ?: c.width.toFloat()
                                    layout.widths[c.id] = maxOf(c.minWidth.toFloat(), cur + with(density) { dx.toDp().value })
                                }
                            }) { Box(Modifier.align(Alignment.Center).width(1.dp).size(1.dp, 20.dp).background(MaterialTheme.colorScheme.outlineVariant)) }
                        }
                    }
                }
            }
            IconButton(onClick = { showColumns = true }, modifier = Modifier.size(40.dp)) { Icon(Icons.Default.ViewColumn, "Columns") }
        }
    }

    val rowView: @Composable (Int, R) -> Unit = { idx, row ->
        val isSel = selected?.contains(keyOf(row)) == true
        var menuOpen by remember { mutableStateOf(false) }
        Box {
            Row(Modifier.fillMaxWidth()
                .background(if (isSel) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer)
                // a row is ticked only while ticking (Select); otherwise a tap opens it and never ticks it
                .combinedClickable(onClick = { if (selecting && onToggle != null) onToggle(row) else onOpen?.invoke(row) },
                    onLongClick = if (menu != null) ({ menuOpen = true }) else null)
                .heightIn(min = rh), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).horizontalScroll(h), verticalAlignment = Alignment.CenterVertically) {
                    visible.forEach { c ->
                        Box(Modifier.width(w(c)).padding(horizontal = 8.dp, vertical = 4.dp), contentAlignment = if (c.end) Alignment.CenterEnd else Alignment.CenterStart) {
                            if (c.isIndex) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                // the tick circle always in the same place, the number on the right
                                if (selecting) Icon(if (isSel) Icons.Default.CheckCircle else Icons.Default.RadioButtonUnchecked, null, Modifier.size(16.dp),
                                    tint = if (isSel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                                Spacer(Modifier.weight(1f))
                                Text("${idx + 1}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            } else c.cell(row)
                        }
                    }
                }
                Box(Modifier.width(40.dp))
            }
            if (menu != null) DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                menu(row).forEach { a ->
                    DropdownMenuItem(text = { Text(a.label, color = if (a.destructive) MaterialTheme.colorScheme.error else Color.Unspecified) }, enabled = a.enabled,
                        leadingIcon = a.icon?.let { { Icon(it, null, tint = if (a.destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant) } },
                        onClick = { menuOpen = false; a.run() })
                }
            }
        }
        Divider()
    }

    val fabSpace = LocalFabSpace.current
    // the table is a rounded card with a 10 dp side margin and 8 dp above (docs/DESIGN_SYSTEM.md, Table)
    Column(modifier.fillMaxSize().padding(horizontal = 10.dp).padding(top = 8.dp)
        .clip(RoundedCornerShape(DS.radiusCard * ui.cornerFactor))
        .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(DS.radiusCard * ui.cornerFactor))
        .background(MaterialTheme.colorScheme.surfaceContainer)) {
        if (lazy) {
            // the end of the list scrolls clear of the floating button
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = fabSpace)) {
                stickyHeader { header() }
                itemsIndexed(rows) { i, r -> rowView(i, r) }
                if (footer != null) item { footer() }
            }
        } else {
            header()
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                rows.forEachIndexed { i, r -> androidx.compose.runtime.key(keyOf(r)) { rowView(i, r) } }
                if (footer != null) footer()
                Spacer(Modifier.height(fabSpace))
            }
        }
    }

    if (showColumns) ModalBottomSheet(onDismissRequest = { showColumns = false }) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text("Columns", style = MaterialTheme.typography.titleLarge)
            Hint("Tick the columns to show; the arrows change the order. Drag the right edge of a heading in the table to change a column's width.")
            layout.ordered(cols).forEach { c ->
                Row(Modifier.fillMaxWidth().clickable { layout.toggle(c, cols) }, verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = !layout.isHidden(c), onCheckedChange = { layout.toggle(c, cols) })
                    Text(c.title, Modifier.weight(1f))
                    IconButton(onClick = { layout.move(c, -1, cols) }) { Icon(Icons.Default.ArrowUpward, "Move up") }
                    IconButton(onClick = { layout.move(c, 1, cols) }) { Icon(Icons.Default.ArrowDownward, "Move down") }
                }
            }
            TextButton(onClick = { layout.reset() }) { Text("Reset columns", color = MaterialTheme.colorScheme.error) }
        }
    }
}

/** Select mode for a table: "Select" turns taps into selection; then "N of M selected · Select all" and the bulk action. */
@Composable
fun SelectionBar(count: Int, total: Int, selecting: Boolean, onSelecting: (Boolean) -> Unit, onAll: () -> Unit,
                 actionLabel: String = "Delete selected", busy: Boolean = false, extra: @Composable () -> Unit = {}, action: () -> Unit) {
    Row(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { onSelecting(!selecting) }) { Text(if (selecting) "Done" else "Select") }
        if (selecting) {
            Text("$count of $total selected", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
            TextButton(onClick = onAll) { Text(if (count == total) "Clear" else "Select all") }
            extra()   // more actions for the ticked rows (print, mark printed…)
            TextButton(onClick = action, enabled = !busy && count > 0) { Text(actionLabel, color = MaterialTheme.colorScheme.error) }
        } else Box(Modifier.weight(1f))
    }
}

sealed class BulkOutcome { object Deleted : BulkOutcome(); object Archived : BulkOutcome(); data class Failed(val label: String, val reason: String) : BulkOutcome() }

/** Runs delete for every id one at a time (stock and ledger stay consistent) and reports one summary. */
suspend fun <T> bulkDelete(ids: List<T>, notify: (String, Boolean) -> Unit, delete: suspend (T) -> BulkOutcome) {
    var ok = 0; var archived = 0; val failed = mutableListOf<String>()
    for (id in ids) when (val r = delete(id)) {
        BulkOutcome.Deleted -> ok++
        BulkOutcome.Archived -> archived++
        is BulkOutcome.Failed -> failed.add(if (r.reason.isEmpty()) r.label else "${r.label}: ${r.reason}")
    }
    val parts = mutableListOf<String>()
    if (ok > 0) parts.add("$ok deleted")
    if (archived > 0) parts.add("$archived archived (had history)")
    if (parts.isNotEmpty()) notify(parts.joinToString(", ") + ".", false)
    if (failed.isNotEmpty()) notify("Could not delete ${failed.size}: " + failed.take(5).joinToString("; ") + if (failed.size > 5) "…" else "", true)
}

/** "₹1,234.00 Dr" (they owe you), "₹1,234.00 Cr" (you owe them) or "Settled". */
fun balanceText(v: Double) = if (kotlin.math.abs(v) < 0.005) "Settled" else "${com.local.billbox.data.Fmt.money(kotlin.math.abs(v))} ${if (v > 0) "Dr" else "Cr"}"
