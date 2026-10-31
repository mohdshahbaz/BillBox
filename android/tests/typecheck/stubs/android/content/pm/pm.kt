package android.content.pm
abstract class PackageManager {
    abstract fun hasSystemFeature(name: String): Boolean
    abstract fun getPackageInfo(packageName: String, flags: Int): Any
    companion object { const val FEATURE_CAMERA_ANY = "camera" }
}
