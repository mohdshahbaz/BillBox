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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Per-phone look (Settings › Appearance): theme, light / dark, panels, corners, row height, text size, start screen. */
class UiPrefs(private val p: SharedPreferences) {
    var theme by mutableStateOf(p.getString("theme", "clean") ?: "clean")
    var appearance by mutableStateOf(p.getString("appearance", "auto") ?: "auto")
    var cardStyle by mutableStateOf(p.getString("cardStyle", "soft") ?: "soft")
    var corners by mutableStateOf(p.getString("corners", "normal") ?: "normal")
    var density by mutableStateOf(p.getString("density", "regular") ?: "regular")
    var textSize by mutableStateOf(p.getString("textSize", "default") ?: "default")
    var fontStyle by mutableStateOf(p.getString("fontStyle", "system") ?: "system")
    var fontWeight by mutableStateOf(p.getString("fontWeight", "regular") ?: "regular")
    var startPage by mutableStateOf(p.getString("startPage", "billing") ?: "billing")
    var showPhotoCard by mutableStateOf(p.getBoolean("showPhotoCard", true))
    var accentOverride by mutableStateOf(p.getString("accentOverride", "") ?: "")
    var pageStyle by mutableStateOf(p.getString("pageStyle", "") ?: "")

    fun set(key: String, v: String) {
        p.edit().putString(key, v).apply()
        when (key) {
            "theme" -> theme = v; "appearance" -> appearance = v; "cardStyle" -> cardStyle = v; "corners" -> corners = v
            "density" -> density = v; "textSize" -> textSize = v; "startPage" -> startPage = v
            "fontStyle" -> fontStyle = v; "fontWeight" -> fontWeight = v
            "accentOverride" -> accentOverride = v; "pageStyle" -> pageStyle = v
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
    AppTheme("midnight", "Midnight", 0xFF2563EB, 0xFF60A5FA, 0xFFEEF2F7, 0xFF0B1220),
    AppTheme("mint", "Mint", 0xFF0F9D7A, 0xFF34D3A6, 0xFFEAF7F2, 0xFF0F1A16),
    AppTheme("lavender", "Lavender", 0xFF7C5CC4, 0xFFB49CFF, 0xFFF4F0FB, 0xFF17131F),
    AppTheme("saffron", "Saffron", 0xFFE07000, 0xFFFFA733, 0xFFFFF5E6, 0xFF1F170C),
    AppTheme("crimson", "Crimson", 0xFFB91C1C, 0xFFF87171, 0xFFFBEFEF, 0xFF1E1010),
    AppTheme("coffee", "Coffee", 0xFF7A4E2D, 0xFFC9925E, 0xFFF6EFE8, 0xFF1C1612),
    AppTheme("graphite", "Graphite", 0xFF1F2937, 0xFFE5E7EB, 0xFFF2F2F3, 0xFF000000),
    AppTheme("teal", "Teal", 0xFF0F766E, 0xFF2DD4BF, 0xFFE9F6F4, 0xFF0D1A19),
    AppTheme("sky", "Sky", 0xFF0284C7, 0xFF38BDF8, 0xFFEAF5FC, 0xFF0B1A24),
    AppTheme("emerald", "Emerald", 0xFF047857, 0xFF34D399, 0xFFE8F6EF, 0xFF0B1913),
    AppTheme("plum", "Plum", 0xFF86198F, 0xFFE879F9, 0xFFF8EEF9, 0xFF1C1020),
    AppTheme("sand", "Sand", 0xFF8A6A3B, 0xFFD6B37A, 0xFFF7F2E9, 0xFF1C1812),
    AppTheme("peacock", "Peacock", 0xFF006D77, 0xFF4FD1C5, 0xFFE6F4F5, 0xFF0B1A1C),
    AppTheme("cherry", "Cherry", 0xFF9F1239, 0xFFFB7185, 0xFFFCEEF2, 0xFF1E0F14),
    AppTheme("olive", "Olive", 0xFF556B2F, 0xFFA3C46B, 0xFFF2F4EA, 0xFF161A0F),
)

/** Settings › Appearance › Accent colour: the theme's own, or one of these (light, dark). */
val AccentChoices = listOf(
    Triple("indigo", 0xFF4F46E5, 0xFF8B8CF8), Triple("blue", 0xFF2563EB, 0xFF60A5FA), Triple("sky", 0xFF0284C7, 0xFF38BDF8), Triple("teal", 0xFF0F766E, 0xFF2DD4BF),
    Triple("green", 0xFF15803D, 0xFF4ADE80), Triple("lime", 0xFF4D7C0F, 0xFFA3E635), Triple("amber", 0xFFB45309, 0xFFFBBF24), Triple("orange", 0xFFC2410C, 0xFFFB923C),
    Triple("red", 0xFFB91C1C, 0xFFF87171), Triple("pink", 0xFFBE185D, 0xFFF472B6), Triple("purple", 0xFF7E22CE, 0xFFC084FC), Triple("brown", 0xFF7A4E2D, 0xFFC9925E))

/** The theme with the chosen accent colour and background (Theme, Plain, Tinted). */
fun customised(t: AppTheme, accent: String, page: String): AppTheme {
    val a = AccentChoices.firstOrNull { it.first == accent }
    val al = a?.second ?: t.accentLight; val ad = a?.third ?: t.accentDark
    fun tint(c: Long, base: Long): Long {
        // 10 % of the accent over the base colour
        fun ch(v: Long, sh: Int) = (v shr sh) and 0xFF
        fun mix(sh: Int) = (ch(base, sh) * 9 + ch(c, sh)) / 10
        return (0xFFL shl 24) or (mix(16) shl 16) or (mix(8) shl 8) or mix(0)
    }
    val (pl, pd) = when (page) { "plain" -> 0xFFF2F2F7 to 0xFF000000; "tinted" -> tint(al, 0xFFFFFFFF) to tint(ad, 0xFF0C0C0E); else -> t.pageLight to t.pageDark }
    return t.copy(accentLight = al, accentDark = ad, pageLight = pl, pageDark = pd)
}

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

/** Settings › Appearance › Letters: the type scale in the chosen family (system, rounded, serif, mono) and weight. */
private fun typeFor(style: String, weight: String): Typography {
    val fam = when (style) {
        "serif" -> androidx.compose.ui.text.font.FontFamily.Serif
        "mono" -> androidx.compose.ui.text.font.FontFamily.Monospace
        "rounded" -> androidx.compose.ui.text.font.FontFamily.SansSerif
        else -> androidx.compose.ui.text.font.FontFamily.Default
    }
    val body = when (weight) {
        "light" -> androidx.compose.ui.text.font.FontWeight.Light; "medium" -> androidx.compose.ui.text.font.FontWeight.Medium
        "bold" -> androidx.compose.ui.text.font.FontWeight.SemiBold; else -> null
    }
    if (style == "system" && body == null) return BillBoxType
    fun t(x: androidx.compose.ui.text.TextStyle, isBody: Boolean) = x.copy(fontFamily = fam, fontWeight = if (isBody && body != null) body else x.fontWeight)
    val b = BillBoxType
    return b.copy(headlineSmall = t(b.headlineSmall, false), titleLarge = t(b.titleLarge, false), titleMedium = t(b.titleMedium, false), titleSmall = t(b.titleSmall, false),
        bodyLarge = t(b.bodyLarge, true), bodyMedium = t(b.bodyMedium, true), bodySmall = t(b.bodySmall, true),
        labelLarge = t(b.labelLarge, false), labelMedium = t(b.labelMedium, false), labelSmall = t(b.labelSmall, false))
}

@Composable
fun BillBoxTheme(prefs: UiPrefs, content: @Composable () -> Unit) {
    val dark = when (prefs.appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }
    val ctx = LocalContext.current
    val t = customised(Themes.firstOrNull { it.id == prefs.theme } ?: Themes[0], prefs.accentOverride, prefs.pageStyle)
    val colors = if (t.id == "dynamic" && Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    } else scheme(t, dark)
    val base = LocalDensity.current
    androidx.compose.runtime.CompositionLocalProvider(
        LocalDensity provides Density(base.density, base.fontScale * prefs.fontScale),
        LocalUi provides prefs,
        LocalDark provides dark,
    ) {
        MaterialTheme(colorScheme = colors, typography = typeFor(prefs.fontStyle, prefs.fontWeight), content = content)
    }
}

val LocalUi = androidx.compose.runtime.staticCompositionLocalOf<UiPrefs> { error("UiPrefs not provided") }
/** Dark mode as chosen in Settings › Appearance (or the system's), for the semantic colours in Components.kt. */
val LocalDark = androidx.compose.runtime.staticCompositionLocalOf { false }

/** Design tokens from docs/DESIGN_SYSTEM.md, the same numbers as the iPhone's `DS`. */
object DS {
    val space4 = 4.dp; val space8 = 8.dp; val space12 = 12.dp; val space16 = 16.dp; val space20 = 20.dp; val space24 = 24.dp; val space32 = 32.dp
    val screenPad = 16.dp; val screenPadWide = 20.dp; val cardPad = 14.dp; val cardGap = 12.dp; val cellPad = 8.dp
    val radiusCard = 14.dp; val radiusHero = 22.dp; val radiusControl = 12.dp
    val dateMin = 122.dp; val moneyMin = 90.dp
    /** Smallest touch target on Android (48 dp). */
    val hitTarget = 48.dp
    /** Pill and badge background strength. */
    const val tint = 0.13f
}
