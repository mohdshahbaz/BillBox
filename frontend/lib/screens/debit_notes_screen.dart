import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../print/print_dialog.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Debit notes: goods sent back to a supplier (damaged, expired, short or wrong supply). The pieces leave stock and the
/// supplier's ledger is debited. Same engine routes and rules as the Mac's Debit Notes (backend/src/services/debitNotes.js).
class DebitNotesScreen extends StatefulWidget {
  const DebitNotesScreen({super.key});
  @override
  State<DebitNotesScreen> createState() => _DebitNotesState();
}

class _DebitNotesState extends State<DebitNotesScreen> {
  String q = '';
  List<Json> rows = [];
  Json totals = {};
  bool loading = true;
  String? loadError;
  final _debounce = Debouncer();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePending());
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  /// "Return goods…" on a purchase bill opens a new note filled from that bill.
  void _takePending() {
    if (!mounted) return;
    final id = AppScope.read(context).takeEdit('RETURN_PURCHASE');
    if (id != null) _edit(fromPurchase: id);
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/debit-notes', {'q': q}) as Json;
      if (!mounted) return;
      setState(() {
        rows = (r['rows'] as List).cast<Json>();
        totals = (r['totals'] as Json?) ?? {};
        loading = false;
        loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = e.message;
      });
    }
  }

  Future<void> _edit({int? id, int? fromPurchase}) async {
    final saved = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DebitNoteEditor(editId: id, fromPurchase: fromPurchase),
    );
    await _load();
    if (saved != null && saved < 0 && mounted) await printDebitNote(context, -saved); // negative id = "save and print"
  }

  Future<void> _delete(Json r) async {
    if (!await confirm(context, 'Delete debit note ${r['note_no']}?', 'The returned pieces go back into stock and its ledger entry is removed. This cannot be undone.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await guard(context, () async {
      await Api.delete('/debit-notes/${r['id']}');
      if (mounted) toast(context, 'Deleted debit note ${r['note_no']}.');
      await _load();
    });
  }

  Future<void> _view(Json r) async {
    await guard(context, () async {
      final n = await Api.get('/debit-notes/${r['id']}') as Json;
      if (!mounted) return;
      final ls = (n['lines'] as List).cast<Json>();
      final inter = num_(n['igst']) > 0;
      final act = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${n['note_no']} · ${n['party_name'] ?? ''}'),
          content: SizedBox(
            width: math.min(940.0, MediaQuery.sizeOf(ctx).width - 80),
            height: math.min(520.0, MediaQuery.sizeOf(ctx).height - 220),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text([
                dmy(n['date']),
                if ('${n['against_bill'] ?? ''}'.isNotEmpty) 'Against bill ${n['against_bill']}',
                if ('${n['reason'] ?? ''}'.isNotEmpty) '${n['reason']}',
                'Total ${money(n['total'])}',
              ].join('   ·   ')),
              const SizedBox(height: 8),
              Expanded(
                child: table(['Item', 'Qty', 'Rate', 'Batch', 'Taxable', 'GST', 'Tax'], [
                  for (final l in ls)
                    [
                      t('${l['item_name']}'),
                      t(_qtyText(l)),
                      t('${money(l['rate'])} / ${l['unit'] == 'BOX' ? 'box' : 'pc'}'),
                      t('${l['batch_no'] ?? ''}'),
                      t(money(l['taxable'])),
                      t('${l['gst_rate']}%'),
                      t(money(num_(l['cgst']) + num_(l['sgst']) + num_(l['igst'])), bold: true),
                    ],
                ], numeric: {4, 5, 6}),
              ),
              const SizedBox(height: 8),
              SummaryCard([
                SumItem('Taxable', money(n['taxable'])),
                if (inter) SumItem('IGST', money(n['igst'])) else ...[SumItem('CGST', money(n['cgst'])), SumItem('SGST', money(n['sgst']))],
                SumItem('Total', money(n['total']), strong: true),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text('Delete', style: TextStyle(color: Palette.brick))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'edit'), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
            FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'print'), icon: const Icon(Icons.print), label: const Text('Print')),
          ],
        ),
      );
      if (!mounted) return;
      if (act == 'edit') await _edit(id: r['id'] as int);
      if (act == 'print') await printDebitNote(context, r['id'] as int);
      if (act == 'delete') await _delete(r);
    });
  }

  static String _qtyText(Json l) {
    final pcs = num_(l['pcs_qty']).toInt(), per = num_(l['pcs_per_box']).toInt();
    if (l['unit'] == 'BOX' && per > 1) return '${num_(l['qty']).toInt()} box ($pcs pcs)';
    return '$pcs pcs';
  }

  @override
  Widget build(BuildContext context) {
    final gst = num_(totals['cgst']) + num_(totals['sgst']) + num_(totals['igst']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader('Debit notes', actions: [
        FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New debit note')),
      ]),
      Text('Goods sent back to a supplier. The pieces leave stock and the supplier\'s balance goes down by the note total.', style: TextStyle(color: Palette.muted)),
      const SizedBox(height: 10),
      AppField(
        width: 320,
        prefix: const Icon(Icons.search),
        hint: 'Note no, supplier, against bill',
        onChanged: (v) {
          q = v;
          _debounce.run(_load);
        },
      ),
      const SizedBox(height: 12),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : loadError != null && rows.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.error_outline, color: Palette.brick, size: 32),
                      const SizedBox(height: 8),
                      Text(loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  )
                : rows.isEmpty
                    ? Center(child: Text('No debit notes yet. Use New debit note, or Return goods on a purchase bill in All bills.', style: TextStyle(color: Palette.muted)))
                    : table(['Date', 'Note no', 'Supplier', 'Against bill', 'Reason', 'Taxable', 'GST', 'Total', ''], [
                        for (final r in rows)
                          [
                            t(dmy(r['date'])),
                            t('${r['note_no']}'),
                            t('${r['party']}'),
                            t('${r['against_bill'] ?? ''}'),
                            t('${r['reason'] ?? ''}'),
                            t(money(r['taxable'])),
                            t(money(num_(r['cgst']) + num_(r['sgst']) + num_(r['igst']))),
                            t(money(r['total']), bold: true),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              TextButton(onPressed: () => _view(r), child: const Text('View')),
                              TextButton(onPressed: () => printDebitNote(context, r['id'] as int), child: const Text('Print')),
                            ]),
                          ],
                      ], numeric: {5, 6, 7}, menu: (i) {
                        final r = rows[i];
                        return [
                          RowAction('View', () => _view(r), icon: Icons.visibility_outlined),
                          RowAction('Print', () => printDebitNote(context, r['id'] as int), icon: Icons.print_outlined),
                          RowAction('Edit', () => _edit(id: r['id'] as int), icon: Icons.edit_outlined),
                          RowAction('Delete', () => _delete(r), icon: Icons.delete_outline, danger: true),
                        ];
                      }),
      ),
      const SizedBox(height: 8),
      SummaryCard([
        SumItem('Notes', '${num_(totals['count']).toInt()}'),
        SumItem('Taxable', money(totals['taxable'])),
        SumItem('GST reversed', money(gst)),
        SumItem('Total', money(totals['total']), strong: true),
      ]),
    ]);
  }
}

