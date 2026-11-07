package com.local.billbox.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate

enum class Page(val title: String) {
    Dashboard("Dashboard"), Billing("Billing"), Purchases("Purchases"), Bills("All Bills"), Stock("Stock"), Parties("Parties"),
    Salesmen("Salesmen"), Reports("Books & GST"), Settings("Settings"), DebitNotes("Debit Notes");

    companion object { fun of(s: String?) = entries.firstOrNull { it.name.equals(s, true) } }
}

data class Toast(val text: String, val error: Boolean, val stamp: Long = System.nanoTime())

/** A bill, purchase or debit note another screen should open for editing. */
data class PendingEdit(val type: String, val id: Int)

/** A PDF ready to print or share (bills, vouchers, debit notes); sale bills in it are marked printed once sent to the printer. */
data class PrintJob(val title: String, val fileName: String, val pdf: java.io.File, val invoiceIds: List<Int> = emptyList(), val stamp: Long = System.nanoTime())

/** App-wide state: which company is open, which financial year is being viewed, its settings, navigation and messages. */
class AppState(private val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val prefs = context.getSharedPreferences("billbox", Context.MODE_PRIVATE)

    var companies by mutableStateOf(listOf<J>())
    var companyId by mutableStateOf<Int?>(null)
    var settings by mutableStateOf(J())
    var ready by mutableStateOf(false)
    var startError by mutableStateOf<String?>(null)
    var section by mutableStateOf(Page.of(prefs.getString("startPage", "billing")) ?: Page.Billing)
    var toast by mutableStateOf<Toast?>(null)
    var pendingEdit by mutableStateOf<PendingEdit?>(null)
    var printJob by mutableStateOf<PrintJob?>(null)
    var openUnprinted by mutableStateOf(false)
    var itemsVersion by mutableIntStateOf(0)
    /** Bumped (after a short pause, so a burst of writes reloads once) whenever data changed; list screens reload on it. */
    var dataVersion by mutableIntStateOf(0)
    private var dataBump: kotlinx.coroutines.Job? = null

    // Financial year (1 April – 31 March): every list, report and the dashboard show only the selected year.
    var fy by mutableStateOf("")
        private set
    var fyYears by mutableStateOf(listOf<J>())

    val company: J? get() = companies.firstOrNull { it.id == companyId }
    val companyName: String get() = company?.str("name") ?: "BillBox"
    val lowStockQty: Double get() = if (settings.has("low_stock_qty")) settings.num("low_stock_qty") else 10.0
    val defaultPayMode: String get() = settings.str("bill_pay_mode").takeIf { it in listOf("CASH", "UPI", "CARD", "CREDIT") } ?: "CREDIT"
    val defaultSaleType: String get() = if (settings.str("bill_sale_type") == "VAN") "VAN" else "COUNTER"
    val dashboardHidden: Set<String> get() = settings.str("dash_hide").split(',').filter { it.isNotBlank() }.toSet()

    val fyInfo: J? get() = fyYears.firstOrNull { it.str("label") == fy } ?: fyYears.firstOrNull { it.bool("current") }
    val fyLabel: String get() = fyInfo?.str("label") ?: ""
    val fyFrom: String get() = fyInfo?.str("from") ?: ""
    val fyTo: String get() = fyInfo?.str("to") ?: ""
    val isCurrentFY: Boolean get() = fyInfo?.bool("current") ?: true
    /** Today, or the last day of the year when an earlier year is open (so new entries land inside that year). */
    val dateInFY: String get() {
        val t = Fmt.today
        if (fyFrom.isEmpty()) return t
        return if (t < fyFrom) fyFrom else if (t > fyTo) fyTo else t
    }
    val monthStartInFY: String get() = dateInFY.take(7) + "-01"

    fun setting(k: String) = settings.str(k)

    /** Screen state that outlives switching tabs (the bill being typed), kept per company and year like the iPhone's tabs. */
    private val kept = mutableMapOf<String, Any>()
    @Suppress("UNCHECKED_CAST")
    fun <T : Any> keep(name: String, make: () -> T): T = kept.getOrPut("$companyId|$fy|$name", make) as T

    suspend fun start() {
        Api.onItemsChanged = { scope.launch { itemsVersion++ } }
        Api.onDataChanged = { scope.launch { dataBump?.cancel(); dataBump = scope.launch { kotlinx.coroutines.delay(300); dataVersion++ } } }
        try {
            reloadCompanies(pick = true)
            startError = null
        } catch (e: Exception) {
            startError = e.message
        }
        ready = true
        startSyncLoop()
    }

    private var syncLoop: kotlinx.coroutines.Job? = null
    private var syncVersion = -1
    /** Live sync (Settings › Sync): every 3 s the engine swaps changes with the other devices; when some arrived, every
     *  open screen reloads (dataVersion) and the billing lists too. */
    private fun startSyncLoop() {
        if (syncLoop != null) return
        syncLoop = scope.launch {
            while (true) {
                kotlinx.coroutines.delay(3000)
                val r = try { Api.get("/sync/tick") } catch (_: Exception) { null } ?: continue
                if (!r.bool("on")) continue
                val v = r.int("version")
                if (syncVersion >= 0 && v != syncVersion) {
                    Api.onDataChanged?.invoke()
                    Api.onItemsChanged?.invoke()
                    try { settings = Api.get("/settings") } catch (_: Exception) {}
                }
                syncVersion = v
            }
        }
    }

    suspend fun reloadCompanies(pick: Boolean = false) {
        val r = Api.get("/companies")
        companies = r.list("companies")
        if (pick || companyId == null || company == null) {
            val last = r.optInt("last_used")
            companyId = if (companies.any { it.id == last }) last else companies.firstOrNull()?.id
        }
        Api.companyId = companyId
        settings = Api.get("/settings")
        loadYears()
    }

    suspend fun loadYears() {
        val r = Api.get("/fy")
        fyYears = r.list("years")
        if (fyYears.none { it.str("label") == fy }) setYear(r.str("current"))
    }

    fun setYear(label: String) {
        fy = label
        Api.fy = label.ifEmpty { null }
    }

    suspend fun switchCompany(id: Int) {
        if (id == companyId) return
        guarded {
            companyId = id
            Api.companyId = id
            Api.obj("POST", "/companies/$id/activate")
            settings = Api.get("/settings")
            setYear("")
            loadYears()
        }
    }

    suspend fun saveSettings(changes: Map<String, Any?>) {
        guarded { settings = Api.obj("PUT", "/settings", body = changes) }
    }

    fun notify(text: String, error: Boolean = false) {
        val t = Toast(text, error)
        toast = t
        scope.launch {
            delay(if (error) 7000 else 3500)
            if (toast == t) toast = null
        }
    }

    /** Runs work and shows any failure as a message instead of crashing or going silent. */
    suspend fun guarded(work: suspend () -> Unit) {
        try { work() } catch (e: kotlinx.coroutines.CancellationException) { throw e } catch (e: Exception) { notify(e.message ?: "Something went wrong", error = true) }
    }

    fun launch(work: suspend () -> Unit) = scope.launch { guarded(work) }

    // MARK: year books (Marg style: each financial year can be its own company file with the same name)

    data class YearChoice(val label: String, val from: String, val to: String, val current: Boolean, val bookId: Int) {
        val title: String get() = if (label.isEmpty()) "Main books (years without their own file)"
            else "FY $label  (${Fmt.dmy(from)} to ${Fmt.dmy(to)})" + if (current) "  · current" else ""
    }

    private fun bookKey(c: J) = c.str("name").split(' ').filter { it.isNotEmpty() }.joinToString(" ").lowercase()
    val currentFYStart: Int get() { val t = LocalDate.now(); return if (t.monthValue < 4) t.year - 1 else t.year }
    val booksFY: String get() = company?.str("fy") ?: ""
    val siblingBooks: List<J> get() { val c = company ?: return emptyList(); val k = bookKey(c); return companies.filter { bookKey(it) == k } }

    /** One entry per company name: the main books, else the newest year file. */
    val companyGroups: List<J> get() {
        val seen = mutableSetOf<String>(); val out = mutableListOf<J>()
        for (c in companies) {
            val k = bookKey(c)
            if (!seen.add(k)) continue
            val same = companies.filter { bookKey(it) == k }
            out.add(same.firstOrNull { it.str("fy").isEmpty() } ?: same.maxByOrNull { it.str("fy") } ?: c)
        }
        return out
    }
    fun isOpenGroup(c: J) = company?.let { bookKey(it) == bookKey(c) } ?: false

    val yearChoices: List<YearChoice> get() {
        val cid = companyId ?: return emptyList()
        val byLabel = linkedMapOf<String, YearChoice>()
        for (y in fyYears) byLabel[y.str("label")] = YearChoice(y.str("label"), y.str("from"), y.str("to"), y.bool("current"), cid)
        for (s in siblingBooks) if (s.id != cid && s.str("fy").isNotEmpty()) {
            val l = s.str("fy"); val start = l.take(4).toIntOrNull() ?: 0
            byLabel[l] = YearChoice(l, "$start-04-01", "${start + 1}-03-31", start == currentFYStart, s.id)
        }
        val out = byLabel.values.sortedByDescending { it.label }.toMutableList()
        if (booksFY.isNotEmpty()) siblingBooks.firstOrNull { it.str("fy").isEmpty() }?.let { out.add(YearChoice("", "", "", false, it.id)) }
        return out
    }

    /** A party's ledger for one financial year; a year kept in its own file has its own copy of the party, found there by name. */
    suspend fun ledger(party: J, year: String): J {
        val choice = yearChoices.firstOrNull { it.label == year }
        if (choice == null || choice.bookId == companyId) return Api.get("/parties/${party.id}/ledger", mapOf("fy" to year))
        val name = party.str("name").lowercase()
        val p = Api.list("/parties", mapOf("q" to party.str("name"), "fy" to year), company = choice.bookId).firstOrNull { it.str("name").lowercase() == name }
            ?: throw Exception("${party.str("name")} is not in the FY $year books.")
        return Api.get("/parties/${p.id}/ledger", mapOf("fy" to year), company = choice.bookId)
    }

    suspend fun chooseYear(y: YearChoice) {
        if (y.bookId != companyId) switchCompany(y.bookId)
        if (y.label.isNotEmpty()) setYear(y.label)
    }

    suspend fun addYearBooks(fy: String, carry: Boolean) {
        val cid = companyId ?: return
        guarded {
            val r = Api.obj("POST", "/companies/$cid/years", body = mapOf("fy" to fy, "carry" to carry))
            reloadCompanies()
            switchCompany(r.int("id"))
            notify("FY $fy books are ready" + if (carry) ": items, parties and opening balances carried forward." else " (empty).")
        }
    }

    // MARK: daily backup while BillBox is open (checked every minute and shortly after opening, like the Mac)

    private var backupTimer: kotlinx.coroutines.Job? = null

    fun onForeground() {
        backupTimer?.cancel()
        backupTimer = scope.launch {
            delay(5000)
            while (true) {
                try { com.local.billbox.system.BackupWork.tick()?.let { notify("Backup complete: " + it.substringAfterLast('/')) } } catch (_: Exception) {}
                delay(60_000)
            }
        }
    }

    /** Leaving BillBox counts as quitting for "Back up when I quit" (Android has no quit). */
    fun onBackground() {
        backupTimer?.cancel(); backupTimer = null
        if (!ready || startError != null) return
        scope.launch {
            try {
                val c = Api.get("/backup").obj("config")
                if (c.bool("on_exit")) Api.obj("POST", "/backup/run", body = emptyMap<String, Any>())
            } catch (_: Exception) {}
        }
    }

    fun fyLabelFor(start: Int) = "$start-" + (start + 1).toString().takeLast(2)
}
