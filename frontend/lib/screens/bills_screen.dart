import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../print/print_dialog.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// All Bills: every sales invoice and purchase bill in one searchable, filterable list.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsState();
}

class _BillsState extends State<BillsScreen> {
  String type = 'ALL';
  String from = '${todayStr().substring(0, 7)}-01', to = todayStr(), q = '';
  bool unpaid = false;
  List<Json> rows = [];
  Json totals = {};
  bool loading = true;
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
        final r = await Api.get('/bills', {'type': type, 'from': from, 'to': to, 'q': q, 'unpaid': unpaid ? 1 : 0}) as Json;
        if (!mounted) return;
        setState(() {
          rows = (r['rows'] as List).cast<Json>();
          totals = r['totals'] as Json;
          loading = false;
        });
      });

  Future<void> _open(Json r) async {
    final sale = r['type'] == 'SALE';
    await guard(context, () async {
      final b = await Api.get(sale ? '/invoices/${r['id']}' : '/purchases/${r['id']}') as Json;
      if (!mounted) return;
      final ls = (b['lines'] as List).cast<Json>();
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${sale ? b['invoice_no'] : b['purchase_no']} · ${b['party_name'] ?? 'Cash customer'}'),
          content: SizedBox(
            width: math.min(900.0, MediaQuery.sizeOf(ctx).width - 80),
            height: math.min(460.0, MediaQuery.sizeOf(ctx).height - 220),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${dmy(b['date'])}${sale ? '' : '   ·   Supplier bill ${b['supplier_invoice_no'] ?? '-'}'}   ·   Total ${money(b['total'])}   ·   Paid ${money(b['paid'])}   ·   Due ${money(num_(b['total']) - num_(b['paid']))}'),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: sale
                      ? table(['Item', 'Qty', 'Free', 'Rate', 'Taxable', 'GST', 'Amount'], [
                          for (final l in ls)
                            [t('${l['item_name']}'), t('${l['qty']}'), t('${l['free_qty']}'), t(money(l['rate'])), t(money(l['taxable'])), t('${l['gst_rate']}%'), t(money(l['amount']), bold: true)],
                        ], numeric: {2, 3, 4, 5, 6, 7})
                      : table(['S.No', 'Item name', 'HSN code', 'Qty', 'Unit', 'Price', 'Amount'], [
                          for (final l in ls) [t('${l['sno']}'), t('${l['item_name']}'), t('${l['hsn'] ?? ''}'), t('${l['qty']}'), t('${l['unit'] ?? 'PCS'}'), t(money(l['rate'])), t(money(l['amount']), bold: true)],
                        ], numeric: {3, 5, 6}),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            if (!sale)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Discount ${money(b['discount'])}  CGST ${money(b['cgst'])}  SGST ${money(b['sgst'])}  IGST ${money(b['igst'])}  Round off ${money(b['round_off'])}',
                    style: tabular.copyWith(fontSize: 12, color: Palette.muted)),
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                AppScope.read(context).requestEdit(sale ? 'INVOICE' : 'PURCHASE', r['id'] as int);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit bill'),
            ),
            if (sale)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  printInvoice(context, r['id'] as int, forcePreview: true);
                },
                icon: const Icon(Icons.print),
                label: const Text('Print'),
              ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeader('All bills'),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'ALL', label: Text('All')), ButtonSegment(value: 'SALE', label: Text('Sales')), ButtonSegment(value: 'PURCHASE', label: Text('Purchases'))],
          selected: {type},
          onSelectionChanged: (s) {
            type = s.first;
            _load();
          },
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await pickDate(context, from);
            if (d != null) {
              from = d;
              _load();
            }
          },
          icon: const Icon(Icons.event, size: 16),
          label: Text('From ${dmy(from)}'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final d = await pickDate(context, to);
            if (d != null) {
              to = d;
              _load();
            }
          },
          icon: const Icon(Icons.event, size: 16),
          label: Text('To ${dmy(to)}'),
        ),
        AppField(
          width: 280,
          prefix: const Icon(Icons.search),
          hint: 'Bill no, supplier bill no, party',
          onChanged: (v) {
            q = v;
            _debounce.run(_load);
          },
        ),
        FilterChip(
          label: const Text('Unpaid only'),
          selected: unpaid,
          onSelected: (v) {
            unpaid = v;
            _load();
          },
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? const Center(child: Text('No bills match these filters.', style: TextStyle(color: Palette.muted)))
                : SingleChildScrollView(
                    child: table(['Date', 'Type', 'Bill no', 'Supplier bill', 'Party', 'Total', 'Paid', 'Due', ''], [
                      for (final r in rows)
                        [
                          t(dmy(r['date'])),
                          StatusPill(r['type'] == 'SALE' ? 'Sale' : 'Purchase', tint: r['type'] == 'SALE' ? Palette.teal : Palette.turmeric),
                          t('${r['no']}'),
                          t('${r['ref'] ?? ''}'),
                          t('${r['party']}'),
                          t(money(r['total'])),
                          t(money(r['paid'])),
                          t(money(num_(r['total']) - num_(r['paid'])), color: num_(r['total']) - num_(r['paid']) > 0.5 ? Palette.brick : null, bold: true),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(onPressed: () => _open(r), child: const Text('View')),
                            TextButton(onPressed: () => AppScope.read(context).requestEdit(r['type'] == 'SALE' ? 'INVOICE' : 'PURCHASE', r['id'] as int), child: const Text('Edit')),
                          ]),
                        ],
                    ], numeric: {5, 6, 7}),
                  ),
      ),
      SummaryCard([
        SumItem('Bills', '${rows.length}'),
        SumItem('Sales', money(totals['sales'])),
        SumItem('Purchases', money(totals['purchases'])),
        SumItem('Due', money(totals['due']), strong: true, tint: num_(totals['due']) > 0.5 ? Palette.brick : null),
      ]),
    ]);
  }
}
