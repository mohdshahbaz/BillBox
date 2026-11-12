import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';

/// Colours from docs/DESIGN_SYSTEM.md (the "Clean" theme, the default on every BillBox). The old names are kept so every
/// screen picks the new values up: `teal` is the accent, `turmeric` the warning, `brick` the negative and `leaf` the
/// positive role. Each text colour has at least 4.5:1 contrast on white and on `paper`.
class Palette {
  static const ink = Color(0xFF18181B); // text
  static const teal = Color(0xFF4F46E5); // accent
  static const paper = Color(0xFFF6F6F7); // page
  static const turmeric = Color(0xFFC2410C); // warning: not printed, expiring, low stock
  static const brick = Color(0xFFDC2626); // negative: due, loss, errors
  static const leaf = Color(0xFF15803D); // positive: profit, paid
  static const info = Color(0xFF2563EB); // notices, bills to print
  static const line = Color(0xFFE4E4E7); // borders and dividers
  static const muted = Color(0xFF6B6B74); // secondary text
  static const headerBand = Color(0xFFF1F1FD); // table heading: the accent at 6% over white
}

/// Design tokens (docs/DESIGN_SYSTEM.md §4), the same numbers as the iPhone's `DS` and Android's `DS`.
class DS {
  static const double s4 = 4, s8 = 8, s12 = 12, s16 = 16, s20 = 20, s24 = 24, s32 = 32;
  static const double cardPad = 14, cardGap = 12, cellPad = 8;
  static const double radiusCard = 14, radiusHero = 22, radiusControl = 12;
  static const double hitTarget = 48;
  static const double tint = 0.13;
}

/// One height for every text box and dropdown in the app.
const double kFieldH = 44;
const double kRadius = DS.radiusControl;

/// Screens narrower than this switch to the compact layout (icon-only navigation, stacked forms).
const double kNarrow = 900;
bool isNarrow(BuildContext c) => MediaQuery.sizeOf(c).width < kNarrow;

/// App-wide look. Every input, dropdown, button and card gets its size and colour from here,
/// so pages cannot drift apart.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.teal, surface: Palette.paper).copyWith(primary: Palette.teal, error: Palette.brick);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: const BorderSide(color: Palette.line));
  final inputTheme = InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    constraints: const BoxConstraints(minHeight: kFieldH, maxHeight: kFieldH),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.teal, width: 1.6)),
    errorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.brick)),
    focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.brick, width: 1.6)),
    labelStyle: const TextStyle(color: Palette.muted, fontSize: 14),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    hintStyle: const TextStyle(color: Color(0xFF8C979B), fontSize: 14),
  );
  final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius));
  const btnSize = Size(64, kFieldH);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    visualDensity: VisualDensity.compact,
    textTheme: Typography.blackCupertino.apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    inputDecorationTheme: inputTheme,
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: inputTheme,
      textStyle: const TextStyle(fontSize: 14),
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: WidgetStatePropertyAll(Colors.white),
        maximumSize: WidgetStatePropertyAll(Size(520, 360)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: btnSize, shape: btnShape, padding: const EdgeInsets.symmetric(horizontal: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: btnSize, shape: btnShape, side: const BorderSide(color: Palette.line), foregroundColor: Palette.teal, padding: const EdgeInsets.symmetric(horizontal: 16))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 40), shape: btnShape, foregroundColor: Palette.teal)),
    cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.radiusCard), side: const BorderSide(color: Palette.line))),
    dialogTheme: DialogThemeData(backgroundColor: Colors.white, surfaceTintColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1, thickness: 1),
    // tables: the heading band tinted with the accent, upper-case small semibold labels in the secondary colour
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: Palette.muted, fontSize: 12, letterSpacing: .4),
      dataTextStyle: TextStyle(color: Palette.ink, fontSize: 13.5),
      headingRowColor: WidgetStatePropertyAll(Palette.headerBand),
      dividerThickness: .6,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: btnShape),
    scrollbarTheme: const ScrollbarThemeData(thumbVisibility: WidgetStatePropertyAll(true)),
  );
}

/// Delays a repeated action (typing in a search box) until the user pauses.
class Debouncer {
  final Duration delay;
  Timer? _t;
  Debouncer([this.delay = const Duration(milliseconds: 280)]);
  void run(VoidCallback f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }

