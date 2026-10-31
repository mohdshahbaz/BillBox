@file:Suppress("unused", "UNUSED_PARAMETER")
package android.webkit
annotation class JavascriptInterface
class WebSettings { var javaScriptEnabled = false; var allowFileAccessFromFileURLs = false; var allowFileAccess = false; var domStorageEnabled = false }
open class WebChromeClient { open fun onConsoleMessage(m: ConsoleMessage): Boolean = false }
class ConsoleMessage { enum class MessageLevel { ERROR, LOG }; fun messageLevel(): MessageLevel = MessageLevel.LOG; fun message(): String = ""; fun sourceId(): String = ""; fun lineNumber(): Int = 0 }
class WebView(context: android.content.Context) {
    val settings: WebSettings = WebSettings()
    var webChromeClient: WebChromeClient? = null
    fun addJavascriptInterface(o: Any, name: String) {}
    fun loadUrl(url: String) {}
    fun evaluateJavascript(script: String, cb: android.webkit.ValueCallback<String>?) {}
}
fun interface ValueCallback<T> { fun onReceiveValue(v: T) }
