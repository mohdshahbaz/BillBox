package androidx.compose.ui.text.style
@JvmInline value class TextAlign(val value: Int) { companion object { val Start = TextAlign(0); val End = TextAlign(1); val Center = TextAlign(2) } }
@JvmInline value class TextOverflow(val value: Int) { companion object { val Ellipsis = TextOverflow(0); val Clip = TextOverflow(1) } }
class TextDecoration { companion object { val LineThrough = TextDecoration(); val Underline = TextDecoration() } }
