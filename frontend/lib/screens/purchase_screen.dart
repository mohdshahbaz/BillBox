import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

const _unitList = ['PCS', 'BOX', 'CASE', 'KG', 'GM', 'LTR', 'ML', 'PKT', 'DOZ', 'SET', 'NOS'];

/// One row of the bill: Item Name, HSN Code, Qty, Unit, Price, Amount. S.No is its position in the list.
class _PLine {
  int? itemId;
  String desc = ''; // name as printed on the supplier's bill (kept for reference)
  String unit = 'PCS';
  bool matched = true, amountManual = false, created = false;
  final hsn = TextEditingController(), qty = TextEditingController(text: '1'), rate = TextEditingController(), amount = TextEditingController();
  Key key = UniqueKey();

  double get q => double.tryParse(qty.text.trim()) ?? 0;
  double get r => double.tryParse(rate.text.trim()) ?? 0;

  /// Amount follows Qty x Price until the user (or the PDF) sets it by hand.
  void autoAmount() {
    if (amountManual) return;
    final v = q * r;
    amount.text = v == 0 ? '' : v.toStringAsFixed(2);
  }

  void dispose() {
    hsn.dispose();
    qty.dispose();
    rate.dispose();
    amount.dispose();
  }
}

/// Purchase bill entry: manual, scanned from a supplier PDF, or an already saved bill opened for editing.
/// Saving adds the received pieces to stock and posts the bill to the supplier's ledger;
/// saving an edit reverses the old bill first and writes the corrected one under the same number.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseState();
}

class _PurchaseState extends State<PurchaseScreen> {
  List<Json> suppliers = [], items = [];
  int supplierId = 0;
  String date = todayStr(), payMode = 'CASH', source = 'MANUAL';
  final noCtl = TextEditingController(), paidCtl = TextEditingController();
  // bill-level amounts (blank tax / round off = worked out automatically)
  final discCtl = TextEditingController(), cgstCtl = TextEditingController(), sgstCtl = TextEditingController(), igstCtl = TextEditingController(), roundCtl = TextEditingController();
  final lines = <_PLine>[_PLine()];
  Json? preview, parsed, pendingSupplier;
  String? error;
  List<String> warnings = [];
  double? printedTotal;
  bool scanning = false, busy = false, autoTax = false;
  int _seq = 0, _formKey = 0;
  int? editingId;
  String? editingNo;
  final _debounce = Debouncer();

  @override
  void initState() {
    super.initState();
    _loadLists().then((_) {
      final id = mounted ? AppScope.read(context).takeEdit('PURCHASE') : null;
      if (id != null) _loadForEdit(id);
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    for (final c in [noCtl, paidCtl, discCtl, cgstCtl, sgstCtl, igstCtl, roundCtl]) {
      c.dispose();
    }
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() => guard(context, () async {
        final r = await Future.wait([Api.get('/parties', {'kind': 'SUPPLIER'}), Api.get('/items')]);
        if (!mounted) return;
        setState(() {
          suppliers = (r[0] as List).cast<Json>();
          items = (r[1] as List).cast<Json>();
        });
      });

  /// Controllers of removed rows are disposed after the frame that stops showing them.
  void _retire(Iterable<_PLine> old) {
    final copy = old.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final l in copy) {
        l.dispose();
      }
    });
  }

  Json? _item(int? id) => items.cast<Json?>().firstWhere((i) => i!['id'] == id, orElse: () => null);
  String _t(TextEditingController c) => c.text.trim();

  Json _payload({bool dup = false}) => {
        'party_id': supplierId == 0 ? null : supplierId,
        'supplier_invoice_no': _t(noCtl),
        'date': date,
        'source': source,
        if (_t(paidCtl).isNotEmpty) 'paid_amount': double.tryParse(_t(paidCtl)),
        'pay_mode': payMode,
        'discount': _t(discCtl),
        'cgst': _t(cgstCtl),
        'sgst': _t(sgstCtl),
        'igst': _t(igstCtl),
        'round_off': _t(roundCtl),
        if (printedTotal != null) 'printed_total': printedTotal,
        if (autoTax) 'auto_tax': true,
        if (dup) 'allow_duplicate': true,
        'lines': [
          for (final l in lines)
            {'item_id': l.itemId, 'hsn': _t(l.hsn), 'qty': l.qty.text.trim(), 'unit': l.unit, 'rate': _t(l.rate), 'amount': _t(l.amount)},
        ],
      };

