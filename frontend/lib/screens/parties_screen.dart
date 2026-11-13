import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../print/print_dialog.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';
import 'payment_sheet.dart';

const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});
  @override
  State<PartiesScreen> createState() => _PartiesState();
}

class _PartiesState extends State<PartiesScreen> {
  List<Json> parties = [], routes = [], salesmen = [];
  String q = '';
  String kind = 'CUSTOMER'; // CUSTOMER | SUPPLIER
  final _debounce = Debouncer();

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = await Future.wait([Api.get('/parties', {'q': q, 'kind': kind}), Api.get('/routes'), Api.get('/salesmen')]);
        if (!mounted) return;
        setState(() {
          parties = (r[0] as List).cast<Json>();
          routes = (r[1] as List).cast<Json>();
          salesmen = (r[2] as List).cast<Json>();
        });
      });

  Future<void> _form([Json? p]) async {
    final v = await showDialog<Json>(
      context: context,
      builder: (_) => _PartyForm(party: p, routes: routes, salesmen: salesmen, defaultType: kind == 'SUPPLIER' ? 'SUPPLIER' : 'RETAILER'),
    );
    if (v == null || !mounted) return;
    await guard(context, () async {
      if (p == null) {
        await Api.post('/parties', v);
      } else {
        await Api.put('/parties/${p['id']}', v);
      }
      await _load();
    });
  }

  /// Customers go on every route that lists a place (comma separated in the route's name) found in their name or address
  /// (POST /routes/auto-assign): preview, untick, apply. A customer can get several routes.
  Future<void> _autoRoutes() => guard(context, () async {
        final pre = await Api.post('/routes/auto-assign', {'apply': false}) as Json;
        if (!mounted) return;
        final matches = (pre['matches'] as List).cast<Json>();
        String key(Json m) => '${m['party_id']}-${m['route_id']}';
        final skip = <String>{};   // unticked "party-route" pairs
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
            final n = matches.where((m) => !skip.contains(key(m))).length;
            final unmatched = num_(pre['unmatched']).toInt();
            return AlertDialog(
              title: const Text('Assign routes from name and address'),
              content: SizedBox(
                width: math.min(620.0, MediaQuery.sizeOf(ctx).width - 80),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(matches.isEmpty
                      ? 'No customer has a place of a route in its name or address (that it is not on already).'
                      : '${matches.length} routes to add. A customer goes on every route whose name lists a place (comma separated) found in the customer\'s name or address. Untick any that are wrong.'),
                  if (unmatched > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Left without a route: $unmatched customers matching no route.',
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final m in matches)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: !skip.contains(key(m)),
                          onChanged: (v) => setSt(() {
                            if (v == true) {
                              skip.remove(key(m));
                            } else {
                              skip.add(key(m));
                            }
                          }),
                          title: Text('${m['party_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${'${m['address'] ?? ''}'.isEmpty ? '' : '${m['address']}\n'}→ ${m['route_name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ]),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: n == 0 ? null : () => Navigator.pop(ctx, true), child: Text('Assign $n')),
              ],
            );
          }),
        );
        if (ok != true || !mounted) return;
        final picked = [for (final m in matches) if (!skip.contains(key(m))) {'party_id': m['party_id'], 'route_id': m['route_id']}];
        final r = await Api.post('/routes/auto-assign', {'apply': true, 'assignments': picked}) as Json;
        if (mounted) toast(context, '${r['assigned']} routes assigned.');
        await _load();
      });

  Future<void> _delete(Json p) async {
    if (!await confirm(context, 'Delete ${p['name']}?', 'A party with bills or ledger entries is archived (hidden, books stay correct). A party with no history is removed.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await guard(context, () async {
      final r = await Api.delete('/parties/${p['id']}') as Json;
      if (mounted) toast(context, r['result'] == 'archived' ? '${p['name']} archived. History is kept.' : '${p['name']} deleted.');
      await _load();
    });
  }

  /// Returns the date of the saved payment (null when cancelled or it failed).
  Future<String?> _voucher(Json p) async {
    final supplier = p['type'] == 'SUPPLIER';
    final v = await formDialog(context, 'Payment · ${p['name']}', [
      FieldSpec('direction', 'Direction', initial: supplier ? 'PAID' : 'RECEIVED', options: const {'RECEIVED': 'Received from them (money in)', 'PAID': 'Paid to them (money out)'}),
      const FieldSpec('amount', 'Amount', number: true),
      const FieldSpec('mode', 'Mode', options: {'CASH': 'Cash', 'UPI': 'UPI', 'CARD': 'Card', 'CHEQUE': 'Cheque', 'BANK': 'Bank transfer'}),
      FieldSpec('date', 'Date', initial: todayStr(), date: true),
      const FieldSpec('reference', 'Reference / cheque no. (optional)'),
    ], okLabel: 'Record payment');
    if (v == null || !mounted) return null;
    String? savedDate;
    await guard(context, () async {
      final r = await Api.post('/vouchers', v..['party_id'] = '${p['id']}') as Json;
      savedDate = '${v['date'] ?? ''}';
      if (mounted) toast(context, '${r['voucher_no']} recorded. ${_balText(r['balance'])}');
      await _load();
      if (mounted && await confirm(context, 'Print voucher?', '${r['voucher_no']} for ${money(r['amount'])}', ok: 'Print')) {
        if (mounted) await printVoucher(context, '${r['voucher_no']}');
      }
    });
    return savedDate;
  }

  String _balText(dynamic b) {
    final n = num_(b);
    if (n.abs() < 0.5) return 'Settled';
    return n > 0 ? 'To receive ${money(n)}' : 'To pay ${money(-n)}';
  }

  /// "2026-27" for a date like 2026-11-02 (the financial year runs 1 April to 31 March).
  String _fyOf(String iso) {
    final q = iso.split('-');
    if (q.length < 2) return '';
    final y = int.tryParse(q[0]), m = int.tryParse(q[1]);
    if (y == null || m == null) return '';
    final s = m >= 4 ? y : y - 1;
    return '$s-${((s + 1) % 100).toString().padLeft(2, '0')}';
  }

  /// The party's ledger. Receipts, payments and opening balances can be deleted here; a bill's own line is removed by
  /// deleting or editing the bill. After "Record payment" the ledger opens again, on the year of the new line.
  Future<void> _ledger(Json p, {String fy = ''}) async {
    var wantVoucher = false;
    await guard(context, () async {
      Future<Json> fetch() async => await Api.get('/parties/${p['id']}/ledger', fy.isEmpty ? null : {'fy': fy}) as Json;
      var l = await fetch();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
          final rows = (l['entries'] as List).cast<Json>();
          bool deletable(Json r) => const ['RECEIPT', 'PAYMENT', 'OPENING'].contains(r['type']);
          Future<void> remove(Json r) async {
            final amt = num_(r['credit']) > 0 ? r['credit'] : r['debit'];
            if (!await confirm(ctx, 'Delete ${r['type']} ${r['ref_no'] ?? ''} · ${money(amt)}?', 'The voucher behind it is removed too and the balance is worked out again. This cannot be undone.', ok: 'Delete', danger: true)) return;
            if (!mounted) return;
            await guard(context, () async {
              await Api.delete('/ledger/${r['id']}');
              l = await fetch();
              if (mounted) toast(context, 'Deleted ${r['type']} ${r['ref_no'] ?? ''}.');
              setSt(() {});
              await _load();
            });
          }

          return AlertDialog(
            title: Text('${p['name']} · ledger${fy.isEmpty ? '' : ' · FY $fy'}'),
            content: SizedBox(
              width: math.min(860.0, MediaQuery.sizeOf(ctx).width - 80),
              height: math.min(460.0, MediaQuery.sizeOf(ctx).height - 220),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_balText(l['balance']), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: num_(l['balance']) > 0 ? Palette.turmeric : (num_(l['balance']) < 0 ? Palette.brick : Palette.leaf))),
                const SizedBox(height: 8),
                Expanded(
                  child: table(['Date', 'Type', 'Reference', 'Narration', 'Debit', 'Credit', 'Balance', ''], [
                      for (final r in rows)
                        [
                          t(dmy(r['date'])),
                          t('${r['type']}'),
                          t('${r['ref_no'] ?? ''}'),
                          t('${r['narration'] ?? ''}'),
                          t(num_(r['debit']) > 0 ? money(r['debit']) : ''),
                          t(num_(r['credit']) > 0 ? money(r['credit']) : ''),
                          t('${money(num_(r['balance']).abs())} ${num_(r['balance']) > 0 ? 'Dr' : (num_(r['balance']) < 0 ? 'Cr' : '')}', bold: true),
                          deletable(r)
                              ? IconButton(tooltip: 'Delete this line', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => remove(r))
                              : const SizedBox.shrink(),
                        ],
                    ], numeric: {4, 5, 6}),
                ),
                Text('Dr = they owe you. Cr = you owe them. Use the bin to delete a receipt, payment or opening line.', style: TextStyle(color: Palette.muted, fontSize: 12)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
              FilledButton(
                  onPressed: () {
                    wantVoucher = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Record payment')),
            ],
          );
        }),
      );
    });
    if (wantVoucher && mounted) {
      final d = await _voucher(p);
      // the ledger comes back either way, on the year of the line that was just saved
      if (mounted) await _ledger(p, fy: d == null ? fy : _fyOf(d));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader('Parties', actions: [
        if (kind != 'SUPPLIER') OutlinedButton.icon(onPressed: _autoRoutes, icon: const Icon(Icons.alt_route), label: const Text('Assign routes')),
        if (kind != 'SUPPLIER')
          OutlinedButton.icon(
            onPressed: () async {
              if (await showPaymentSheet(context)) _load();
            },
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Payments from a list'),
          ),
        FilledButton.icon(onPressed: () => _form(), icon: const Icon(Icons.add), label: Text(kind == 'SUPPLIER' ? 'New supplier' : 'New customer')),
      ]),
      FormWrap([
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'CUSTOMER', label: Text('Customers')), ButtonSegment(value: 'SUPPLIER', label: Text('Suppliers'))],
          selected: {kind},
          onSelectionChanged: (s) {
            kind = s.first;
            _load();
          },
        ),
        AppField(
          width: 320,
          prefix: const Icon(Icons.search),
          hint: 'Search name, phone, mobile or GSTIN',
          onChanged: (v) {
            q = v;
            _debounce.run(_load);
          },
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: table([
            'Party', kind == 'SUPPLIER' ? 'GSTIN' : 'Route', if (kind != 'SUPPLIER') 'Tier', if (kind == 'SUPPLIER') 'Contact', 'Phone', if (kind != 'SUPPLIER') 'Credit limit', 'Balance', ''
          ], [
            for (final p in parties)
              [
                t('${p['name']}', bold: true),
                t(kind == 'SUPPLIER' ? '${p['gstin'] ?? ''}' : '${p['route_name'] ?? ''}'),
                if (kind != 'SUPPLIER') t('${p['price_tier']}'),
                if (kind == 'SUPPLIER') t('${p['mobiles'] ?? p['tel'] ?? ''}'),
                t('${p['phone'] ?? ''}'),
                if (kind != 'SUPPLIER') t(num_(p['credit_limit']) > 0 ? money(p['credit_limit']) : 'No limit'),
                t(
                  num_(p['balance']).abs() < 0.5 ? 'Settled' : (num_(p['balance']) > 0 ? 'To receive ${money(p['balance'])}' : 'To pay ${money(-num_(p['balance']))}'),
                  bold: true,
                  color: num_(p['credit_limit']) > 0 && num_(p['balance']) > num_(p['credit_limit'])
                      ? Palette.brick
                      : (num_(p['balance']) > 0.5 ? Palette.turmeric : (num_(p['balance']) < -0.5 ? Palette.teal : null)),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: () => _ledger(p), child: const Text('Ledger')),
                  TextButton(onPressed: () => _voucher(p), child: const Text('Payment')),
                  IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _form(p)),
                  IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline, color: Palette.brick), onPressed: () => _delete(p)),
                ]),
              ],
          ], numeric: {if (kind != 'SUPPLIER') ...{4, 5} else 4}, menu: (i) {
            final p = parties[i];
            return [
              RowAction('Ledger', () => _ledger(p), icon: Icons.menu_book_outlined),
              RowAction('Payment', () => _voucher(p), icon: Icons.payments_outlined),
              RowAction('Edit party', () => _form(p), icon: Icons.edit_outlined),
              RowAction('Delete', () => _delete(p), icon: Icons.delete_outline, danger: true),
            ];
          }),
      ),
    ]);
  }
}

