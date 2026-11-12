import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../api.dart';
import '../print/invoice_pdf.dart';
import '../state/app_state.dart';
import '../widgets.dart';
import 'drive_backup.dart';
import 'license_screen.dart';
import 'sync_screen.dart';
import 'update_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          PageHeader('Settings'),
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Companies'), Tab(text: 'Backup'), Tab(text: 'Printing'), Tab(text: 'Stock'), Tab(text: 'Sync'), Tab(text: 'Updates'), Tab(text: 'Licence')]),
          SizedBox(height: 14),
          Expanded(child: TabBarView(children: [_Companies(), _Backup(), _Printing(), _StockSettings(), SyncTab(), UpdateTab(), LicenseTab()])),
        ]),
      );
}

// ---------------------------------------------------------------- companies
class _Companies extends StatelessWidget {
  const _Companies();

  List<FieldSpec> _fields([Json? c]) {
    String v(String k, [String d = '']) => c == null || c[k] == null ? d : '${c[k]}';
    return [
      FieldSpec('name', 'Company / business name', initial: v('name')),
      FieldSpec('company_gstin', 'GSTIN (blank if unregistered)', initial: v('company_gstin')),
      FieldSpec('state_code', 'State code (09 = Uttar Pradesh, 07 = Delhi)', initial: v('state_code', '09')),
      FieldSpec('company_address', 'Address', initial: v('company_address')),
      FieldSpec('company_phone', 'Phone', initial: v('company_phone')),
      FieldSpec('invoice_terms', 'Terms printed on invoices', initial: v('invoice_terms', 'Goods once sold will not be taken back.')),
    ];
  }

  Future<void> _add(BuildContext context) async {
    final app = AppScope.read(context);
    final v = await formDialog(context, 'New company', _fields());
    if (v == null || !context.mounted) return;
    await guard(context, () async {
      final r = await Api.post('/companies', v) as Json;
      await app.reloadCompanies();
      if (context.mounted && await confirm(context, 'Company created', 'Open ${v['name']} now?', ok: 'Open it')) await app.switchCompany(r['id'] as int);
    });
  }

  Future<void> _edit(BuildContext context, Json c) async {
    final app = AppScope.read(context);
    final v = await formDialog(context, 'Edit ${c['name']}', _fields(c));
    if (v == null || !context.mounted) return;
    await guard(context, () async {
      await Api.put('/companies/${c['id']}', v);
      await app.reloadCompanies();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(children: [
      Row(children: [
        const Expanded(child: Text('Each company has its own separate books: items, parties, bills and ledgers. Switching never mixes data.', style: TextStyle(color: Palette.muted))),
        FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add_business_outlined), label: const Text('Add company')),
      ]),
      const SizedBox(height: 14),
      for (final c in app.companies)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(backgroundColor: Palette.teal.withValues(alpha: .12), child: Text('${c['name']}'.substring(0, 1).toUpperCase(), style: const TextStyle(color: Palette.teal, fontWeight: FontWeight.w700))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('GSTIN ${(c['company_gstin'] ?? '') == '' ? 'not set' : c['company_gstin']}  ·  State ${c['state_code']}  ·  ${c['company_address'] ?? ''}', style: const TextStyle(color: Palette.muted, fontSize: 12)),
                ]),
              ),
              if (c['id'] == app.companyId)
                const Chip(label: Text('Open now'), backgroundColor: Color(0x1F2E7D5B))
              else
                OutlinedButton(onPressed: () => guard(context, () => app.switchCompany(c['id'] as int)), child: const Text('Switch to')),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, c)),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- backup
class _Backup extends StatefulWidget {
  const _Backup();
  @override
  State<_Backup> createState() => _BackupState();
}

class _BackupState extends State<_Backup> {
  final dirCtl = TextEditingController(), keepCtl = TextEditingController();
  bool enabled = false, busy = false, loaded = false;
  String time = '21:00', lastStatus = '', lastRun = '';
  List<Json> backups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _fill(Json r) {
    final c = r['config'] as Json;
    dirCtl.text = '${c['dir']}';
    keepCtl.text = '${c['keep']}';
    enabled = c['enabled'] == true;
    time = '${c['time']}';
    lastStatus = '${c['last_status']}';
    lastRun = '${c['last_run']}';
    backups = (r['backups'] as List).cast<Json>();
    loaded = true;
  }