  void dispose() => _t?.cancel();
}

/// Plain text box, same height as every dropdown. Overflowing text scrolls inside the box instead of resizing it.
class AppField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label, hint, suffixText;
  final bool number, readOnly, autofocus, obscure;
  final double? width;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final Widget? prefix, suffix;
  final TextAlign align;
  const AppField({super.key, this.controller, this.label, this.hint, this.suffixText, this.number = false, this.readOnly = false, this.autofocus = false, this.obscure = false, this.width, this.onChanged, this.onSubmitted, this.onTap, this.focusNode, this.prefix, this.suffix, this.align = TextAlign.start});
  @override
  Widget build(BuildContext context) {
    final f = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: readOnly,
      obscureText: obscure,
      maxLines: 1,
      textAlign: align,
      style: number ? tabular.copyWith(fontSize: 14) : const TextStyle(fontSize: 14),
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffixText, prefixIcon: prefix, suffixIcon: suffix),
    );
    return width == null ? f : SizedBox(width: width, child: f);
  }
}

/// Opens a list in a dialog (with a search box when [search]) and returns the chosen key.
Future<T?> pickFromList<T>(BuildContext context, {required String title, required Map<T, String> options, T? selected, bool search = true}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      var q = '';
      final size = MediaQuery.sizeOf(ctx);
      return StatefulBuilder(builder: (ctx, setS) {
        final shown = [for (final e in options.entries) if (q.isEmpty || e.value.toLowerCase().contains(q.toLowerCase())) e];
        return Dialog(
          child: SizedBox(
            width: math.min(460.0, size.width - 48),
            height: math.min(520.0, size.height - 80),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 18)),
                ]),
              ),
              if (search)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AppField(
                    autofocus: true,
                    prefix: const Icon(Icons.search),
                    hint: 'Type to search',
                    onChanged: (v) => setS(() => q = v.trim()),
                    onSubmitted: (_) {
                      if (shown.isNotEmpty) Navigator.pop(ctx, shown.first.key);
                    },
                  ),
                ),
              const Divider(),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Nothing matches', style: TextStyle(color: Palette.muted)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          selected: shown[i].key == selected,
                          title: Text(shown[i].value, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(ctx, shown[i].key),
                        ),
                      ),
              ),
            ]),
          ),
        );
      });
    },
  );
}

/// A field that looks like every other input (same height, border, font) and picks from a list.
/// Long choices are cut with an ellipsis, so it can never overflow its row. Replaces Flutter's DropdownMenu,
/// whose width handling overflowed inside rows.
class PickerField<T> extends StatefulWidget {
  final String? label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final double? width;
  final bool search;
  const PickerField({super.key, this.label, required this.value, required this.options, required this.onChanged, this.width, this.search = false});
  @override
  State<PickerField<T>> createState() => _PickerFieldState<T>();
}

class _PickerFieldState<T> extends State<PickerField<T>> {
  T? _v;
  @override
  void initState() {
    super.initState();
    _v = widget.value;
  }

  @override
  void didUpdateWidget(PickerField<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _v = widget.value;
  }

  void _set(T? v) {
    setState(() => _v = v);
    widget.onChanged(v);
  }

  Widget _box(double? w) {
    final text = widget.options[_v];
    final box = InputDecorator(
      isEmpty: text == null,
      decoration: InputDecoration(labelText: widget.label, suffixIcon: const Icon(Icons.arrow_drop_down)),
      child: Text(text ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
    );
    return w == null ? box : SizedBox(width: w, child: box);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.search) {
      return InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () async {
          final v = await pickFromList<T>(context, title: widget.label ?? 'Choose', options: widget.options, selected: _v);
          if (v != null && mounted) _set(v);
        },
        child: _box(widget.width),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final w = widget.width ?? (c.hasBoundedWidth ? c.maxWidth : 220.0);
      return PopupMenuButton<T>(
        tooltip: '',
        position: PopupMenuPosition.under,
        constraints: BoxConstraints(minWidth: w, maxWidth: math.max(w, 200)),
        onSelected: _set,
        itemBuilder: (_) => [for (final e in widget.options.entries) PopupMenuItem<T>(value: e.key, height: 40, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))],
        child: _box(w),
      );
    });
  }
}

