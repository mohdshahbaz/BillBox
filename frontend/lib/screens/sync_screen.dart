import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Settings › Sync: live sync of a company's books between this computer, the Mac and Android phones through the
/// BillBox Firebase database (the engine does the work: backend/src/services/sync.js; AppState calls /sync/tick).
class SyncTab extends StatefulWidget {
  const SyncTab({super.key});
  @override
  State<SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<SyncTab> {
  Json s = {};
  List<Json>? remote;
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;

  bool get signedIn => s['signed_in'] == true;
  bool get on => s['on'] == true;

  @override
  void initState() {
    super.initState();
    Api.get('/sync').then((r) { if (mounted) setState(() => s = r as Json); if (signedIn) _loadRemote(); }).catchError((_) {});
  }

  Future<void> _loadRemote() async {
    try {
      final r = await Api.get('/sync/remote') as Json;
      if (mounted) setState(() => remote = (r['books'] as List).cast<Json>());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _run(String path, [Map<String, dynamic> body = const {}, String? done]) async {
    setState(() => busy = true);
    await guard(context, () async {
      final r = await Api.post(path, body) as Json;
      setState(() => s = r);
      if (path == '/sync/join' && mounted) await AppScope.read(context).reloadCompanies();
      if (path == '/sync/signin') password.clear();
      if (!mounted) return;
      final err = '${r['last_error'] ?? ''}';
      if (err.isNotEmpty) { toast(context, err, error: true); } else if (done != null) { toast(context, done); }
      if (path == '/sync/signout') { setState(() => remote = null); } else { await _loadRemote(); }
    });
    if (mounted) setState(() => busy = false);
  }

  Widget _btn(String label, IconData icon, VoidCallback? f, {bool primary = false, bool danger = false}) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18), const SizedBox(width: 8), Flexible(child: Text(label))]);
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(44)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: primary
          ? FilledButton(style: style, onPressed: busy ? null : f, child: child)
          : OutlinedButton(style: danger ? style.copyWith(foregroundColor: WidgetStateProperty.all(Palette.brick)) : style, onPressed: busy ? null : f, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).companyName;
    const muted = TextStyle(color: Palette.muted, fontSize: 12);
    return ListView(children: [
      Panel(
        title: 'Live sync',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(on ? Icons.cloud_sync : (signedIn ? Icons.cloud_outlined : Icons.cloud_off), color: on ? Colors.green : Palette.muted, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(!signedIn ? 'Not signed in' : on ? '$name is synced live' : 'Signed in as ${s['email']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                if (signedIn) Text(on ? 'Changes made on any device show on the others within a few seconds.' : 'Turn on sync for $name to share it with your other devices.', style: muted),
                if ('${s['last_sync'] ?? ''}'.isNotEmpty) Text('Last sync: ${s['last_sync']}${num_(s['pending']) > 0 ? ' · ${s['pending']} changes waiting' : ''}', style: muted),
                if ('${s['last_error'] ?? ''}'.isNotEmpty) Text('${s['last_error']}', style: const TextStyle(color: Palette.brick, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 14),
            if (!signedIn) ...[
              AppField(controller: email, label: 'E-mail'),
              const SizedBox(height: 8),
              AppField(controller: password, label: 'Password (6 or more characters)', obscure: true),
              const SizedBox(height: 10),
              _btn('Sign in', Icons.login, () => _run('/sync/signin', {'email': email.text.trim(), 'password': password.text, 'create': false}, 'Signed in to sync.'), primary: true),
              _btn('Create a sync account', Icons.person_add_alt, () => _run('/sync/signin', {'email': email.text.trim(), 'password': password.text, 'create': true},
                  'Sync account made. Now turn on sync for a company, or bring one here from your other device.')),
            ] else ...[
              if (on) ...[
                _btn('Sync now', Icons.sync, () => _run('/sync/now'), primary: true),
                _btn('Stop syncing $name on this computer', Icons.cloud_off, () => _run('/sync/off'), danger: true),
              ] else
                _btn('Turn on sync for $name', Icons.cloud_upload_outlined, () => _run('/sync/on', {}, '$name is synced now.'), primary: true),
              _btn('Sign out of sync', Icons.logout, () => _run('/sync/signout')),
            ],
            const Text('Every device keeps its own copy of the books and works without internet; changes go across when it is online. Sign in with the same account on each device. '
                'Stock sold on two devices at once counts both sales; two bills made at the same moment keep different numbers.', style: muted),
          ]),
        ),
      ),
      if (signedIn)
        Panel(
          title: 'Companies in your sync account',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final b in remote ?? <Json>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${b['name']}'),
                  subtitle: b['fy'] == null ? null : Text('Year ${b['fy']}'),
                  trailing: b['on_this_device'] == true
                      ? const Text('On this computer', style: muted)
                      : TextButton(onPressed: busy ? null : () => _run('/sync/join', {'key': b['key']}, 'The company is on this computer now. Switch to it from the company menu.'), child: const Text('Bring here')),
                ),
              if (remote != null && remote!.isEmpty) const Text('No company is synced in this account yet.', style: muted),
              const SizedBox(height: 8),
              _btn(remote == null ? 'Show the companies in this account' : 'Look again', Icons.list, _loadRemote),
            ]),
          ),
        ),
      Panel(
        title: 'One-time Firebase setup',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('1. Firebase console › Authentication › Sign-in method › turn on Email/Password.\n2. Realtime Database › Rules › paste these rules and Publish:'),
          const SizedBox(height: 8),
          SelectableText('${s['rules'] ?? ''}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: '${s['rules'] ?? ''}')); toast(context, 'Rules copied.'); }, icon: const Icon(Icons.copy, size: 16), label: const Text('Copy rules'))),
        ]),
      ),
    ]);
  }
}
