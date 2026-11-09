package com.local.billbox.system


/** Settings › Updates: this app's version (the new APK is downloaded in the browser). */
object Updater {
    /** This app's version (from the release build, e.g. 16.2.12 or 16.2.12-admin). */
    val version: String
        get() = try {
            val c = Platform.context
            c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: ""
        } catch (_: Exception) { "" }
}