/// One row of goods going back.
class _DLine {
  int itemId = 0;
  String unit = 'PCS';
  int batchId = 0; // 0 = earliest expiry first
  List<Json> batches = [];
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController();
  void dispose() {
    qty.dispose();
    rate.dispose();
  }
}

/// New or edit a debit note. Pops with the note id, or minus the id when "Save and print" was used.
class DebitNoteEditor extends StatefulWidget {
  final int? editId, fromPurchase;
  const DebitNoteEditor({super.key, this.editId, this.fromPurchase});
  @override
  State<DebitNoteEditor> createState() => _DebitNoteEditorState();
}

class _DebitNoteEditorState extends State<DebitNoteEditor> {
  static const _reasons = ['Damaged', 'Expired / near expiry', 'Short supply', 'Wrong item sent', 'Rate difference', 'Excess supply'];
  List<Json> suppliers = [], items = [], bills = [];
  int? partyId, purchaseId;
  String date = todayStr();
  final against = TextEditingController(), reason = TextEditingController(), discount = TextEditingController(), notes = TextEditingController();
  final lines = <_DLine>[_DLine()];
  Json? preview;
  String? problem;
  bool busy = false, ready = false;
  final _debounce = Debouncer(const Duration(milliseconds: 250));

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _debounce.dispose();
    for (final c in [against, reason, discount, notes]) {
      c.dispose();
    }
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Json _item(int id) => items.firstWhere((i) => i['id'] == id, orElse: () => <String, dynamic>{});

