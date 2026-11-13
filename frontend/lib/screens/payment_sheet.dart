import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Many customer payments at once from a list ("Ram Store 1200, 850 - 2000" per line), as the Mac's payments-from-a-photo
/// sheet without the photo step: the list is typed or pasted (text read from a photo elsewhere works too).
/// POST /receipts/sheet/parse matches each line to a customer and its bills; POST /receipts/sheet saves them together.
Future<bool> showPaymentSheet(BuildContext context) async =>
    (await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const _PaymentSheet())) == true;

class _Row {
  final Json r;
  bool include;
  int? partyId;
  final TextEditingController amount;
  _Row(this.r)
      : include = ((r['problems'] as List?) ?? []).isEmpty,
        partyId = r['party_id'] as int?,
        amount = TextEditingController(text: num_(r['amount']) > 0 ? '${r['amount']}' : '');
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet();
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  static const _modes = ['CASH', 'UPI', 'CHEQUE', 'BANK', 'CARD'];
  final text = TextEditingController();
  List<Json> customers = [];
  List<_Row> rows = [];
  String date = todayStr(), mode = 'CASH';
  String? problem;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final m = '${AppScope.read(context).settings['pay_default_mode'] ?? ''}';
    if (_modes.contains(m)) mode = m;
    guard(context, () async {
      final r = (await Api.get('/parties', {'kind': 'CUSTOMER'}) as List).cast<Json>();
      if (mounted) setState(() => customers = r);
    });
  }

  @override
  void dispose() {
    text.dispose();
    for (final r in rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    setState(() => busy = true);
    try {
      final r = await Api.post('/receipts/sheet/parse', {'text': text.text}) as Json;
      rows = [for (final x in (r['rows'] as List).cast<Json>()) _Row(x)];
      problem = rows.isEmpty ? 'No lines with a name and an amount were found.' : null;
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  List<_Row> get _ready => rows.where((r) => r.include && r.partyId != null && num_(r.amount.text.trim()) > 0).toList();

  Future<void> _save() async {
    final ready = _ready;
    setState(() => busy = true);
    try {
      final r = await Api.post('/receipts/sheet', {
        'date': date,
        'mode': mode,
        'rows': [for (final x in ready) {'party_id': x.partyId, 'amount': num_(x.amount.text.trim()), 'reference': x.r['reference']}],
      }) as Json;
      if (!mounted) return;
      toast(context, 'Saved ${r['count']} payments, total ${money(r['total'])}.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          problem = e.message;
        });
      }
    }
  }

  Map<int, String> _options(_Row row) {
    final cands = ((row.r['candidates'] as List?) ?? []).cast<Json>();
    return {
      for (final c in cands) c['id'] as int: '${c['name']} · ${(num_(c['score']) * 100).round()}% match',
      for (final c in customers) if (!cands.any((x) => x['id'] == c['id'])) c['id'] as int: '${c['name']}',
    };
  }

  String _bills(Json r) {
    final b = ((r['bills'] as List?) ?? []).cast<Json>();
    if (b.isEmpty) return '';
    return 'Bills: ${b.map((x) => '${x['invoice_no'] ?? ''} ${money(x['amount'])}${x['invoice_no'] == null ? ' (no bill found)' : ''}'.trim()).join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ready = _ready;
    final total = ready.fold<num>(0, (a, r) => a + num_(r.amount.text.trim()));
    return AlertDialog(
      title: const Text('Payments from a list'),
      content: SizedBox(
        width: math.min(900.0, size.width - 80),
        height: math.min(620.0, size.height - 200),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('1. Type or paste the list: one customer per line, the bills and then what was paid, e.g. "Ram Store 1200, 850 - 2000".',
              style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: TextField(
              controller: text,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(hintText: 'Sharma Kirana 4200\nGupta Store 1200, 950 - 2000', constraints: BoxConstraints()),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            OutlinedButton(onPressed: busy || text.text.trim().isEmpty ? null : _read, child: const Text('Read these lines')),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await pickDate(context, date);
                if (d != null) setState(() => date = d);
              },
              icon: const Icon(Icons.event, size: 16),
              label: Text('Date ${dmy(date)}'),
            ),
            const SizedBox(width: 8),
            AppDropdown<String>(width: 140, label: 'Mode', value: mode, options: {for (final m in _modes) m: m}, onChanged: (v) => setState(() => mode = v ?? mode)),
          ]),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(problem!, style: TextStyle(color: Palette.brick))),
          const Divider(height: 20),
          Text('2. Check each payment', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
          const SizedBox(height: 6),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text('The lines appear here after Read these lines.', style: TextStyle(color: Palette.muted)))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final probs = ((row.r['problems'] as List?) ?? []).cast<String>();
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Checkbox(value: row.include, onChanged: (v) => setState(() => row.include = v ?? false)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${row.r['text']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              PickerField<int>(
                                width: 320,
                                label: 'Customer',
                                search: true,
                                value: row.partyId,
                                options: _options(row),
                                onChanged: (v) => setState(() {
                                  row.partyId = v;
                                  if (num_(row.amount.text.trim()) > 0) row.include = true;
                                }),
                              ),
                              AppField(width: 140, label: 'Amount ₹', number: true, controller: row.amount, onChanged: (_) => setState(() {})),
                            ]),
                            if (_bills(row.r).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_bills(row.r), style: TextStyle(fontSize: 12, color: Palette.muted))),
                            for (final p in probs) Text(p, style: TextStyle(fontSize: 12, color: Palette.turmeric)),
                          ]),
                        ),
                      ]);
                    },
                  ),
          ),
          const SizedBox(height: 6),
          Text('${ready.length} of ${rows.length} ready · total ${money(total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy || ready.isEmpty ? null : _save, child: Text('Save ${ready.length} payments')),
      ],
    );
  }
}
