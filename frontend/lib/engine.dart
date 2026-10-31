import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api.dart';

/// The books engine (backend/src, the same code as the Mac app's server) runs beside the app on Linux and Windows.
/// The app ships it in its own folder:
///
///   <app folder>/engine/node            (node.exe on Windows: Node.js 22, which has SQLite built in)
///   <app folder>/engine/backend/src/server.js
///
/// It is started on a free port on 127.0.0.1 with the books in the user's own data folder, and stops by itself when
/// the app closes (it watches the app's process id). A developer copy (no engine folder, `npm start` running) is used
/// as it is.
class Engine {
  static Process? _proc;
  static String log = '';

  /// Linux: ~/.local/share/BillBox (or $XDG_DATA_HOME/BillBox). Windows: %APPDATA%\BillBox. macOS: ~/Library/Application Support/BillBox.
  static String get dataDir {
    final env = Platform.environment;
    if (Platform.isWindows) return '${env['APPDATA'] ?? env['USERPROFILE'] ?? '.'}\\BillBox';
    if (Platform.isMacOS) return '${env['HOME']}/Library/Application Support/BillBox';
    final xdg = env['XDG_DATA_HOME'];
    return '${(xdg != null && xdg.isNotEmpty) ? xdg : '${env['HOME']}/.local/share'}/BillBox';
  }

  static String get _appDir => File(Platform.resolvedExecutable).parent.path;

  static String? _find(List<String> candidates) {
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  static Future<bool> _alive(String root) async {
    try {
      final r = await http.get(Uri.parse('$root/api/companies')).timeout(const Duration(seconds: 2));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _freePort() async {
    for (final p in [37420, 37421, 37422, 37423]) {
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, p);
        await s.close();
        return p;
      } catch (_) {}
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  /// Starts the bundled engine (when there is one) and points [Api] at it. Returns an error text, or null when ready.
  static Future<String?> start() async {
    final sep = Platform.pathSeparator;
    final dir = '$_appDir${sep}engine';
    final node = _find(['$dir${sep}node.exe', '$dir${sep}node', '$dir${sep}bin${sep}node']);
    final server = _find(['$dir${sep}backend${sep}src${sep}server.js']);
    if (node == null || server == null) {
      // developer copy: the server started by hand (npm start)
      Api.root = 'http://127.0.0.1:${Platform.environment['BILLBOX_PORT'] ?? '3000'}';
      return null;
    }
    final port = await _freePort();
    Directory(dataDir).createSync(recursive: true);
    final backups = '$dataDir${sep}Backups';
    _proc = await Process.start(node, ['--no-warnings', server],
        workingDirectory: '$dir${sep}backend',
        environment: {
          'PORT': '$port',
          'DATA_DIR': '$dataDir${sep}data',
          'BILLBOX_BACKUP_DIR': backups,
          'BILLBOX_PARENT_PID': '$pid',
          // which BillBox this is (services/license.js): chosen when the app is built (desktop/build.sh)
          'BILLBOX_EDITION': const String.fromEnvironment('BILLBOX_EDITION', defaultValue: 'public'),
          'NODE_ENV': 'production',
        });
    _proc!.stdout.transform(const SystemEncoding().decoder).listen((s) => log = (log + s).substring((log.length + s.length - 8000).clamp(0, 1 << 30)));
    _proc!.stderr.transform(const SystemEncoding().decoder).listen((s) => log = (log + s).substring((log.length + s.length - 8000).clamp(0, 1 << 30)));
    var exited = false;
    unawaited(_proc!.exitCode.then((_) => exited = true));
    Api.root = 'http://127.0.0.1:$port';
    final until = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(until)) {
      if (exited) return 'The BillBox engine stopped while starting.\n\n${log.trim()}';
      if (await _alive(Api.root)) return null;
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return 'The BillBox engine did not start in time.\n\n${log.trim()}';
  }

  /// Stops the engine (it also stops by itself when the app is gone).
  static void stop() {
    _proc?.kill();
    _proc = null;
  }
}