  Future<void> _load() => guard(context, () async {
        final r = await Api.get('/backup') as Json;
        if (mounted) setState(() => _fill(r));
      });

  Future<void> _saveCfg() => guard(context, () async {
        await Api.put('/backup/config', {'dir': dirCtl.text.trim(), 'enabled': enabled, 'time': time, 'keep': keepCtl.text.trim()});
        if (mounted) toast(context, enabled ? 'Saved. A backup will run every day at $time while the app is open.' : 'Saved. Automatic backup is off.');
      });

  Future<void> _now() async {
    setState(() => busy = true);
    await guard(context, () async {
      await _saveCfgQuiet();
      final r = await Api.post('/backup/run', {}) as Json;
      if (mounted) {
        toast(context, 'Backup complete: ${r['folder']}');
        setState(() => _fill(r));
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _saveCfgQuiet() => Api.put('/backup/config', {'dir': dirCtl.text.trim(), 'keep': keepCtl.text.trim()});

  Future<void> _browse() async {
    final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose the backup folder (for example on an external drive)');
    if (d != null) setState(() => dirCtl.text = d);
  }

  Future<void> _pickTime() async {
    final p = time.split(':');
    final t0 = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t0 != null) setState(() => time = '${t0.hour.toString().padLeft(2, '0')}:${t0.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _restoreFolder() async {
    final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a backup folder (FMCG_Backup_…)');
    if (d != null && mounted && await restoreBackup(context, folder: d, label: d.split(RegExp(r'[\\/]')).last)) _load();
  }

  Future<void> _restoreFile() async {
    final r = await FilePicker.platform.pickFiles(dialogTitle: 'One company file (.db) from a backup', type: FileType.custom, allowedExtensions: ['db']);
    final f = r?.files.single.path;
    if (f != null && mounted && await restoreBackup(context, file: f, companyId: AppScope.read(context).companyId, label: f.split(RegExp(r'[\\/]')).last)) _load();
  }

  String _size(num b) => b > 1e6 ? '${(b / 1e6).toStringAsFixed(1)} MB' : '${(b / 1e3).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final ok = lastStatus.startsWith('OK');
    return ListView(children: [
      Panel(
        title: 'Backup to a folder on this computer or an external drive',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: AppField(controller: dirCtl, label: 'Backup folder (full path)')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _browse, icon: const Icon(Icons.folder_open), label: const Text('Browse…')),
          ]),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Back up automatically every day'),
            subtitle: Text('At $time. If the computer was off at that time, it runs shortly after the app starts.'),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.schedule), label: Text('Time  $time')),
            AppField(width: 160, controller: keepCtl, number: true, label: 'Keep last N backups'),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton(onPressed: _saveCfg, child: const Text('Save settings')),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: busy ? null : _now,
              icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup_outlined),
              label: Text(busy ? 'Backing up…' : 'Backup now'),
            ),
          ]),
          const SizedBox(height: 12),
          if (lastStatus.isNotEmpty)
            Text(ok ? 'Last backup OK: ${lastStatus.substring(3)}' : lastStatus, style: TextStyle(color: ok ? Palette.leaf : Palette.brick, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Each backup is a new folder named FMCG_Backup_YYYYMMDD_HHMMSS holding a verified copy of every company\'s database — the same backup the Mac, iPhone and Android make, so it restores on any of them.',
              style: TextStyle(color: Palette.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(onPressed: _restoreFolder, icon: const Icon(Icons.settings_backup_restore), label: const Text('Restore from a backup folder…')),
            OutlinedButton.icon(onPressed: _restoreFile, icon: const Icon(Icons.description_outlined), label: const Text('Restore one company file (.db)…')),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      DrivePanel(onRestored: _load),
      const SizedBox(height: 14),
      Panel(
        title: 'Backups in this folder',
        child: backups.isEmpty
            ? const Text('No backups yet.', style: TextStyle(color: Palette.muted))
            : table(['Folder', 'Created', 'Files', 'Size', ''], [
                for (final b in backups)
                  [
                    Text(b['name']),
                    Text('${b['created'] ?? 'incomplete'}'.replaceFirst('T', ' ').split('.').first),
                    t('${b['files']}'),
                    t(_size(num_(b['bytes']))),
                    TextButton(onPressed: () async { if (await restoreBackup(context, name: '${b['name']}', label: '${b['name']}')) _load(); }, child: const Text('Restore…')),
                  ],
              ], numeric: {2, 3}),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- printing
class _Printing extends StatefulWidget {
  const _Printing();
  @override
  State<_Printing> createState() => _PrintingState();
}

class _PrintingState extends State<_Printing> {
  List<Printer> printers = [];
  bool direct = false, loading = true;
  late PrintLayout layout;
  late bool auto;
  String printerName = '';
  String gstLines = 'split';

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    layout = PrintLayoutInfo.parse(s['print_layout'] as String?);
    auto = s['print_auto'] == '1';
    printerName = '${s['print_printer'] ?? ''}';
    gstLines = s['print_gst_lines'] == 'rate' ? 'rate' : 'split';
    _scan();
  }

  Future<void> _scan() async {
    try {
      direct = (await Printing.info()).directPrint;
      printers = direct ? await Printing.listPrinters() : [];
    } catch (_) {
      direct = false;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      Panel(
        title: 'Invoice printing',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppDropdown<PrintLayout>(
            width: 480,
            label: 'Default layout',
            value: layout,
            options: {for (final l in PrintLayout.values) l: l.label},
            onChanged: (v) => layout = v ?? layout,
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else if (printers.isEmpty)
            const Text('No printer list available. The system print sheet is used when you press Print.', style: TextStyle(color: Palette.muted))
          else
            AppDropdown<String>(
              width: 480,
              label: 'Default printer',
              value: printers.any((p) => p.name == printerName) ? printerName : '',
              options: {'': 'Ask every time', for (final p in printers) p.name: p.name},
              onChanged: (v) => printerName = v ?? '',
            ),
          const SizedBox(height: 12),
          AppDropdown<String>(
            width: 480,
            label: 'GST in the totals',
            value: gstLines,
            options: const {'split': 'CGST and SGST', 'rate': 'One line per rate (GST @5%)'},
            onChanged: (v) => gstLines = v ?? gstLines,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Print straight after saving a bill'),
            subtitle: const Text('Skips the preview and uses the default printer. You can still open the preview from All bills.'),
            value: auto,
            onChanged: (v) => setState(() => auto = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => guard(context, () async {
              await AppScope.read(context).saveSettings({'print_layout': layout.name, 'print_printer': printerName, 'print_auto': auto ? '1' : '0', 'print_gst_lines': gstLines});
              if (context.mounted) toast(context, 'Printing settings saved for this company');
            }),
            child: const Text('Save'),
          ),
          const SizedBox(height: 14),
          const Text('Half-A4 means 210 × 148.5 mm. Load half-A4 stationery (or A5 landscape) and choose that paper size for the printer. For plain A4 paper, use the "Original on top, Duplicate below" layout and cut along the line.',
              style: TextStyle(color: Palette.muted, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- stock
/// One company-wide low-stock level (items have no individual reorder level).
class _StockSettings extends StatefulWidget {
  const _StockSettings();
  @override
  State<_StockSettings> createState() => _StockSettingsState();
}

class _StockSettingsState extends State<_StockSettings> {
  late final TextEditingController low;

  @override
  void initState() {
    super.initState();
    low = TextEditingController(text: '${AppScope.read(context).settings['low_stock_qty'] ?? 10}');
  }

  @override
  void dispose() {
    low.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
        Panel(
          title: 'Low stock alert',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('An item that has been stocked before is listed as low when its stock is at or below this many pieces. The same level applies to every item.', style: TextStyle(color: Palette.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppField(width: 200, controller: low, number: true, label: 'Low stock level (pieces)'),
              FilledButton(
                onPressed: () => guard(context, () async {
                  await AppScope.read(context).saveSettings({'low_stock_qty': low.text.trim()});
                  if (context.mounted) toast(context, 'Saved. The dashboard and Stock page use this level.');
                }),
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),
      ]);
}