/// Plain dropdown (a handful of fixed choices).
class AppDropdown<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final double? width;
  const AppDropdown({super.key, this.label, required this.value, required this.options, required this.onChanged, this.width = 220});
  @override
  Widget build(BuildContext context) => PickerField<T>(label: label, value: value, options: options, onChanged: onChanged, width: width);
}

/// Dropdown whose list can be filtered by typing (parties, items).
class AppDropdownSearch<T> extends StatelessWidget {
  final String? label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final double? width;
  const AppDropdownSearch({super.key, this.label, required this.value, required this.options, required this.onChanged, this.width = 260});
  @override
  Widget build(BuildContext context) => PickerField<T>(label: label, value: value, options: options, onChanged: onChanged, width: width, search: true);
}

/// Lays children out in a wrap that never overflows: each child keeps its width and moves to the next line when space runs out.
class FormWrap extends StatelessWidget {
  final List<Widget> children;
  const FormWrap(this.children, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

/// Saves bytes through the macOS save dialog. Returns the chosen path, or null if cancelled.
Future<String?> saveBytes(BuildContext context, String fileName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(dialogTitle: 'Save $fileName', fileName: fileName, bytes: bytes);
  if (path == null) return null;
  // On desktop saveFile only returns the path; write the content ourselves when the plugin did not.
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() == 0) await f.writeAsBytes(bytes);
  } on FileSystemException catch (e) {
    if (context.mounted) toast(context, 'Could not save the file: ${e.message}', error: true);
    return null;
  }
  return path;
}

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String money(dynamic v) => _inr.format(num_(v));
num num_(dynamic v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: error ? Palette.brick : Palette.ink, behavior: SnackBarBehavior.floating, width: math.min(520.0, MediaQuery.sizeOf(c).width - 32)));
}

/// Runs an action and shows any API error as a snackbar instead of crashing.
Future<void> guard(BuildContext c, Future<void> Function() f) async {
  try {
    await f();
  } on ApiException catch (e) {
    if (c.mounted) toast(c, e.message, error: true);
  }
}

class FieldSpec {
  final String key, label;
  final bool number;
  final String? initial;
  final Map<String, String>? options; // value -> label (renders a dropdown)
  final bool date; // value is a date: shown as DD-MM-YYYY, chosen with the calendar, returned as YYYY-MM-DD
  const FieldSpec(this.key, this.label, {this.number = false, this.initial, this.options, this.date = false});
}

Future<Map<String, String>?> formDialog(BuildContext context, String title, List<FieldSpec> fields,
    {String okLabel = 'Save'}) {
  final vals = {for (final f in fields) f.key: f.initial ?? (f.options?.keys.first ?? '')};
  final ctrls = {for (final f in fields.where((f) => f.options == null)) f.key: TextEditingController(text: f.date ? dmy(f.initial ?? '') : (f.initial ?? ''))};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      void submit() {
        final out = {...vals};
        ctrls.forEach((k, c) => out[k] = fields.firstWhere((f) => f.key == k).date ? (isoFromDmy(c.text) ?? '') : c.text.trim());
        Navigator.pop(ctx, out);
      }

      final w = math.min(460.0, MediaQuery.sizeOf(ctx).width - 80);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: w,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: f.options != null
                      ? AppDropdown<String>(width: w, label: f.label, value: vals[f.key], options: f.options!, onChanged: (v) => vals[f.key] = v ?? vals[f.key]!)
                      : f.date
                          ? AppField(
                              width: w,
                              controller: ctrls[f.key],
                              label: f.label,
                              readOnly: true,
                              suffix: const Icon(Icons.event, size: 18),
                              onTap: () async {
                                final d = await pickDate(ctx, isoFromDmy(ctrls[f.key]!.text) ?? todayStr());
                                if (d != null) ctrls[f.key]!.text = dmy(d);
                              },
                            )
                          : AppField(width: w, controller: ctrls[f.key], label: f.label, number: f.number, autofocus: f == fields.first, onSubmitted: (_) => submit()),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: Text(okLabel)),
        ],
      );
    },
  );
}

class PageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final head = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, color: Palette.ink));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: head),
        // The actions wrap onto more lines when the window is narrow instead of overflowing.
        Flexible(flex: 3, child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions)),
      ]),
    );
  }
}

