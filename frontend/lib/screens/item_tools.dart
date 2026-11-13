import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

// Stock tools from the Mac (StockView / ItemToolsView): set the stock count, merge items, tidy names and merge duplicates,
// fill missing MRPs, pack sizes from names, items from the internet, and prices for each MRP. Each returns true when
// something changed, so the Stock list reloads.

Size _dlg(BuildContext c, double w, double h) {
  final s = MediaQuery.sizeOf(c);
  return Size(math.min(w, s.width - 80), math.min(h, s.height - 200));
}

/// Stock count after a physical count: the difference is booked as an adjustment batch.
Future<bool> setStockDialog(BuildContext context, Json it) async {
  final v = await formDialog(context, 'Set stock of ${it['name']}', [
    FieldSpec('qty', 'Pieces in stock now (was ${num_(it['stock']).toInt()})', number: true, initial: '${num_(it['stock']).toInt()}'),
  ]);
  if (v == null || !context.mounted) return false;
  final q = int.tryParse('${v['qty']}'.replaceAll(',', '').trim());
  if (q == null) {
    toast(context, 'Enter a whole number of pieces', error: true);
    return false;
  }
  var ok = false;
  await guard(context, () async {
    await Api.post('/items/${it['id']}/set-stock', {'qty': q});
    ok = true;
    if (context.mounted) toast(context, 'Stock of ${it['name']} set to $q pcs.');
  });
  return ok;
}

/// Merge other items into [keep]: their bills, purchases, batches and schemes move to it and they are removed.
Future<bool> mergeIntoDialog(BuildContext context, Json keep, List<Json> items) async {
  final picked = <int>{};
  var q = '';
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final size = _dlg(ctx, 560, 560);
      final shown = items.where((i) => i['id'] != keep['id'] && (q.isEmpty || '${i['name']}'.toLowerCase().contains(q.toLowerCase()))).toList();
      return AlertDialog(
        title: Text('Merge into ${keep['name']}'),
        content: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Tick the duplicates. Their bills, purchases, batches and schemes move to ${keep['name']}, and they are removed.', style: TextStyle(color: Palette.muted)),
            const SizedBox(height: 8),
            AppField(prefix: const Icon(Icons.search), hint: 'Search items', onChanged: (v) => setS(() => q = v.trim())),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(children: [
                for (final i in shown)
                  CheckboxListTile(
                    dense: true,
                    value: picked.contains(i['id']),
                    onChanged: (v) => setS(() => v == true ? picked.add(i['id'] as int) : picked.remove(i['id'])),
                    title: Text('${i['name']}'),
                    subtitle: Text('MRP ${money(i['mrp'])} · ${num_(i['pcs_per_box']).toInt()} per box · stock ${num_(i['stock']).toInt()}'),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text('Merge ${picked.length} into it')),
        ],
      );
    }),
  );
  if (go != true || !context.mounted) return false;
  var ok = false;
  await guard(context, () async {
    final r = await Api.post('/items/merge', {'keep_id': keep['id'], 'merge_ids': picked.toList()}) as Json;
    ok = true;
    if (context.mounted) toast(context, 'Merged ${(r['merged'] as List).length} item(s) into ${r['name']}.');
  });
  return ok;
}

