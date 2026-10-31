@file:Suppress("unused", "UNUSED_PARAMETER")
package android.print
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
class PrintAttributes
class PageRange { companion object { val ALL_PAGES = PageRange() } }
class PrintDocumentInfo { class Builder(name: String) { fun setContentType(t: Int): Builder = this; fun build(): PrintDocumentInfo = PrintDocumentInfo() }
    companion object { const val CONTENT_TYPE_DOCUMENT = 0 } }
abstract class PrintDocumentAdapter {
    abstract class LayoutResultCallback { open fun onLayoutFinished(info: PrintDocumentInfo, changed: Boolean) {}; open fun onLayoutCancelled() {} }
    abstract class WriteResultCallback { open fun onWriteFinished(pages: Array<PageRange>) {}; open fun onWriteFailed(error: CharSequence?) {} }
    abstract fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes?, cancellationSignal: CancellationSignal?, callback: LayoutResultCallback, extras: Bundle?)
    abstract fun onWrite(pages: Array<out PageRange>?, destination: ParcelFileDescriptor, cancellationSignal: CancellationSignal?, callback: WriteResultCallback)
}
class PrintJob
class PrintManager { fun print(name: String, adapter: PrintDocumentAdapter, attrs: PrintAttributes?): PrintJob = PrintJob() }
