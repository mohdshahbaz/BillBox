import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

String _csv(List<List<dynamic>> rows) => rows.map((r) => r.map((c) => '"${'$c'.replaceAll('"', '""')}"').join(',')).join('\n');

/// Accounting books and GST: Sales Book, Purchase Book, monthly GST outward supplies by rate slab.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          PageHeader('Books and GST'),
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Sales book'), Tab(text: 'Purchase book'), Tab(text: 'GST outward supplies')]),
          SizedBox(height: 12),
          Expanded(child: TabBarView(children: [_Book(type: 'sales'), _Book(type: 'purchase'), _Gst()])),
        ]),
      );
}

class _Book extends StatefulWidget {
  final String type;
  const _Book({required this.type});
  @override
  State<_Book> createState() => _BookState();
}

class _BookState extends State<_Book> with AutomaticKeepAliveClientMixin {
  String from = '${todayStr().substring(0, 7)}-01', to = todayStr();
  Json? data;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = await Api.get('/reports/book/${widget.type}', {'from': from, 'to': to}) as Json;
        if (mounted) setState(() => data = r);
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sales = widget.type == 'sales';
    final rows = (data?['rows'] as List?)?.cast<Json>() ?? const <Json>[];
    final tot = (data?['totals'] as Json?) ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
        TextButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(
                      text: _csv([
                    ['Date', 'No', if (!sales) 'Supplier bill', 'Party', 'GSTIN', 'Taxable', 'CGST', 'SGST', 'IGST', 'Round off', 'Total'],
                    for (final r in rows) [dmy(r['date']), r['no'], if (!sales) r['ref'], r['party'], r['gstin'], r['taxable'], r['cgst'], r['sgst'], r['igst'], r['round_off'], r['total']],
                    ['TOTAL', '', if (!sales) '', '', '', tot['taxable'], tot['cgst'], tot['sgst'], tot['igst'], tot['round_off'], tot['total']],
                  ])));
                  if (mounted) toast(context, 'Copied. Paste into Excel or Numbers.');
                },
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copy as CSV'),
        ),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: data == null
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text('No entries in this period.', style: TextStyle(color: Palette.muted)))
                : SingleChildScrollView(
                    child: table(['Date', sales ? 'Invoice' : 'Our ref', if (!sales) 'Supplier bill', 'Party', 'GSTIN', 'Taxable', 'CGST', 'SGST', 'IGST', 'Round off', 'Total'], [
                      for (final r in rows)
                        [t(dmy(r['date'])), t('${r['no']}'), if (!sales) t('${r['ref']}'), t('${r['party']}'), t('${r['gstin']}'), t(money(r['taxable'])), t(money(r['cgst'])), t(money(r['sgst'])), t(money(r['igst'])), t(money(r['round_off'])), t(money(r['total']), bold: true)],
                      [
                        t('TOTAL', bold: true), t('${tot['count']} entries'), if (!sales) const Text(''), const Text(''), const Text(''),
                        t(money(tot['taxable']), bold: true), t(money(tot['cgst']), bold: true), t(money(tot['sgst']), bold: true), t(money(tot['igst']), bold: true), t(money(tot['round_off']), bold: true), t(money(tot['total']), bold: true),
                      ],
                    ], numeric: sales ? {5, 6, 7, 8, 9, 10} : {6, 7, 8, 9, 10, 11}),
                  ),
      ),
      if (data != null && rows.isNotEmpty)
        SummaryCard([
          SumItem('Entries', '${tot['count'] ?? rows.length}'),
          SumItem('Taxable', money(tot['taxable'])),
          SumItem('Tax', money(num_(tot['cgst']) + num_(tot['sgst']) + num_(tot['igst']))),
          SumItem('Total', money(tot['total']), strong: true),
        ]),
    ]);
  }
}

class _Gst extends StatefulWidget {
  const _Gst();
  @override
  State<_Gst> createState() => _GstState();
}

class _GstState extends State<_Gst> with AutomaticKeepAliveClientMixin {
  String month = todayStr().substring(0, 7);
  Json? d;
  bool exporting = false;

