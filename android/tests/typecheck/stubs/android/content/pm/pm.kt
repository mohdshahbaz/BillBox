package android.content.pm
abstract class PackageManager {
    abstract fun hasSystemFeature(name: String): Boolean
    abstract fun getPackageInfo(packageName: String, flags: Int): PackageInfo
    abstract fun canRequestPackageInstalls(): Boolean
    companion object { const val FEATURE_CAMERA_ANY = "camera" }
}

class ApplicationInfo { var flags: Int = 0; companion object { const val FLAG_DEBUGGABLE = 2 } }

class PackageInfo { @JvmField var versionName: String? = null }
