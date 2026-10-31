import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../print/print_dialog.dart';
import '../state/app_state.dart';
import '../widgets.dart';

class _Line {
  final Json item;
  int boxes, pcs;
  double disc;
  final key = UniqueKey();
  _Line(this.item, {this.boxes = 0, this.pcs = 1, this.disc = 0});
  int get ppb => num_(item['pcs_per_box']).toInt().clamp(1, 1000000).toInt();
  int get totalPcs => boxes * ppb + pcs;
}

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => BillingScreenState();
}

class BillingScreenState extends State<BillingScreen> {
  List<Json> parties = [], salesmen = [], allItems = [];
  final lines = <_Line>[];
  int partyId = 0, salesmanId = 0; // 0 = walk-in / none
  String saleType = 'COUNTER', payMode = 'CASH', billDate = todayStr();
  Json? preview;
  String? error;
  bool busy = false;
  int _seq = 0;
  final barcodeCtl = TextEditingController();
  final barcodeFocus = FocusNode();
  final paidCtl = TextEditingController();
  final _debounce = Debouncer();

  /// Set while an already saved bill is being corrected: saving rewrites that bill under the same number.
  int? editingId;
  String? editingNo;

  @override
  void dispose() {
    _debounce.dispose();
    barcodeCtl.dispose();
    barcodeFocus.dispose();
    paidCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => focusBarcode());
  }

  void focusBarcode() => barcodeFocus.requestFocus();

  /// Opens a saved bill in this screen. Stock and ledger are only touched when the corrected bill is saved.
  Future<void> loadForEdit(int id) async {
    try {
      final inv = await Api.get('/invoices/$id') as Json;
      if (!mounted) return;
      final ls = (inv['edit_lines'] as List).cast<Json>();
      setState(() {
        lines
          ..clear()
          ..addAll([
            for (final l in ls)
              _Line({'id': l['item_id'], 'name': l['item_name'], 'pcs_per_box': l['pcs_per_box']},
                  boxes: 0, pcs: num_(l['qty']).toInt(), disc: num_(l['manual_disc']).toDouble()),
          ]);
        editingId = id;
        editingNo = inv['invoice_no'] as String;
        partyId = (inv['party_id'] as int?) ?? 0;
        salesmanId = (inv['salesman_id'] as int?) ?? 0;
        saleType = (inv['sale_type'] as String?) ?? 'COUNTER';
        payMode = (inv['pay_mode'] as String?) ?? 'CASH';
        paidCtl.text = num_(inv['paid']).toStringAsFixed(2);
        billDate = '${inv['date'] ?? todayStr()}';
      });
      _recalc();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> reload() async {
    try {
      final r = await Future.wait([Api.get('/parties', {'kind': 'CUSTOMER'}), Api.get('/salesmen'), Api.get('/items')]);
      if (!mounted) return;
      setState(() {
        parties = (r[0] as List).cast<Json>();
        salesmen = (r[1] as List).cast<Json>();
        allItems = (r[2] as List).cast<Json>();
      });
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Json? get party => partyId == 0 ? null : parties.cast<Json?>().firstWhere((p) => p!['id'] == partyId, orElse: () => null);

  Json _payload({bool override = false}) => {
        'party_id': partyId == 0 ? null : partyId,
        'salesman_id': salesmanId == 0 ? null : salesmanId,
        'date': billDate,
        'sale_type': saleType,
        'pay_mode': payMode,
        if (paidCtl.text.trim().isNotEmpty) 'paid_amount': double.tryParse(paidCtl.text.trim()),
        if (override) 'override_credit': true,
        'lines': [for (final l in lines) {'item_id': l.item['id'], 'boxes': l.boxes, 'pcs': l.pcs, 'disc_pct': l.disc}],
      };

  // ---- adding items -------------------------------------------------------
  /// Items whose name contains every typed word (or whose barcode / HSN starts with the text), in-stock first.
  Iterable<Json> _suggest(String text) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    final hits = allItems.where((i) {
      final n = '${i['name']}'.toLowerCase();
      return words.every(n.contains) || '${i['barcode'] ?? ''}'.toLowerCase() == q || '${i['hsn'] ?? ''}'.startsWith(q);
    }).toList();
    hits.sort((a, b) {
      final sa = num_(a['stock']) > 0 ? 0 : 1, sb = num_(b['stock']) > 0 ? 0 : 1;
      if (sa != sb) return sa - sb;
      final ia = '${a['name']}'.toLowerCase().indexOf(words.first), ib = '${b['name']}'.toLowerCase().indexOf(words.first);
      return ia != ib ? ia - ib : '${a['name']}'.compareTo('${b['name']}');
    });
    return hits.take(8);
  }

  Widget _searchBox() => LayoutBuilder(
        builder: (context, box) => RawAutocomplete<Json>(
          textEditingController: barcodeCtl,
          focusNode: barcodeFocus,
          displayStringForOption: (o) => '${o['name']}',
          optionsBuilder: (v) => _suggest(v.text),
          onSelected: (o) {
            _addItem(o);
            barcodeCtl.clear();
            focusBarcode();
          },
          fieldViewBuilder: (ctx, ctl, fn, onSubmit) => AppField(
            controller: ctl,
            focusNode: fn,
            prefix: const Icon(Icons.search),
            hint: 'Type an item name or scan a barcode   (F2 or ⌘K to return here)',
            onSubmitted: (t) {
              if (_suggest(t).isNotEmpty) {
                onSubmit();
              } else {
                _scan(t);
              }
            },
          ),
          optionsViewBuilder: (ctx, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(kRadius),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth, maxHeight: 360),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        title: Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Stock ${num_(o['stock']).toInt()} pcs  ·  MRP ${money(o['mrp'])}  ·  GST ${o['gst_rate']}%', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: num_(o['stock']) <= 0 ? const Text('Out of stock', style: TextStyle(color: Palette.brick, fontSize: 12)) : null,
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _scan(String text) async {
    final q = text.trim();
    barcodeCtl.clear();
    if (q.isEmpty) {
      focusBarcode();
      return;
    }
    try {
      final r = ((await Api.get('/items', {'q': q})) as List).cast<Json>();
      if (r.isEmpty) {
        if (mounted) toast(context, 'No item matches "$q"', error: true);
      } else {
        Json? pick;
        for (final i in r) {
          if ('${i['name']}'.toLowerCase() == q.toLowerCase()) pick = i;
        }
        pick ??= r.length == 1 ? r.first : await _choose(r);
        if (pick != null) _addItem(pick);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    focusBarcode();
  }

  Future<Json?> _choose(List<Json> items) => showDialog<Json>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Which item?'), children: [
          SizedBox(
            width: math.min(520.0, MediaQuery.sizeOf(context).width - 80),
            height: 360,
            child: ListView(children: [
              for (final i in items)
                ListTile(
                  dense: true,
                  title: Text(i['name']),
                  subtitle: Text('Stock ${i['stock']} pcs · MRP ${money(i['mrp'])}'),
                  onTap: () => Navigator.pop(ctx, i),
                ),
            ]),
          ),
        ]),
      );

  void _addItem(Json item) {
    final existing = lines.where((l) => l.item['id'] == item['id']);
    setState(() => existing.isNotEmpty ? existing.first.pcs += 1 : lines.add(_Line(item)));
    _recalc();
  }

  // ---- live totals from the server (same engine as save) ------------------
  /// Typing in a quantity box recalculates after a short pause instead of on every key.
  void _recalcSoon() => _debounce.run(_recalc);

  Future<void> _recalc() async {
    final my = ++_seq;
    if (lines.isEmpty) {
      setState(() {
        preview = null;
        error = null;
      });
      return;
    }
    try {
      final p = await Api.post('/invoices/preview', _payload()) as Json;
      if (my != _seq || !mounted) return;
      setState(() {
        preview = p;
        error = null;
      });
    } on ApiException catch (e) {
      if (my != _seq || !mounted) return;
      setState(() {
        preview = null;
        error = e.message;
      });
    }
  }

  void _clear() {
    setState(() {
      lines.clear();
      preview = null;
      error = null;
      partyId = 0;
      paidCtl.clear();
      payMode = 'CASH';
      billDate = todayStr();
      editingId = null;
      editingNo = null;
    });
    _seq++;
    focusBarcode();
  }

  Future<void> _save({bool override = false}) async {
    if (busy || lines.isEmpty || preview == null) return;
    setState(() => busy = true);
    try {
      final wasEdit = editingId;
      final r = (wasEdit != null ? await Api.put('/invoices/$wasEdit', _payload(override: override)) : await Api.post('/invoices', _payload(override: override))) as Json;
      if (!mounted) return;
      toast(context, '${wasEdit != null ? 'Updated' : 'Saved'} ${r['invoice_no']} · ${money(r['total'])}');
      _clear();
      reload(); // refresh dues
      await printInvoice(context, r['id'] as int); // in-app preview, or straight to the saved printer
    } on ApiException catch (e) {
      if (e.code == 'CREDIT_LIMIT' && mounted) {
        final ok = await confirm(context, 'Credit limit exceeded', e.message, ok: 'Bill anyway', danger: true);
        if (mounted) setState(() => busy = false);
        if (ok) return _save(override: true);
      } else if (mounted) {
        toast(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---- UI -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final pl = (preview?['lines'] as List?)?.cast<Json>() ?? const <Json>[];
    final narrow = isNarrow(context);
    final left = Padding(
      padding: EdgeInsets.all(narrow ? 12 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (editingId != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Palette.turmeric.withValues(alpha: .15), borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: Palette.turmeric)),
            child: Row(children: [
              const Icon(Icons.edit_note, color: Palette.turmeric),
              const SizedBox(width: 8),
              Expanded(child: Text('Editing $editingNo. Saving replaces the old bill; stock and ledger are corrected automatically.', maxLines: 2, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: _clear, child: const Text('Cancel edit')),
            ]),
          ),
        _searchBox(),
        const SizedBox(height: 12),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Search an item above and pick it to start the bill.', style: TextStyle(color: Palette.muted, fontSize: 16)))
              : Card(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final table = !narrow && box.maxWidth >= 760;
                      return Column(children: [
                        if (table) _header(),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: lines.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _lineRow(i, i < pl.length ? pl[i] : null, narrow, table),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
        ),
        if (error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Palette.brick.withValues(alpha: .1), borderRadius: BorderRadius.circular(kRadius)),
            child: Text(error!, style: const TextStyle(color: Palette.brick)),
          ),
      ]),
    );
    final side = Container(
      width: narrow ? double.infinity : 380,
      decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: Palette.line))),
      padding: const EdgeInsets.all(18),
      child: _side(narrow ? double.infinity : 344, narrow),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): focusBarcode,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): focusBarcode,
        const SingleActivator(LogicalKeyboardKey.f4): _clear,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _clear,
        const SingleActivator(LogicalKeyboardKey.f9): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: Focus(
        // Wide windows: items on the left, totals on the right. Narrow windows: stacked and scrollable.
        child: narrow
            ? SingleChildScrollView(child: Column(children: [SizedBox(height: 420, child: left), side]))
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: left), side]),
      ),
    );
  }

  Widget _qtyField(String label, int value, void Function(int) set) => SizedBox(
        width: 72,
        child: TextFormField(
          initialValue: value == 0 ? '' : '$value',
          style: tabular.copyWith(fontSize: 14),
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            set(int.tryParse(v) ?? 0);
            _recalcSoon();
          },
        ),
      );

  Widget _header() {
    const st = TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Palette.muted);
    Widget c(String t, double w, {bool right = false}) => SizedBox(width: w, child: Text(t, textAlign: right ? TextAlign.right : TextAlign.start, style: st));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
      child: Row(children: [
        c('S.No', 34),
        const Expanded(child: Text('Item name', style: st)),
        c('Box', 78),
        c('Pcs', 72),
        c('Total', 56, right: true),
        c('Disc %', 76),
        c('Rate', 78, right: true),
        c('Free', 70, right: true),
        c('Amount', 100, right: true),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _lineRow(int i, Json? p, bool narrow, bool table) {
    final l = lines[i];
    final dual = l.ppb > 1;
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l.item['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(
        [
          if (dual) '${l.ppb} pcs / box',
          'Stock ${num_(l.item['stock']).toInt()} pcs',
          if (p != null) ...(p['schemes'] as List).cast<String>(),
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Palette.muted, fontSize: 12),
      ),
    ]);
    final inputs = Row(mainAxisSize: MainAxisSize.min, children: [
      if (dual) ...[_qtyField('Box', l.boxes, (v) => l.boxes = v), const SizedBox(width: 6)] else if (table) const SizedBox(width: 78),
      _qtyField('Pcs', l.pcs, (v) => l.pcs = v),
      SizedBox(width: 56, child: Text(dual ? '= ${l.totalPcs}' : '', textAlign: TextAlign.center, style: tabular.copyWith(color: Palette.muted))),
      SizedBox(
        width: 76,
        child: TextFormField(
          initialValue: l.disc == 0 ? '' : '${l.disc}',
          style: tabular.copyWith(fontSize: 14),
          decoration: const InputDecoration(labelText: 'Disc %'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            l.disc = double.tryParse(v) ?? 0;
            _recalcSoon();
          },
        ),
      ),
    ]);
    final figures = Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 78, child: Text(p == null ? '' : money(p['rate']), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular)),
      SizedBox(
          width: 70,
          child: Text(p != null && num_(p['free_qty']) > 0 ? '+${p['free_qty']} free' : '',
              textAlign: TextAlign.right, maxLines: 1, style: const TextStyle(color: Palette.leaf, fontWeight: FontWeight.w600))),
      SizedBox(width: 100, child: Text(p == null ? '' : money(p['amount']), textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular.copyWith(fontWeight: FontWeight.w600))),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Remove',
        onPressed: () {
          setState(() => lines.removeAt(i));
          _recalc();
        },
      ),
    ]);
    return Padding(
      key: l.key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('${i + 1}.  ', style: tabular.copyWith(color: Palette.muted)), Expanded(child: info)]), const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [inputs, figures])])
          : LayoutBuilder(builder: (context, box) {
              // Not enough room for everything on one line: put the boxes under the item name.
              if (box.maxWidth < 760) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 6), Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [inputs, figures])]);
              }
              return Row(children: [SizedBox(width: 34, child: Text('${i + 1}', style: tabular.copyWith(color: Palette.muted))), Expanded(child: info), inputs, figures]);
            }),
    );
  }

  Widget _side(double w, bool narrow) {
    final p = preview;
    final pt = party;
    Widget row(String a, String b, {bool big = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(a, style: TextStyle(fontSize: big ? 18 : 14, fontWeight: big ? FontWeight.w700 : null)),
            const Spacer(),
            Flexible(child: Text(b, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular.copyWith(fontSize: big ? 26 : 14, fontWeight: big ? FontWeight.w700 : null, color: color))),
          ]),
        );
    final ddw = narrow ? math.min(MediaQuery.sizeOf(context).width - 60, 520.0) : w;
    final buttons = [
      FilledButton.icon(
        onPressed: busy || preview == null ? null : _save,
        icon: Icon(editingId != null ? Icons.save : Icons.print),
        label: Text(editingId != null ? 'Update bill and print   F9' : 'Save and print   F9'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _clear, child: Text(editingId != null ? 'Cancel edit' : 'New bill   F4')),
    ];
    return Column(mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
        onPressed: () async {
          final d = await pickDate(context, billDate);
          if (d != null) {
            setState(() => billDate = d);
            _recalc();
          }
        },
        icon: const Icon(Icons.event, size: 18),
        label: Text('Bill date  ${dmy(billDate)}'),
      ),
      const SizedBox(height: 12),
      AppDropdownSearch(
        key: ValueKey('party$partyId${parties.length}'),
        width: ddw,
        label: 'Party',
        value: partyId,
        options: {0: 'Walk-in cash customer', for (final x in parties) x['id'] as int: '${x['name']}'},
        onChanged: (v) {
          setState(() => partyId = v ?? 0);
          _recalc();
        },
      ),
      if (pt != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Dues ${money(pt['balance'])}'
            '${num_(pt['credit_limit']) > 0 ? ' of ${money(pt['credit_limit'])} limit' : ''} · ${pt['price_tier']} price',
            style: TextStyle(color: num_(pt['credit_limit']) > 0 && num_(pt['balance']) > num_(pt['credit_limit']) ? Palette.brick : Palette.muted),
          ),
        ),
      const SizedBox(height: 12),
      AppDropdown<int>(
        width: ddw,
        label: 'Salesman',
        value: salesmanId,
        options: {0: 'None (counter)', for (final s in salesmen) s['id'] as int: '${s['name']}'},
        onChanged: (v) => salesmanId = v ?? 0,
      ),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'COUNTER', label: Text('Counter')), ButtonSegment(value: 'VAN', label: Text('Van sale'))],
        selected: {saleType},
        onSelectionChanged: (s) => setState(() => saleType = s.first),
      ),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'CASH', label: Text('Cash')),
          ButtonSegment(value: 'UPI', label: Text('UPI')),
          ButtonSegment(value: 'CARD', label: Text('Card')),
          ButtonSegment(value: 'CREDIT', label: Text('Credit')),
        ],
        selected: {payMode},
        onSelectionChanged: (s) => setState(() => payMode = s.first),
      ),
      const SizedBox(height: 12),
      AppField(controller: paidCtl, number: true, label: 'Paid now (optional)', hint: 'Blank = full amount, or nothing on Credit'),
      const Divider(height: 28),
      row('Items', p == null ? '–' : money(p['subtotal'])),
      row('Discount', p == null ? '–' : '- ${money(p['discount'])}'),
      row('Taxable', p == null ? '–' : money(p['taxable'])),
      if (p != null && p['supply'] == 'INTRA') ...[row('CGST', money(p['cgst'])), row('SGST', money(p['sgst']))],
      if (p != null && p['supply'] == 'INTER') row('IGST', money(p['igst'])),
      row('Round off', p == null ? '–' : money(p['round_off'])),
      const Divider(height: 20),
      row('Total', p == null ? '₹ 0' : money(p['total']), big: true, color: Palette.teal),
      if (narrow) const SizedBox(height: 16) else const Spacer(),
      ...buttons,
    ]);
  }
}
