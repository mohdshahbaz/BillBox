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

  Future<void> _addRoute() async {
    final v = await formDialog(context, 'New route (beat)', [
      const FieldSpec('name', 'Route name'),
      FieldSpec('salesman_id', 'Salesman', options: {for (final s in sms) '${s['id']}': '${s['name']}'}),
      FieldSpec('day_of_week', 'Visit day', options: {for (var i = 0; i < 7; i++) '$i': _days[i]}),
    ]);
    if (v == null || !mounted) return;
    await guard(context, () async {
      await Api.post('/routes', v);
      if (mounted) toast(context, 'Route created. Assign parties to it from the Parties screen.');
      await _loadSelected();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = perf;
    final outlets = (beat?['outlets'] as List?)?.cast<Json>() ?? const <Json>[];
    final ach = p == null ? null : p['achievement_pct'];
    final dayInfo = p?['day'] as Json?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader('Salesmen and routes', actions: [
        OutlinedButton.icon(onPressed: sms.isEmpty ? null : _addRoute, icon: const Icon(Icons.route), label: const Text('New route')),
        FilledButton.icon(onPressed: _addSalesman, icon: const Icon(Icons.person_add_alt), label: const Text('New salesman')),
      ]),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 240,
            child: ListView(children: [
              for (final s in sms)
                ListTile(
                  selected: s['id'] == sel,
                  selectedTileColor: Palette.teal.withOpacity(.1),
                  title: Text(s['name']),
                  subtitle: Text(s['phone'] ?? ''),
                  onTap: () {
                    setState(() => sel = s['id'] as int);
                    _loadSelected();
                  },
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
