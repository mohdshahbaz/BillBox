package com.local.billbox.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.local.billbox.data.Fmt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** A panel in the style chosen in Settings › Appearance (soft shadow, outlined or flat) with its corner roundness. */
@Composable
fun Modifier.panel(radius: Dp = 14.dp): Modifier {
    val ui = LocalUi.current
    val r = radius * ui.cornerFactor
    val shape = RoundedCornerShape(r)
    val base = when (ui.cardStyle) {
        "soft" -> this.shadow(3.dp, shape, clip = false)
        else -> this
    }
    val withBg = base.clip(shape).background(MaterialTheme.colorScheme.surfaceContainer)
    return if (ui.cardStyle == "outline") withBg.border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape) else withBg
}

@Composable
fun Panel(modifier: Modifier = Modifier, padding: Dp = 14.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().panel().padding(padding), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = modifier.padding(top = 8.dp, bottom = 2.dp))
}

@Composable
fun Hint(text: String, modifier: Modifier = Modifier, color: Color = MaterialTheme.colorScheme.onSurfaceVariant) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color, modifier = modifier)
}

@Composable
fun ErrorText(text: String?) { if (!text.isNullOrBlank()) Text(text, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

@Composable
fun Banner(text: String, icon: ImageVector = Icons.Default.Info, tint: Color = Color(0xFFE08A00)) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(tint.copy(alpha = 0.12f)).padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        Icon(icon, null, tint = tint)
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun EmptyState(title: String, message: String = "", icon: ImageVector? = null) {
    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (icon != null) Icon(icon, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        if (message.isNotEmpty()) Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
fun Loading() { Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }

enum class Kb { Text, Number, Decimal, Phone, Email, Caps, Signed }

private fun kbOptions(k: Kb) = when (k) {
    Kb.Number -> KeyboardOptions(keyboardType = KeyboardType.Number)
    Kb.Decimal -> KeyboardOptions(keyboardType = KeyboardType.Decimal)
    Kb.Signed -> KeyboardOptions(keyboardType = KeyboardType.Text)
    Kb.Phone -> KeyboardOptions(keyboardType = KeyboardType.Phone)
    Kb.Email -> KeyboardOptions(keyboardType = KeyboardType.Email)
    Kb.Caps -> KeyboardOptions(capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Characters)
    Kb.Text -> KeyboardOptions(capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Sentences)
}

/** An outlined text field with its label (Material). */
@Composable
fun Field(label: String, value: String, onValue: (String) -> Unit, modifier: Modifier = Modifier, kb: Kb = Kb.Text,
          placeholder: String = "", singleLine: Boolean = true, minLines: Int = 1, supporting: String? = null, enabled: Boolean = true,
          trailing: (@Composable () -> Unit)? = null) {
    OutlinedTextField(value = value, onValueChange = onValue, label = { Text(label) }, modifier = modifier.fillMaxWidth(),
        keyboardOptions = kbOptions(kb), singleLine = singleLine, minLines = minLines, enabled = enabled,
        placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder) }) else null,
        supportingText = supporting?.let { { Text(it) } }, trailingIcon = trailing)
}

/** A compact number box for table cells (boxes, pieces, discount, rate). */
@Composable
fun NumberCell(value: String, onValue: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = "", label: String? = null, decimal: Boolean = true) {
    OutlinedTextField(value = value, onValueChange = onValue, modifier = modifier, singleLine = true,
        textStyle = MaterialTheme.typography.bodyMedium.copy(textAlign = TextAlign.End),
        label = label?.let { { Text(it, fontSize = 11.sp) } },
        placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth()) }) else null,
        keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number))
}

