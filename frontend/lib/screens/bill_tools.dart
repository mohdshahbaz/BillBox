import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../print/invoice_pdf.dart';
import '../state/app_state.dart';
import '../widgets.dart';

// ---------------------------------------------------------------- WhatsApp

/// The customer's WhatsApp number as wa.me wants it (country code + number, digits only), or null.
/// Same rules as the Mac (WhatsApp.swift): phone first, then each mobile; 00 dropped; a leading 0 on an 11-digit number
/// dropped; a 10-digit number gets the country code; 11–15 digits accepted.
String? waNumber(Json inv, String cc) {
  final candidates = ['${inv['party_phone'] ?? ''}', ...'${inv['party_mobiles'] ?? ''}'.split(RegExp(r'[,;/]'))];
  for (final c in candidates) {
    var d = c.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) d = d.substring(1);
    if (d.length == 10) d = '$cc$d';
    if (d.length >= 11 && d.length <= 15) return d;
  }
  return null;
}

const kWaTemplate = 'Hello {name}, thank you for your purchase. Your bill {invoice} for {total} is attached. - {company}';

/// Opens the customer's WhatsApp chat with the bill message, after saving the bill PDF for attaching. The desktop app
/// cannot press Send by itself as the Mac does, so the person attaches the saved PDF and sends.
Future<void> shareOnWhatsApp(BuildContext context, int invoiceId) async {
  final app = AppScope.read(context);
  await guard(context, () async {
    final inv = await Api.get('/invoices/$invoiceId') as Json;
    final cc = '${app.settings['wa_cc'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    final to = waNumber(inv, cc.isEmpty ? '91' : cc);
    if (to == null) {
      if (context.mounted) toast(context, '${'${inv['party_name'] ?? ''}'.isEmpty ? 'The customer' : inv['party_name']} has no mobile number on file.', error: true);
      return;
    }
    final tpl = '${app.settings['wa_message'] ?? ''}'.trim().isEmpty ? kWaTemplate : '${app.settings['wa_message']}';
    final text = tpl
        .replaceAll('{name}', '${inv['party_name'] ?? ''}')
        .replaceAll('{invoice}', '${inv['invoice_no']}')
        .replaceAll('{total}', money(inv['total']))
        .replaceAll('{company}', app.companyName);
    // one Original copy, as the Mac attaches
    final Uint8List pdf = await buildInvoicePdf(inv, app.settings, PrintLayout.single);
    if (!context.mounted) return;
    final name = '${'${inv['invoice_no']}'.replaceAll('/', '-')}.pdf';
    final saved = await saveBytes(context, name, pdf);
    if (saved == null) return;
    final ok = await launchUrl(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    toast(context, ok ? 'WhatsApp is opening the chat. Attach $name (saved at $saved) and press Send.' : 'Could not open WhatsApp. The bill is saved at $saved.', error: !ok);
  });
}

// ---------------------------------------------------------------- e-way bill

/// E-way bill JSON for the GST portal's bulk upload (one bill), and the number the portal gave back.
/// Same engine routes and checks as the Mac's E-way bill sheet (backend/src/services/ewayBill.js).
Future<void> showEwayBill(BuildContext context, int invoiceId) async {
  Json? e;
  await guard(context, () async => e = await Api.get('/invoices/$invoiceId/ewaybill') as Json);
  if (e == null || !context.mounted) return;
  await showDialog(context: context, builder: (_) => _EwayDialog(id: invoiceId, data: e!));
}

class _EwayDialog extends StatefulWidget {
  final int id;
  final Json data;
  const _EwayDialog({required this.id, required this.data});
  @override
  State<_EwayDialog> createState() => _EwayDialogState();
}

class _EwayDialogState extends State<_EwayDialog> {
  late final Map<String, TextEditingController> c;
  int mode = 1;
  bool odc = false;
  String? problem, saved;
  List<String> warnings = [];
  bool busy = false;
  String docDate = '', ewbDate = '', ewbValid = '';

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    String v(String k) => '${d[k] ?? ''}';
    c = {
      for (final k in ['from_pincode', 'to_pincode', 'vehicle_no', 'transporter_id', 'transporter_name', 'trans_doc_no', 'ewb_no']) k: TextEditingController(text: v(k)),
      'distance': TextEditingController(text: d['distance'] == null ? '' : v('distance')),
    };
    mode = (num_(d['mode']).toInt()).clamp(1, 4);
    odc = d['vehicle_type'] == 'O';
    docDate = v('trans_doc_date');
    ewbDate = v('ewb_date').isEmpty ? todayStr() : v('ewb_date');
    ewbValid = v('ewb_valid');
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _make() async {
    setState(() {
      busy = true;
      problem = null;
      saved = null;
    });
    try {
      final road = mode == 1;
      final r = await Api.post('/invoices/${widget.id}/ewaybill', {
        'from_pincode': c['from_pincode']!.text.trim(),
        'to_pincode': c['to_pincode']!.text.trim(),
        'distance': c['distance']!.text.trim(),
        'mode': mode,
        'vehicle_no': road ? c['vehicle_no']!.text.trim() : '',
        'vehicle_type': odc ? 'O' : 'R',
        'transporter_id': c['transporter_id']!.text.trim(),
        'transporter_name': c['transporter_name']!.text.trim(),
        'trans_doc_no': road ? '' : c['trans_doc_no']!.text.trim(),
        'trans_doc_date': road ? '' : docDate,
      }) as Json;
      warnings = ((r['warnings'] as List?) ?? []).cast<String>();
      final json = const JsonEncoder.withIndent('  ').convert(r['ewaybill']);
      if (!mounted) return;
      final path = await saveBytes(context, '${r['file_name']}', Uint8List.fromList(utf8.encode(json)));
      if (path != null) saved = 'Saved $path. Upload it on ewaybillgst.gov.in › e-Waybill › Bulk Generation.';
    } on ApiException catch (e) {
      problem = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _saveNumber() async {
    await guard(context, () async {
      final r = await Api.put('/invoices/${widget.id}/ewaybill', {'ewb_no': c['ewb_no']!.text.trim(), 'ewb_date': ewbDate, 'ewb_valid': ewbValid}) as Json;
      if (!mounted) return;
      toast(context, r['ewb_no'] == null ? 'E-way bill number cleared.' : 'E-way bill ${r['ewb_no']} saved on the bill.');
      Navigator.pop(context);
    });
  }

  Widget _date(String label, String v, ValueChanged<String> set) => OutlinedButton.icon(
        onPressed: () async {
          final d = await pickDate(context, v.isEmpty ? todayStr() : v);
          if (d != null) setState(() => set(d));
        },
        icon: const Icon(Icons.event, size: 16),
        label: Text('$label ${v.isEmpty ? '–' : dmy(v)}'),
      );

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final size = MediaQuery.sizeOf(context);
    final road = mode == 1;
    return AlertDialog(
      title: Text('E-way bill · ${d['invoice_no']}'),
      content: SizedBox(
        width: math.min(640.0, size.width - 80),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${d['party'] ?? 'Cash customer'}  ·  ${money(d['total'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (d['needed'] != true) Text('Under ₹50,000: an e-way bill is usually not needed.', style: TextStyle(color: Palette.turmeric)),
            if ('${d['ewb_no'] ?? ''}'.isNotEmpty) Text('E-way bill ${d['ewb_no']}${'${d['ewb_valid'] ?? ''}'.isEmpty ? '' : ' · valid until ${dmy(d['ewb_valid'])}'}', style: TextStyle(color: Palette.leaf)),
            const SizedBox(height: 12),
            Text('1. Transport', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppField(width: 130, label: 'Your PIN', number: true, controller: c['from_pincode']),
              AppField(width: 130, label: "Party's PIN", number: true, controller: c['to_pincode']),
              AppField(width: 180, label: 'Distance km', hint: '0 = portal works it out', number: true, controller: c['distance']),
              AppDropdown<int>(width: 130, label: 'Mode', value: mode, options: const {1: 'Road', 2: 'Rail', 3: 'Air', 4: 'Ship'}, onChanged: (v) => setState(() => mode = v ?? 1)),
              if (road) ...[
                AppField(width: 180, label: 'Vehicle number', controller: c['vehicle_no']),
                FilterChip(label: const Text('Over-dimensional cargo'), selected: odc, onSelected: (v) => setState(() => odc = v)),
              ] else ...[
                AppField(width: 220, label: 'RR / airway bill / B/L no.', controller: c['trans_doc_no']),
                _date('Document date', docDate, (v) => docDate = v),
              ],
              AppField(width: 220, label: 'Transporter name (optional)', controller: c['transporter_name']),
              AppField(width: 220, label: 'Transporter ID / GSTIN (optional)', controller: c['transporter_id']),
            ]),
            const SizedBox(height: 14),
            Text('2. The file for the portal', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: busy ? null : _make, icon: const Icon(Icons.file_download_outlined), label: const Text('Make the e-way bill file')),
            for (final w in warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text(w, style: TextStyle(color: Palette.turmeric))),
            if (problem != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(problem!, style: TextStyle(color: Palette.brick))),
            if (saved != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(saved!, style: TextStyle(color: Palette.leaf))),
            const SizedBox(height: 14),
            Text('3. The number the portal gave', style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AppField(width: 180, label: 'E-way bill number (12 digits)', number: true, controller: c['ewb_no']),
              _date('Date', ewbDate, (v) => ewbDate = v),
              _date('Valid until', ewbValid, (v) => ewbValid = v),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _saveNumber, child: const Text('Save the number')),
      ],
    );
  }
}
