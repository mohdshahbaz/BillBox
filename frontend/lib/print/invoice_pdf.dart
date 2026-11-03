/// Half-A4 dual-copy GST invoice layout.
///
/// A half-A4 sheet is 210 x 148.5 mm (595.28 x 420.95 pt). Every sheet is built from fixed-height blocks
/// (header, column heads, one-line item rows, totals, footer), so how many rows fit is plain arithmetic and
/// nothing is ever clipped. If the items do not fit, the invoice continues on the next half-sheet with a short
/// "continued" header, and the totals block goes only on the last sheet of each copy.
///
/// Layouts:
///   halfSheets : ORIGINAL pages, then DUPLICATE pages. Each copy sits at the TOP of its own A4 page (lower half blank)
///   a4TwoUp    : A4 sheets, ORIGINAL in the top half, DUPLICATE in the bottom half (same page number), cut line between
///   single     : ORIGINAL only, at the top of an A4 page
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../state/app_state.dart' show Json;
import '../widgets.dart' show dmy;

enum PrintLayout { halfSheets, a4TwoUp, single }

extension PrintLayoutInfo on PrintLayout {
  String get label => switch (this) {
        PrintLayout.halfSheets => 'Half-A4 copies: Original on page 1, Duplicate on next page (both at top)',
        PrintLayout.a4TwoUp => 'A4 sheet: Original on top, Duplicate below',
        PrintLayout.single => 'Half-A4: Original copy only (at top of page)',
      };
  static PrintLayout parse(String? s) => PrintLayout.values.firstWhere((l) => l.name == s, orElse: () => PrintLayout.halfSheets);
}

const copyLabels = ['ORIGINAL FOR RECIPIENT', 'DUPLICATE FOR TRANSPORTER/SUPPLIER'];

class Geo {
  static const double w = 595.276, h = 420.945; // half of A4 (portrait 595.276 x 841.89)
  static const double m = 12; // sheet margin (narrow: more item rows)
  static const double rowH = 12, headFirst = 76, headNext = 30, tableHead = 14, foot = 22, totals = 92;
  static const double inner = h - 2 * m;
  static final halfFormat = PdfPageFormat(w, h, marginAll: 0);
  static final a4Format = PdfPageFormat(w, h * 2, marginAll: 0);

  /// How many item rows fit on a sheet.
  static int cap({required bool first, required bool last}) =>
      ((inner - (first ? headFirst : headNext) - tableHead - foot - (last ? totals : 0)) / rowH).floor();
}

/// Splits n item rows into sheets. Returns the row indexes per sheet (always at least one sheet).
List<List<int>> paginate(int n) {
  List<int> range(int a, int b) => [for (var i = a; i < b; i++) i];
  if (n <= Geo.cap(first: true, last: true)) return [range(0, n)];
  final pages = <List<int>>[];
  var i = 0, first = true;
  while (true) {
    final remaining = n - i;
    if (remaining <= Geo.cap(first: first, last: true)) {
      pages.add(range(i, n));
      break;
    }
    // leave at least one row for the last sheet so totals never sit alone on an empty sheet
    final take = [Geo.cap(first: first, last: false), remaining - 1].reduce((a, b) => a < b ? a : b);
    pages.add(range(i, i + take));
    i += take;
    first = false;
  }
  return pages;
}

/// One half-A4 copy per A4 page, pinned to the top edge (the lower half of the page stays blank), so the
/// original prints at the top of page 1 and the duplicate at the top of the next page.
pw.Page a4TopPage(pw.Widget sheet) => pw.Page(
      pageFormat: Geo.a4Format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [sheet],
      ),
    );

final _money = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _m(dynamic v) => _money.format(_n(v));
String _cut(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 2)}..';
pw.TextStyle _s(double size, {bool bold = false}) =>
    pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

const _wNo = 16.0, _wHsn = 40.0, _wQty = 74.0, _wMrp = 32.0, _wRate = 34.0, _wDisc = 24.0, _wTax = 46.0, _wGst = 22.0, _wAmt = 50.0;

pw.Widget _cell(String t, double? width, double height, {bool bold = false, bool right = false, double size = 7, bool grid = false}) {
  final c = pw.Container(
    width: width,
    height: height,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
    decoration: grid ? const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: .3, color: PdfColors.grey500))) : null,
    alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    child: pw.Text(t, style: _s(size, bold: bold), maxLines: 1),
  );
  return width == null ? pw.Expanded(child: c) : c;
}

