import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';

typedef Json = Map<String, dynamic>;

const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class SalesmenScreen extends StatefulWidget {
  const SalesmenScreen({super.key});
  @override
  State<SalesmenScreen> createState() => _SalesmenState();
}

class _SalesmenState extends State<SalesmenScreen> {
  List<Json> sms = [];
  int? sel;
  Json? perf, beat;
  int day = DateTime.now().weekday % 7; // Dart: Mon=1..Sun=7 -> 0=Sunday like the API

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = ((await Api.get('/salesmen')) as List).cast<Json>();
        if (!mounted) return;
        setState(() {
          sms = r;
          sel ??= r.isEmpty ? null : r.first['id'] as int;
        });
        await _loadSelected();
      });

  Future<void> _loadSelected() async {
    if (sel == null) return;
    await guard(context, () async {
      final r = await Future.wait([Api.get('/salesmen/$sel/performance'), Api.get('/salesmen/$sel/beat', {'day': day})]);
      if (mounted) {
        setState(() {
          perf = r[0];
          beat = r[1];
        });
      }
    });
  }

  Future<void> _addSalesman() async {
    final v = await formDialog(context, 'New salesman / MR', [
      const FieldSpec('name', 'Name'),
      const FieldSpec('phone', 'Phone'),
      const FieldSpec('monthly_target', 'Monthly sales target (₹)', number: true, initial: '0'),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/salesmen', v);
      await _load();
    });
  }

  Json? get _selected => sms.cast<Json?>().firstWhere((s) => s!['id'] == sel, orElse: () => null);

  Future<void> _editSalesman(Json s) async {
    final v = await formDialog(context, 'Edit ${s['name']}', [
      FieldSpec('name', 'Name', initial: '${s['name'] ?? ''}'),
      FieldSpec('phone', 'Phone', initial: '${s['phone'] ?? ''}'),
      FieldSpec('monthly_target', 'Monthly sales target (₹)', number: true, initial: '${s['monthly_target'] ?? 0}'),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.put('/salesmen/${s['id']}', {...v, 'active': true});
      await _load();
    });
  }

  /// Moves every bill, receipt and route of [s] to another salesman, then removes [s] (as on the Mac).
  Future<void> _mergeSalesman(Json s) async {
    final others = {for (final o in sms.where((o) => o['id'] != s['id'])) o['id'] as int: '${o['name']}'};
    if (others.isEmpty) return;
    final into = await pickFromList<int>(context, title: 'Merge ${s['name']} into…', options: others);
    if (into == null || !mounted) return;
    if (!await confirm(context, 'Merge ${s['name']} into ${others[into]}?', "All of ${s['name']}'s bills, receipts and routes move to ${others[into]}, and ${s['name']} is removed.", ok: 'Merge')) return;
    if (!mounted) return;
    await guard(context, () async {
      final r = await Api.post('/salesmen/${s['id']}/merge', {'into': into}) as Json;
      final m = (r['moved'] as Json?) ?? {};
      if (mounted) toast(context, 'Merged: ${m['invoices'] ?? 0} bills, ${m['receipts'] ?? 0} receipts and ${m['routes'] ?? 0} routes moved.');
      sel = into;
      await _load();
    });
  }

  Future<void> _deleteSalesman(Json s) async {
    if (!await confirm(context, 'Delete ${s['name']}?', 'Their routes are left without a salesman. Bills and receipts keep the name. To move their bills to someone else, use Merge instead.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    await guard(context, () async {
      await Api.delete('/salesmen/${s['id']}');
      if (sel == s['id']) {
        sel = null;
        perf = null;
        beat = null;
      }
      await _load();
    });
  }

  /// New route, or edit one: name, salesman, visit days. Returns true when saved.
  Future<bool> _routeForm([Json? existing]) async {
    final name = TextEditingController(text: existing == null ? '' : '${existing['name'] ?? ''}');
    String salesman = existing == null ? (sms.isEmpty ? '' : '${sms.first['id']}') : (existing['salesman_id'] == null ? '' : '${existing['salesman_id']}');
    final daysText = existing == null ? '1' : '${existing['days'] ?? existing['day_of_week'] ?? ''}';
    final days = daysText.split(',').map((x) => int.tryParse(x.trim())).whereType<int>().where((d) => d >= 0 && d <= 6).toSet();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
            title: Text(existing == null ? 'New route (beat)' : 'Edit route'),
            content: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Route name', hintText: 'places, comma separated: Qazipara, Mandi, Mandawar Road')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: salesman,
                  decoration: const InputDecoration(labelText: 'Salesman'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Not assigned')),
                    for (final s in sms) DropdownMenuItem(value: '${s['id']}', child: Text('${s['name']}')),
                  ],
                  onChanged: (v) => salesman = v ?? '',
                ),
                const SizedBox(height: 12),
                const Text('Visit days'),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (var i = 0; i < 7; i++)
                    FilterChip(
                      label: Text(_days[i]),
                      selected: days.contains(i),
                      onSelected: (on) => setSt(() {
                        if (on) {
                          days.add(i);
                        } else {
                          days.remove(i);
                        }
                      }),
                    ),
                ]),
                if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: Palette.brick))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) return setSt(() => err = 'Route name is required');
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          )),
    );
    if (ok != true || !mounted) return false;
    final body = {'name': name.text.trim(), 'salesman_id': salesman, 'days': (days.toList()..sort()).join(',')};
    var saved = false;
    await guard(context, () async {
      if (existing == null) {
        await Api.post('/routes', body);
        if (mounted) toast(context, 'Route created. Assign parties to it from the Parties screen.');
      } else {
        await Api.put('/routes/${existing['id']}', body);
        if (mounted) toast(context, 'Route saved.');
      }
      saved = true;
      await _loadSelected();
    });
    return saved;
  }

  Future<void> _addRoute() async {
    await _routeForm();
  }

  /// Every route with its salesman, visit days and outlets: Edit and Delete.
  Future<void> _routes() => guard(context, () async {
        var list = ((await Api.get('/routes')) as List).cast<Json>();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
            Future<void> reload() async {
              final r = ((await Api.get('/routes')) as List).cast<Json>();
              setSt(() => list = r);
            }

            String detail(Json r) {
              final ds = '${r['days'] ?? r['day_of_week'] ?? ''}'.split(',').map((x) => int.tryParse(x.trim())).whereType<int>().where((d) => d >= 0 && d <= 6).map((d) => _days[d]).join(', ');
              final n = num_(r['outlets']).toInt();
              return '${'${r['salesman_name'] ?? ''}'.isEmpty ? 'no salesman' : r['salesman_name']} · ${ds.isEmpty ? 'no visit day' : ds} · $n outlet${n == 1 ? '' : 's'}';
            }

            return AlertDialog(
              title: const Text('Routes'),
              content: SizedBox(
                width: 560,
                child: list.isEmpty
                    ? const Text('No routes yet. Add one with New route.')
                    : ListView(shrinkWrap: true, children: [
                        for (final r in list)
                          ListTile(
                            title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(detail(r)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () async {
                                  if (await _routeForm(r)) await reload();
                                },
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(Icons.delete_outline, color: Palette.brick),
                                onPressed: () async {
                                  if (!await confirm(context, 'Delete ${r['name']}?', 'Its outlets stay: those on other routes too keep them, the others are left without a route.', ok: 'Delete', danger: true)) return;
                                  if (!mounted) return;
                                  await guard(context, () async {
                                    await Api.delete('/routes/${r['id']}');
                                    await reload();
                                    await _loadSelected();
                                  });
                                },
                              ),
                            ]),
                          ),
                      ]),
              ),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
            );
          }),
        );
      });

  @override
  Widget build(BuildContext context) {
    final p = perf;
    final outlets = (beat?['outlets'] as List?)?.cast<Json>() ?? const <Json>[];
    final ach = p == null ? null : p['achievement_pct'];
    final dayInfo = p?['day'] as Json?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader('Salesmen and routes', actions: [
        OutlinedButton.icon(onPressed: _routes, icon: const Icon(Icons.list_alt), label: const Text('Routes')),
        OutlinedButton.icon(onPressed: sms.isEmpty ? null : _addRoute, icon: const Icon(Icons.route), label: const Text('New route')),
        PopupMenuButton<String>(
          tooltip: 'Salesman',
          enabled: _selected != null,
          onSelected: (v) {
            final s = _selected;
            if (s == null) return;
            if (v == 'edit') _editSalesman(s);
            if (v == 'merge') _mergeSalesman(s);
            if (v == 'delete') _deleteSalesman(s);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit salesman…')),
            PopupMenuItem(value: 'merge', enabled: sms.length > 1, child: const Text('Merge into another…')),
            PopupMenuItem(value: 'delete', child: Text('Delete salesman…', style: TextStyle(color: Palette.brick))),
          ],
          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_horiz)),
        ),
        FilledButton.icon(onPressed: _addSalesman, icon: const Icon(Icons.person_add_alt), label: const Text('New salesman')),
      ]),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 240,
            child: ListView(children: [
              for (final s in sms)
                GestureDetector(
                  onSecondaryTapDown: (d) async {
                    final v = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(d.globalPosition.dx, d.globalPosition.dy, d.globalPosition.dx, d.globalPosition.dy), items: [
                      const PopupMenuItem(value: 'edit', child: Text('Edit…')),
                      PopupMenuItem(value: 'merge', enabled: sms.length > 1, child: const Text('Merge into another…')),
                      PopupMenuItem(value: 'delete', child: Text('Delete…', style: TextStyle(color: Palette.brick))),
                    ]);
                    if (v == 'edit') _editSalesman(s);
                    if (v == 'merge') _mergeSalesman(s);
                    if (v == 'delete') _deleteSalesman(s);
                  },
                  child: ListTile(
                  selected: s['id'] == sel,
                  selectedTileColor: Palette.teal.withValues(alpha: .1),
                  title: Text(s['name']),
                  subtitle: Text(s['phone'] ?? ''),
                  onTap: () {
                    setState(() => sel = s['id'] as int);
                    _loadSelected();
                  },
                ),
                ),
            ]),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: p == null
                ? const Text('Add a salesman to start tracking targets, beats and collections.')
                : ListView(children: [
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      Stat('Target for ${p['month']}', money(p['target'])),
                      Stat('Sales (${p['invoices']} bills)', money(p['sales'])),
                      Stat('Achievement', ach == null ? 'No target set' : '$ach%', color: ach != null && ach >= 100 ? Palette.leaf : Palette.turmeric),
                      Stat('Collections this month', money(p['collections']), color: Palette.leaf),
                    ]),
                    if (ach != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: 888, child: LinearProgressIndicator(value: (num_(ach) / 100).clamp(0, 1).toDouble(), minHeight: 8, color: Palette.teal)),
                    ],
                    const SizedBox(height: 24),
                    Text('Today', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    if (dayInfo != null)
                      Text('${dayInfo['bills']} bills · ${money(dayInfo['sales'])} sold · ${money(dayInfo['credit_given'])} given on credit · collected: '
                          '${(dayInfo['collected_by_mode'] as List).isEmpty ? 'nothing yet' : (dayInfo['collected_by_mode'] as List).map((m) => '${m['mode']} ${money(m['amount'])}').join(', ')}'),
                    const SizedBox(height: 24),
                    Row(children: [
                      Text('Beat plan', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 16),
                      Wrap(spacing: 6, children: [
                        for (var i = 0; i < 7; i++)
                          ChoiceChip(
                            label: Text(_days[i]),
                            selected: day == i,
                            onSelected: (_) {
                              setState(() => day = i);
                              _loadSelected();
                            },
                          ),
                      ]),
                    ]),
                    const SizedBox(height: 8),
                    outlets.isEmpty
                        ? Text('No outlets on ${_days[day]}. Create a route for this day and assign parties to it.')
                        : table(['Outlet', 'Route', 'Last order', 'Outstanding to collect'], [
                            for (final o in outlets)
                              [Text(o['name']), Text(o['route_name']), Text(o['last_order'] ?? 'Never'), t(money(o['outstanding']), bold: true, color: num_(o['outstanding']) > 0 ? Palette.turmeric : null)],
                          ], numeric: {3}),
                    if (outlets.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('To collect on this beat: ${money(beat!['total_outstanding'])}')),
                  ]),
          ),
        ]),
      ),
    ]);
  }
}
