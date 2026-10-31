package com.local.billbox.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * A compact editable cell for tables (boxes, pieces, discount, rate): a small outlined box, right-aligned, the number pad.
 * Typing goes straight into the bill; when the bill changes the number from elsewhere the text follows.
 */
@Composable
fun EditCell(value: String, onValue: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = "", color: Color = Color.Unspecified,
             decimal: Boolean = true) {
    var tf by remember { mutableStateOf(TextFieldValue(value, TextRange(value.length))) }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(value) { if (tf.text != value) tf = TextFieldValue(value, TextRange(value.length)) }
    val style = MaterialTheme.typography.bodyMedium.copy(textAlign = TextAlign.End, color = if (color == Color.Unspecified) MaterialTheme.colorScheme.onSurface else color)
    BasicTextField(
        value = tf,
        onValueChange = { v ->
            val clean = v.text.filter { it.isDigit() || (decimal && it == '.') }.take(12)
            tf = if (clean == v.text) v else TextFieldValue(clean, TextRange(clean.length))
            if (clean != value) onValue(clean)
        },
        singleLine = true,
        textStyle = style,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(keyboardType = if (decimal) KeyboardType.Decimal else KeyboardType.Number, imeAction = ImeAction.Next),
        modifier = modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = 34.dp)
                .border(if (focused) 2.dp else 1.dp, if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(6.dp))
                .padding(horizontal = 6.dp), contentAlignment = Alignment.CenterEnd) {
                if (tf.text.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, style = style.copy(color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)), maxLines = 1)
                inner()
            }
        },
    )
}

/** Whole numbers only (boxes, pieces): blank reads as 0. */
@Composable
fun IntCell(value: Int, onValue: (Int) -> Unit, modifier: Modifier = Modifier) {
    var text by remember { mutableStateOf(value.toString()) }
    LaunchedEffect(value) { if ((text.toIntOrNull() ?: 0) != value) text = value.toString() }
    EditCell(text, { t -> val d = t.filter { it.isDigit() }.take(7); text = d; val n = d.toIntOrNull() ?: 0; if (n != value) onValue(n) }, modifier, placeholder = "0", decimal = false)
}
