@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.material3

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.window.DialogProperties

@RequiresOptIn annotation class ExperimentalMaterial3Api

class ColorScheme(val primary: Color, val onPrimary: Color, val primaryContainer: Color, val onPrimaryContainer: Color, val secondary: Color, val tertiary: Color,
                  val background: Color, val surface: Color, val onSurface: Color, val onSurfaceVariant: Color, val surfaceContainer: Color,
                  val surfaceContainerLow: Color, val surfaceContainerHigh: Color, val outline: Color, val outlineVariant: Color, val error: Color,
                  val inverseSurface: Color, val inverseOnSurface: Color)
fun lightColorScheme(primary: Color = Color.Unspecified, onPrimary: Color = Color.Unspecified, secondary: Color = Color.Unspecified, tertiary: Color = Color.Unspecified,
                     background: Color = Color.Unspecified, surface: Color = Color.Unspecified, surfaceContainer: Color = Color.Unspecified,
                     surfaceContainerLow: Color = Color.Unspecified, surfaceContainerHigh: Color = Color.Unspecified): ColorScheme = TODO()
fun darkColorScheme(primary: Color = Color.Unspecified, onPrimary: Color = Color.Unspecified, secondary: Color = Color.Unspecified, tertiary: Color = Color.Unspecified,
                    background: Color = Color.Unspecified, surface: Color = Color.Unspecified, surfaceContainer: Color = Color.Unspecified,
                    surfaceContainerLow: Color = Color.Unspecified, surfaceContainerHigh: Color = Color.Unspecified): ColorScheme = TODO()
fun dynamicLightColorScheme(context: android.content.Context): ColorScheme = TODO()
fun dynamicDarkColorScheme(context: android.content.Context): ColorScheme = TODO()
class Typography(val headlineMedium: TextStyle = TextStyle(), val headlineSmall: TextStyle = TextStyle(), val titleLarge: TextStyle = TextStyle(),
                 val titleMedium: TextStyle = TextStyle(), val titleSmall: TextStyle = TextStyle(), val bodyLarge: TextStyle = TextStyle(),
                 val bodyMedium: TextStyle = TextStyle(), val bodySmall: TextStyle = TextStyle(), val labelLarge: TextStyle = TextStyle(),
                 val labelMedium: TextStyle = TextStyle(), val labelSmall: TextStyle = TextStyle())
class Shapes(val small: Shape, val medium: Shape, val large: Shape)
object MaterialTheme {
    val colorScheme: ColorScheme @Composable get() = TODO()
    val typography: Typography @Composable get() = TODO()
    val shapes: Shapes @Composable get() = TODO()
}
@Composable fun MaterialTheme(colorScheme: ColorScheme = TODO(), shapes: Shapes = TODO(), typography: Typography = TODO(), content: @Composable () -> Unit) {}

@Composable fun Text(text: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified, fontSize: TextUnit = TextUnit(0), fontWeight: FontWeight? = null,
                     fontFamily: FontFamily? = null, textDecoration: TextDecoration? = null, textAlign: TextAlign? = null, overflow: TextOverflow = TextOverflow.Clip,
                     softWrap: Boolean = true, maxLines: Int = Int.MAX_VALUE, minLines: Int = 1, style: TextStyle = TextStyle()) {}
@Composable fun Icon(imageVector: ImageVector, contentDescription: String?, modifier: Modifier = Modifier, tint: Color = Color.Unspecified) {}
@Composable fun IconButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable () -> Unit) {}
@Composable fun Button(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {}
@Composable fun TextButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {}
@Composable fun OutlinedButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {}
@Composable fun FilledTonalButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit) {}
@Composable fun ExtendedFloatingActionButton(text: @Composable () -> Unit, icon: @Composable () -> Unit, onClick: () -> Unit, modifier: Modifier = Modifier, expanded: Boolean = true) {}
@Composable fun Surface(modifier: Modifier = Modifier, shape: Shape = TODO(), color: Color = Color.Unspecified, contentColor: Color = Color.Unspecified, tonalElevation: Dp = Dp(0f),
                        shadowElevation: Dp = Dp(0f), border: BorderStroke? = null, content: @Composable () -> Unit) {}
@Composable fun Surface(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, shape: Shape = TODO(), color: Color = Color.Unspecified,
                        tonalElevation: Dp = Dp(0f), shadowElevation: Dp = Dp(0f), border: BorderStroke? = null, content: @Composable () -> Unit) {}