  void _recalcSoon() => _debounce.run(_recalc);

  Future<void> _recalc() async {
    final my = ++_seq;
    try {
      final p = await Api.post('/purchases/preview', _payload()) as Json;
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

  // ---------------- PDF scan ----------------
  Future<void> _scanPdf() async {
    final f = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (f == null || f.files.isEmpty || !mounted) return;
    final bytes = f.files.first.bytes;
    if (bytes == null) {
      toast(context, 'Could not read that file', error: true);
      return;
    }
    setState(() => scanning = true);
    await guard(context, () async {
      // create_missing: the supplier and every new item (HSN, GST rate, pieces per box, category) are added automatically.
      final r = await Api.post('/purchases/parse-pdf', {'pdf_base64': base64Encode(bytes), 'create_missing': true}) as Json;
      final fresh = await Future.wait([Api.get('/parties', {'kind': 'SUPPLIER'}), Api.get('/items')]);
      if (!mounted) return;
      suppliers = (fresh[0] as List).cast<Json>();
      items = (fresh[1] as List).cast<Json>();
      _apply(r);
    });
    if (mounted) setState(() => scanning = false);
  }

  String _numText(dynamic v) => v == null ? '' : (num_(v) == 0 ? '' : '$v');

  void _apply(Json r) {
    final sup = r['supplier'] as Json;
    final ls = <_PLine>[];
    for (final x in (r['lines'] as List).cast<Json>()) {
      final l = _PLine()
        ..itemId = x['item_id'] as int?
        ..desc = '${x['description']}'
        ..unit = '${x['unit'] ?? 'PCS'}'.toUpperCase()
        ..matched = x['item_id'] != null
        ..created = x['created'] == true
        ..amountManual = true; // the printed amount is the truth for a scanned bill
      l.hsn.text = '${x['hsn'] ?? ''}';
      l.qty.text = '${num_(x['qty']) % 1 == 0 ? num_(x['qty']).toInt() : x['qty']}';
      l.rate.text = '${x['rate'] ?? ''}';
      l.amount.text = '${x['amount'] ?? ''}';
      ls.add(l);
    }
    final t = (r['totals'] as Json?) ?? {};
    final pg = (r['pages'] as Json?) ?? {};
    final skipped = ((pg['skipped'] as List?) ?? []).cast<Json>();
    setState(() {
      source = 'PDF';
      parsed = r;
      warnings = (r['warnings'] as List).cast<String>();
      noCtl.text = (r['invoice_no'] ?? '') as String;
      if (r['date'] != null) date = r['date'] as String;
      supplierId = (sup['matched_party_id'] as int?) ?? 0;
      pendingSupplier = supplierId == 0 && sup['name'] != null ? sup : null;
      discCtl.text = _numText(t['discount']);
      cgstCtl.text = _numText(t['cgst']);
      sgstCtl.text = _numText(t['sgst']);
      igstCtl.text = _numText(t['igst']);
      roundCtl.text = t['round_off'] == null ? '' : '${t['round_off']}';
      printedTotal = t['grand_total'] == null ? null : num_(t['grand_total']).toDouble();
      autoTax = false;
      _retire(lines);
      lines
        ..clear()
        ..addAll(ls.isEmpty ? [_PLine()] : ls);
      if (skipped.isNotEmpty) warnings.insert(0, 'Read page(s) ${(pg['used'] as List).join(', ')} (Original). Skipped ${skipped.map((s) => '${s['page']} (${s['kind']})').join(', ')}.');
      _formKey++;
    });
    _recalc();
  }

  // ---------------- edit a saved bill ----------------
  Future<void> _loadForEdit(int id) async {
    await guard(context, () async {
      final b = await Api.get('/purchases/$id') as Json;
      if (!mounted) return;
      final ls = <_PLine>[];
      for (final x in (b['lines'] as List).cast<Json>()) {
        final l = _PLine()
          ..itemId = x['item_id'] as int?
          ..unit = '${x['unit'] ?? 'PCS'}'
          ..amountManual = true;
        l.hsn.text = '${x['hsn'] ?? ''}';
        l.qty.text = '${num_(x['qty']).toInt()}';
        l.rate.text = '${x['rate']}';
        l.amount.text = '${x['amount']}';
        ls.add(l);
      }
      setState(() {
        editingId = id;
        editingNo = '${b['purchase_no']}';
        supplierId = b['party_id'] as int;
        noCtl.text = '${b['supplier_invoice_no'] ?? ''}';
        date = '${b['date']}';
        payMode = '${b['pay_mode'] ?? 'CASH'}';
        paidCtl.text = num_(b['paid']).toStringAsFixed(2);
        discCtl.text = _numText(b['discount']);
        cgstCtl.text = _numText(b['cgst']);
        sgstCtl.text = _numText(b['sgst']);
        igstCtl.text = _numText(b['igst']);
        roundCtl.text = '${b['round_off'] ?? ''}';
        source = '${b['source'] ?? 'MANUAL'}';
        _retire(lines);
        lines
          ..clear()
          ..addAll(ls.isEmpty ? [_PLine()] : ls);
        _formKey++;
      });
      _recalc();
    });
  }

  // ---------------- create supplier / item from the bill ----------------
  Future<void> _createSupplier() async {
    final s = pendingSupplier!;
    String v(String k) => '${s[k] is List ? (s[k] as List).join(', ') : (s[k] ?? '')}';
    final f = await formDialog(context, 'Create supplier from the bill', [
      FieldSpec('name', 'Supplier name', initial: v('name')),
      FieldSpec('address', 'Address', initial: v('address')),
      FieldSpec('gstin', 'GSTIN', initial: v('gstin')),
      FieldSpec('state_code', 'State code', initial: s['state_code'] == null ? '09' : v('state_code')),
      FieldSpec('tel', 'Tel', initial: v('tel')),
      FieldSpec('phone', 'Phone', initial: v('phone')),
      FieldSpec('mobiles', 'Mobile numbers (comma separated)', initial: v('mobiles')),
      FieldSpec('fssai', 'FSSAI number', initial: v('fssai')),
      FieldSpec('pan', 'PAN number', initial: v('pan')),
      FieldSpec('email', 'Email', initial: v('email')),
    ]);
    if (f == null || !mounted) return;
    await guard(context, () async {
      final r = await Api.post('/parties', {...f, 'type': 'SUPPLIER', 'price_tier': 'WHOLESALE'}) as Json;
      await _loadLists();
      if (!mounted) return;
      setState(() {
        supplierId = r['id'] as int;
        pendingSupplier = null;
      });
      _recalc();
    });
  }

  Future<void> _createItem(_PLine l) async {
    final v = await formDialog(context, 'Create stock item', [
      FieldSpec('name', 'Item name', initial: l.desc),
      FieldSpec('hsn', 'HSN code', initial: _t(l.hsn)),
      const FieldSpec('gst_rate', 'GST rate %', number: true, initial: '18'),
      FieldSpec('unit', 'Unit', initial: l.unit, options: {for (final u in {..._unitList, l.unit}) u: u}),
      const FieldSpec('pcs_per_box', 'Pieces in one box', number: true, initial: '1'),
      FieldSpec('purchase_price', 'Purchase price per unit (ex-GST)', number: true, initial: _t(l.rate)),
      const FieldSpec('mrp', 'MRP per piece (incl. GST)', number: true),
      const FieldSpec('retail_price', 'Retail price (ex-GST)', number: true),
      const FieldSpec('wholesale_price', 'Wholesale price (ex-GST)', number: true),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      final r = await Api.post('/items', v) as Json;
      await _loadLists();
      if (!mounted) return;
      setState(() {
        l.itemId = r['id'] as int;
        l.matched = true;
        l.key = UniqueKey();
      });
      _recalc();
    });
  }

  void _viewText() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Text read from the PDF (${parsed?['method'] == 'ocr' ? 'OCR' : 'text layer'})'),
          content: SizedBox(
            width: math.min(700.0, MediaQuery.sizeOf(ctx).width - 80),
            height: math.min(460.0, MediaQuery.sizeOf(ctx).height - 220),
            child: SingleChildScrollView(child: SelectableText('${parsed?['raw_text'] ?? ''}', style: const TextStyle(fontFamily: 'Menlo', fontSize: 11))),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );

  // ---------------- save ----------------
  Future<void> _save({bool dup = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final wasEdit = editingId;
      final r = (wasEdit != null ? await Api.put('/purchases/$wasEdit', _payload(dup: dup)) : await Api.post('/purchases', _payload(dup: dup))) as Json;
      if (!mounted) return;
      toast(context, '${wasEdit != null ? 'Updated' : 'Saved'} ${r['purchase_no']} · ${money(r['total'])}. Stock and ledger are up to date.');
      _reset();
      _loadLists();
    } on ApiException catch (e) {
      if (e.code == 'DUPLICATE' && mounted) {
        setState(() => busy = false);
        if (await confirm(context, 'Possible duplicate', '${e.message}\n\nSave it again anyway?', ok: 'Save anyway', danger: true)) return _save(dup: true);
      } else if (mounted) {
        toast(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _reset() {
    for (final c in [noCtl, paidCtl, discCtl, cgstCtl, sgstCtl, igstCtl, roundCtl]) {
      c.clear();
    }
    setState(() {
      supplierId = 0;
      date = todayStr();
      source = 'MANUAL';
      parsed = null;
      pendingSupplier = null;
      warnings = [];
      printedTotal = null;
      autoTax = false;
      editingId = null;
      editingNo = null;
      _retire(lines);
      lines
        ..clear()
        ..add(_PLine());
      preview = null;
      error = null;
      _formKey++;
    });
  }

  // ---------------- UI ----------------
  static const double _wSno = 34, _wHsn = 96, _wQty = 80, _wUnit = 96, _wRate = 104, _wAmt = 116, _wAct = 40;

  Widget _numBox(TextEditingController c, String label, double w, {bool decimal = true, void Function(String)? on, bool readOnly = false}) => SizedBox(
        width: w,
        child: AppField(
          controller: c,
          label: label,
          number: decimal,
          align: decimal ? TextAlign.right : TextAlign.start,
          readOnly: readOnly,
          onChanged: (v) {
            on?.call(v);
            _recalcSoon();
          },
        ),
      );

  Widget _itemPicker(_PLine l, double w) => AppDropdownSearch<int>(
        key: ValueKey('${l.key}-${l.itemId}-${items.length}'),
        width: w,
        label: 'Item name',
        value: l.itemId,
        options: {for (final it in items) it['id'] as int: '${it['name']}'},
        onChanged: (v) {
          final it = _item(v);
          setState(() {
            l.itemId = v;
            l.matched = true;
            if (it != null) {
              if (_t(l.hsn).isEmpty) l.hsn.text = '${it['hsn'] ?? ''}';
              if (_t(l.rate).isEmpty && num_(it['purchase_price']) > 0) l.rate.text = '${it['purchase_price']}';
              l.autoAmount();
            }
          });
          _recalc();
        },
      );

  Widget _unitPicker(_PLine l) => AppDropdown<String>(
        key: ValueKey('${l.key}-unit-${l.unit}'),
        width: _wUnit,
        label: 'Unit',
        value: l.unit,
        options: {for (final u in {..._unitList, l.unit}) u: u},
        onChanged: (v) {
          setState(() => l.unit = v ?? l.unit);
          _recalc();
        },
      );

  Widget _lineActions(int i, _PLine l) => SizedBox(
        width: _wAct,
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          IconButton(
            tooltip: 'Remove row',
            icon: const Icon(Icons.close, size: 18),
            onPressed: lines.length > 1
                ? () {
                    setState(() => _retire([lines.removeAt(i)]));
                    _recalc();
                  }
                : null,
          ),
        ]),
      );

  Widget _lineRow(int i, double width) {
    final l = lines[i];
    final wide = width >= 860;
    final qty = _numBox(l.qty, 'Qty', _wQty, on: (_) => l.autoAmount());
    final rate = _numBox(l.rate, 'Price', _wRate, on: (_) => l.autoAmount());
    final amt = _numBox(l.amount, 'Amount', _wAmt, on: (_) => l.amountManual = true);
    final hsn = SizedBox(width: _wHsn, child: AppField(controller: l.hsn, label: 'HSN code', onChanged: (_) => _recalcSoon()));
    final it = _item(l.itemId);
    final perBox = it == null ? 1 : num_(it['pcs_per_box']).toInt();
    final isBox = RegExp(r'^(BOX|CTN|CASE|CARTON|DOZ|DZN)', caseSensitive: false).hasMatch(l.unit);
    final pcsHint = it != null && isBox && perBox > 1 && l.q > 0
        ? '${l.qty.text.trim()} ${l.unit} × $perBox = ${(l.q * perBox).round()} pcs go into stock'
        : (it != null && perBox > 1 ? '1 box = $perBox pcs' : '');
    final note = !l.matched && l.desc.isNotEmpty
        ? Row(children: [
            Flexible(child: Text('On the bill: "${l.desc}" is not in your stock list.', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.brick, fontSize: 12))),
            TextButton(onPressed: () => _createItem(l), child: const Text('Create this item')),
          ])
        : (l.desc.isNotEmpty || pcsHint.isNotEmpty
            ? Text([if (l.created) 'New item added', if (l.desc.isNotEmpty) 'On the bill: ${l.desc}', if (pcsHint.isNotEmpty) pcsHint].join('   ·   '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.created ? Palette.teal : Palette.muted, fontSize: 11))
            : const SizedBox.shrink());
    return Container(
      key: l.key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (wide)
          Row(children: [
            SizedBox(width: _wSno, child: Text('${i + 1}', style: tabular.copyWith(color: Palette.muted))),
            Expanded(child: LayoutBuilder(builder: (_, b) => _itemPicker(l, b.maxWidth))),
            const SizedBox(width: 8),
            hsn,
            const SizedBox(width: 8),
            qty,
            const SizedBox(width: 8),
            _unitPicker(l),
            const SizedBox(width: 8),
            rate,
            const SizedBox(width: 8),
            amt,
            _lineActions(i, l),
          ])
        else
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${i + 1}.', style: tabular.copyWith(color: Palette.muted)),
            _itemPicker(l, math.min(width - 60, 360.0)),
            hsn,
            qty,
            _unitPicker(l),
            rate,
            amt,
            _lineActions(i, l),
          ]),
        Padding(padding: EdgeInsets.only(left: wide ? _wSno : 0, top: 2), child: note),
      ]),
    );
  }

  Widget _head(double width) {
    if (width < 860) return const SizedBox.shrink();
    TextStyle st = const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Palette.muted);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
      child: Row(children: [
        SizedBox(width: _wSno, child: Text('S.No', style: st)),
        Expanded(child: Text('Item name', style: st)),
        const SizedBox(width: 8),
        SizedBox(width: _wHsn, child: Text('HSN code', style: st)),
        const SizedBox(width: 8),
        SizedBox(width: _wQty, child: Text('Qty', style: st, textAlign: TextAlign.right)),
        const SizedBox(width: 8),
        SizedBox(width: _wUnit, child: Text('Unit', style: st)),
        const SizedBox(width: 8),
        SizedBox(width: _wRate, child: Text('Price', style: st, textAlign: TextAlign.right)),
        const SizedBox(width: 8),
        SizedBox(width: _wAmt, child: Text('Amount', style: st, textAlign: TextAlign.right)),
        const SizedBox(width: _wAct),
      ]),
    );
  }

  Widget _totalsPanel(Json? p) {
    final inter = p != null && p['supply'] == 'INTER';
    String hint(String k) => p == null ? '' : '${p[k] ?? ''}';
    Widget amountBox(TextEditingController c, String label, String hintKey) => SizedBox(
          width: 120,
          child: AppField(controller: c, label: label, hint: hint(hintKey), number: true, align: TextAlign.right, onChanged: (_) => _recalcSoon()),
        );
    final printed = printedTotal;
    final mismatch = p != null && num_(p['mismatch']).abs() > 0;
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          amountBox(discCtl, 'Discount', 'discount'),
          if (!inter) ...[amountBox(cgstCtl, 'CGST', 'cgst'), amountBox(sgstCtl, 'SGST', 'sgst')] else amountBox(igstCtl, 'IGST', 'igst'),
          amountBox(roundCtl, 'Rounded off', 'round_off'),
          Tooltip(
            message: 'Work out CGST / SGST / IGST again from each item\'s GST rate',
            child: OutlinedButton.icon(
              onPressed: () {
                cgstCtl.clear();
                sgstCtl.clear();
                igstCtl.clear();
                autoTax = true;
                _recalc();
                autoTax = false;
              },
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Auto tax'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 150, child: AppField(controller: paidCtl, label: 'Paid now', number: true, align: TextAlign.right)),
          AppDropdown<String>(width: 130, label: 'Mode', value: payMode, options: {for (final m in ['CASH', 'UPI', 'BANK', 'CHEQUE']) m: m}, onChanged: (v) => payMode = v ?? payMode),
          if (p != null) ...[
            Text('Items ${money(p['subtotal'])}', style: tabular),
            Text('Taxable ${money(p['taxable'])}', style: tabular),
          ],
        ]),
        const Divider(height: 24),
        Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, children: [
          if (printed != null)
            Text('Printed on bill: ${money(printed)}', style: tabular.copyWith(color: mismatch ? Palette.brick : Palette.muted, fontWeight: mismatch ? FontWeight.w600 : null)),
          if (p != null) Text(money(p['total']), style: tabular.copyWith(fontSize: 26, fontWeight: FontWeight.w700, color: Palette.teal)),
          OutlinedButton(onPressed: _reset, child: Text(editingId != null ? 'Cancel edit' : 'Clear')),
          FilledButton.icon(
            onPressed: busy || p == null ? null : _save,
            icon: Icon(editingId != null ? Icons.save : Icons.inventory),
            label: Text(editingId != null ? 'Update bill' : 'Save and add to stock'),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final pg = (parsed?['pages'] as Json?) ?? {};
    return KeyedSubtree(
      key: ValueKey(_formKey),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(editingId != null ? 'Edit purchase bill $editingNo' : 'Purchase bill', actions: [
          if (parsed != null) TextButton(onPressed: _viewText, child: const Text('View text read from PDF')),
          if (editingId == null)
            OutlinedButton.icon(
              onPressed: scanning ? null : _scanPdf,
              icon: scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.document_scanner_outlined),
              label: Text(scanning ? 'Reading PDF…' : 'Scan PDF bill'),
            ),
        ]),
        if (editingId != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Palette.turmeric.withValues(alpha: .15), borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: Palette.turmeric)),
            child: const Text('Editing a saved bill. Updating reverses the old stock and ledger entries and writes the corrected bill under the same number.'),
          ),
        if (source == 'PDF' && parsed != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Palette.turmeric.withValues(alpha: .12), borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: Palette.turmeric)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Filled in from the PDF (${(pg['used'] as List?)?.length ?? 1} Original page${((pg['used'] as List?)?.length ?? 1) == 1 ? '' : 's'} read). Check every field against the paper bill before saving.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final w in warnings) Text('• $w', style: const TextStyle(color: Palette.brick)),
            ]),
          ),
        FormWrap([
          AppDropdownSearch<int>(
            key: ValueKey('sup$supplierId${suppliers.length}'),
            width: 300,
            label: 'Supplier',
            value: supplierId,
            options: {0: 'Select supplier…', for (final s in suppliers) s['id'] as int: '${s['name']}'},
            onChanged: (v) {
              setState(() => supplierId = v ?? 0);
              _recalc();
            },
          ),
          AppField(width: 200, controller: noCtl, label: 'Supplier invoice no.', onChanged: (_) => _recalcSoon()),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await pickDate(context, date);
              if (d != null) {
                setState(() => date = d);
                _recalc();
              }
            },
            icon: const Icon(Icons.event, size: 18),
            label: Text('Bill date  ${dmy(date)}'),
          ),
          if (pendingSupplier != null)
            FilledButton.tonalIcon(onPressed: _createSupplier, icon: const Icon(Icons.person_add_alt), label: Text('Create supplier "${pendingSupplier!['name']}"')),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _head(box.maxWidth - 24),
                    for (var i = 0; i < lines.length; i++) _lineRow(i, box.maxWidth - 24),
                    TextButton.icon(
                      onPressed: () => setState(() => lines.add(_PLine())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add row'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(error!, style: const TextStyle(color: Palette.brick))),
        const SizedBox(height: 8),
        _totalsPanel(p),
      ]),
    );
  }
}
