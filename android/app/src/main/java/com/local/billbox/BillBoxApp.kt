package com.local.billbox

import android.app.Application
import android.content.Context
import com.local.billbox.data.AppState
import com.local.billbox.engine.Engine
import com.local.billbox.system.BackupWork
import com.local.billbox.system.CrashCatcher
import com.local.billbox.ui.UiPrefs

class BillBoxApp : Application() {
    /** App-wide state lives as long as the process, so turning the phone or switching apps keeps the bill being made. */
    lateinit var state: AppState
    lateinit var ui: UiPrefs

    override fun onCreate() {
        super.onCreate()
        CrashCatcher.install(this)
        Engine.start(this)
        BackupWork.schedule(this)
        state = AppState(this)
        ui = UiPrefs(getSharedPreferences("billbox_ui", Context.MODE_PRIVATE))
    }
}
