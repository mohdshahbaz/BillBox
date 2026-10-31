@file:Suppress("unused", "UNUSED_PARAMETER")
package com.google.mlkit.vision.text
import com.google.android.gms.tasks.Task
class Text { val textBlocks: List<TextBlock> = emptyList()
    class TextBlock { val lines: List<Line> = emptyList() }
    class Line { val text: String = ""; val boundingBox: android.graphics.Rect? = null } }
interface TextRecognizer { fun process(image: com.google.mlkit.vision.common.InputImage): Task<Text> }
object TextRecognition { @JvmStatic fun getClient(options: com.google.mlkit.vision.text.latin.TextRecognizerOptions): TextRecognizer = TODO() }
