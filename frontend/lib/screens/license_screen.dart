import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';

/// Settings › Licence: the trial or the licence of this computer, Buy (on the website) and the licence key
/// (the rules are in the engine: backend/src/services/license.js).
class LicenseTab extends StatefulWidget {
  const LicenseTab({super.key});
  @override
  State<LicenseTab> createState() => _LicenseTabState();
}

class _LicenseTabState extends State<LicenseTab> {
  Json s = {};
  final keyCtl = TextEditingController();
  bool busy = false;

  String get state => '${s['state'] ?? ''}';
  int _i(String k) => num_(s[k]).toInt();

  @override
  void initState() {
    super.initState();
    Api.get('/license').then((r) { if (mounted) setState(() => s = r as Json); }).catchError((_) {});
  }

  Future<void> _run(String path, Map<String, dynamic> body) async {
    setState(() => busy = true);
    await guard(context, () async {
      final r = await Api.post(path, body) as Json;
      setState(() { s = r; if (state == 'licensed') keyCtl.clear(); });
      if (!mounted) return;
      final err = '${r['renew_error'] ?? ''}';
      toast(context, err.isNotEmpty ? err : (state == 'licensed' ? 'Licence checked: BillBox is licensed on this computer.' : 'Done.'), error: err.isNotEmpty);
    });
    if (mounted) setState(() => busy = false);
  }

  Widget _btn(String label, IconData icon, VoidCallback? f, {bool primary = false, bool danger = false}) {
    final child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)]);
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
    final headline = switch (state) {
      'licensed' => s['plan'] == 'lifetime' ? 'Licensed for life' : 'Licensed',
      'trial' => 'Free trial: ${_i('trial_days_left')} day${_i('trial_days_left') == 1 ? '' : 's'} left',
      'expired' => 'The trial has ended',
      _ => 'No licence needed',
    };
    final detail = switch (state) {
      'licensed' => s['expires'] == null ? 'Everything in BillBox, on this computer, with no end date.' : 'Everything in BillBox until ${dmy(s['expires'])}.',
      'trial' => 'Everything works during the ${_i('trial_days')}-day trial. After it, your books stay safe and can be seen, printed and backed up; adding or changing anything needs a licence.',
      'expired' => '${'${s['reason'] ?? ''}'.isEmpty ? '' : '${s['reason']}. '}Your books are safe: they can still be seen, printed, exported and backed up. Buy a licence or enter your key to add and change things again.',
      _ => 'This copy of BillBox is not limited.',
    };
    return ListView(children: [
      Panel(
        title: 'Licence',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(state == 'expired' ? Icons.lock : (state == 'trial' ? Icons.hourglass_bottom : Icons.verified), color: state == 'expired' ? Palette.brick : Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(detail, style: const TextStyle(color: Palette.muted, fontSize: 12)),
              ])),
            ]),
            if (s['edition'] == 'admin') const Padding(padding: EdgeInsets.only(top: 8), child: Text('Admin (test) edition: test licence keys and Razorpay test payments only.', style: TextStyle(color: Colors.orange, fontSize: 12))),
            const SizedBox(height: 14),
            if (state.isNotEmpty && state != 'unlimited') ...[
              if (state != 'licensed') ...[
                _btn('Buy a licence…', Icons.shopping_cart_outlined, () => launchUrl(Uri.parse('${s['buy_url']}')), primary: true),
                const Text('Yearly ₹1,499 · Lifetime ₹3,999 (India: UPI, cards, net banking). The licence key arrives on the page after paying; enter it below.', style: TextStyle(color: Palette.muted, fontSize: 12)),
                const SizedBox(height: 12),
                AppField(controller: keyCtl, label: 'Licence key (BB1.…)'),
                const SizedBox(height: 8),
                _btn('Use this licence key', Icons.key, () => _run('/license/activate', {'key': keyCtl.text.trim()}), primary: true),
              ] else ...[
                Text('Plan: ${s['plan'] == 'lifetime' ? 'Lifetime' : 'Yearly'} · valid till ${s['expires'] == null ? 'no end' : dmy(s['expires'])}${'${s['email'] ?? ''}'.isEmpty ? '' : ' · ${s['email']}'} · checked online by ${dmy(s['renew_by'])}'),
                const SizedBox(height: 10),
                _btn('Check the licence now', Icons.refresh, () => _run('/license/renew', {})),
                _btn('Remove the licence from this computer', Icons.remove_circle_outline, () => _run('/license/deactivate', {}), danger: true),
              ],
              Text('Device ${s['device']}. One licence works on 2 devices (Mac, Windows, Linux, iPhone or Android). BillBox checks it online every few weeks and keeps working offline in between. To move it, remove it here first.',
                  style: const TextStyle(color: Palette.muted, fontSize: 12)),
              if (s['edition'] == 'admin') ...[
                const SizedBox(height: 12),
                _btn('Start the trial again (testing)', Icons.restart_alt, () => _run('/license/reset-trial', {}), danger: true),
              ],
            ],
          ]),
        ),
      ),
    ]);
  }
}
