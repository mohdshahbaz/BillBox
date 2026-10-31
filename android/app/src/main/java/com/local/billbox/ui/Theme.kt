package com.local.billbox.ui

import android.content.SharedPreferences
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp

/** Per-phone look (Settings › Appearance): theme, light / dark, panels, corners, row height, text size, start screen. */
class UiPrefs(private val p: SharedPreferences) {
    var theme by mutableStateOf(p.getString("theme", "clean") ?: "clean")
    var appearance by mutableStateOf(p.getString("appearance", "auto") ?: "auto")
    var cardStyle by mutableStateOf(p.getString("cardStyle", "soft") ?: "soft")
    var corners by mutableStateOf(p.getString("corners", "normal") ?: "normal")
    var density by mutableStateOf(p.getString("density", "regular") ?: "regular")
    var textSize by mutableStateOf(p.getString("textSize", "default") ?: "default")
    var startPage by mutableStateOf(p.getString("startPage", "billing") ?: "billing")
    var showPhotoCard by mutableStateOf(p.getBoolean("showPhotoCard", true))

    fun set(key: String, v: String) {
        p.edit().putString(key, v).apply()
        when (key) {
            "theme" -> theme = v; "appearance" -> appearance = v; "cardStyle" -> cardStyle = v; "corners" -> corners = v
            "density" -> density = v; "textSize" -> textSize = v; "startPage" -> startPage = v
        }
    }
    fun setPhotoCard(v: Boolean) { p.edit().putBoolean("showPhotoCard", v).apply(); showPhotoCard = v }

    val rowFactor: Float get() = when (density) { "compact" -> 0.82f; "roomy" -> 1.22f; else -> 1f }
    val cornerFactor: Float get() = when (corners) { "square" -> 0.45f; "round" -> 1.6f; else -> 1f }
    val fontScale: Float get() = when (textSize) { "small" -> 0.9f; "large" -> 1.12f; "xlarge" -> 1.25f; else -> 1f }
}

data class AppTheme(val id: String, val name: String, val accentLight: Long, val accentDark: Long, val pageLight: Long, val pageDark: Long)

val Themes = listOf(
    // calm greys, white panels, one indigo accent (the default, as on the Mac and iPhone)
    AppTheme("clean", "Clean", 0xFF4F46E5, 0xFF8B8CF8, 0xFFF6F6F7, 0xFF0C0C0E),
    AppTheme("dynamic", "Your wallpaper", 0xFF0A84FF, 0xFF0A84FF, 0xFFF7F9FC, 0xFF121418),
    AppTheme("classic", "Classic", 0xFF0A84FF, 0xFF0A84FF, 0xFFF2F2F7, 0xFF000000),
    AppTheme("ocean", "Ocean", 0xFF0E7C9B, 0xFF35B6D6, 0xFFEAF4F8, 0xFF0F1C22),
    AppTheme("forest", "Forest", 0xFF2E7D52, 0xFF4FBF82, 0xFFEBF4EE, 0xFF101A14),
    AppTheme("sunset", "Sunset", 0xFFD9552B, 0xFFFF7F50, 0xFFFCF0E8, 0xFF21150F),
    AppTheme("royal", "Royal", 0xFF6D3FD0, 0xFF9B7BF0, 0xFFF2EEFA, 0xFF181325),
    AppTheme("rose", "Rose", 0xFFC9285F, 0xFFF0608F, 0xFFFBEEF3, 0xFF22141A),
    AppTheme("gold", "Marigold", 0xFFB7791F, 0xFFF2B544, 0xFFFBF5E6, 0xFF1E190F),
    AppTheme("slate", "Slate", 0xFF4A5C70, 0xFF93A8BD, 0xFFEEF0F3, 0xFF1B1D20),
)

