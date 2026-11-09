/// Receipt / payment voucher, one half-A4 sheet (same sheet size and layout choices as invoices).
///
///   halfSheets / single : one voucher per half-A4 sheet, ORIGINAL and then an office copy
///   a4TwoUp             : both copies on one A4 sheet, cut line between
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../state/app_state.dart' show Json;
import '../widgets.dart' show dmy;
import 'invoice_pdf.dart' show Geo, PrintLayout, a4TopPage;

final _money = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 2);
num _n(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);
String _m(dynamic v) => _money.format(_n(v));
pw.TextStyle _s(double size, {bool bold = false}) => pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

const _copyLabels = ['PARTY COPY', 'OFFICE COPY'];

pw.Widget _line(String label, String value, {bool big = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 110, child: pw.Text(label, style: _s(8.5))),
        pw.Expanded(child: pw.Text(value, style: _s(big ? 13 : 9, bold: true), maxLines: 2)),
      ]),
    );

pw.Widget _sheet(Json v, String copy) {
  final co = (v['company'] as Json?) ?? {};
  final party = (v['party'] as Json?) ?? {};
  final received = v['direction'] == 'RECEIVED';
  final bal = _n(v['balance']);
  final balText = bal.abs() < 0.5 ? 'Settled' : (bal > 0 ? 'Balance to receive: Rs. ${_m(bal)}' : 'Balance to pay: Rs. ${_m(-bal)}');
  return pw.Container(
    width: Geo.w,
    height: Geo.h,
    padding: const pw.EdgeInsets.all(Geo.m),
    child: pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('${co['name'] ?? ''}', style: _s(13, bold: true), maxLines: 1),
                pw.Text('${co['address'] ?? ''}', style: _s(7), maxLines: 2),
                pw.Text('${(co['gstin'] ?? '') != '' ? 'GSTIN: ${co['gstin']}   ' : ''}${(co['phone'] ?? '') != '' ? 'Ph: ${co['phone']}' : ''}', style: _s(7)),
              ]),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: .6)),
              child: pw.Text(copy, style: _s(7, bold: true)),
            ),
          ]),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(color: PdfColors.grey300, border: pw.Border.symmetric(horizontal: pw.BorderSide(width: .6))),
          child: pw.Center(child: pw.Text('${v['title']}'.toUpperCase(), style: _s(11, bold: true))),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Voucher No: ${v['no']}', style: _s(9, bold: true)),
              pw.Text('Date: ${dmy(v['date'])}', style: _s(9, bold: true)),
            ]),
            pw.SizedBox(height: 6),
            _line(received ? 'Received from' : 'Paid to', '${party['name'] ?? ''}'),
            if ((party['address'] ?? '') != '') _line('Address', '${party['address']}'),
            if ((party['gstin'] ?? '') != '') _line('GSTIN', '${party['gstin']}'),
            _line('Payment mode', '${v['mode']}${(v['reference'] ?? '') != '' ? '   Ref: ${v['reference']}' : ''}'),
            _line('Amount', 'Rs. ${_m(v['amount'])}', big: true),
            _line('Amount in words', '${v['amount_words']}'),
            pw.SizedBox(height: 4),
            pw.Text(balText, style: _s(8)),
          ]),
        ),
        pw.Spacer(),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(width: 130, height: .6, color: PdfColors.grey700),
              pw.SizedBox(height: 2),
              pw.Text(received ? 'Payer signature' : 'Receiver signature', style: _s(7)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('For ${co['name'] ?? ''}', style: _s(7.5)),
              pw.SizedBox(height: 18),
              pw.Container(width: 130, height: .6, color: PdfColors.grey700),
              pw.Text('Authorised signatory', style: _s(7)),
            ]),
          ]),
        ),
      ]),
    ),
  );
}

/// [v] is GET /vouchers/:no. [settings] is accepted so this can be used wherever invoices are built.
Future<Uint8List> buildVoucherPdf(Json v, Json settings, PrintLayout layout) async {
  final doc = pw.Document(
    title: '${v['title']} ${v['no']}',
    theme: pw.ThemeData.withFont(base: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );
  if (layout == PrintLayout.a4TwoUp) {
    doc.addPage(pw.Page(
      pageFormat: Geo.a4Format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(children: [
        pw.Column(children: [_sheet(v, _copyLabels[0]), _sheet(v, _copyLabels[1])]),
        pw.Positioned(left: 0, right: 0, top: Geo.h - .3, child: pw.Container(height: .6, color: PdfColors.grey500)),
      ]),
    ));
  } else {
    final copies = layout == PrintLayout.single ? [_copyLabels[0]] : _copyLabels;
    for (final c in copies) {
      doc.addPage(a4TopPage(_sheet(v, c)));
    }
  }
  return doc.save();
}
