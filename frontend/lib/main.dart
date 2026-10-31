import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/billing_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/parties_screen.dart';
import 'screens/purchase_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/salesmen_screen.dart';
import 'screens/settings_screen.dart';
import 'engine.dart';
import 'state/app_state.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engineError = await Engine.start();
  final state = AppState();
  if (engineError != null) {
    state
      ..error = engineError
      ..ready = true;
  } else {
    state.init();
  }
  AppLifecycleListener(onExitRequested: () async { Engine.stop(); return AppExitResponse.exit; });
  runApp(AppScope(state: state, child: const DistributorApp()));
}

class DistributorApp extends StatelessWidget {
  const DistributorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BillBox',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Gate(),
      );
}

/// Waits for the company list, then shows the shell. Shows a clear message if the backend is not running.
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (app.error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Palette.brick),
            const SizedBox(height: 12),
            Text(app.error!, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 14),
            FilledButton(onPressed: app.init, child: const Text('Try again')),
          ]),
        ),
      );
    }
    return const Shell();
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 1; // open on Billing
  // One billing screen per company: switching company never carries a half-made bill into the other books.
  final _billingKeys = <int?, GlobalKey<BillingScreenState>>{};
  GlobalKey<BillingScreenState> _bk(int? id) => _billingKeys.putIfAbsent(id, () => GlobalKey<BillingScreenState>());

  static const _nav = [
    (Icons.space_dashboard_outlined, 'Dashboard'),
    (Icons.point_of_sale, 'Billing'),
    (Icons.local_shipping_outlined, 'Purchases'),
    (Icons.receipt_long_outlined, 'All bills'),
    (Icons.inventory_2_outlined, 'Stock'),
    (Icons.storefront_outlined, 'Parties'),
    (Icons.route_outlined, 'Salesmen'),
    (Icons.menu_book_outlined, 'Books & GST'),
    (Icons.settings_outlined, 'Settings'),
  ];

  /// An Edit button elsewhere asked to open a saved bill: switch to its screen.
  void _routeEdit(AppState app) {
    final e = app.pendingEdit;
    if (e == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (e['type'] == 'INVOICE') {
        final id = app.takeEdit('INVOICE');
        setState(() => _i = 1);
        if (id != null) _bk(app.companyId).currentState?.loadForEdit(id);
      } else if (e['type'] == 'PURCHASE') {
        setState(() => _i = 2); // the purchase screen picks the request up when it opens
      }
    });
  }

  void _go(int i) {
    setState(() => _i = i);
    if (i == 1) {
      final key = _bk(AppScope.read(context).companyId);
      WidgetsBinding.instance.addPostFrameCallback((_) => key.currentState
        ?..reload()
        ..focusBarcode());
    }
  }

  Widget _page(int i) => switch (i) {
        0 => const DashboardScreen(),
        2 => const PurchaseScreen(),
        3 => const BillsScreen(),
        4 => const InventoryScreen(),
        5 => const PartiesScreen(),
        6 => const SalesmenScreen(),
        7 => const ReportsScreen(),
        8 => const SettingsScreen(),
        _ => const SizedBox.shrink(),
      };

  Widget _sidebar(AppState app, bool compact) => Container(
        width: compact ? 68 : 214,
        color: Palette.ink,
        child: Column(children: [
          const SizedBox(height: 14),
          PopupMenuButton<int>(
            tooltip: 'Switch company',
            offset: const Offset(0, 48),
            onSelected: (id) => guard(context, () => app.switchCompany(id)),
            itemBuilder: (_) => [
              for (final c in app.companies) PopupMenuItem(value: c['id'] as int, child: Text('${c['name']}', style: TextStyle(fontWeight: c['id'] == app.companyId ? FontWeight.w700 : FontWeight.w400))),
            ],
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
              child: compact
                  ? const Center(child: Icon(Icons.business, color: Colors.white70, size: 20))
                  : Row(children: [
                      const Icon(Icons.business, color: Colors.white70, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(app.companyName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      const Icon(Icons.unfold_more, color: Colors.white54, size: 18),
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(children: [
              for (var n = 0; n < _nav.length; n++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                  child: Tooltip(
                    message: compact ? _nav[n].$2 : '',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => _go(n),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: 10),
                        decoration: BoxDecoration(color: _i == n ? Palette.teal : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                        child: compact
                            ? Center(child: Icon(_nav[n].$1, size: 20, color: _i == n ? Colors.white : Colors.white60))
                            : Row(children: [
                                Icon(_nav[n].$1, size: 19, color: _i == n ? Colors.white : Colors.white60),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_nav[n].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _i == n ? Colors.white : Colors.white70, fontWeight: _i == n ? FontWeight.w600 : FontWeight.w400))),
                                if (n < 9) Text('⌘${n + 1}', style: const TextStyle(color: Colors.white24, fontSize: 11)),
                              ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    _routeEdit(app);
    final digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {for (var n = 0; n < _nav.length; n++) SingleActivator(digits[n], meta: true): () => _go(n)},
        child: Scaffold(
          body: Row(children: [
            _sidebar(app, MediaQuery.sizeOf(context).width < kNarrow),
            Expanded(
              // A new key per company: every screen (and the half-made bill) is rebuilt from the new company's data.
              child: KeyedSubtree(
                key: ValueKey(app.companyId),
                child: Stack(fit: StackFit.expand, children: [
                  Offstage(offstage: _i != 1, child: BillingScreen(key: _bk(app.companyId))),
                  if (_i != 1) Positioned.fill(child: Padding(padding: EdgeInsets.all(isNarrow(context) ? 14 : 24), child: _page(_i))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