@Composable fun HorizontalDivider(modifier: Modifier = Modifier, thickness: Dp = Dp(1f), color: Color = Color.Unspecified) {}
@Composable fun CircularProgressIndicator(modifier: Modifier = Modifier, color: Color = Color.Unspecified, strokeWidth: Dp = Dp(4f)) {}
@Composable fun LinearProgressIndicator(progress: () -> Float, modifier: Modifier = Modifier) {}
@Composable fun AlertDialog(onDismissRequest: () -> Unit, confirmButton: @Composable () -> Unit, modifier: Modifier = Modifier, dismissButton: (@Composable () -> Unit)? = null,
                            icon: (@Composable () -> Unit)? = null, title: (@Composable () -> Unit)? = null, text: (@Composable () -> Unit)? = null, properties: DialogProperties = DialogProperties()) {}
@Composable fun ListItem(headlineContent: @Composable () -> Unit, modifier: Modifier = Modifier, overlineContent: (@Composable () -> Unit)? = null, supportingContent: (@Composable () -> Unit)? = null,
                         leadingContent: (@Composable () -> Unit)? = null, trailingContent: (@Composable () -> Unit)? = null) {}
@Composable fun Switch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier, enabled: Boolean = true) {}
@Composable fun Checkbox(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier, enabled: Boolean = true) {}
@Composable fun RadioButton(selected: Boolean, onClick: (() -> Unit)?, modifier: Modifier = Modifier, enabled: Boolean = true) {}
@Composable fun FilterChip(selected: Boolean, onClick: () -> Unit, label: @Composable () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                           leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null) {}

@Composable fun OutlinedTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, readOnly: Boolean = false,
                                  textStyle: TextStyle = TextStyle(), label: (@Composable () -> Unit)? = null, placeholder: (@Composable () -> Unit)? = null,
                                  leadingIcon: (@Composable () -> Unit)? = null, trailingIcon: (@Composable () -> Unit)? = null, prefix: (@Composable () -> Unit)? = null,
                                  suffix: (@Composable () -> Unit)? = null, supportingText: (@Composable () -> Unit)? = null, isError: Boolean = false,
                                  keyboardOptions: KeyboardOptions = KeyboardOptions(), keyboardActions: KeyboardActions = KeyboardActions(), singleLine: Boolean = false,
                                  maxLines: Int = Int.MAX_VALUE, minLines: Int = 1, shape: Shape = TODO()) {}

