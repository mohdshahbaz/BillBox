package com.local.billbox.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

// Shared pieces from docs/DESIGN_SYSTEM.md §5, the same as the iPhone's SummaryCard, StatusPill, SkeletonRows and
// ErrorState, so the totals under a table, a status and a failed load look alike on every BillBox.

/** One figure in a [SummaryCard]: label above, value below; `strong` marks the main one. */
data class SummaryItem(val label: String, val value: String, val strong: Boolean = false, val tint: Color? = null)

/** Totals under a table: as many label / figure cells per line as fit, in a rounded card with the table's side margin. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SummaryCard(items: List<SummaryItem>, modifier: Modifier = Modifier) {
    val ui = LocalUi.current
    FlowRow(
        modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = DS.space8)
            .clip(RoundedCornerShape(DS.radiusCard * ui.cornerFactor))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(horizontal = DS.cardPad, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(DS.space8),
    ) {
        items.forEach { it ->
            Column(Modifier.widthIn(min = 104.dp)) {
                Text(it.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                Text(it.value, style = MaterialTheme.typography.bodyLarge, fontWeight = if (it.strong) FontWeight.Bold else FontWeight.Medium,
                    color = it.tint ?: MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** A small coloured label for a state (Sale, Not yet, Retailer…); an empty one keeps its place. */
@Composable
fun StatusPill(text: String, tint: Color) {
    if (text.isEmpty()) { Spacer(Modifier.height(1.dp)); return }
    Text(text, color = tint, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(tint.copy(alpha = DS.tint)).padding(horizontal = DS.space8, vertical = 3.dp))
}

/** Grey placeholder rows while a table loads, so the screen keeps its shape (a spinner only for a first full-screen load). */
@Composable
fun SkeletonRows(rows: Int = 8, modifier: Modifier = Modifier) {
    val bar = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    Column(modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = DS.space8)
        .clip(RoundedCornerShape(DS.radiusCard)).background(MaterialTheme.colorScheme.surfaceContainer).padding(vertical = DS.space8)) {
        repeat(rows) { i ->
            Row(Modifier.fillMaxWidth().height(40.dp).padding(horizontal = DS.space12), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(28.dp, 12.dp).clip(RoundedCornerShape(4.dp)).background(bar))
                Spacer(Modifier.width(DS.space12))
                Box(Modifier.size((110 + (i * 37) % 90).dp, 12.dp).clip(RoundedCornerShape(4.dp)).background(bar))
                Spacer(Modifier.weight(1f))
                Box(Modifier.size(64.dp, 12.dp).clip(RoundedCornerShape(4.dp)).background(bar))
            }
        }
    }
}

/** A list could not load: what happened and Try again. */
@Composable
fun ErrorState(message: String, title: String = "Couldn't load this", retry: (() -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().padding(DS.space24), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.space8)) {
        Icon(Icons.Default.Warning, null, Modifier.size(34.dp), tint = Bad)
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        if (retry != null) Button(onClick = retry) { Text("Try again") }
    }
}
