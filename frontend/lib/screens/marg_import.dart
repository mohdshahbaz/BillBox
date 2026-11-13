import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Settings › Marg import: items, parties, bills, receipts and payments from a Marg "Export All Data" CSV backup
/// (a folder or a .zip), with the same checks as the Mac (backend/src/services/margImport.js). The engine reads the files
/// from this computer by their path. Importing twice is safe: what is already here is matched and skipped.
class MargImportTab extends StatefulWidget {
  const MargImportTab({super.key});
  @override
  State<MargImportTab> createState() => _MargImportTabState();
}

class _MargImportTabState extends State<MargImportTab> {
  String? path;
  Json? preview, result, prices;
  String? problem, priceProblem;
  bool busy = false;

  Future<void> _choose({required bool zip}) async {
    String? p;
    if (zip) {
      final r = await FilePicker.platform.pickFiles(dialogTitle: 'Choose the Marg backup (.zip)', type: FileType.custom, allowedExtensions: ['zip']);
      p = r?.files.single.path;
    } else {
      p = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose the Marg backup folder');
    }
    if (p == null || !mounted) return;
    setState(() {
      path = p;
      preview = null;
      result = null;
      prices = null;
      problem = null;
      priceProblem = null;
    });
    await _preview();
  }

  Future<void> _preview() async {
    setState(() => busy = true);
    try {
      final r = await Api.post('/import/marg/preview', {'path': path}) as Json;
      preview = r;
      problem = null;
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _import() async {
    final app = AppScope.read(context);
    if (!await confirm(context, 'Import into ${app.companyName}?', 'Items, parties, bills, receipts and payments from this Marg backup are added. What is already here is kept and skipped.', ok: 'Import')) return;
    setState(() => busy = true);
    try {
      final r = await Api.post('/import/marg', {'path': path}) as Json;
      result = r;
      problem = null;
      app.dataVersion++;
      if (mounted) toast(context, 'Marg data imported into ${app.companyName}.');
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _prices({required bool apply}) async {
    setState(() => busy = true);
    try {
      final r = await Api.post('/import/marg/prices', {'path': path, 'apply': apply}) as Json;
      prices = r;
      priceProblem = null;
      if (apply && mounted) toast(context, 'Corrected the prices of ${r['changed']} items.');
    } on ApiException catch (e) {
      priceProblem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 220, child: Text(k, style: TextStyle(color: Palette.muted))),
          Text(v, style: tabular.copyWith(fontWeight: FontWeight.w600, color: color ?? Palette.ink)),
        ]),
      );

  Widget _check(String label, Json? c) {
    if (c == null) return const SizedBox.shrink();
    final problems = ((c['problems'] as List?) ?? []).cast<String>();
    final ok = problems.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber, size: 18, color: ok ? Palette.leaf : Palette.turmeric),
          const SizedBox(width: 8),
          Text('$label: ${c['ok']} of ${c['checked']} match'),
        ]),
        for (final p in problems.take(50)) Padding(padding: const EdgeInsets.only(left: 26), child: Text(p, style: TextStyle(fontSize: 12, color: Palette.turmeric))),
      ]),
    );
  }

  String _n(Json? m, String k) => '${num_(m?[k]).toInt()}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = preview;
    final found = (p?['found'] as Json?) ?? {};
    final totals = (p?['totals'] as Json?) ?? {};
    final checks = (p?['checks'] as Json?) ?? {};
    final period = p?['period'] as Json?;
    final adds = (result?['added'] ?? p?['would_add']) as Json?;
    final here = (result?['already_here'] ?? p?['already_here']) as Json?;
    final numbering = result?['numbering'] as Json?;
    return ListView(children: [
      Panel(
        title: 'Import from Marg',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('In Marg: Reports › Management Report › Data Transfer Utility › Export All Data › CSV. Then choose the folder it made, or a .zip of it.',
              style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: busy ? null : () => _choose(zip: false), icon: const Icon(Icons.folder_open), label: const Text('Choose the Marg backup folder…')),
            OutlinedButton.icon(onPressed: busy ? null : () => _choose(zip: true), icon: const Icon(Icons.folder_zip_outlined), label: const Text('Choose a .zip…')),
          ]),
          if (path != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(path!, style: const TextStyle(fontSize: 12))),
          if (busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(problem!, style: TextStyle(color: Palette.brick))),
        ]),
      ),
      if (p != null) ...[
        const SizedBox(height: 12),
        Panel(
          title: period == null ? 'In the backup' : 'In the backup: ${dmy(period['from'])} to ${dmy(period['to'])}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Items', _n(found, 'items')),
            _kv('Customers', _n(found, 'customers')),
            _kv('Suppliers', _n(found, 'suppliers')),
            _kv('Sale bills', '${_n(found, 'sales')}  ·  ${money(totals['sales'])}'),
            _kv('Purchase bills', '${_n(found, 'purchases')}  ·  ${money(totals['purchases'])}'),
            _kv('Debit notes', '${_n(found, 'debit_notes')}  ·  ${money(totals['debit_notes'])}'),
            _kv('Receipts', '${_n(found, 'receipts')}  ·  ${money(totals['receipts'])}'),
            _kv('Payments', '${_n(found, 'payments')}  ·  ${money(totals['payments'])}'),
            _kv('Opening receivable', money(totals['opening_receivable'])),
            _kv('Opening payable', money(totals['opening_payable'])),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          title: 'Checked against Marg',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _check('Bill totals', checks['bills'] as Json?),
            _check('Party closing balances', checks['party_balances'] as Json?),
            _check('Item closing stock', checks['stock'] as Json?),
            for (final c in ((p['cleaning'] as List?) ?? []).cast<String>()) Text('· $c', style: const TextStyle(fontSize: 12)),
            for (final w in ((p['warnings'] as List?) ?? []).cast<String>()) Text('· $w', style: TextStyle(fontSize: 12, color: Palette.turmeric)),
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          title: result == null ? 'Importing adds to ${app.companyName}' : 'Added to ${app.companyName}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Items', _n(adds, 'items')),
            _kv('Categories', _n(adds, 'categories')),
            _kv('Customers', _n(adds, 'customers')),
            _kv('Suppliers', _n(adds, 'suppliers')),
            _kv('Sale bills', _n(adds, 'sales')),
            _kv('Purchase bills', _n(adds, 'purchases')),
            _kv('Debit notes', _n(adds, 'debit_notes')),
            _kv('Receipts', _n(adds, 'receipts')),
            _kv('Payments', _n(adds, 'payments')),
            if (here != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Already here and skipped: ${_n(here, 'items')} items, ${_n(here, 'parties')} parties, ${_n(here, 'bills')} bills, ${_n(here, 'vouchers')} receipts/payments.',
                    style: TextStyle(color: Palette.muted, fontSize: 12)),
              ),
            if (numbering != null && '${numbering['INV'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text("New bills carry on Marg's numbering: next sale bill ${numbering['INV']}.")),
            const SizedBox(height: 10),
            if (result == null) FilledButton.icon(onPressed: busy ? null : _import, icon: const Icon(Icons.download_done), label: Text('Import into ${app.companyName}')),
          ]),
        ),
      ],
      if (path != null) ...[
        const SizedBox(height: 12),
        Panel(
          title: 'Item prices',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Checks the selling and purchase prices of your items against this backup (a price is changed only when it is far off, e.g. a box price stored as a piece price).',
                style: TextStyle(color: Palette.muted)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: busy ? null : () => _prices(apply: false), child: const Text('Check item prices against this backup')),
            if (priceProblem != null) Text(priceProblem!, style: TextStyle(color: Palette.brick)),
            if (prices != null) ...[
              const SizedBox(height: 8),
              if (num_(prices!['changed']) == 0)
                Text('All ${prices!['checked']} match.', style: TextStyle(color: Palette.leaf))
              else ...[
                for (final it in ((prices!['items'] as List?) ?? []).cast<Json>().take(40))
                  Text('${it['name']}   ${money(it['retail_old'])} → ${money(it['retail_new'])}', style: tabular.copyWith(fontSize: 12)),
                if (num_(prices!['changed']) > 40) Text('…and ${num_(prices!['changed']).toInt() - 40} more', style: TextStyle(color: Palette.muted)),
                const SizedBox(height: 8),
                if (prices!['applied'] != true)
                  FilledButton(onPressed: busy ? null : () => _prices(apply: true), child: Text('Correct ${prices!['changed']} prices')),
              ],
            ],
          ]),
        ),
      ],
    ]);
  }
}
