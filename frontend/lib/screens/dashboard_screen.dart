import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  Json? d;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/reports/dashboard');
      if (!mounted) return;
      setState(() {
        d = r;
        err = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => err = e.message);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    if (err != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(err!, style: const TextStyle(color: Palette.brick)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _load, child: const Text('Try again')),
      ]));
    }
    if (d == null) return const Center(child: CircularProgressIndicator());
    final x = d!;
    final company = AppScope.of(context).companyName;
    final gst = num_(x['gst_liability']);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1060;
      final cardW = wide ? (c.maxWidth - 4 * 14) / 5 : (c.maxWidth - 14) / 2;
      Widget card(String label, String value, String sub, IconData icon, Color color) => SizedBox(
            width: cardW,
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: TextStyle(color: Palette.muted, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 14),
                Text(value, style: tabular.copyWith(fontSize: 25, fontWeight: FontWeight.w700, color: Palette.ink, letterSpacing: -.5)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(color: Palette.muted, fontSize: 12), maxLines: 2),
              ]),
            ),
          );

      final panels = [
        Panel(title: 'Sales and purchases, last 14 days', child: _Bars(series: (x['series'] as List).cast<Json>())),
        Panel(
          title: 'Low stock alerts',
          trailing: Text('${x['low_stock_count']} items', style: TextStyle(color: Palette.muted, fontSize: 12)),
          child: (x['low_stock'] as List).isEmpty
              ? const Text('No item is at or below the low-stock level.', style: TextStyle(color: Palette.muted))
              : Column(children: [
                  for (final i in (x['low_stock'] as List).cast<Json>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(i['name'], maxLines: 1, overflow: TextOverflow.ellipsis)),
                        t('${i['stock']} pcs', color: num_(i['stock']) == 0 ? Palette.brick : Palette.turmeric, bold: true),
                      ]),
                    ),
                ]),
        ),
        Panel(
          title: 'Highest dues to collect',
          child: (x['top_dues'] as List).isEmpty
              ? const Text('No pending dues.', style: TextStyle(color: Palette.muted))
              : Column(children: [
                  for (final p in (x['top_dues'] as List).cast<Json>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [Expanded(child: Text(p['name'])), t(money(p['balance']), bold: true)]),
                    ),
                ]),
        ),
      ];

      return ListView(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_greeting()}', style: TextStyle(color: Palette.muted, fontSize: 14)),
              Text(company, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Palette.ink, letterSpacing: -.6)),
            ]),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          card('Total sales (${x['month']})', money(x['month_sales']), 'Today ${money(x['today_sales'])} · ${x['today_bills']} bills', Icons.trending_up, Palette.teal),
          card('Total purchases', money(x['month_purchases']), '${x['month_purchase_bills']} supplier bills this month', Icons.local_shipping_outlined, Palette.leaf),
          card('Outstanding dues', money(x['receivable']), 'To receive. You owe suppliers ${money(x['payable'])}', Icons.account_balance_wallet_outlined, Palette.turmeric),
          card('GST liability', money(gst.abs()), gst >= 0 ? 'Payable: output ${money(x['gst_output'])} − input ${money(x['gst_input'])}' : 'Credit carried forward (input exceeds output)',
              Icons.receipt_long_outlined, gst >= 0 ? Palette.brick : Palette.leaf),
          card('Low stock', '${x['low_stock_count']}', 'Items at or below ${AppScope.read(context).settings['low_stock_qty'] ?? 10} pieces', Icons.warning_amber_rounded,
              num_(x['low_stock_count']) > 0 ? Palette.brick : Palette.leaf),
        ]),
        const SizedBox(height: 14),
        if (wide) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: panels[0]), const SizedBox(width: 14), Expanded(flex: 2, child: panels[1])]),
          const SizedBox(height: 14),
          panels[2],
        ] else
          for (final p in panels) Padding(padding: const EdgeInsets.only(bottom: 14), child: p),
      ]);
    });
  }
}

class _Bars extends StatelessWidget {
  final List<Json> series;
  const _Bars({required this.series});
  @override
  Widget build(BuildContext context) {
    var mx = 1.0;
    for (final s in series) {
      mx = [mx, num_(s['sales']).toDouble(), num_(s['purchases']).toDouble()].reduce((a, b) => a > b ? a : b);
    }
    const h = 150.0;
    return Column(children: [
      SizedBox(
        height: h + 18,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final s in series)
            Expanded(
              child: Tooltip(
                message: '${dmy(s['date'])}\nSales ${money(s['sales'])}\nPurchases ${money(s['purchases'])}',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 9, height: 2 + h * num_(s['sales']).toDouble() / mx, decoration: BoxDecoration(color: Palette.teal, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 2),
                    Container(width: 9, height: 2 + h * num_(s['purchases']).toDouble() / mx, decoration: BoxDecoration(color: Palette.turmeric, borderRadius: BorderRadius.circular(3))),
                  ]),
                  const SizedBox(height: 4),
                  Text((s['date'] as String).substring(8, 10), style: const TextStyle(fontSize: 10, color: Palette.muted)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      const Row(children: [
        Icon(Icons.circle, size: 10, color: Palette.teal), SizedBox(width: 4), Text('Sales', style: TextStyle(fontSize: 12)),
        SizedBox(width: 14),
        Icon(Icons.circle, size: 10, color: Palette.turmeric), SizedBox(width: 4), Text('Purchases', style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }
}
