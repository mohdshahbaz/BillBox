package androidx.compose.ui.text.font
class FontWeight(val weight: Int) { companion object { val Normal = FontWeight(400); val Medium = FontWeight(500); val SemiBold = FontWeight(600); val Bold = FontWeight(700) } }
abstract class FontFamily { companion object { val Monospace: FontFamily = TODO(); val Default: FontFamily = TODO() } }
