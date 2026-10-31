package android.content.pm
abstract class PackageManager {
    abstract fun hasSystemFeature(name: String): Boolean
    abstract fun getPackageInfo(packageName: String, flags: Int): Any
    companion object { const val FEATURE_CAMERA_ANY = "camera" }
}

class ApplicationInfo { var flags: Int = 0; companion object { const val FLAG_DEBUGGABLE = 2 } }