pw.Widget _cols(List<String> v, double h, {bool bold = false}) => pw.Row(children: [
      _cell(v[0], _wNo, h, bold: bold, grid: true),
      _cell(v[1], null, h, bold: bold, grid: true),
      _cell(v[2], _wHsn, h, bold: bold, grid: true),
      _cell(v[3], _wQty, h, bold: bold, right: true, grid: true),
      _cell(v[4], _wMrp, h, bold: bold, right: true, grid: true),
      _cell(v[5], _wRate, h, bold: bold, right: true, grid: true),
      _cell(v[6], _wDisc, h, bold: bold, right: true, grid: true),
      _cell(v[7], _wTax, h, bold: bold, right: true, grid: true),
      _cell(v[8], _wGst, h, bold: bold, right: true, grid: true),
      _cell(v[9], _wAmt, h, bold: bold, right: true),
    ]);

String _qty(Json l) {
  final q = _n(l['qty']).toInt(), f = _n(l['free_qty']).toInt(), ppb = _n(l['pcs_per_box']).toInt();
  var s = '$q';
  if (ppb > 1 && q >= ppb) s = '$q (${q ~/ ppb}B${q % ppb > 0 ? '+${q % ppb}' : ''})';
  if (f > 0) s += ' +${f}F';
  return s;
}

pw.Widget _row(int no, Json l) => pw.SizedBox(
      height: Geo.rowH,
      child: pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: .3, color: PdfColors.grey500))),
        child: _cols([
          '$no', _cut('${l['item_name']}', 58), '${l['hsn'] ?? ''}',
          _qty(l), _m(l['mrp']), _m(l['rate']), _n(l['disc_pct']) > 0 ? '${_n(l['disc_pct'])}' : '', _m(l['taxable']), '${_n(l['gst_rate'])}', _m(l['amount']),
        ], Geo.rowH),
      ),
    );

pw.Widget _rule() => pw.Container(height: .6, color: PdfColors.grey700);

pw.Widget _headFirst(Json inv, Json co, String copy) {
  const topH = 44.0;
  final intra = inv['supply'] != 'INTER';
  return pw.SizedBox(
    height: Geo.headFirst,
    child: pw.Column(children: [
      pw.SizedBox(
        height: topH,
        child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(5, 3, 5, 0),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_cut('${co['company_name']}', 48), style: _s(11, bold: true), maxLines: 1),
                pw.Text(_cut('${co['company_address'] ?? ''}', 95), style: _s(6.5), maxLines: 1),
                pw.Text('GSTIN: ${co['company_gstin'] ?? ''}   State code: ${co['state_code'] ?? ''}${(co['company_phone'] ?? '') != '' ? '   Ph: ${co['company_phone']}' : ''}', style: _s(6.5), maxLines: 1),
              ]),
            ),
            pw.SizedBox(
              width: 190,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('TAX INVOICE', style: _s(10, bold: true)),
                pw.Text('No: ${inv['invoice_no']}    Date: ${dmy(inv['date'])}', style: _s(7.5), maxLines: 1),
                pw.SizedBox(height: 2),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
                  child: pw.Text(copy, style: _s(6.5, bold: true), maxLines: 1),
                ),
              ]),
            ),
          ]),
        ),
      ),
      _rule(),
      pw.SizedBox(
        height: Geo.headFirst - topH - .6,
        child: pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(5, 2, 5, 0),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Bill to: ${_cut('${inv['party_name'] ?? 'Cash customer'}', 55)}', style: _s(8.5, bold: true), maxLines: 1),
                pw.Text(_cut('${inv['party_address'] ?? ''}', 95), style: _s(6.5), maxLines: 1),
                pw.Text('${(inv['party_gstin'] ?? '') != '' ? 'GSTIN: ${inv['party_gstin']}   ' : ''}${(inv['party_state'] ?? '') != '' ? 'State code: ${inv['party_state']}' : ''}', style: _s(6.5), maxLines: 1),
              ]),
            ),
            pw.SizedBox(
              width: 190,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Salesman: ${inv['salesman_name'] ?? '-'}', style: _s(6.5), maxLines: 1),
                pw.Text('Payment: ${inv['pay_mode']}${inv['sale_type'] == 'VAN' ? '  (Van sale)' : ''}', style: _s(6.5), maxLines: 1),
                pw.Text(intra ? 'Intra-state supply: CGST + SGST' : 'Inter-state supply: IGST', style: _s(6.5), maxLines: 1),
              ]),
            ),
          ]),
        ),
      ),
      _rule(),
    ]),
  );
}

pw.Widget _headNext(Json inv, Json co, String copy) => pw.SizedBox(
      height: Geo.headNext,
      child: pw.Column(children: [
        pw.SizedBox(
          height: Geo.headNext - .6,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('${_cut('${co['company_name']}', 40)}  -  Tax Invoice ${inv['invoice_no']} (continued)', style: _s(8, bold: true), maxLines: 1),
              pw.Text('${_cut('${inv['party_name'] ?? 'Cash customer'}', 30)}   ${dmy(inv['date'])}', style: _s(7), maxLines: 1),
            ]),
          ),
        ),
        _rule(),
      ]),
    );

