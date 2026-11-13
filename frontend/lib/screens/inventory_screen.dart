import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';
import 'item_tools.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryState();
}

class _InventoryState extends State<InventoryScreen> {
  List<Json> items = [], cats = [];
  String q = '';
  int? catId;
  bool loading = true, categorising = false;
  final _debounce = Debouncer();
  num lowQty = 10;

  @override
  void initState() {
    super.initState();
    lowQty = num_(AppScope.read(context).settings['low_stock_qty'] ?? 10);
    _load();
  }

  @override
  void dispose() {
    _debounce.dispose();
    super.dispose();
  }

  Future<void> _load() => guard(context, () async {
        final r = await Future.wait([Api.get('/items', {'q': q, if (catId != null) 'category_id': catId}), Api.get('/categories')]);
        if (!mounted) return;
        setState(() {
          items = (r[0] as List).cast<Json>();
          cats = (r[1] as List).cast<Json>();
          loading = false;
        });
      });

  Map<String, String> get _catOptions => {'': 'None', for (final c in cats) '${c['id']}': c['name'] as String};

  static const _baseUnits = ['PCS', 'BOX', 'CASE', 'KG', 'GM', 'LTR', 'ML', 'PKT', 'DOZ', 'SET'];
  Map<String, String> _units(String cur) => {for (final u in {..._baseUnits, cur}) u: u};

  List<FieldSpec> _itemFields([Json? it]) {
    String v(String k, [String d = '']) => it == null || it[k] == null ? d : '${it[k]}';
    return [
      FieldSpec('name', 'Item name', initial: v('name')),
      FieldSpec('category_id', 'Category', options: _catOptions, initial: v('category_id')),
      FieldSpec('hsn', 'HSN code', initial: v('hsn')),
      FieldSpec('unit', 'Unit', initial: v('unit', 'PCS'), options: _units(v('unit', 'PCS'))),
      FieldSpec('gst_rate', 'GST rate %', number: true, initial: v('gst_rate', '18')),
      FieldSpec('pcs_per_box', 'Pieces in one box (1 if sold loose only)', number: true, initial: v('pcs_per_box', '1')),
      FieldSpec('mrp', 'MRP per piece (incl. GST)', number: true, initial: v('mrp')),
      FieldSpec('retail_price', 'Retail price per piece (ex-GST)', number: true, initial: v('retail_price')),
      FieldSpec('wholesale_price', 'Wholesale price per piece (ex-GST)', number: true, initial: v('wholesale_price')),
      FieldSpec('purchase_price', 'Purchase price per piece (ex-GST)', number: true, initial: v('purchase_price')),
    ];
  }