  Future<void> _start() async {
    try {
      final r = await Future.wait([Api.get('/parties', {'kind': 'SUPPLIER'}), Api.get('/items')]);
      suppliers = (r[0] as List).cast<Json>();
      items = (r[1] as List).cast<Json>();
      if (widget.editId != null) await _loadNote(widget.editId!);
      if (widget.fromPurchase != null) await _fillFromPurchase(widget.fromPurchase!, setParty: true);
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (!mounted) return;
    setState(() => ready = true);
    _schedulePreview();
  }

  Future<void> _loadBills() async {
    bills = [];
    final p = suppliers.firstWhere((s) => s['id'] == partyId, orElse: () => <String, dynamic>{});
    if (p.isEmpty) return;
    final r = await Api.get('/bills', {'type': 'PURCHASE', 'q': '${p['name']}', 'from': '2000-01-01', 'to': '2100-12-31'}) as Json;
    bills = (r['rows'] as List).cast<Json>().where((b) => b['party'] == p['name']).toList();
  }

  Future<void> _loadBatches(_DLine l) async {
    l.batches = [];
    if (l.itemId == 0) return;
    final r = await Api.get('/items/${l.itemId}/batches') as List;
    l.batches = r.cast<Json>().where((b) => num_(b['qty']) > 0).toList();
  }

  Future<void> _loadNote(int id) async {
    final n = await Api.get('/debit-notes/$id') as Json;
    partyId = n['party_id'] as int?;
    purchaseId = n['purchase_id'] as int?;
    date = '${n['date']}';
    if (purchaseId == null) against.text = '${n['against_bill'] ?? ''}';
    reason.text = '${n['reason'] ?? ''}';
    notes.text = '${n['notes'] ?? ''}';
    discount.text = num_(n['discount']) == 0 ? '' : '${n['discount']}';
    for (final l in lines) {
      l.dispose();
    }
    lines.clear();
    for (final x in (n['lines'] as List).cast<Json>()) {
      final l = _DLine()
        ..itemId = x['item_id'] as int
        ..unit = x['unit'] == 'BOX' ? 'BOX' : 'PCS'
        ..batchId = (x['batch_id'] as int?) ?? 0;
      l.qty.text = '${num_(x['qty']).toInt()}';
      l.rate.text = '${x['rate']}';
      await _loadBatches(l);
      lines.add(l);
    }
    if (lines.isEmpty) lines.add(_DLine());
    await _loadBills();
  }

  static final _boxUnit = RegExp(r'^(box|case|ctn|carton|bx|cs)', caseSensitive: false);

  Future<void> _fillFromPurchase(int id, {bool setParty = false}) async {
    final p = await Api.get('/purchases/$id') as Json;
    if (setParty) {
      partyId = p['party_id'] as int?;
      await _loadBills();
    }
    purchaseId = id;
    for (final l in lines) {
      l.dispose();
    }
    lines.clear();
    for (final x in (p['lines'] as List).cast<Json>()) {
      final l = _DLine()
        ..itemId = (x['item_id'] as int?) ?? 0
        ..unit = _boxUnit.hasMatch('${x['unit'] ?? ''}') ? 'BOX' : 'PCS'
        ..batchId = (x['batch_id'] as int?) ?? 0;
      l.qty.text = '${num_(x['qty']).toInt()}';
      l.rate.text = '${x['rate']}';
      await _loadBatches(l);
      lines.add(l);
    }
    if (lines.isEmpty) lines.add(_DLine());
  }

  Json _body() => {
        'party_id': partyId,
        'date': date,
        if (purchaseId != null) 'purchase_id': purchaseId,
        'against_bill': against.text.trim(),
        'reason': reason.text.trim(),
        'notes': notes.text.trim(),
        'discount': discount.text.trim(),
        'lines': [
          for (final l in lines.where((l) => l.itemId > 0))
            {'item_id': l.itemId, 'qty': l.qty.text.trim(), 'unit': l.unit, 'rate': l.rate.text.trim(), if (l.batchId > 0) 'batch_id': l.batchId},
        ],
      };

  void _schedulePreview() => _debounce.run(_preview);

  Future<void> _preview() async {
    if (partyId == null || !lines.any((l) => l.itemId > 0)) {
      if (mounted) setState(() => preview = null);
      return;
    }
    try {
      final r = await Api.post('/debit-notes/preview', _body()) as Json;
      if (mounted) {
        setState(() {
          preview = r;
          problem = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          preview = null;
          problem = e.message;
        });
      }
    }
  }

  Future<void> _save({bool print = false}) async {
    setState(() => busy = true);
    try {
      final r = widget.editId == null ? await Api.post('/debit-notes', _body()) as Json : await Api.put('/debit-notes/${widget.editId}', _body()) as Json;
      if (!mounted) return;
      toast(context, 'Saved debit note ${r['note_no']} for ${money(r['total'])}. The pieces are out of stock.');
      final id = r['id'] as int;
      Navigator.pop(context, print ? -id : id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          problem = e.message;
        });
      }
    }
  }

  String _batchLabel(Json b, int perBox) {
    final q = num_(b['qty']).toInt();
    final qty = perBox > 1 && q >= perBox ? '${q ~/ perBox} box + ${q % perBox} pcs' : '$q pcs';
    final exp = '${b['exp_date'] ?? ''}';
    return '${b['batch_no']} · $qty${exp.isNotEmpty && exp.compareTo('2099-01-01') < 0 ? ' · exp ${dmy(exp)}' : ''}';
  }

  Widget _lineRow(int n, _DLine l, double w) {
    final it = _item(l.itemId);
    final perBox = math.max(1, num_(it['pcs_per_box']).toInt());
    final pcs = (int.tryParse(l.qty.text.replaceAll(',', '').trim()) ?? 0) * (l.unit == 'BOX' ? perBox : 1);
    final short = it.isNotEmpty && pcs > num_(it['stock']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PickerField<int>(
            width: math.min(300, w),
            label: 'Item ${n + 1}',
            search: true,
            value: l.itemId == 0 ? null : l.itemId,
            options: {for (final i in items) i['id'] as int: '${i['name']}  ·  ${i['hsn'] ?? ''}  ·  stock ${num_(i['stock']).toInt()}'},
            onChanged: (v) async {
              if (v == null) return;
              l.itemId = v;
              l.batchId = 0;
              final x = _item(v);
              if (l.rate.text.trim().isEmpty) {
                final pp = num_(x['purchase_price']) * (l.unit == 'BOX' ? math.max(1, num_(x['pcs_per_box'])) : 1);
                l.rate.text = pp == 0 ? '' : pp.toStringAsFixed(2);
              }
              await guard(context, () => _loadBatches(l));
              if (mounted) setState(() {});
              _schedulePreview();
            },
          ),
          AppField(width: 80, label: 'Qty', number: true, controller: l.qty, onChanged: (_) {
            setState(() {});
            _schedulePreview();
          }),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'PCS', label: Text('Pcs')), ButtonSegment(value: 'BOX', label: Text('Box'))],
            selected: {l.unit},
            onSelectionChanged: (s) {
              setState(() => l.unit = s.first);
              _schedulePreview();
            },
          ),
          AppField(width: 110, label: l.unit == 'BOX' ? 'Rate / box' : 'Rate / pc', number: true, controller: l.rate, onChanged: (_) => _schedulePreview()),
          PickerField<int>(
            width: 240,
            label: 'Batch',
            value: l.batchId,
            options: {0: 'Earliest expiry first', for (final b in l.batches) b['id'] as int: _batchLabel(b, perBox)},
            onChanged: (v) {
              l.batchId = v ?? 0;
              _schedulePreview();
            },
          ),
          IconButton(
            tooltip: 'Remove this row',
            icon: Icon(Icons.remove_circle_outline, color: lines.length > 1 ? Palette.brick : Palette.hint),
            onPressed: lines.length > 1
                ? () {
                    setState(() => lines.removeAt(n).dispose());
                    _schedulePreview();
                  }
                : null,
          ),
        ]),
        if (it.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text('$pcs pcs out of stock · in stock ${num_(it['stock']).toInt()} · GST ${it['gst_rate']}%',
                style: TextStyle(fontSize: 12, color: short ? Palette.brick : Palette.muted)),
          ),
      ]),
    );
  }

  Widget _totals() {
    final p = preview;
    if (p == null) return Text(problem ?? 'Choose the supplier and at least one item.', style: TextStyle(color: problem != null ? Palette.brick : Palette.muted));
    final inter = p['supply'] == 'INTER';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (problem != null) Text(problem!, style: TextStyle(color: Palette.brick)),
      SummaryCard([
        SumItem('Items', money(p['subtotal'])),
        SumItem('Taxable', money(p['taxable'])),
        if (inter) SumItem('IGST', money(p['igst'])) else ...[SumItem('CGST', money(p['cgst'])), SumItem('SGST', money(p['sgst']))],
        if (num_(p['round_off']) != 0) SumItem('Round off', money(p['round_off'])),
        SumItem('Debit note total', money(p['total']), strong: true),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = math.min(900.0, size.width - 80);
    return AlertDialog(
      title: Text(widget.editId == null ? 'New debit note' : 'Edit debit note'),
      content: SizedBox(
        width: w,
        height: math.min(640.0, size.height - 200),
        child: !ready
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        PickerField<int>(
                          width: 300,
                          label: 'Supplier',
                          search: true,
                          value: partyId,
                          options: {for (final s in suppliers) s['id'] as int: '${s['name']}'},
                          onChanged: (v) async {
                            partyId = v;
                            purchaseId = null;
                            await guard(context, _loadBills);
                            if (mounted) setState(() {});
                            _schedulePreview();
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final d = await pickDate(context, date);
                            if (d != null) {
                              setState(() => date = d);
                              _schedulePreview();
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Date ${dmy(date)}'),
                        ),
                        PickerField<int>(
                          width: 300,
                          label: 'Against purchase bill (optional)',
                          value: purchaseId ?? 0,
                          options: {0: 'None', for (final b in bills) b['id'] as int: '${'${b['ref'] ?? ''}'.isEmpty ? b['no'] : b['ref']} · ${dmy(b['date'])} · ${money(b['total'])}'},
                          onChanged: (v) => setState(() => purchaseId = (v == null || v == 0) ? null : v),
                        ),
                        if (purchaseId != null)
                          TextButton.icon(
                            onPressed: () async {
                              await guard(context, () => _fillFromPurchase(purchaseId!));
                              if (mounted) setState(() {});
                              _schedulePreview();
                            },
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Fill the rows from this bill'),
                          )
                        else
                          AppField(width: 200, label: "Supplier's bill no.", controller: against),
                        AppField(
                          width: 300,
                          label: 'Reason',
                          controller: reason,
                          suffix: PopupMenuButton<String>(
                            tooltip: 'Common reasons',
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (v) => setState(() => reason.text = v),
                            itemBuilder: (_) => [for (final r in _reasons) PopupMenuItem(value: r, child: Text(r))],
                          ),
                        ),
                        AppField(width: 130, label: 'Discount ₹', number: true, controller: discount, onChanged: (_) => _schedulePreview()),
                        AppField(width: 300, label: 'Notes', controller: notes),
                      ]),
                      const SizedBox(height: 16),
                      Text('Goods going back', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
                      const SizedBox(height: 8),
                      for (var n = 0; n < lines.length; n++) _lineRow(n, lines[n], w),
                      TextButton.icon(onPressed: () => setState(() => lines.add(_DLine())), icon: const Icon(Icons.add), label: const Text('Add a row')),
                    ]),
                  ),
                ),
                const Divider(),
                _totals(),
              ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton(onPressed: busy || preview == null ? null : () => _save(), child: const Text('Save')),
        FilledButton.icon(onPressed: busy || preview == null ? null : () => _save(print: true), icon: const Icon(Icons.print), label: const Text('Save and print')),
      ],
    );
  }
}