/// Looks up missing MRPs (from item names and the internet) and shows what was found per category.
Future<bool> autoMrpDialog(BuildContext context) async {
  Json? r;
  await guard(context, () async => r = await Api.post('/items/auto-mrp', {}) as Json);
  final x = r;
  if (x == null || !context.mounted) return false;
  final by = ((x['by_category'] as Json?) ?? {}).entries.toList();
  final missing = ((x['missing'] as List?) ?? []).cast<Json>();
  await showDialog(
    context: context,
    builder: (ctx) {
      final size = _dlg(ctx, 620, 560);
      return AlertDialog(
        title: const Text('Missing MRPs'),
        content: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Checked ${x['checked']} items without an MRP: found ${x['found']}, still missing ${x['still_missing']}.'),
            const SizedBox(height: 10),
            if (by.isNotEmpty)
              table(['Category', 'MRP found', 'Still missing'], [
                for (final e in by)
                  [
                    t(e.key),
                    t('${(e.value as Json)['found']}'),
                    t('${(e.value as Json)['missing']}', color: num_((e.value as Json)['missing']) > 0 ? Palette.turmeric : null),
                  ],
              ], numeric: {1, 2}),
            const SizedBox(height: 10),
            if (missing.isNotEmpty) Text('Still without an MRP', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
            Expanded(child: ListView(children: [for (final m in missing) Text('· ${m['name']}${'${m['category'] ?? ''}'.isEmpty ? '' : '  (${m['category']})'}')])),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      );
    },
  );
  return num_(x['found']) > 0;
}

/// Pieces per box read from item names ("… 12x100g", "Box of 24").
Future<bool> autoPack(BuildContext context) async {
  var ok = false;
  await guard(context, () async {
    final r = await Api.post('/items/auto-pack', {}) as Json;
    ok = num_(r['changed']) > 0;
    if (context.mounted) toast(context, '${r['changed']} of ${r['checked']} items with a pack size in the name were updated.');
  });
  return ok;
}

// ---------------------------------------------------------------- tidy names and merge duplicates

Future<bool> tidyDialog(BuildContext context) async => (await showDialog<bool>(context: context, builder: (_) => const _Tidy())) == true;

class _Tidy extends StatefulWidget {
  const _Tidy();
  @override
  State<_Tidy> createState() => _TidyState();
}

class _TidyState extends State<_Tidy> {
  String match = 'similar', kase = 'keep';
  Json? d;
  bool busy = false, changed = false;
  final keep = <int, int>{}; // group index -> id to keep
  final leaveOut = <int>{}; // item ids not merged
  final renameOff = <int>{}; // item ids not renamed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => busy = true);
    await guard(context, () async {
      d = await Api.get('/items/clean-preview', {'case': kase, 'match': match}) as Json;
      keep.clear();
      leaveOut.clear();
      renameOff.clear();
    });
    if (mounted) setState(() => busy = false);
  }

  List<Json> get _groups => ((d?['groups'] as List?) ?? []).cast<Json>();
  List<Json> _members(Json g) => [g['keep'] as Json, ...((g['merge'] as List?) ?? []).cast<Json>()];
  int _keepId(int gi) => keep[gi] ?? (_groups[gi]['keep'] as Json)['id'] as int;

  Future<void> _merge(int gi) async {
    final k = _keepId(gi);
    final ids = [for (final m in _members(_groups[gi])) if (m['id'] != k && !leaveOut.contains(m['id'])) m['id'] as int];
    if (ids.isEmpty) return;
    await guard(context, () async {
      await Api.post('/items/merge', {'keep_id': k, 'merge_ids': ids});
      changed = true;
      await _load();
    });
  }

  Future<void> _mergeAll() async {
    for (var gi = _groups.length - 1; gi >= 0; gi--) {
      final k = _keepId(gi);
      final ids = [for (final m in _members(_groups[gi])) if (m['id'] != k && !leaveOut.contains(m['id'])) m['id'] as int];
      if (ids.isEmpty) continue;
      try {
        await Api.post('/items/merge', {'keep_id': k, 'merge_ids': ids});
        changed = true;
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message, error: true);
        break;
      }
    }
    await _load();
  }

  Future<void> _rename() async {
    final rs = ((d?['renames'] as List?) ?? []).cast<Json>();
    final ids = [for (final r in rs) if (!renameOff.contains(r['id'])) r['id'] as int];
    if (ids.isEmpty) return;
    await guard(context, () async {
      final r = await Api.post('/items/clean-names', {'case': kase, 'ids': ids}) as Json;
      changed = true;
      if (mounted) toast(context, 'Renamed ${r['renamed']} items.');
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = _dlg(context, 880, 640);
    final renames = ((d?['renames'] as List?) ?? []).cast<Json>();
    return AlertDialog(
      title: const Text('Tidy names and merge duplicates'),
      content: SizedBox(
        width: size.width,
        height: size.height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'exact', label: Text('Same name')), ButtonSegment(value: 'similar', label: Text('Similar')), ButtonSegment(value: 'loose', label: Text('Loose'))],
              selected: {match},
              onSelectionChanged: (s) {
                match = s.first;
                _load();
              },
            ),
            AppDropdown<String>(width: 220, label: 'Names', value: kase, options: const {'keep': 'Keep as typed', 'title': 'Title Case', 'upper': 'UPPER CASE'}, onChanged: (v) {
              kase = v ?? kase;
              _load();
            }),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: d == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    Row(children: [
                      Expanded(child: Text('${_groups.length} groups of duplicates in ${d!['items']} items', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink))),
                      if (_groups.isNotEmpty) FilledButton(onPressed: busy ? null : _mergeAll, child: Text('Merge all ${_groups.length} groups')),
                    ]),
                    for (var gi = 0; gi < _groups.length; gi++)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Panel(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Wrap(spacing: 8, children: [
                              StatusPill(_groups[gi]['match'] == 'same' ? 'Same name' : 'Similar (${(num_(_groups[gi]['score']) * 100).round()}% words alike)'),
                              for (final w in ((_groups[gi]['warnings'] as List?) ?? []).cast<String>()) StatusPill(w, tint: Palette.turmeric),
                            ]),
                            for (final m in _members(_groups[gi]))
                              Row(children: [
                                Checkbox(
                                  value: m['id'] == _keepId(gi) || !leaveOut.contains(m['id']),
                                  onChanged: m['id'] == _keepId(gi) ? null : (v) => setState(() => v == true ? leaveOut.remove(m['id']) : leaveOut.add(m['id'] as int)),
                                ),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${m['name']}', style: TextStyle(fontWeight: m['id'] == _keepId(gi) ? FontWeight.w700 : FontWeight.w400)),
                                    Text('MRP ${money(m['mrp'])} · ${num_(m['pcs_per_box']).toInt()} per box · ${m['used']} bill lines · ${num_(m['stock']).toInt()} pcs',
                                        style: TextStyle(fontSize: 12, color: Palette.muted)),
                                  ]),
                                ),
                                m['id'] == _keepId(gi) ? StatusPill('Kept', tint: Palette.leaf) : TextButton(onPressed: () => setState(() => keep[gi] = m['id'] as int), child: const Text('Keep this')),
                              ]),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(onPressed: busy ? null : () => _merge(gi), child: const Text('Merge into the kept item')),
                            ),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Text('${renames.length} names to tidy', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink))),
                      if (renames.isNotEmpty) FilledButton(onPressed: busy ? null : _rename, child: Text('Rename ${renames.length - renames.where((r) => renameOff.contains(r['id'])).length} items')),
                    ]),
                    for (final r in renames)
                      CheckboxListTile(
                        dense: true,
                        value: !renameOff.contains(r['id']),
                        onChanged: (v) => setState(() => v == true ? renameOff.remove(r['id']) : renameOff.add(r['id'] as int)),
                        title: Text('${r['clean']}'),
                        subtitle: Text('was ${r['name']}'),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context, changed), child: const Text('Done'))],
    );
  }
}

