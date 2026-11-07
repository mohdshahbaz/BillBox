import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';

typedef Json = Map<String, dynamic>;

/// App-wide state: which company is open, its profile/settings, and print preferences.
/// Screens read it through AppScope.of(context) and rebuild when the company changes.
class AppState extends ChangeNotifier {
  List<Json> companies = [];
  int? companyId;
  Json settings = {};
  bool ready = false;
  String? error;

  /// Set by "Edit" buttons (All bills): the shell opens the right screen, which then loads that bill for editing.
  Json? pendingEdit;
  void requestEdit(String type, int id) {
    pendingEdit = {'type': type, 'id': id};
    notifyListeners();
  }

  /// Returns the waiting edit request of this type (and clears it), or null.
  int? takeEdit(String type) {
    final e = pendingEdit;
    if (e == null || e['type'] != type) return null;
    pendingEdit = null;
    return e['id'] as int;
  }

  Json? get company => companies.cast<Json?>().firstWhere((c) => c!['id'] == companyId, orElse: () => null);
  String get companyName => (company?['name'] ?? 'BillBox') as String;

  Future<void> init() async {
    try {
      await reloadCompanies(pick: true);
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    }
    ready = true;
    notifyListeners();
    _startSync();
  }

  /// Bumped when changes from other devices arrive (live sync): the list screens rebuild and read the books again.
  int dataVersion = 0;
  Timer? _sync;
  int _syncVersion = -1;
  bool _syncBusy = false;
  /// Settings › Sync: every 3 s the engine swaps changes with the other devices (GET /sync/tick).
  void _startSync() {
    _sync ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_syncBusy) return;
      _syncBusy = true;
      try {
        final r = await Api.get('/sync/tick') as Json;
        if (r['on'] == true) {
          final v = (r['version'] as num?)?.toInt() ?? 0;
          if (_syncVersion >= 0 && v != _syncVersion) {
            await loadSettings();
            dataVersion++;
            notifyListeners();
          }
          _syncVersion = v;
        }
      } catch (_) {
        // the engine is busy or offline: the next tick tries again
      } finally {
        _syncBusy = false;
      }
    });
  }

  Future<void> reloadCompanies({bool pick = false}) async {
    final r = await Api.get('/companies') as Json;
    companies = (r['companies'] as List).cast<Json>();
    if (pick || companyId == null || company == null) {
      final last = r['last_used'] as int?;
      companyId = companies.any((c) => c['id'] == last) ? last : companies.first['id'] as int;
    }
    Api.companyId = companyId;
    await loadSettings();
    notifyListeners();
  }

  Future<void> loadSettings() async {
    settings = (await Api.get('/settings') as Json);
  }

  Future<void> switchCompany(int id) async {
    if (id == companyId) return;
    companyId = id;
    Api.companyId = id;
    await Api.post('/companies/$id/activate', {});
    await loadSettings();
    notifyListeners(); // every screen is rebuilt under a new key, so nothing from the old company lingers
  }

  Future<void> saveSettings(Json changes) async {
    settings = (await Api.put('/settings', changes) as Json);
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => (c.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