@Composable fun DropdownMenu(expanded: Boolean, onDismissRequest: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {}
@Composable fun DropdownMenuItem(text: @Composable () -> Unit, onClick: () -> Unit, modifier: Modifier = Modifier, leadingIcon: (@Composable () -> Unit)? = null,
                                 trailingIcon: (@Composable () -> Unit)? = null, enabled: Boolean = true) {}
enum class MenuAnchorType { PrimaryNotEditable, PrimaryEditable, SecondaryEditable }
@ExperimentalMaterial3Api abstract class ExposedDropdownMenuBoxScope {
    abstract fun Modifier.menuAnchor(type: MenuAnchorType, enabled: Boolean = true): Modifier
    @Composable fun ExposedDropdownMenu(expanded: Boolean, onDismissRequest: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {}
}
@ExperimentalMaterial3Api @Composable fun ExposedDropdownMenuBox(expanded: Boolean, onExpandedChange: (Boolean) -> Unit, modifier: Modifier = Modifier, content: @Composable ExposedDropdownMenuBoxScope.() -> Unit) {}
@ExperimentalMaterial3Api object ExposedDropdownMenuDefaults { @Composable fun TrailingIcon(expanded: Boolean, modifier: Modifier = Modifier) {} }

interface SingleChoiceSegmentedButtonRowScope : RowScope
@ExperimentalMaterial3Api @Composable fun SingleChoiceSegmentedButtonRow(modifier: Modifier = Modifier, space: Dp = Dp(1f), content: @Composable SingleChoiceSegmentedButtonRowScope.() -> Unit) {}
@ExperimentalMaterial3Api @Composable fun SingleChoiceSegmentedButtonRowScope.SegmentedButton(selected: Boolean, onClick: () -> Unit, shape: Shape, modifier: Modifier = Modifier,
                                                                                                enabled: Boolean = true, label: @Composable () -> Unit) {}
@ExperimentalMaterial3Api object SegmentedButtonDefaults { @Composable fun itemShape(index: Int, count: Int, baseShape: Shape = TODO()): Shape = TODO() }

class TopAppBarColors
@ExperimentalMaterial3Api object TopAppBarDefaults {
    @Composable fun topAppBarColors(containerColor: Color = Color.Unspecified, scrolledContainerColor: Color = Color.Unspecified): TopAppBarColors = TopAppBarColors()
    @Composable fun centerAlignedTopAppBarColors(containerColor: Color = Color.Unspecified, scrolledContainerColor: Color = Color.Unspecified): TopAppBarColors = TopAppBarColors()
}
@ExperimentalMaterial3Api @Composable fun TopAppBar(title: @Composable () -> Unit, modifier: Modifier = Modifier, navigationIcon: @Composable () -> Unit = {},
                                                    actions: @Composable RowScope.() -> Unit = {}, colors: TopAppBarColors = TopAppBarColors()) {}
@ExperimentalMaterial3Api @Composable fun CenterAlignedTopAppBar(title: @Composable () -> Unit, modifier: Modifier = Modifier, navigationIcon: @Composable () -> Unit = {},
                                                                 actions: @Composable RowScope.() -> Unit = {}, colors: TopAppBarColors = TopAppBarColors()) {}
@Composable fun Scaffold(modifier: Modifier = Modifier, topBar: @Composable () -> Unit = {}, bottomBar: @Composable () -> Unit = {}, snackbarHost: @Composable () -> Unit = {},
                         floatingActionButton: @Composable () -> Unit = {}, containerColor: Color = Color.Unspecified, contentWindowInsets: WindowInsets = WindowInsets(),
                         content: @Composable (PaddingValues) -> Unit) {}
@Composable fun NavigationBar(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {}
@Composable fun RowScope.NavigationBarItem(selected: Boolean, onClick: () -> Unit, icon: @Composable () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                                           label: (@Composable () -> Unit)? = null, alwaysShowLabel: Boolean = true) {}
@Composable fun NavigationRail(modifier: Modifier = Modifier, header: (@Composable ColumnScope.() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {}
@Composable fun NavigationRailItem(selected: Boolean, onClick: () -> Unit, icon: @Composable () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                                   label: (@Composable () -> Unit)? = null, alwaysShowLabel: Boolean = true) {}
@ExperimentalMaterial3Api @Composable fun PrimaryScrollableTabRow(selectedTabIndex: Int, modifier: Modifier = Modifier, edgePadding: Dp = Dp(52f), tabs: @Composable () -> Unit) {}
@Composable fun Tab(selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, text: (@Composable () -> Unit)? = null, icon: (@Composable () -> Unit)? = null) {}

@ExperimentalMaterial3Api class DatePickerState { val selectedDateMillis: Long? = null }
@ExperimentalMaterial3Api @Composable fun rememberDatePickerState(initialSelectedDateMillis: Long? = null): DatePickerState = DatePickerState()
@ExperimentalMaterial3Api @Composable fun DatePicker(state: DatePickerState, modifier: Modifier = Modifier) {}
@ExperimentalMaterial3Api @Composable fun DatePickerDialog(onDismissRequest: () -> Unit, confirmButton: @Composable () -> Unit, modifier: Modifier = Modifier,
                                                           dismissButton: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {}
@ExperimentalMaterial3Api class TimePickerState { val hour: Int = 0; val minute: Int = 0 }
@ExperimentalMaterial3Api @Composable fun rememberTimePickerState(initialHour: Int = 0, initialMinute: Int = 0, is24Hour: Boolean = false): TimePickerState = TimePickerState()
@ExperimentalMaterial3Api @Composable fun TimePicker(state: TimePickerState, modifier: Modifier = Modifier) {}
@ExperimentalMaterial3Api class SheetState
@ExperimentalMaterial3Api @Composable fun rememberModalBottomSheetState(skipPartiallyExpanded: Boolean = false): SheetState = SheetState()
@ExperimentalMaterial3Api @Composable fun ModalBottomSheet(onDismissRequest: () -> Unit, modifier: Modifier = Modifier, sheetState: SheetState = SheetState(), content: @Composable ColumnScope.() -> Unit) {}
