import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import '../api.dart';
import '../state/app_state.dart';
import '../widgets.dart';
import 'invoice_pdf.dart';
import 'voucher_pdf.dart';
import 'print_jobs.dart';

/// Print an invoice. Honours the "print straight away" setting; otherwise opens the in-app print manager.
Future<void> printInvoice(BuildContext context, int invoiceId, {bool forcePreview = false}) async {
  final app = AppScope.read(context);
  final inv = await Api.get('/invoices/$invoiceId') as Json;
  if (!context.mounted) return;
  final auto = app.settings['print_auto'] == '1' && !forcePreview;
  if (auto) {
    final layout = PrintLayoutInfo.parse(app.settings['print_layout'] as String?);
    final bytes = await buildInvoicePdf(inv, app.settings, layout);
    final printers = await _printers();
    final want = '${app.settings['print_printer'] ?? ''}';
    final p = printers.where((x) => x.name == want).firstOrNull;
    if (p != null && await _directOk()) {
      await _send(PrintJobs.instance.add('Invoice ${inv['invoice_no']}', p.name, layout.name, 1, bytes), p, layout);
      if (context.mounted) toast(context, 'Sent ${inv['invoice_no']} to ${p.name}');
      return;
    }
    // no saved/available printer: fall through to the manager so the operator can choose one
  }
  final rows = (inv['lines'] as List).length;
  final sheets = sheetsPerCopy(rows);
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PrintManager(
      title: 'Invoice ${inv['invoice_no']}',
      heading: 'Print preview · ${inv['invoice_no']} · $rows items · $sheets half-sheet${sheets > 1 ? 's' : ''} per copy',
      build: (settings, layout) => buildInvoicePdf(inv, settings, layout),
    ),
  );
}

/// Print a receipt / payment voucher (same print manager, same printer and layout settings as invoices).
Future<void> printVoucher(BuildContext context, String voucherNo) async {
  final v = await Api.get('/vouchers/${Uri.encodeComponent(voucherNo)}') as Json;
  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PrintManager(
      title: '${v['title']} ${v['no']}',
      heading: 'Print preview · ${v['title']} ${v['no']}',
      build: (settings, layout) => buildVoucherPdf(v, settings, layout),
    ),
  );
}

Future<bool> _directOk() async {
  try {
    return (await Printing.info()).directPrint;
  } catch (_) {
    return false;
  }
}

Future<List<Printer>> _printers() async {
  try {
    return await Printing.listPrinters();
  } catch (_) {
    return [];
  }
}

// Every layout is now built on A4 pages (half-sheet copies sit at the top of the page).
/// Always portrait A4: a half sheet sits upright at the top of the page, where the A5 sheet fed sideways (long edge first, as on
/// an HP LaserJet 1020) catches it whole.
PdfPageFormat _formatFor(PrintLayout l) => Geo.a4Format;

Future<void> _send(PrintJob job, Printer printer, PrintLayout layout) async {
  try {
    for (var i = 0; i < job.copies; i++) {
      final ok = await Printing.directPrintPdf(printer: printer, onLayout: (_) async => job.bytes, name: job.title, format: _formatFor(layout));
      if (!ok) throw 'The printer did not accept the job';
    }
    PrintJobs.instance.update(job, JobStatus.done);
  } catch (e) {
    PrintJobs.instance.update(job, JobStatus.failed, '$e');
  }
}

/// The in-app print manager: live preview of the exact pages, printer choice, layout, copies, and a job list.
class PrintManager extends StatefulWidget {
  final String title, heading;
  final Future<Uint8List> Function(Json settings, PrintLayout layout) build;
  const PrintManager({super.key, required this.title, required this.heading, required this.build});
  @override
  State<PrintManager> createState() => _PrintManagerState();
}