// ---------------------------------------------------------------- items from the internet

Future<bool> onlineItemsDialog(BuildContext context) async => (await showDialog<bool>(context: context, builder: (_) => const _Online())) == true;

class _Found {
  bool on;
  final TextEditingController name, mrp;
  final String? exists;
  _Found(Json x)
      : on = x['exists_id'] == null,
        name = TextEditingController(text: '${x['name']}'),
        mrp = TextEditingController(text: x['mrp'] == null ? '' : '${x['mrp']}'),
        exists = x['exists_name'] as String?;
}

class _Online extends StatefulWidget {
  const _Online();
  @override
  State<_Online> createState() => _OnlineState();
}

class _OnlineState extends State<_Online> {
  final company = TextEditingController(), category = TextEditingController(), url = TextEditingController(), pasted = TextEditingController(), gst = TextEditingController(text: '18');
  String kase = 'title';
  List<Json> results = [];
  List<_Found> found = [];
  String? problem, note;
  bool busy = false;

  @override
  void dispose() {
    for (final c in [company, category, url, pasted, gst]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  void _take(Json r) {
    found = [for (final x in ((r['items'] as List?) ?? []).cast<Json>()) _Found(x)];
    note = 'Found ${r['found'] ?? found.length} items (${r['new'] ?? found.where((f) => f.exists == null).length} new).';
  }

  Future<void> _search() => _run(() async {
        final r = await Api.post('/items/online/search', {'company': company.text.trim(), 'category': category.text.trim()}) as Json;
        results = ((r['results'] as List?) ?? []).cast<Json>();
        if (results.isEmpty) note = 'Nothing found. Try another spelling, or paste the list below.';
      });

  Future<void> _fetch(String u) => _run(() async => _take(await Api.post('/items/online/fetch', {'url': u, 'company': company.text.trim(), 'case': kase}) as Json));

  Future<void> _extract() => _run(() async => _take(await Api.post('/items/online/extract', {'text': pasted.text, 'company': company.text.trim(), 'case': kase}) as Json));

  Future<void> _add() => _run(() async {
        final chosen = found.where((f) => f.on && f.name.text.trim().isNotEmpty).toList();
        final r = await Api.post('/items/bulk-add', {
          'items': [for (final f in chosen) {'name': f.name.text.trim(), if (num_(f.mrp.text) > 0) 'mrp': num_(f.mrp.text)}],
          if (category.text.trim().isNotEmpty) 'category': category.text.trim(),
          'gst_rate': num_(gst.text),
        }) as Json;
        if (!mounted) return;
        toast(context, 'Added ${(r['added'] as List).length} items${(r['skipped'] as List).isEmpty ? '' : ', skipped ${(r['skipped'] as List).length}'}.');
        Navigator.pop(context, true);
      });

  @override
  Widget build(BuildContext context) {
    final size = _dlg(context, 900, 660);
    final n = found.where((f) => f.on).length;
    return AlertDialog(
      title: const Text('Items from the internet'),
      content: SizedBox(
        width: size.width,
        height: size.height,
        child: ListView(children: [
          Text("Find a company's price list online, or paste one. The items it lists can be added with their MRP.", style: TextStyle(color: Palette.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppField(width: 240, label: 'Company (brand)', controller: company),
            AppField(width: 200, label: 'Category (optional)', controller: category),
            FilledButton(onPressed: busy ? null : _search, child: const Text('Search online')),
            AppDropdown<String>(width: 170, label: 'Names', value: kase, options: const {'title': 'Title Case', 'upper': 'UPPER CASE', 'keep': 'As written'}, onChanged: (v) => kase = v ?? kase),
          ]),
          for (final r in results)
            ListTile(
              dense: true,
              leading: Icon(r['pdf'] == true ? Icons.picture_as_pdf_outlined : Icons.public, size: 18),
              title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${r['url']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: busy ? null : () => _fetch('${r['url']}'),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppField(width: 420, label: 'Or a page / PDF address', controller: url),
            OutlinedButton(onPressed: busy ? null : () => _fetch(url.text.trim()), child: const Text('Read this page')),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: TextField(controller: pasted, maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top, decoration: const InputDecoration(hintText: 'Or paste a price list here (one item per line)', constraints: BoxConstraints())),
          ),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton(onPressed: busy ? null : _extract, child: const Text('Read the pasted list'))),
          if (busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(problem!, style: TextStyle(color: Palette.brick))),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!)),
          for (final f in found)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Checkbox(value: f.on, onChanged: (v) => setState(() => f.on = v ?? false)),
                Expanded(child: AppField(label: 'Name', controller: f.name)),
                const SizedBox(width: 8),
                AppField(width: 110, label: 'MRP', number: true, controller: f.mrp),
                if (f.exists != null) Padding(padding: const EdgeInsets.only(left: 8), child: StatusPill('Already: ${f.exists}', tint: Palette.turmeric)),
              ]),
            ),
          if (found.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppField(width: 200, label: 'Put them in category', controller: category),
              AppField(width: 100, label: 'GST %', number: true, controller: gst),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
        FilledButton(onPressed: busy || n == 0 ? null : _add, child: Text('Add $n items')),
      ],
    );
  }
}

