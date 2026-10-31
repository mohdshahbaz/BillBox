package com.local.billbox

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.local.billbox.system.Platform
import com.local.billbox.system.SelfTest
import com.local.billbox.ui.BillBoxTheme
import com.local.billbox.ui.MainScaffold
import com.local.billbox.ui.UiPrefs

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Platform.attach(this)
        val app = (application as BillBoxApp).state
        val prefs = (application as BillBoxApp).ui
        if (SelfTest.wanted(this)) {
            // GitHub's emulator check: replay the parity session first, then show the app and walk its screens
            SelfTest.begin(this, app)
            setContent {
                if (SelfTest.replaying) androidx.compose.material3.Text("BillBox self-test: replaying the working session…")
                else BillBoxTheme(prefs) { MainScaffold(app) }
            }
            return
        }
        setContent {
            BillBoxTheme(prefs) { MainScaffold(app) }
        }
    }

    override fun onResume() { super.onResume(); (application as BillBoxApp).state.onForeground() }
    override fun onPause() { super.onPause(); (application as BillBoxApp).state.onBackground() }
}