/// Add / edit a party. The Route box has a "+ New route…" entry that reveals name, salesman and visit day,
/// so a route can be created and assigned without leaving this form.
class _PartyForm extends StatefulWidget {
  final Json? party;
  final List<Json> routes, salesmen;
  final String defaultType;
  const _PartyForm({required this.party, required this.routes, required this.salesmen, required this.defaultType});
  @override
  State<_PartyForm> createState() => _PartyFormState();
}

class _PartyFormState extends State<_PartyForm> {
  late final Map<String, TextEditingController> c;
  late String type, tier;
  final routeSet = <int>{}; // ids of the routes this party is on (a party can be on several)
  bool addNew = false;
  String newSalesman = '', newDay = '1';
  String? err;

  static const _keys = ['name', 'gstin', 'state_code', 'phone', 'tel', 'mobiles', 'email', 'fssai', 'pan', 'address', 'credit_limit', 'credit_days', 'opening_balance', 'new_route'];

  @override
  void initState() {
    super.initState();
    final p = widget.party;
    String v(String k, [String d = '']) => p == null || p[k] == null ? d : '${p[k]}';
    c = {
      for (final k in _keys)
        k: TextEditingController(text: k == 'new_route' ? '' : v(k, k == 'state_code' ? '09' : (k == 'credit_limit' || k == 'credit_days' || k == 'opening_balance' ? '0' : '')))
    };
    type = p == null ? widget.defaultType : v('type', 'RETAILER');
    tier = v('price_tier', 'RETAIL');
    routeSet.addAll(v('route_ids').split(',').map((x) => int.tryParse(x.trim())).whereType<int>());
    if (routeSet.isEmpty && p != null && p['route_id'] != null) routeSet.add(num_(p['route_id']).toInt());
    // Typing a GSTIN fills the state code and PAN boxes (the first 2 digits are the state, characters 3 to 12 the PAN).
    c['gstin']!.addListener(() {
      final g = c['gstin']!.text.trim().toUpperCase();
      if (g.length >= 2 && RegExp(r'^\d{2}').hasMatch(g) && c['state_code']!.text != g.substring(0, 2)) c['state_code']!.text = g.substring(0, 2);
      if (g.length == 15 && c['pan']!.text.trim().isEmpty) c['pan']!.text = g.substring(2, 12);
    });
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  /// Width of one column: two columns side by side in a wide dialog, one column in a narrow window.
  double _w(double total, {bool full = false}) => full || total < 520 ? total : (total - 12) / 2;

  Widget _tf(String k, String label, double w, {bool number = false, String? hint}) => AppField(width: w, controller: c[k], label: label, hint: hint, number: number);

  void _submit() {
    if (c['name']!.text.trim().isEmpty) return setState(() => err = 'Party name is required');
    final supplier = type == 'SUPPLIER';
    final makeRoute = addNew && !supplier;
    if (makeRoute && c['new_route']!.text.trim().isEmpty) return setState(() => err = 'Enter a name for the new route');
    final out = <String, dynamic>{
      for (final k in ['name', 'gstin', 'state_code', 'phone', 'address', 'credit_limit', 'credit_days', 'tel', 'mobiles', 'email', 'fssai', 'pan']) k: c[k]!.text.trim(),
      'type': type,
      'price_tier': tier,
      'route_ids': supplier ? <int>[] : [for (final r in widget.routes) if (routeSet.contains(num_(r['id']).toInt())) num_(r['id']).toInt()],
    };
    if (widget.party == null) out['opening_balance'] = c['opening_balance']!.text.trim();
    if (makeRoute) out['new_route'] = {'name': c['new_route']!.text.trim(), 'salesman_id': newSalesman, 'day_of_week': newDay};
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final supplier = type == 'SUPPLIER';
    final total = math.min(560.0, MediaQuery.sizeOf(context).width - 80);
    final half = _w(total), full = total;
    return AlertDialog(
      title: Text(widget.party == null ? 'New party' : 'Edit ${widget.party!['name']}'),
      content: SizedBox(
        width: total,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _tf('name', 'Party name', full),
              AppDropdown<String>(
                width: half,
                label: 'Type',
                value: type,
                options: const {'RETAILER': 'Retailer', 'WHOLESALER': 'Wholesaler', 'SUPPLIER': 'Supplier / vendor'},
                onChanged: (v) => setState(() => type = v ?? type),
              ),
              _tf('gstin', 'GSTIN (blank if unregistered)', half),
              _tf('state_code', 'State code (09 UP, 07 Delhi)', half, hint: 'decides CGST+SGST or IGST'),
              _tf('address', 'Address', full),
              if (supplier) ...[
                _tf('tel', 'Tel (landline)', half),
                _tf('phone', 'Phone', half),
                _tf('mobiles', 'Mobile numbers', full, hint: 'more than one: separate with commas'),
                _tf('email', 'Email', half),
                _tf('fssai', 'FSSAI number (14 digits)', half),
                _tf('pan', 'PAN number', half, hint: 'filled from GSTIN'),
              ] else
                _tf('phone', 'Phone', half),
              if (!supplier) ...[
                AppDropdown<String>(
                  width: half,
                  label: 'Price tier',
                  value: tier,
                  options: const {'RETAIL': 'Retail price', 'WHOLESALE': 'Wholesale price', 'MRP': 'MRP'},
                  onChanged: (v) => tier = v ?? tier,
                ),
                _tf('credit_limit', 'Credit limit (0 = no limit)', half, number: true),
                _tf('credit_days', 'Credit days', half, number: true),
                SizedBox(
                  width: full,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Delivery / sales routes (tick every route this party is on)', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final r in widget.routes)
                        FilterChip(
                          label: Text('${r['name']}${r['day_of_week'] != null ? ' · ${_dayNames[r['day_of_week']]}' : ''}'),
                          selected: routeSet.contains(num_(r['id']).toInt()),
                          onSelected: (on) => setState(() {
                            final id = num_(r['id']).toInt();
                            if (on) {
                              routeSet.add(id);
                            } else {
                              routeSet.remove(id);
                            }
                          }),
                        ),
                      FilterChip(label: const Text('+ New route…'), selected: addNew, onSelected: (on) => setState(() => addNew = on)),
                    ]),
                  ]),
                ),
                if (addNew)
                  Container(
                    width: full,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Palette.paper, borderRadius: BorderRadius.circular(kRadius), border: Border.all(color: Palette.line)),
                    child: Wrap(spacing: 12, runSpacing: 12, children: [
                      _tf('new_route', 'New route name (e.g. Nagina Road Beat)', full - 24),
                      AppDropdown<String>(
                        width: _w(full - 24),
                        label: 'Salesman for this route',
                        value: '',
                        options: {'': 'Not assigned yet', for (final s in widget.salesmen) '${s['id']}': '${s['name']}'},
                        onChanged: (v) => newSalesman = v ?? '',
                      ),
                      AppDropdown<String>(
                        width: _w(full - 24),
                        label: 'Visit day',
                        value: newDay,
                        options: {for (var i = 0; i < 7; i++) '$i': _dayNames[i]},
                        onChanged: (v) => newDay = v ?? newDay,
                      ),
                    ]),
                  ),
              ],
              if (widget.party == null) _tf('opening_balance', supplier ? 'Opening balance (negative = you owe them)' : 'Opening balance (they owe you)', full, number: true),
              if (err != null) Text(err!, style: TextStyle(color: Palette.brick)),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