/// Figure with a coloured edge: the edge colour carries meaning (e.g. brick = needs attention).
class Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const Stat(this.label, this.value, {super.key, this.color = Palette.teal});
  @override
  Widget build(BuildContext context) => Container(
        width: 210,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(DS.radiusCard), border: Border(left: BorderSide(color: color, width: 4), top: const BorderSide(color: Palette.line), right: const BorderSide(color: Palette.line), bottom: const BorderSide(color: Palette.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.ink)),
        ]),
      );
}

/// Data table in a bordered card. Scrolls sideways on small windows; long cell text is cut with an ellipsis.
Widget table(List<String> cols, List<List<Widget>> rows, {Set<int> numeric = const {}, double maxCell = 280}) => Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 48,
              columnSpacing: 22,
              columns: [for (var i = 0; i < cols.length; i++) DataColumn(label: Text(cols[i].toUpperCase()), numeric: numeric.contains(i))],
              rows: [
                for (final r in rows)
                  DataRow(cells: [for (final c in r) DataCell(ConstrainedBox(constraints: BoxConstraints(maxWidth: maxCell), child: c))])
              ],
            ),
          ),
        ),
      ),
    );

Text t(String s, {Color? color, bool bold = false}) =>
    Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular.copyWith(color: color, fontWeight: bold ? FontWeight.w600 : null));

/// Indian date format used everywhere on screen and on paper: 2026-09-30 -> 30-09-2026 (a time after the date is kept).
String dmy(dynamic v) {
  final s = '${v ?? ''}';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return s == 'null' ? '' : s;
  return '${m[3]}-${m[2]}-${m[1]}${s.substring(m.end)}';
}

/// "30-09-2026" or "30/09/26" -> "2026-09-30" (what the server stores); null if it is not a date.
String? isoFromDmy(String s) {
  final m = RegExp(r'^\s*(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\s*$').firstMatch(s);
  if (m == null) return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim()) ? s.trim() : null;
  final y = m[3]!.length == 2 ? '20${m[3]}' : m[3]!;
  final d = DateTime.tryParse('$y-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}');
  return d == null ? null : d.toIso8601String().substring(0, 10);
}

String todayStr() => DateTime.now().toIso8601String().substring(0, 10);

Future<String?> pickDate(BuildContext c, String initial) async {
  final d = await showDatePicker(
    context: c,
    initialDate: DateTime.tryParse(initial) ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'Choose a date (day-month-year)',
  );
  return d?.toIso8601String().substring(0, 10);
}

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Palette.brick) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Soft white card used across the dashboard and settings.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final String? title;
  final Widget? trailing;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.title, this.trailing});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DS.radiusCard),
          border: Border.all(color: Palette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Flexible(child: Text(title!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.ink))),
                const Spacer(),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ]),
      );
}


/// Totals under a table (docs/DESIGN_SYSTEM.md §5): label above figure, as many per line as fit; one can be the main one.
class SumItem {
  final String label, value;
  final bool strong;
  final Color? tint;
  const SumItem(this.label, this.value, {this.strong = false, this.tint});
}

class SummaryCard extends StatelessWidget {
  final List<SumItem> items;
  const SummaryCard(this.items, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: DS.s8),
        padding: const EdgeInsets.symmetric(horizontal: DS.cardPad, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(DS.radiusCard), border: Border.all(color: Palette.line)),
        child: Wrap(spacing: 18, runSpacing: DS.s8, children: [
          for (final it in items)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 104),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(it.label, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                Text(it.value, style: tabular.copyWith(fontSize: 14.5, fontWeight: it.strong ? FontWeight.w700 : FontWeight.w500, color: it.tint ?? Palette.ink)),
              ]),
            ),
        ]),
      );
}

/// A small coloured label for a state (Sale, Not yet, Retailer…).
class StatusPill extends StatelessWidget {
  final String text;
  final Color tint;
  const StatusPill(this.text, {super.key, this.tint = Palette.teal});
  @override
  Widget build(BuildContext context) => text.isEmpty
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
          decoration: BoxDecoration(color: tint.withValues(alpha: DS.tint), borderRadius: BorderRadius.circular(999)),
          child: Text(text, maxLines: 1, style: TextStyle(color: tint, fontSize: 12, fontWeight: FontWeight.w600)),
        );
}
