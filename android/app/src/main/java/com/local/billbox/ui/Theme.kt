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

/** Per-phone look (Settings › Appearance): theme, light / dark, panels, corners, row height, text size, start screen. */
class UiPrefs(private val p: SharedPreferences) {
    var theme by mutableStateOf(p.getString("theme", "dynamic") ?: "dynamic")
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
    return if (dark) darkColorScheme(primary = accent, secondary = accent, tertiary = Color(0xFF34C759), background = page, surface = page,
        surfaceContainer = Color(0xFF1E2126), surfaceContainerLow = Color(0xFF1A1C20), surfaceContainerHigh = Color(0xFF26292F), onPrimary = Color.White)
    else lightColorScheme(primary = accent, secondary = accent, tertiary = Color(0xFF248A3D), background = page, surface = page,
        surfaceContainer = Color.White, surfaceContainerLow = Color(0xFFFBFCFE), surfaceContainerHigh = Color(0xFFF1F3F7), onPrimary = Color.White)
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
        MaterialTheme(colorScheme = colors, typography = Typography(), content = content)
    }
}

val LocalUi = androidx.compose.runtime.staticCompositionLocalOf<UiPrefs> { error("UiPrefs not provided") }