/** A drop-down choice (Material exposed menu). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> Choice(label: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }, modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(value = options.firstOrNull { it.first == selected }?.second ?: "", onValueChange = {}, readOnly = true,
            label = { Text(label) }, trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(open) },
            modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable))
        ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (v, t) -> DropdownMenuItem(text = { Text(t) }, onClick = { onSelect(v); open = false }) }
        }
    }
}

/** Two to five choices side by side (Material segmented buttons). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> Segments(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { i, (v, t) ->
            SegmentedButton(selected = v == selected, onClick = { onSelect(v) }, shape = SegmentedButtonDefaults.itemShape(i, options.size)) {
                Text(t, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

@Composable
fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Hint(subtitle)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
fun InfoLine(label: String, value: String, bold: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(label, Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal)
    }
}

/** A date field that opens the Material date picker; value and result are yyyy-MM-dd. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateField(label: String, iso: String, onChange: (String) -> Unit, modifier: Modifier = Modifier, allowClear: Boolean = false) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedTextField(value = if (iso.isEmpty()) "" else Fmt.dmy(iso), onValueChange = {}, readOnly = true, label = { Text(label) },
            trailingIcon = { Icon(Icons.Default.CalendarMonth, null) }, modifier = Modifier.fillMaxWidth())
        Box(Modifier.matchParentSize().clickable { open = true })
    }
    if (open) {
        val start = Fmt.parseIso(iso) ?: LocalDate.now()
        val st = rememberDatePickerState(initialSelectedDateMillis = start.atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
        DatePickerDialog(onDismissRequest = { open = false },
            confirmButton = { TextButton({ st.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }; open = false }) { Text("OK") } },
            dismissButton = {
                Row {
                    if (allowClear) TextButton({ onChange(""); open = false }) { Text("Clear") }
                    TextButton({ open = false }) { Text("Cancel") }
                }
            }) { DatePicker(st) }
    }
}

/**
 * A full-screen form (Android's pattern for creating and editing on a phone): close, title and the save action on top,
 * the fields scrolling below; a failed save shows its reason above the fields and keeps the form open.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FormDialog(title: String, onDismiss: () -> Unit, saveLabel: String = "Save", canSave: Boolean = true,
               onSave: (suspend () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, "Close") } },
                    actions = {
                        if (onSave != null) TextButton(enabled = canSave && !busy, onClick = {
                            scope.launch {
                                busy = true; error = null
                                try { onSave(); onDismiss() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { error = e.message ?: "Could not save" }
                                busy = false
                            }
                        }) { if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) else Text(saveLabel, fontWeight = FontWeight.SemiBold) }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = MaterialTheme.colorScheme.surface))
            },
        ) { pad ->
            Column(Modifier.fillMaxSize().padding(pad).imePadding().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (error != null) Banner(error!!, tint = MaterialTheme.colorScheme.error)
                content()
                Spacer(Modifier.height(40.dp))
            }
        }
    }
}

/** A read-only full-screen page (bill details, ledgers, reports opened from a row). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InfoDialog(title: String, onDismiss: () -> Unit, actions: @Composable RowScope.() -> Unit = {}, scroll: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Scaffold(topBar = {
            androidx.compose.material3.TopAppBar(title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } }, actions = actions)
        }) { pad ->
            val m = Modifier.fillMaxSize().padding(pad)
            Column((if (scroll) m.verticalScroll(rememberScrollState()) else m).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
        }
    }
}

@Composable
fun Confirm(title: String, text: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit, destructive: Boolean = false) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(text) },
        confirmButton = { TextButton(onClick = { onConfirm(); onDismiss() }) { Text(confirm, color = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

/** A figure card that opens the screen behind it. */
@Composable
fun Kpi(title: String, value: String, note: String, icon: ImageVector, tint: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier.panel().clickable(onClick = onClick).padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(tint.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp)) }
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1)
        // two lines kept for every note, so all cards are the same height
        Text(note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, minLines = 2)
    }
}

@Composable
fun Chip(text: String, color: Color, modifier: Modifier = Modifier) {
    Text(text, color = color, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
        modifier = modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 4.dp))
}

/** Runs work a moment after the last call; calls made in between are dropped (typing in a search box loads once). */
class Debouncer(private val scope: kotlinx.coroutines.CoroutineScope) {
    private var job: Job? = null
    fun run(ms: Long = 250, work: suspend () -> Unit) { job?.cancel(); job = scope.launch { delay(ms); work() } }
}

@Composable
fun rememberDebouncer(): Debouncer { val s = rememberCoroutineScope(); return remember { Debouncer(s) } }

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null) {
    Button(onClick = onClick, enabled = enabled, modifier = modifier) {
        if (icon != null) { Icon(icon, null, Modifier.size(18.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text)
    }
}

@Composable
fun Divider() = HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))

