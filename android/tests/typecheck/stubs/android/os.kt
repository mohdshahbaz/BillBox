@file:Suppress("unused", "UNUSED_PARAMETER")
package android.os
class Bundle
interface Parcelable
object Build { object VERSION { @JvmField val SDK_INT: Int = 34 } }
class Looper { companion object { fun getMainLooper(): Looper = Looper() } }
class Handler(looper: Looper) { fun post(r: Runnable): Boolean = true }
class CancellationSignal { val isCanceled: Boolean = false }
class ParcelFileDescriptor : java.io.Closeable {
    val fileDescriptor: java.io.FileDescriptor get() = TODO()
    override fun close() {}
    companion object { const val MODE_READ_ONLY = 1; fun open(file: java.io.File, mode: Int): ParcelFileDescriptor = TODO() }
}