  /// Sets retail and wholesale prices of a whole category from the MRP: price = MRP without GST, less the chosen percentage.
  Future<void> _bulkPrices() async {
    int cat = catId ?? 0;
    final retail = TextEditingController(), whole = TextEditingController();
    String? preview;
    bool busy = false;
    Json body(bool pv) => {
          if (cat != 0) 'category_id': cat,
          if (retail.text.trim().isNotEmpty) 'retail_off': retail.text.trim(),
          if (whole.text.trim().isNotEmpty) 'wholesale_off': whole.text.trim(),
          'preview': pv,
        };
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Set prices from MRP'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppDropdown<int>(
                width: 420,
                label: 'Category',
                value: cat,
                options: {0: 'All categories', for (final c in cats) c['id'] as int: '${c['name']}'},
                onChanged: (v) => setD(() {
                  cat = v ?? 0;
                  preview = null;
                }),
              ),
              const SizedBox(height: 12),
              AppField(controller: retail, number: true, label: 'Retail price: % below MRP', hint: 'e.g. 10', onChanged: (_) => setD(() => preview = null)),
              const SizedBox(height: 12),
              AppField(controller: whole, number: true, label: 'Wholesale price: % below MRP', hint: 'e.g. 15', onChanged: (_) => setD(() => preview = null)),
              const SizedBox(height: 10),
              Text('Price = MRP without GST, less this percentage. Leave a box empty to keep that price as it is. Items without an MRP are skipped.',
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              if (preview != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(preview!, style: const TextStyle(fontSize: 13))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setD(() => busy = true);
                      try {
                        final r = await Api.post('/items/bulk-prices', body(true)) as Json;
                        final ex = (r['sample'] as List).cast<Json>().take(3).map((c) {
                          final parts = <String>[
                            if (c['retail_new'] != null) 'retail ${money(c['retail_old'])} → ${money(c['retail_new'])}',
                            if (c['wholesale_new'] != null) 'wholesale ${money(c['wholesale_old'])} → ${money(c['wholesale_new'])}',
                          ];
                          return '${c['name']}: ${parts.join(', ')}';
                        }).join('\n');
                        setD(() => preview = '${r['would_update']} items will change${num_(r['skipped_no_mrp']) > 0 ? ' (${r['skipped_no_mrp']} without MRP skipped)' : ''}.\n$ex');
                      } on ApiException catch (e) {
                        setD(() => preview = e.message);
                      }
                      setD(() => busy = false);
                    },
              child: const Text('Preview'),
            ),
            FilledButton(onPressed: busy ? null : () => Navigator.pop(ctx, true), child: const Text('Update prices')),
          ],
        ),
      ),
    );
    final bodyNow = body(false);
    retail.dispose();
    whole.dispose();
    if (go != true || !mounted) return;
    await guard(context, () async {
      final r = await Api.post('/items/bulk-prices', bodyNow) as Json;
      if (mounted) toast(context, 'Prices updated for ${r['updated']} items');
      await _load();
    });
  }

  Future<void> _addCategory() async {
    final v = await formDialog(context, 'New category', [const FieldSpec('name', 'Category name')]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/categories', v);
      await _load();
    });
  }

  Json? get _currentCat => catId == null ? null : cats.cast<Json?>().firstWhere((c) => c!['id'] == catId, orElse: () => null);

  Future<void> _renameCategory() async {
    final c = _currentCat;
    if (c == null) return;
    final v = await formDialog(context, 'Rename category', [FieldSpec('name', 'Category name', initial: '${c['name']}')]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.put('/categories/${c['id']}', {'name': (v['name'] ?? '').trim()});
      await _load();
    });
  }

  /// Delete: its items are kept and become Uncategorised.
  Future<void> _deleteCategory() async {
    final c = _currentCat;
    if (c == null) return;
    if (!await confirm(context, 'Delete category ${c['name']}?', 'Its items are kept and moved to Uncategorised.', ok: 'Delete', danger: true) || !mounted) return;
    await guard(context, () async {
      final r = await Api.delete('/categories/${c['id']}') as Json;
      catId = null;
      if (mounted) toast(context, '${c['name']} deleted; ${r['uncategorised']} items moved to Uncategorised.');
      await _load();
    });
  }

  Future<void> _addItem() async {
    final v = await formDialog(context, 'New item', _itemFields());
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/items', v);
      if (mounted) toast(context, 'Item added. Record a purchase (or add stock) to start selling it.');
      await _load();
    });
  }

  Future<void> _edit(Json it) async {
    final v = await formDialog(context, 'Edit · ${it['name']}', _itemFields(it));
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.put('/items/${it['id']}', v);
      await _load();
    });
  }

  Future<void> _delete(Json it) async {
    if (!await confirm(context, 'Delete ${it['name']}?', 'Items that appear on bills are archived (hidden, history kept). Unused items are removed.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await guard(context, () async {
      final r = await Api.delete('/items/${it['id']}') as Json;
      if (mounted) toast(context, r['result'] == 'archived' ? '${it['name']} archived. Old bills are unchanged.' : '${it['name']} deleted.');
      await _load();
    });
  }

  Future<void> _addStock(Json it) async {
    final v = await formDialog(context, 'Add stock · ${it['name']}', [
      const FieldSpec('qty', 'Quantity (pieces)', number: true),
      FieldSpec('purchase_price', 'Purchase price per piece (ex-GST)', number: true, initial: '${it['purchase_price']}'),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/batches', {...v, 'item_id': it['id']});
      if (mounted) toast(context, 'Added ${v['qty']} pieces of ${it['name']}');
      await _load();
    });
  }

  /// Fills the category of every item that has none, from the item name (rules first, then the internet).
  Future<void> _autoCategorise() async {
    setState(() => categorising = true);
    await guard(context, () async {
      final r = await Api.post('/items/auto-categorize', {}) as Json;
      if (mounted) toast(context, '${r['categorised']} of ${r['checked']} items categorised${num_(r['from_internet']) > 0 ? ' (${r['from_internet']} found on the internet)' : ''}.');
      await _load();
    });
    if (mounted) setState(() => categorising = false);
  }

  Future<void> _addScheme(Json it) async {
    final v = await formDialog(context, 'Scheme · ${it['name']}', [
      const FieldSpec('type', 'Scheme type', options: {'FREE_QTY': 'Buy X get Y free', 'PERCENT': 'Percent off from a minimum quantity'}),
      const FieldSpec('buy_qty', 'Buy quantity / minimum quantity (pieces)', number: true, initial: '10'),
      const FieldSpec('free_qty', 'Free pieces (for Buy X get Y)', number: true, initial: '1'),
      const FieldSpec('percent', 'Discount % (for percent scheme)', number: true, initial: '0'),
      const FieldSpec('valid_from', 'Valid from (optional)', date: true),
      const FieldSpec('valid_to', 'Valid to (optional)', date: true),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/schemes', {...v, 'item_id': it['id']});
      if (mounted) toast(context, 'Scheme saved. It applies automatically at billing.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader('Stock', actions: [
        OutlinedButton.icon(
          onPressed: categorising ? null : _autoCategorise,
          icon: categorising ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_outlined),
          label: Text(categorising ? 'Finding categories…' : 'Auto categories'),
        ),
        OutlinedButton.icon(onPressed: _bulkPrices, icon: const Icon(Icons.price_change_outlined), label: const Text('Set prices from MRP')),
        OutlinedButton.icon(onPressed: _addCategory, icon: const Icon(Icons.category_outlined), label: const Text('New category')),
        if (catId != null) ...[
          OutlinedButton.icon(onPressed: _renameCategory, icon: const Icon(Icons.edit_outlined), label: const Text('Rename category')),
          OutlinedButton.icon(onPressed: _deleteCategory, icon: const Icon(Icons.delete_outline), label: const Text('Delete category')),
        ],
        PopupMenuButton<String>(
          tooltip: 'More stock tools',
          onSelected: (v) async {
            final changed = switch (v) {
              'mrp' => await autoMrpDialog(context),
              'pack' => await autoPack(context),
              'tidy' => await tidyDialog(context),
              'online' => await onlineItemsDialog(context),
              'table' => await pricePerMrpDialog(context, categoryId: catId),
              _ => false,
            };
            if (changed) _load();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'mrp', child: Text('Auto-fill missing MRPs')),
            PopupMenuItem(value: 'pack', child: Text('Pieces per box from item names')),
            PopupMenuItem(value: 'table', child: Text('Price for each MRP…')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'tidy', child: Text('Tidy names & merge duplicates…')),
            PopupMenuItem(value: 'online', child: Text('Items from the internet…')),
          ],
          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.more_horiz), SizedBox(width: 6), Text('More')])),
        ),
        FilledButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('New item')),
      ]),
      FormWrap([
        AppField(
          width: 340,
          prefix: const Icon(Icons.search),
          hint: 'Search item name or HSN',
          onChanged: (v) {
            q = v;
            _debounce.run(_load);
          },
        ),
        AppDropdown<int>(
          width: 220,
          label: 'Category',
          value: catId ?? 0,
          options: {0: 'All categories', for (final c in cats) c['id'] as int: '${c['name']}'},
          onChanged: (v) {
            catId = (v == null || v == 0) ? null : v;
            _load();
          },
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : table(
                  ['Item', 'Category', 'HSN', 'Unit', 'Stock (pcs)', 'Box', 'MRP', 'Retail', 'Wholesale', 'Cost', 'GST', 'Your margin', 'Retailer margin', ''],
                  [
                    for (final it in items)
                      [
                        t('${it['name']}'),
                        t('${it['category'] ?? ''}'),
                        t('${it['hsn'] ?? ''}'),
                        t('${it['unit'] ?? 'PCS'}'),
                        t(_stock(it), color: num_(it['stock']) <= lowQty ? Palette.turmeric : null, bold: true),
                        t(num_(it['pcs_per_box']) > 1 ? '${it['pcs_per_box']} pcs' : '–'),
                        t(money(it['mrp'])),
                        t(money(it['retail_price'])),
                        t(money(it['wholesale_price'])),
                        t(money(it['purchase_price'])),
                        t('${it['gst_rate']}%'),
                        t('${it['dist_margin_pct']}%'),
                        t('${it['retailer_margin_pct']}%'),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(it)),
                          IconButton(tooltip: 'Add opening stock', icon: const Icon(Icons.add_box_outlined), onPressed: () => _addStock(it)),
                          IconButton(tooltip: 'Add scheme', icon: const Icon(Icons.local_offer_outlined), onPressed: () => _addScheme(it)),
                          IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline, color: Palette.brick), onPressed: () => _delete(it)),
                        ]),
                      ],
                  ],
                  numeric: {4, 6, 7, 8, 9, 10, 11, 12},
                  menu: (i) {
                    final it = items[i];
                    return [
                      RowAction('Edit item', () => _edit(it), icon: Icons.edit_outlined),
                      RowAction('Add opening stock', () => _addStock(it), icon: Icons.add_box_outlined),
                      RowAction('Set stock count…', () async {
                        if (await setStockDialog(context, it)) _load();
                      }, icon: Icons.inventory_outlined),
                      RowAction('Merge duplicates into this…', () async {
                        if (await mergeIntoDialog(context, it, items)) _load();
                      }, icon: Icons.merge_type),
                      RowAction('Add scheme', () => _addScheme(it), icon: Icons.local_offer_outlined),
                      RowAction('Delete', () => _delete(it), icon: Icons.delete_outline, danger: true),
                    ];
                  },
                ),
      ),
    ]);
  }

  /// Stock shown in pieces, with the box breakdown when the item has one.
  String _stock(Json it) {
    final s = num_(it['stock']).toInt(), b = num_(it['pcs_per_box']).toInt();
    return b > 1 && s >= b ? '$s (${s ~/ b}B+${s % b})' : '$s';
  }
}