// ---------------------------------------------------------------- price for each MRP

/// Retail and wholesale price for each MRP (box or piece, GST included or not), with a preview of every item it changes.
Future<bool> pricePerMrpDialog(BuildContext context, {int? categoryId}) async =>
    (await showDialog<bool>(context: context, builder: (_) => _PriceTable(categoryId: categoryId))) == true;

class _PriceTable extends StatefulWidget {
  final int? categoryId;
  const _PriceTable({this.categoryId});
  @override
  State<_PriceTable> createState() => _PriceTableState();
}

class _PriceTableState extends State<_PriceTable> {
  List<Json> groups = [];
  final retail = <num, TextEditingController>{}, wholesale = <num, TextEditingController>{};
  String per = 'box';
  bool gstIncl = true, busy = true;
  Json? preview;
  String? problem;
  final _debounce = Debouncer(const Duration(milliseconds: 300));

  @override
  void initState() {
    super.initState();
    guard(context, () async {
      groups = (await Api.get('/items/mrp-table', {if (widget.categoryId != null) 'category_id': widget.categoryId}) as List).cast<Json>();
      for (final g in groups) {
        retail[num_(g['mrp'])] = TextEditingController();
        wholesale[num_(g['mrp'])] = TextEditingController();
      }
    }).whenComplete(() {
      if (mounted) setState(() => busy = false);
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    for (final c in [...retail.values, ...wholesale.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Json> get _tiers => [
        for (final g in groups)
          if (retail[num_(g['mrp'])]!.text.trim().isNotEmpty || wholesale[num_(g['mrp'])]!.text.trim().isNotEmpty)
            {
              'mrp': g['mrp'],
              if (retail[num_(g['mrp'])]!.text.trim().isNotEmpty) 'retail': num_(retail[num_(g['mrp'])]!.text),
              if (wholesale[num_(g['mrp'])]!.text.trim().isNotEmpty) 'wholesale': num_(wholesale[num_(g['mrp'])]!.text),
            },
      ];

  Json _body(bool preview) => {
        'mode': 'table',
        'tiers': _tiers,
        'per': per,
        'include_gst': gstIncl,
        if (widget.categoryId != null) 'category_id': widget.categoryId,
        'preview': preview,
      };

  void _changed() => _debounce.run(() async {
        if (_tiers.isEmpty) {
          if (mounted) setState(() => preview = null);
          return;
        }
        try {
          final r = await Api.post('/items/set-prices', _body(true)) as Json;
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
      });

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final r = await Api.post('/items/set-prices', _body(false)) as Json;
      if (!mounted) return;
      toast(context, 'Updated the prices of ${r['updated']} items.');
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

  @override
  Widget build(BuildContext context) {
    final size = _dlg(context, 900, 660);
    final items = ((preview?['items'] as List?) ?? []).cast<Json>();
    final n = num_(preview?['would_update']).toInt();
    String now(Json g, String k) => money(g['${k}_$per']);
    return AlertDialog(
      title: const Text('Price for each MRP'),
      content: SizedBox(
        width: size.width,
        height: size.height,
        child: busy && groups.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(children: [
                Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [ButtonSegment(value: 'box', label: Text('Price per box')), ButtonSegment(value: 'piece', label: Text('Price per piece'))],
                    selected: {per},
                    onSelectionChanged: (s) {
                      setState(() => per = s.first);
                      _changed();
                    },
                  ),
                  FilterChip(
                    label: const Text('Prices include GST'),
                    selected: gstIncl,
                    onSelected: (v) {
                      setState(() => gstIncl = v);
                      _changed();
                    },
                  ),
                ]),
                const SizedBox(height: 8),
                Text('Type the new price next to an MRP; leave it blank to keep that MRP as it is. Today\'s highest price is shown in grey.', style: TextStyle(color: Palette.muted)),
                const SizedBox(height: 8),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      SizedBox(
                        width: 220,
                        child: Text('MRP ${money(g['mrp'])}  ·  ${g['items']} items${((g['boxes'] as List?) ?? []).isEmpty ? '' : '  ·  box ${(g['boxes'] as List).join('/')}'}'),
                      ),
                      AppField(width: 160, label: 'Retail', hint: now(g, 'retail'), number: true, controller: retail[num_(g['mrp'])], onChanged: (_) => _changed()),
                      const SizedBox(width: 8),
                      AppField(width: 160, label: 'Wholesale', hint: now(g, 'wholesale'), number: true, controller: wholesale[num_(g['mrp'])], onChanged: (_) => _changed()),
                    ]),
                  ),
                if (problem != null) Text(problem!, style: TextStyle(color: Palette.brick)),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('$n items change', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 260,
                    child: table(['Item', 'MRP', 'Retail (bill)', 'Wholesale (bill)'], [
                      for (final it in items.take(150))
                        [
                          t('${it['name']}'),
                          t(money(it['mrp'])),
                          t(it['retail_bill'] == null ? '–' : '${money(it['retail_old_bill'])} → ${money(it['retail_bill'])}'),
                          t(it['wholesale_bill'] == null ? '–' : '${money(it['wholesale_old_bill'])} → ${money(it['wholesale_bill'])}'),
                        ],
                    ], numeric: {1, 2, 3}),
                  ),
                ],
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy || n == 0 ? null : _save, child: Text('Update $n items')),
      ],
    );
  }
}
