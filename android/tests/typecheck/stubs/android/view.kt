@file:Suppress("unused", "UNUSED_PARAMETER")
package android.view
open class View { val width: Int = 0; val height: Int = 0 }
class Window { val decorView: View get() = TODO() }
object PixelCopy {
    const val SUCCESS = 0
    fun interface OnPixelCopyFinishedListener { fun onPixelCopyFinished(copyResult: Int) }
    fun request(source: Window, dest: android.graphics.Bitmap, listener: OnPixelCopyFinishedListener, listenerThread: android.os.Handler) {}
}
