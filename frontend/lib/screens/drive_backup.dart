import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Asks Replace or Merge, then restores a backup (by name in the backup folder, a folder anywhere, or one company file).
Future<bool> restoreBackup(BuildContext context, {String? name, String? folder, String? file, int? companyId, required String label}) async {
  final mode = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Restore $label?'),
      content: const SizedBox(
        width: 460,
        child: Text('Replace: each company in the backup replaces the company with the same name (a safety backup of today is made first).\n\n'
            'Merge: only the records missing here are added; nothing here is changed.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        OutlinedButton(onPressed: () => Navigator.pop(c, 'merge'), child: const Text('Merge')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Palette.brick), onPressed: () => Navigator.pop(c, 'replace'), child: const Text('Replace')),
      ],
    ),
  );
  if (mode == null || !context.mounted) return false;
  var done = false;
  await guard(context, () async {
    final r = await Api.post('/backup/restore', {
      if (name != null) 'name': name,
      if (folder != null) 'folder': folder,
      if (file != null) 'file': file,
      if (companyId != null) 'company_id': companyId,
      'mode': mode,
    }) as Json;
    final restored = ((r['restored'] as List?) ?? []).join(', ');
    if (context.mounted) {
      toast(context, mode == 'merge' ? 'Merged into $restored.' : 'Restored: $restored.');
      await AppScope.read(context).reloadCompanies();
    }
    done = true;
  });
  return done;
}

/// Settings › Backup › Google Drive: each backup also goes into "BillBox Backups" in the user's Google Drive, and any
/// backup there can be brought back. Sign-in is Google's code sign-in (a short code entered at google.com/device).
class DrivePanel extends StatefulWidget {
  final VoidCallback? onRestored;
  const DrivePanel({super.key, this.onRestored});
  @override
  State<DrivePanel> createState() => _DrivePanelState();
}

class _DrivePanelState extends State<DrivePanel> {
  Json status = {};
  final idCtl = TextEditingController(), secretCtl = TextEditingController();
  bool editing = false, busy = false;
  String code = '', link = 'https://www.google.com/device';
  Timer? _poll;

  bool get connected => status['connected'] == true;
  bool get hasKeys => '${status['client_id'] ?? ''}'.isNotEmpty && status['has_secret'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await Api.get('/backup/drive') as Json;
      if (mounted) setState(() => status = s);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    await guard(context, f);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(dialogTitle: 'The client_secret_….json downloaded from Google Cloud', type: FileType.custom, allowedExtensions: ['json']);
    final path = r?.files.single.path;
    if (path == null) return;
    await _run(() async {
      final s = await Api.put('/backup/drive/client', {'json': await File(path).readAsString()}) as Json;
      setState(() { status = s; editing = false; });
      if (mounted) toast(context, 'Google keys imported. Now press Connect Google Drive.');
    });
    await _load();
  }

  Future<void> _saveKeys() => _run(() async {
        final s = await Api.put('/backup/drive/client', {'client_id': idCtl.text.trim(), 'client_secret': secretCtl.text.trim()}) as Json;
        setState(() { status = s; editing = false; secretCtl.clear(); });
        if (mounted) toast(context, 'Google keys saved. Now press Connect Google Drive.');
      });

  Future<void> _connect() => _run(() async {
        final r = await Api.post('/backup/drive/connect', {}) as Json;
        final every = (num_(r['interval']).toInt()).clamp(5, 60);
        final until = DateTime.now().add(Duration(seconds: num_(r['expires_in']).toInt().clamp(60, 3600)));
        setState(() { code = '${r['user_code']}'; link = '${r['verification_url'] ?? link}'; });
        _poll?.cancel();
        _poll = Timer.periodic(Duration(seconds: every), (t) async {
          if (DateTime.now().isAfter(until)) {
            t.cancel();
            if (mounted) { setState(() => code = ''); toast(context, 'The code ran out. Press Connect Google Drive again.', error: true); }
            return;
          }
          try {
            final p = await Api.post('/backup/drive/poll', {}) as Json;
            if (p['connected'] == true) {
              t.cancel();
              if (mounted) { setState(() => code = ''); toast(context, 'Google Drive connected. Backups now also go to Drive › BillBox Backups.'); }
              await _load();
            }
          } on ApiException catch (e) {
            if (e.code == 'OFFLINE') return;
            t.cancel();
            if (mounted) { setState(() => code = ''); toast(context, e.message, error: true); }
            await _load();
          }
        });
      });

  Future<void> _upload() => _run(() async {
        final r = await Api.post('/backup/drive/upload', {}) as Json;
        if (mounted) toast(context, 'Uploaded ${r['folder']} to Google Drive (${r['files']} files).');
        await _load();
      });

  Future<void> _disconnect() => _run(() async {
        final s = await Api.post('/backup/drive/disconnect', {}) as Json;
        setState(() => status = s);
        if (mounted) toast(context, 'Google Drive disconnected. Backups stay on this computer; the copies already in Drive are not touched.');
      });