/// The bank details as (label, value) rows: Bank, A/c name, A/c no., IFSC, Branch, Address (empty ones left out).
List<List<String>> _bankRows(Json co) {
  if ('${co['print_bank_block'] ?? ''}' == '0') return [];
  String v(String k) => '${co[k] ?? ''}'.trim();
  final code = v('bank_branch_code');
  final branch = v('bank_branch') + (code.isEmpty ? '' : (v('bank_branch').isEmpty ? 'Code $code' : ' ($code)'));
  return [
    ['Bank', v('bank_name')],
    ['A/c name', v('bank_ac_name')],
    ['A/c no.', v('bank_ac_no')],
    ['IFSC', v('bank_ifsc')],
    ['Branch', branch],
    ['Address', v('bank_address')],
  ].where((r) => r[1].isNotEmpty).toList();
}

/// Settings "print_bank_size": text size and how the band's left side is shared between "Amount in words" (flex) and the bank block.
({double scale, int words, int bank}) _bankSize(Json co) {
  switch ('${co['print_bank_size'] ?? ''}') {
    case 's':
      return (scale: 0.9, words: 44, bank: 56);
    case 'l':
      return (scale: 1.15, words: 34, bank: 66);
    case 'xl':
      return (scale: 1.3, words: 30, bank: 70);
    default:
      return (scale: 1.0, words: 38, bank: 62);
  }
}

/// The bank details as a small table beside "Amount in words" that also uses the free height of the band: one column when
/// every row fits [fit] lines, else two. Labels, a tab, then the values, lined up, behind a fine divider.
pw.Widget _bankTab(Json co, int fit) {
  final sc = _bankSize(co).scale;
  final lh = 7.2 * sc;
  final rows = _bankRows(co);
  if (rows.isEmpty) return pw.SizedBox();
  final per = rows.length <= fit ? rows.length : ((rows.length + 1) / 2).ceil();
  pw.Widget col(List<List<String>> rs) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final r in rs)
            pw.SizedBox(
              height: lh,
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(width: 34 * sc, child: pw.Text('${r[0]}:', style: _s(6 * sc, bold: true), maxLines: 1)),
                pw.SizedBox(width: 3),
                pw.Expanded(child: pw.Text(r[1], style: _s(7 * sc), maxLines: 1)),
              ]),
            ),
        ]),
      );
  return pw.Container(
    padding: const pw.EdgeInsets.only(left: 6),
    decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: .5, color: PdfColors.grey600))),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (var i = 0; i < rows.length; i += per) ...[
        if (i > 0) pw.SizedBox(width: 6),
        col(rows.skip(i).take(per).toList()),
      ],
    ]),
  );
}

pw.Widget _totals(Json inv, Json co) {
  final intra = inv['supply'] != 'INTER';
  final g = (inv['gst_summary'] as List).cast<Json>().take(6).toList();
  pw.Widget srow(List<String> v, {bool bold = false}) => pw.SizedBox(
        height: 9,
        child: pw.Row(children: [
          _cell(v[0], 36, 9, bold: bold, size: 6.5),
          _cell(v[1], 62, 9, bold: bold, right: true, size: 6.5),
          _cell(v[2], 54, 9, bold: bold, right: true, size: 6.5),
          if (v.length > 3) _cell(v[3], 54, 9, bold: bold, right: true, size: 6.5),
        ]),
      );
  pw.Widget kv(String a, String b, {bool big = false}) => pw.Container(
        height: big ? 16 : 9.5,
        margin: big ? const pw.EdgeInsets.symmetric(vertical: 1.5) : null,
        padding: big ? const pw.EdgeInsets.symmetric(horizontal: 3) : null,
        decoration: big ? pw.BoxDecoration(color: PdfColors.grey200, border: pw.Border.all(width: .6)) : null,
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text(a, style: _s(big ? 9 : 7.5, bold: big)),
          pw.Text(b, style: _s(big ? 11 : 7.5, bold: big)),
        ]),
      );
  final due = _n(inv['total']) - _n(inv['paid']);
  // lines of the left column still free once the GST rows have their height (the bank rows may use all of it)
  final bankFit = ((Geo.totals - 3 - 9.0 * (1 + g.length) - 3 - 2) / (7.2 * _bankSize(co).scale)).floor();
  return pw.SizedBox(
    height: Geo.totals,
    child: pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(5, 3, 5, 0),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: .6))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            srow(['GST %', 'Taxable', intra ? 'CGST' : 'IGST', if (intra) 'SGST'], bold: true),
            for (final x in g) srow(['${_n(x['rate'])}%', _m(x['taxable']), intra ? _m(x['cgst']) : _m(x['igst']), if (intra) _m(x['sgst'])]),
            pw.SizedBox(height: 3),
            // "Amount in words" on the left, the bank details beside it (no extra height)
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Expanded(flex: _bankRows(co).isEmpty ? 100 : _bankSize(co).words, child: pw.Text('Amount in words: ${inv['amount_words']}', style: _s(6.5), maxLines: 3)),
              if (_bankRows(co).isNotEmpty) ...[pw.SizedBox(width: 6), pw.Expanded(flex: _bankSize(co).bank, child: _bankTab(co, bankFit))],
            ]),
          ]),
        ),
        pw.SizedBox(width: 14),
        pw.SizedBox(
          width: 190,
          child: pw.Column(children: [
            kv('Items total', _m(inv['subtotal'])),
            kv('Discount', '- ${_m(inv['discount'])}'),
            kv('Taxable value', _m(inv['taxable'])),
            if (intra) ...[kv('CGST', _m(inv['cgst'])), kv('SGST', _m(inv['sgst']))] else kv('IGST', _m(inv['igst'])),
            kv('Round off', _m(inv['round_off'])),
            kv('Invoice total (Rs.)', _m(inv['total']), big: true),
            kv('Paid ${_m(inv['paid'])}', 'Balance ${_m(due)}'),
          ]),
        ),
      ]),
    ),
  );
}