  /// Monthly workbook: Summary, B2B bills, B2C bills and the tax-rate-wise summary.
  Future<void> _export() async {
    setState(() => exporting = true);
    await guard(context, () async {
      final Uint8List bytes = await Api.getBytes('/reports/gst-outward.xlsx', {'month': month});
      if (!mounted) return;
      final path = await saveBytes(context, 'GST-Outward-$month.xlsx', bytes);
      if (path != null && mounted) toast(context, 'Saved $path');
    });
    if (mounted) setState(() => exporting = false);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = await Api.get('/reports/gst-outward', {'month': month}) as Json;
        if (mounted) setState(() => d = r);
      });

  void _shift(int by) {
    final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5, 7));
    final n = DateTime(y, m + by, 1);
    setState(() => month = '${n.year}-${n.month.toString().padLeft(2, '0')}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final x = d;
    final rows = (x?['rows'] as List?)?.cast<Json>() ?? const <Json>[];
    final tot = (x?['totals'] as Json?) ?? {};
    return ListView(children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Text('${month.substring(5, 7)}-${month.substring(0, 4)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        FilledButton.icon(
          onPressed: x == null || exporting ? null : _export,
          icon: exporting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.onAccent)) : const Icon(Icons.table_view_outlined),
          label: const Text('Export month to Excel'),
        ),
        TextButton.icon(
          onPressed: x == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(
                      text: _csv([
                    ['GST rate', 'Taxable value', 'CGST', 'SGST', 'IGST', 'Total tax', 'Invoice value'],
                    for (final r in rows) ['${r['rate']}%', r['taxable'], r['cgst'], r['sgst'], r['igst'], r['tax'], r['value']],
                    ['TOTAL', tot['taxable'], tot['cgst'], tot['sgst'], tot['igst'], tot['tax'], tot['value']],
                  ])));
                  if (mounted) toast(context, 'Copied. Paste into Excel or Numbers.');
                },
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Copy as CSV'),
        ),
      ]),
      const SizedBox(height: 8),
      if (x == null)
        const Center(child: CircularProgressIndicator())
      else ...[
        table(['GST rate', 'Taxable value', 'CGST', 'SGST', 'IGST', 'Total tax', 'Invoice value'], [
          for (final r in rows)
            [
              t('${r['rate']}%', bold: true), t(money(r['taxable'])), t(money(r['cgst'])), t(money(r['sgst'])), t(money(r['igst'])), t(money(r['tax'])), t(money(r['value'])),
            ],
          [t('Total', bold: true), t(money(tot['taxable']), bold: true), t(money(tot['cgst']), bold: true), t(money(tot['sgst']), bold: true), t(money(tot['igst']), bold: true), t(money(tot['tax']), bold: true), t(money(tot['value']), bold: true)],
        ], numeric: {1, 2, 3, 4, 5, 6}),
        const SizedBox(height: 16),
        Wrap(spacing: 14, runSpacing: 14, children: [
          Stat('Invoices in ${x['month']}', '${x['invoices']}'),
          Stat('B2B (party has GSTIN)', money((x['b2b'] as Json)['taxable']), color: Palette.leaf),
          Stat('B2C (no GSTIN)', money((x['b2c'] as Json)['taxable']), color: Palette.turmeric),
          Stat('Input tax credit (purchases)', money((x['input_credit'] as Json)['total']), color: Palette.leaf),
          Stat(num_(x['net_payable']) >= 0 ? 'Net GST payable (estimate)' : 'Credit carried forward', money(num_(x['net_payable']).abs()), color: num_(x['net_payable']) >= 0 ? Palette.brick : Palette.leaf),
        ]),
        const SizedBox(height: 10),
        Text('The Excel file has four sheets: Summary, B2B Bills, B2C Bills and Rate-wise Summary. Rates are taken from each invoice line. Round-off is excluded from taxable value. The net figure is an estimate (output tax minus purchase tax); confirm against your return before filing.',
            style: TextStyle(color: Palette.muted, fontSize: 12)),
      ],
    ]);
  }
}