class _PrintManagerState extends State<PrintManager> {
  late PrintLayout layout;
  List<Printer> printers = [];
  Printer? printer;
  bool direct = false, auto = false, loadingPrinters = true;
  int copies = 1;
  late Future<Uint8List> pdf;


  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    layout = PrintLayoutInfo.parse(s['print_layout'] as String?);
    auto = s['print_auto'] == '1';
    _rebuild();
    _loadPrinters('${s['print_printer'] ?? ''}');
  }

  void _rebuild() => pdf = widget.build(AppScope.read(context).settings, layout);

  Future<void> _loadPrinters(String preferred) async {
    final d = await _directOk();
    final p = d ? await _printers() : <Printer>[];
    if (!mounted) return;
    setState(() {
      direct = d;
      printers = p;
      printer = p.where((x) => x.name == preferred).firstOrNull ?? p.where((x) => x.isDefault).firstOrNull;
      loadingPrinters = false;
    });
  }

  Future<void> _savePrefs() => AppScope.read(context).saveSettings({
        'print_layout': layout.name,
        'print_printer': printer?.name ?? '',
        'print_auto': auto ? '1' : '0',
      });

  Future<void> _print() async {
    final bytes = await pdf;
    await _savePrefs();
    final title = widget.title;
    var sent = false;
    if (printer != null && direct) {
      final job = PrintJobs.instance.add(title, printer!.name, layout.name, copies, bytes);
      await _send(job, printer!, layout);
      sent = job.status == JobStatus.done;
      if (sent && mounted) toast(context, 'Printed on ${printer!.name}');
    } else {
      // Platforms without direct printing fall back to the system print sheet.
      final job = PrintJobs.instance.add(title, 'System print sheet', layout.name, copies, bytes);
      try {
        sent = await Printing.layoutPdf(onLayout: (_) async => bytes, name: title, format: _formatFor(layout));
        PrintJobs.instance.update(job, JobStatus.done);
      } catch (e) {
        PrintJobs.instance.update(job, JobStatus.failed, '$e');
      }
    }
    // Printed: close the print dialog. On failure or a cancelled system sheet it stays open so the error / retry is visible.
    if (sent && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: math.min(1080.0, size.width - 32),
        height: math.min(700.0, size.height - 32),
        child: Row(children: [
          Expanded(
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Text(widget.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: PdfPreview(
                  key: ValueKey(layout),
                  build: (_) => pdf,
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  maxPageWidth: 640,
                  loadingWidget: const CircularProgressIndicator(),
                ),
              ),
            ]),
          ),
          Container(
            width: 330,
            decoration: const BoxDecoration(color: Palette.paper, border: Border(left: BorderSide(color: Palette.line))),
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Print settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              AppDropdown<PrintLayout>(
                width: 294,
                label: 'Layout',
                value: layout,
                options: {for (final l in PrintLayout.values) l: l.label},
                onChanged: (v) => setState(() {
                  layout = v ?? layout;
                  _rebuild();
                }),
              ),
              const SizedBox(height: 12),
              if (loadingPrinters)
                const LinearProgressIndicator()
              else if (printers.isEmpty)
                Text(direct ? 'No printers found. Add one in System Settings > Printers.' : 'Printer list is not available here. The system print sheet will open when you press Print.',
                    style: const TextStyle(color: Palette.muted))
              else
                AppDropdown<Printer>(
                  width: 294,
                  label: 'Printer',
                  value: printer,
                  options: {for (final p in printers) p: p.name},
                  onChanged: (v) => setState(() => printer = v),
                ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Copies of the set'),
                const Spacer(),
                IconButton(onPressed: copies > 1 ? () => setState(() => copies--) : null, icon: const Icon(Icons.remove_circle_outline)),
                Text('$copies', style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(onPressed: copies < 9 ? () => setState(() => copies++) : null, icon: const Icon(Icons.add_circle_outline)),
              ]),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Print straight away next time'),
                subtitle: const Text('Skips this preview using the printer and layout above'),
                value: auto,
                onChanged: (v) => setState(() => auto = v),
              ),
              const Divider(),
              const Text('Print jobs', style: TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: ListenableBuilder(
                  listenable: PrintJobs.instance,
                  builder: (_, __) {
                    final jobs = PrintJobs.instance.jobs;
                    if (jobs.isEmpty) return const Center(child: Text('Nothing printed yet', style: TextStyle(color: Palette.muted)));
                    return ListView(children: [
                      for (final j in jobs)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: switch (j.status) {
                            JobStatus.printing => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            JobStatus.done => const Icon(Icons.check_circle, color: Palette.leaf, size: 20),
                            JobStatus.failed => const Icon(Icons.error, color: Palette.brick, size: 20),
                          },
                          title: Text(j.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(j.status == JobStatus.failed ? '${j.printer} · ${j.error}' : '${j.printer} · ${j.copies} × ${j.layout}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (j.status != JobStatus.printing && printer != null && direct)
                              IconButton(
                                tooltip: 'Print again',
                                icon: const Icon(Icons.replay, size: 18),
                                onPressed: () async {
                                  final again = PrintJobs.instance.add(j.title, printer!.name, j.layout, j.copies, j.bytes);
                                  await _send(again, printer!, PrintLayoutInfo.parse(j.layout));
                                },
                              ),
                            IconButton(tooltip: 'Remove', icon: const Icon(Icons.close, size: 18), onPressed: () => PrintJobs.instance.remove(j)),
                          ]),
                        ),
                    ]);
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                                onPressed: _print,
                icon: const Icon(Icons.print),
                label: Text(printer != null && direct ? 'Print on ${printer!.name}' : 'Print'),
              ),
              TextButton(onPressed: () async {
                await _savePrefs();
                if (context.mounted) Navigator.pop(context);
              }, child: const Text('Close')),
            ]),
          ),
        ]),
      ),
    );
  }
}