private fun scheme(t: AppTheme, dark: Boolean): ColorScheme {
    val accent = Color(if (dark) t.accentDark else t.accentLight)
    val page = Color(if (dark) t.pageDark else t.pageLight)
    // neutral greys (zinc) for text, lines and panels, so the accent is the only colour on screen
    return if (dark) darkColorScheme(primary = accent, onPrimary = Color.White, primaryContainer = accent.copy(alpha = 0.22f), onPrimaryContainer = Color(0xFFE4E4E7),
        secondary = accent, secondaryContainer = Color(0xFF27272A), onSecondaryContainer = Color(0xFFE4E4E7), tertiary = Color(0xFF34C759),
        background = page, onBackground = Color(0xFFF4F4F5), surface = page, onSurface = Color(0xFFF4F4F5), onSurfaceVariant = Color(0xFFA1A1AA),
        surfaceContainerLowest = Color(0xFF0E0E10), surfaceContainerLow = Color(0xFF141416), surfaceContainer = Color(0xFF17171A), surfaceContainerHigh = Color(0xFF1F1F23), surfaceContainerHighest = Color(0xFF27272A),
        outline = Color(0xFF3F3F46), outlineVariant = Color(0xFF27272A), error = Color(0xFFF87171))
    else lightColorScheme(primary = accent, onPrimary = Color.White, primaryContainer = accent.copy(alpha = 0.10f), onPrimaryContainer = Color(0xFF18181B),
        secondary = accent, secondaryContainer = Color(0xFFEDEDF0), onSecondaryContainer = Color(0xFF18181B), tertiary = Color(0xFF15803D),
        background = page, onBackground = Color(0xFF18181B), surface = page, onSurface = Color(0xFF18181B), onSurfaceVariant = Color(0xFF71717A),
        surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFFCFCFD), surfaceContainer = Color.White, surfaceContainerHigh = Color(0xFFF1F1F3), surfaceContainerHighest = Color(0xFFE9E9EC),
        outline = Color(0xFFD4D4D8), outlineVariant = Color(0xFFE4E4E7), error = Color(0xFFDC2626))
}

/** One type scale for every screen: few sizes, clear weights (titles semibold, labels medium), tight line heights. */
private val BillBoxType = Typography().let { b ->
    fun sp(v: Int) = v.sp
    val semi = androidx.compose.ui.text.font.FontWeight.SemiBold
    val med = androidx.compose.ui.text.font.FontWeight.Medium
    b.copy(
        headlineSmall = b.headlineSmall.copy(fontSize = sp(22), lineHeight = sp(28), fontWeight = semi),
        titleLarge = b.titleLarge.copy(fontSize = sp(20), lineHeight = sp(26), fontWeight = semi),
        titleMedium = b.titleMedium.copy(fontSize = sp(16), lineHeight = sp(22), fontWeight = semi),
        titleSmall = b.titleSmall.copy(fontSize = sp(14), lineHeight = sp(20), fontWeight = semi),
        bodyLarge = b.bodyLarge.copy(fontSize = sp(15), lineHeight = sp(22)),
        bodyMedium = b.bodyMedium.copy(fontSize = sp(14), lineHeight = sp(20)),
        bodySmall = b.bodySmall.copy(fontSize = sp(12), lineHeight = sp(16)),
        labelLarge = b.labelLarge.copy(fontSize = sp(14), lineHeight = sp(20), fontWeight = med),
        labelMedium = b.labelMedium.copy(fontSize = sp(12), lineHeight = sp(16), fontWeight = med),
        labelSmall = b.labelSmall.copy(fontSize = sp(11), lineHeight = sp(14), fontWeight = med),
    )
}

@Composable
fun BillBoxTheme(prefs: UiPrefs, content: @Composable () -> Unit) {
    val dark = when (prefs.appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
    val ctx = LocalContext.current
    val t = Themes.firstOrNull { it.id == prefs.theme } ?: Themes[0]
    val colors = if (t.id == "dynamic" && Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    } else scheme(t, dark)
    val base = LocalDensity.current
    androidx.compose.runtime.CompositionLocalProvider(
        LocalDensity provides Density(base.density, base.fontScale * prefs.fontScale),
        LocalUi provides prefs,
    ) {
        MaterialTheme(colorScheme = colors, typography = BillBoxType, content = content)
    }
}

val LocalUi = androidx.compose.runtime.staticCompositionLocalOf<UiPrefs> { error("UiPrefs not provided") }
