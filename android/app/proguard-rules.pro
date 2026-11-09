# BillBox's own code is kept whole: the engine bridges are called from JavaScript by name (@JavascriptInterface) and
# screens read JSON by key, so nothing of ours is renamed or removed. R8 still shrinks the libraries.
-keep class com.local.billbox.** { *; }
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, SourceFile, LineNumberTable
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn org.jetbrains.annotations.**
