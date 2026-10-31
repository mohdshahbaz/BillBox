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
