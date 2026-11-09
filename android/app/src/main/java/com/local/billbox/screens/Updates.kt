package com.local.billbox.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.J
import com.local.billbox.engine.Edition
import com.local.billbox.system.Platform
import com.local.billbox.system.Updater
import com.local.billbox.ui.Hint
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.SectionHeader

/** Settings › Updates: the newest BillBox release of this edition, downloaded and installed from here. */
@Composable
internal fun UpdatesPage() {
    val app = LocalApp.current
    var u by remember { mutableStateOf<J?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    suspend fun check() {
        busy = true; error = null
        try { u = Api.get("/update", mapOf("version" to Updater.version, "edition" to Edition.NAME, "platform" to "android")) }
        catch (e: Exception) { error = e.message } finally { busy = false }
    }
    LaunchedEffect(Unit) { check() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("Updates")
        Text("This phone has BillBox ${Updater.version.ifEmpty { "(unknown version)" }}", fontWeight = FontWeight.Medium)
        val x = u
        when {
            error != null -> Hint(error!!, color = MaterialTheme.colorScheme.error)
            x == null -> Hint("Looking for a new version…")
            x.bool("available") -> {
                Text("BillBox ${x.str("latest")} is available", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                if (x.str("notes").isNotEmpty()) Hint(x.str("notes").take(600))
                // The APK downloads in the browser and Android's installer opens it from there: BillBox itself does not ask to
                // install apps (that permission made Play Protect warn that BillBox might be harmful).
                Button(onClick = {
                    val f = x.obj("file")
                    Platform.openUrl(f.str("url").ifEmpty { x.str("page") })
                }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp)) {
                    Text("Download ${x.str("latest")}")
                }
                Hint("The new version downloads in your browser; open it from the download notice to install. Your books stay as they are; back up first to be safe (Settings › Backup).")
            }
            else -> Hint("BillBox is up to date${if (x.str("latest").isNotEmpty()) " (newest: ${x.str("latest")})" else ""}.")
        }
        OutlinedButton(onClick = { app.launch { check() } }, enabled = !busy, modifier = Modifier.fillMaxWidth().height(48.dp)) { Text("Look again") }
        Spacer(Modifier.height(80.dp))
    }
}