  Future<void> _restoreFromDrive() async {
    List<Json> list = [];
    setState(() => busy = true);
    await guard(context, () async => list = ((await Api.get('/backup/drive/list')) as List).cast<Json>());
    if (!mounted) return;
    setState(() => busy = false);
    final picked = await showDialog<Json>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore from Google Drive'),
        content: SizedBox(
          width: 480,
          height: 380,
          child: list.isEmpty
              ? const Text('No backups in Google Drive › BillBox Backups yet.')
              : ListView(children: [
                  for (final b in list)
                    ListTile(
                      leading: Icon(b['on_device'] == true ? Icons.check_circle_outline : Icons.cloud_download_outlined, color: Theme.of(c).colorScheme.primary),
                      title: Text('${b['name']}', style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(b['on_device'] == true ? 'Also on this computer' : 'Only in Google Drive'),
                      onTap: () => Navigator.pop(c, b),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
      ),
    );
    if (picked == null || !mounted) return;
    String? name;
    await _run(() async {
      final r = await Api.post('/backup/drive/download', {'id': picked['id'], 'name': picked['name']}) as Json;
      name = '${r['name']}';
      if (num_(r['downloaded']) > 0 && mounted) toast(context, 'Brought $name from Google Drive (${r['downloaded']} files).');
    });
    if (name != null && mounted) {
      widget.onRestored?.call();
      await restoreBackup(context, name: name, label: name!);
      widget.onRestored?.call();
    }
  }

  /// One button style for the whole section: full width, same height.
  Widget _btn(String label, IconData icon, VoidCallback? onPressed, {bool primary = false, bool danger = false}) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)]);
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(44)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: primary
          ? FilledButton(style: style, onPressed: busy ? null : onPressed, child: child)
          : OutlinedButton(
              style: danger ? style.copyWith(foregroundColor: WidgetStateProperty.all(Palette.brick)) : style,
              onPressed: busy ? null : onPressed,
              child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = '${status['last_upload'] ?? ''}', lastStatus = '${status['last_status'] ?? ''}';
    return Panel(
      title: 'Google Drive',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(connected ? Icons.cloud_done : Icons.cloud_off_outlined, color: connected ? Palette.leaf : Palette.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(connected ? 'Connected: backups also go to Google Drive › BillBox Backups' : (code.isEmpty ? 'Not connected' : 'Waiting for Google…'),
                style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (connected && last.isNotEmpty) Text('Last upload: $last · ${lastStatus == 'ok' ? 'done' : lastStatus}', style: const TextStyle(color: Palette.muted, fontSize: 12)),
          const SizedBox(height: 12),
          if (code.isNotEmpty) ...[
            const Text('1. Open google.com/device on any phone or computer.\n2. Enter this code and allow BillBox:'),
            const SizedBox(height: 8),
            SelectableText(code, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            _btn('Copy code', Icons.copy, () { Clipboard.setData(ClipboardData(text: code)); toast(context, 'Code copied. Open $link'); }, primary: true),
            _btn('Cancel', Icons.close, () { _poll?.cancel(); setState(() => code = ''); }),
          ] else if (connected) ...[
            _btn('Upload the newest backup now', Icons.cloud_upload_outlined, _upload, primary: true),
            _btn('Restore from Google Drive…', Icons.cloud_download_outlined, _restoreFromDrive),
            _btn('Disconnect Google Drive', Icons.link_off, _disconnect, danger: true),
          ] else if (hasKeys && !editing) ...[
            _btn('Connect Google Drive', Icons.add_link, _connect, primary: true),
            Text('Client ID: ${'${status['client_id']}'.split('.apps.googleusercontent.com').first}', style: const TextStyle(color: Palette.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            _btn('Change Google keys…', Icons.key, () => setState(() { editing = true; idCtl.text = '${status['client_id']}'; })),
          ] else ...[
            _btn('Import the downloaded JSON file…', Icons.upload_file, _import, primary: true),
            const Text('or paste the two keys:', style: TextStyle(color: Palette.muted, fontSize: 12)),
            const SizedBox(height: 6),
            AppField(controller: idCtl, label: 'Client ID (…apps.googleusercontent.com)'),
            const SizedBox(height: 8),
            AppField(controller: secretCtl, label: 'Client secret', obscure: true),
            const SizedBox(height: 8),
            _btn('Save keys', Icons.check_circle_outline, _saveKeys),
            if (hasKeys) _btn('Cancel', Icons.close, () => setState(() => editing = false)),
          ],
          const SizedBox(height: 4),
          Text(
            connected
                ? 'Every backup (Backup now and the daily backup) is also uploaded to your Google Drive, into a folder with the backup\'s name inside BillBox Backups. BillBox can see only the files it made itself in your Drive.'
                : 'One-time setup (about 5 minutes, free): in console.cloud.google.com make a project, turn on the Google Drive API, set up the consent screen (External; add your Gmail as a test user), then Credentials › Create credentials › OAuth client ID › type “TVs and Limited Input devices”. Download its JSON and import it here, then Connect. The same keys work on the Mac, iPhone, Android, Windows and Linux.',
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