pw.Widget _foot(Json inv, Json co, String copy, int page, int pages) => pw.SizedBox(
      height: Geo.foot,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: .6))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(flex: 3, child: pw.Text('${co['invoice_terms'] ?? ''}', style: _s(6), maxLines: 2)),
          pw.Expanded(
            flex: 3,
            child: pw.Column(children: [
              pw.Text(copy, style: _s(7.5, bold: true), maxLines: 1),
              pw.Text('Page ${page + 1} of $pages', style: _s(6.5)),
            ]),
          ),
          pw.SizedBox(
            width: 150,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('For ${_cut('${co['company_name']}', 34)}', style: _s(6.5), maxLines: 1),
              pw.SizedBox(height: 4),
              pw.Text('Authorised signatory', style: _s(6)),
            ]),
          ),
        ]),
      ),
    );

pw.Widget _sheet(Json inv, Json co, String copy, List<Json> rows, int startNo, int page, int pages) {
  final first = page == 0, last = page == pages - 1;
  return pw.Container(
    width: Geo.w,
    height: Geo.h,
    padding: const pw.EdgeInsets.all(Geo.m),
    child: pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        first ? _headFirst(inv, co, copy) : _headNext(inv, co, copy),
        pw.Container(
          height: Geo.tableHead,
          decoration: const pw.BoxDecoration(color: PdfColors.grey300, border: pw.Border(bottom: pw.BorderSide(width: .6))),
          child: _cols(['#', 'Item', 'HSN', 'Qty (pcs)', 'MRP', 'Rate', 'Disc%', 'Taxable', 'GST%', 'Amount'], Geo.tableHead, bold: true),
        ),
        for (var i = 0; i < rows.length; i++) _row(startNo + i + 1, rows[i]),
        pw.Spacer(),
        if (last) _totals(inv, co),
        _foot(inv, co, copy, page, pages),
      ]),
    ),
  );
}

/// Builds the print-ready PDF for one invoice. [inv] is GET /invoices/:id, [co] is GET /settings.
Future<Uint8List> buildInvoicePdf(Json inv, Json co, PrintLayout layout) async {
  final doc = pw.Document(
    title: 'Invoice ${inv['invoice_no']}',
    author: '${co['company_name']}',
    theme: pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );
  final lines = (inv['lines'] as List).cast<Json>();
  final pages = paginate(lines.length);

  pw.Widget sheet(String copy, int p) {
    final idx = pages[p];
    return _sheet(inv, co, copy, [for (final i in idx) lines[i]], idx.isEmpty ? 0 : idx.first, p, pages.length);
  }

  if (layout == PrintLayout.a4TwoUp) {
    for (var p = 0; p < pages.length; p++) {
      doc.addPage(pw.Page(
        pageFormat: Geo.a4Format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(children: [
          pw.Column(children: [sheet(copyLabels[0], p), sheet(copyLabels[1], p)]),
          pw.Positioned(left: 0, right: 0, top: Geo.h - .3, child: pw.Container(height: .6, color: PdfColors.grey500)),
        ]),
      ));
    }
  } else {
    final copies = layout == PrintLayout.single ? [copyLabels[0]] : copyLabels;
    for (final copy in copies) {
      for (var p = 0; p < pages.length; p++) {
        doc.addPage(a4TopPage(sheet(copy, p)));
      }
    }
  }
  return doc.save();
}

/// Sheets per copy, for the preview header ("2 half-sheets per copy").
int sheetsPerCopy(int itemRows) => paginate(itemRows).length;
