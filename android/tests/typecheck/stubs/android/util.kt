@file:Suppress("unused", "UNUSED_PARAMETER")
package android.util
object Base64 { const val NO_WRAP = 2; fun encodeToString(input: ByteArray, flags: Int): String = ""; fun decode(str: String, flags: Int): ByteArray = ByteArray(0) }
object Log { fun e(tag: String, msg: String): Int = 0; fun e(tag: String, msg: String, tr: Throwable?): Int = 0; fun i(tag: String, msg: String): Int = 0; fun w(tag: String, msg: String): Int = 0 }
class Size(val width: Int, val height: Int)
