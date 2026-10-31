package com.local.billbox

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.local.billbox.system.Platform
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
        setContent {
            BillBoxTheme(prefs) { MainScaffold(app) }
        }
    }

    override fun onResume() { super.onResume(); (application as BillBoxApp).state.onForeground() }
    override fun onPause() { super.onPause(); (application as BillBoxApp).state.onBackground() }
}
