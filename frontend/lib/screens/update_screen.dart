import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Settings › Updates: the newest BillBox release of this edition (engine GET /update, services/update.js), downloaded
/// and installed from here. Windows: its setup runs and BillBox opens again; Linux: the .deb is installed (pkexec asks
/// for the password) or opened in the software installer.
class UpdateTab extends StatefulWidget {
  const UpdateTab({super.key});
  static const version = String.fromEnvironment('BILLBOX_VERSION', defaultValue: '');
  static const edition = String.fromEnvironment('BILLBOX_EDITION', defaultValue: 'public');
  static String get platform => Platform.isWindows ? 'windows' : 'linux';

  static Future<Json> check() async =>
      await Api.get('/update', {'version': version, 'edition': edition, 'platform': platform}) as Json;

  @override
  State<UpdateTab> createState() => _UpdateTabState();
}

class _UpdateTabState extends State<UpdateTab> {
  Json? u;
  String? error;
  bool busy = false;
  double? progress;
  String? done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { u = null; error = null; });
    try {
      final r = await UpdateTab.check();
      if (mounted) setState(() => u = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<File> _download(String url, String name) async {
    final dir = await Directory.systemTemp.createTemp('billbox-update-');
    final out = File('${dir.path}${Platform.pathSeparator}$name');
    final res = await http.Client().send(http.Request('GET', Uri.parse(url))..headers['user-agent'] = 'BillBox');
    if (res.statusCode != 200) throw Exception('The download answered ${res.statusCode}.');
    final total = res.contentLength ?? 0;
    var got = 0;
    final sink = out.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0 && mounted) setState(() => progress = got / total);
    }
    await sink.close();
    return out;
  }

  Future<void> _install(Json u) async {
    final f = (u['file'] as Map?)?.cast<String, dynamic>();
    if (f == null || '${f['url'] ?? ''}'.isEmpty) {
      await launchUrl(Uri.parse('${u['page']}'));
      return;
    }
    setState(() { busy = true; progress = 0; error = null; });
    try {
      final file = await _download('${f['url']}', '${f['name']}');
      final exe = Platform.resolvedExecutable;
      if (Platform.isWindows) {
        // the setup replaces this BillBox, then BillBox opens again; this one closes so its files can be replaced
        await Process.start('cmd', ['/c', 'start', '/wait', '', file.path, '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '&', 'start', '', exe],
            mode: ProcessStartMode.detached);
        exit(0);
      } else {
        final r = await Process.run('pkexec', ['apt-get', 'install', '-y', file.path]).catchError((_) => ProcessResult(0, 127, '', 'no pkexec'));
        if (r.exitCode == 0) {
          setState(() => done = '/opt/billbox/billbox');   // where the .deb puts BillBox
        } else {
          // no password prompt here (or it was cancelled): the system's software installer takes the .deb
          await Process.start('xdg-open', [file.path], mode: ProcessStartMode.detached);
          setState(() => error = 'The software installer opened with the new version: install it there, then open BillBox again.');
        }
      }
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() { busy = false; progress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Palette.muted, fontSize: 12);
    final x = u;
    return ListView(children: [
      Panel(
        title: 'Updates',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('This computer has BillBox ${UpdateTab.version.isEmpty ? '(development build)' : UpdateTab.version}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (error != null) Text(error!, style: TextStyle(color: Palette.brick)),
            if (done != null) ...[
              const Text('The new version is installed.', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async { await Process.start(done!, [], mode: ProcessStartMode.detached); exit(0); },
                icon: const Icon(Icons.restart_alt), label: const Text('Open the new BillBox')),
            ] else if (x == null && error == null)
              const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 10), Text('Looking for a new version…')])
            else if (x != null && x['available'] == true) ...[
              Text('BillBox ${x['latest']} is available', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if ('${x['notes'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${x['notes']}'.length > 600 ? '${x['notes']}'.substring(0, 600) : '${x['notes']}', style: muted)),
              const SizedBox(height: 10),
              if (progress != null) LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : () => _install(x),
                icon: const Icon(Icons.system_update_alt),
                label: Text(busy ? 'Downloading…' : 'Download and install ${x['latest']}')),
              const SizedBox(height: 6),
              Text(Platform.isWindows ? 'BillBox closes, the setup puts in the new version and BillBox opens again. Your books stay as they are.'
                  : 'Linux asks for your password to install the new version. Your books stay as they are.', style: muted),
            ] else if (x != null)
              Text('${x['latest'] ?? ''}'.isEmpty ? 'No release found.' : 'BillBox is up to date (newest: ${x['latest']}).', style: muted),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: busy ? null : _load, icon: const Icon(Icons.refresh), label: const Text('Look again'))),
          ]),
        ),
      ),
    ]);
  }
}
