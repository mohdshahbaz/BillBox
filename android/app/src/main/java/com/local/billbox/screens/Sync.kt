package com.local.billbox.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.local.billbox.data.Api
import com.local.billbox.data.Fmt
import com.local.billbox.data.J
import com.local.billbox.ui.Field
import com.local.billbox.ui.Hint
import com.local.billbox.ui.LocalApp
import com.local.billbox.ui.SectionHeader
import com.local.billbox.ui.copyText

/**
 * Settings › Sync: live sync of a company's books between this phone, the Mac and Windows/Linux PCs through the BillBox
 * Firebase database (backend services/sync.js). AppState calls GET /sync/tick every few seconds.
 */
@Composable
internal fun SyncPage() {
    val app = LocalApp.current
    var s by remember { mutableStateOf(J()) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var remote by remember { mutableStateOf<List<J>?>(null) }
    var canMerge by remember { mutableStateOf(false) }
    var mergeKey by remember { mutableStateOf<String?>(null) }
    val signedIn = s.bool("signed_in")
    val on = s.bool("on")
    val name = app.company?.str("name") ?: "this company"
    suspend fun loadRemote() { if (s.bool("signed_in")) try { val r = Api.get("/sync/remote"); remote = r.list("books"); canMerge = r.bool("can_merge") } catch (e: Exception) { app.notify(e.message ?: "Could not read the sync account.", true) } }
    LaunchedEffect(app.companyId) { try { s = Api.get("/sync") } catch (_: Exception) {}; if (remote == null) loadRemote() }
    fun run(path: String, body: Map<String, Any?> = emptyMap(), done: String? = null) = app.launch {
        busy = true
        try {
            s = Api.obj("POST", path, body = body)
            if (path == "/sync/join") app.reloadCompanies()
            if (path == "/sync/merge") { app.reloadCompanies(); app.switchCompany(s.int("company_id")) }
            if (s.str("last_error").isNotEmpty()) app.notify(s.str("last_error"), true) else if (done != null) app.notify(done)
            if (path == "/sync/signin") password = ""
            if (path == "/sync/signout") remote = null else loadRemote()
        } finally { busy = false }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("Live sync")
        Text(if (!signedIn) "Not signed in" else if (on) "$name is synced live" else "Signed in as ${s.str("email")}",
            fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium, color = if (on) Color(0xFF2E7D32) else MaterialTheme.colorScheme.onSurface)
        if (signedIn) Hint(if (on) "Changes made on any device show on the others within a few seconds." else "Turn on sync for $name to share it with your other devices.")
        if (s.str("last_sync").isNotEmpty()) Hint("Last sync: ${Fmt.ist(s.str("last_sync"))}" + if (s.int("pending") > 0) " · ${s.int("pending")} changes waiting" else "")
        if (s.str("last_error").isNotEmpty()) Hint(s.str("last_error"), color = MaterialTheme.colorScheme.error)
        if (!signedIn) {
            Field("E-mail", email, { email = it }, kb = com.local.billbox.ui.Kb.Email)
            OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("Password (6 or more characters)") },
                visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth())
            SyncBtn(if (busy) "Signing in…" else "Sign in", prominent = true, enabled = !busy && email.isNotBlank() && password.isNotEmpty()) {
                run("/sync/signin", mapOf("email" to email, "password" to password, "create" to false), "Signed in to sync.")
            }
            SyncBtn("Create a sync account", enabled = !busy && email.isNotBlank() && password.length >= 6) {
                run("/sync/signin", mapOf("email" to email, "password" to password, "create" to true), "Sync account made. Now turn on sync for a company, or bring one here from your other device.")
            }
        } else {
            if (on) {
                SyncBtn(if (busy) "Syncing…" else "Sync now", prominent = true, enabled = !busy) { run("/sync/now") }
                SyncBtn("Stop syncing $name on this phone", destructive = true, enabled = !busy) { run("/sync/off") }
            } else {
                SyncBtn(if (busy) "Sending the books…" else "Turn on sync for $name", prominent = true, enabled = !busy) { run("/sync/on", done = "$name is synced now.") }
            }
            SyncBtn("Sign out of sync", enabled = !busy) { run("/sync/signout") }
        }
        Hint("Every device keeps its own copy of the books and works without internet; changes go across when it is online. Sign in with the same account on each device. Stock sold on two devices at once counts both sales; two bills made at the same moment keep different numbers.")

        if (signedIn) {
            SectionHeader("Companies in your sync account")
            remote?.forEach { b ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(b.str("name"), fontWeight = FontWeight.Medium)
                        if (b.str("fy").isNotEmpty()) Hint("Year ${b.str("fy")}")
                        // which copy is open here, and which devices use each copy
                        val arr = b.o.optJSONArray("used_by")
                        val names = mutableListOf<String>()
                        if (arr != null) for (i in 0 until arr.length()) names.add(arr.optString(i))
                        val who = names.joinToString(", ")
                        val line = listOfNotNull(if (b.bool("open")) "Open now" else null, if (who.isNotEmpty()) "Used by: $who" else null).joinToString(" · ")
                        if (line.isNotEmpty()) Hint(line)
                    }
                    if (b.bool("same_name") && canMerge) Button(onClick = { mergeKey = b.str("key") }, enabled = !busy) { Text("Merge") }
                    else if (b.bool("on_this_device")) Hint("On this phone")
                    else TextButton(onClick = { run("/sync/join", mapOf("key" to b.str("key")), "The company is on this phone now. Switch to it from the company list.") }, enabled = !busy) { Text("Bring here") }
                }
            }
            if (remote?.isEmpty() == true) Hint("No company is synced in this account yet.")
            if (canMerge && remote?.any { it.bool("same_name") } == true) Hint("$name is in the account twice: each device turned on sync for its own copy, so they do not see each other's bills. Merge puts this phone's bills, parties and stock changes into the other copy and makes it the one used here (a backup is made first).")
            SyncBtn(if (remote == null) "Show the companies in this account" else "Look again", enabled = !busy) { app.launch { loadRemote() } }
        }

        SectionHeader("One-time Firebase setup")
        Hint("1. Firebase console › Authentication › Sign-in method › turn on Email/Password.\n2. Realtime Database › Rules › paste these rules and Publish:")
        Text(s.str("rules"), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        SyncBtn("Copy rules") { copyText(s.str("rules")); app.notify("Rules copied.") }
        Spacer(Modifier.height(80.dp))
    }
    mergeKey?.let { k ->
        AlertDialog(onDismissRequest = { mergeKey = null }, title = { Text("Merge $name into the other copy?") },
            text = { Text("This phone's bills, parties and stock changes since sync was turned on go into the other copy, which every device then shares. This phone's copy is backed up first and kept hidden.") },
            confirmButton = { TextButton(onClick = { mergeKey = null; run("/sync/merge", mapOf("key" to k), "Merged: this phone's changes went into the shared copy.") }) { Text("Merge") } },
            dismissButton = { TextButton(onClick = { mergeKey = null }) { Text("Cancel") } })
    }
}

@Composable
private fun SyncBtn(title: String, prominent: Boolean = false, destructive: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val m = Modifier.fillMaxWidth().height(48.dp)
    if (prominent) Button(onClick = onClick, enabled = enabled, modifier = m) { Text(title) }
    else OutlinedButton(onClick = onClick, enabled = enabled, modifier = m) {
        if (destructive) Text(title, color = MaterialTheme.colorScheme.error) else Text(title)
    }
}