@Composable
fun ListRow(title: String, subtitle: String = "", trailing: String = "", trailingColor: Color = Color.Unspecified, selected: Boolean = false,
            leading: (@Composable () -> Unit)? = null, onClick: () -> Unit = {}, onLongClick: (() -> Unit)? = null, extra: (@Composable () -> Unit)? = null) {
    val ui = LocalUi.current
    Surface(color = if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent) {
        Row(Modifier.fillMaxWidth()
            .combinedClick(onClick, onLongClick)
            .padding(horizontal = 16.dp, vertical = (10 * ui.rowFactor).dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (leading != null) leading()
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (subtitle.isNotEmpty()) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (extra != null) extra()
            }
            if (trailing.isNotEmpty()) Text(trailing, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, color = trailingColor)
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
fun Modifier.combinedClick(onClick: () -> Unit, onLongClick: (() -> Unit)?): Modifier =
    this.combinedClickable(onClick = onClick, onLongClick = onLongClick)

@Composable
fun SmallLabel(text: String) = Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

val Money = Color(0xFF0E8F6F)
val Warn = Color(0xFFE08A00)
val Bad = Color(0xFFD93025)
val Good = Color(0xFF1E8E3E)

@Composable
fun ScreenColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

fun Modifier.pad(h: Int = 16, v: Int = 8) = this.padding(PaddingValues(horizontal = h.dp, vertical = v.dp))

@Composable
fun OutlineBox(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().border(BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), RoundedCornerShape(12.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
}

/** One entry of a searchable list (parties, items). */
data class Pick(val id: Int, val label: String, val detail: String = "")

/** A field that opens a searchable list: for parties and items, where a plain menu would be hundreds of rows long. */
@Composable
fun SearchPicker(title: String, choices: List<Pick>, selection: Int, onPick: (Int) -> Unit, modifier: Modifier = Modifier, placeholder: String = "Select…") {
    var open by remember { mutableStateOf(false) }
    val label = choices.firstOrNull { it.id == selection }?.label
    Box(modifier.fillMaxWidth()) {
        OutlinedTextField(value = label ?: "", onValueChange = {}, readOnly = true, label = { Text(title) }, placeholder = { Text(placeholder) },
            trailingIcon = { Icon(Icons.Default.ArrowDropDown, null) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        Box(Modifier.matchParentSize().clickable { open = true })
    }
    if (open) SearchList(title, choices, onDismiss = { open = false }) { onPick(it.id); open = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchList(title: String, choices: List<Pick>, onDismiss: () -> Unit, onPick: (Pick) -> Unit) {
    var q by remember { mutableStateOf("") }
    val words = q.lowercase().split(' ').filter { it.isNotEmpty() }
    val shown = if (words.isEmpty()) choices else choices.filter { c -> val hay = (c.label + " " + c.detail).lowercase(); words.all { hay.contains(it) } }
    androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().imePadding()) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 16.dp))
            OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth().padding(16.dp), placeholder = { Text("Search ${title.lowercase()}") }, singleLine = true,
                leadingIcon = { Icon(Icons.Default.Search, null) },
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { shown.firstOrNull()?.let(onPick) }),
                keyboardOptions = KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Search))
            androidx.compose.foundation.lazy.LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                items(shown.size) { i ->
                    val c = shown[i]
                    Column(Modifier.fillMaxWidth().clickable { onPick(c) }.padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Text(c.label, style = MaterialTheme.typography.bodyLarge)
                        if (c.detail.isNotEmpty()) Hint(c.detail)
                    }
                }
            }
        }
    }
}

val dayNames = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
fun dayList(csv: String) = csv.split(',').mapNotNull { it.trim().toIntOrNull() }.filter { it in 0..6 }.joinToString(", ") { dayNames[it].take(3) }

/** Seven weekday chips; any number can be on. The value is a list like "1,3,5" (0 = Sunday). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayPicker(days: String, onChange: (String) -> Unit) {
    val set = days.split(',').mapNotNull { it.trim().toIntOrNull() }.toSet()
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        (0..6).forEach { i ->
            val on = i in set
            androidx.compose.material3.FilterChip(selected = on, onClick = { onChange((if (on) set - i else set + i).sorted().joinToString(",")) },
                label = { Text(dayNames[i].take(3), style = MaterialTheme.typography.labelSmall) })
        }
    }
}

/** Puts text on the clipboard (tables copy as tab-separated rows that paste into Excel or Sheets). */
fun copyText(text: String) {
    val cm = com.local.billbox.system.Platform.context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
    cm.setPrimaryClip(android.content.ClipData.newPlainText("BillBox", text))
}

fun tsv(header: List<String>, rows: List<List<String>>) = (listOf(header) + rows).joinToString("\n") { it.joinToString("\t") }

fun cap(s: String) = s.lowercase().replaceFirstChar { it.uppercase() }
