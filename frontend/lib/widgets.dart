import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';

/// One colour theme from Settings › Appearance: the same list and values as the iPhone's `AppTheme.all`
/// (accent, panel and page colours, light and dark).
class BBTheme {
  final String id, name;
  final int accent, accentDark, cardDark, page, pageDark;
  const BBTheme(this.id, this.name, this.accent, this.accentDark, this.cardDark, this.page, this.pageDark);
}

const kThemes = <BBTheme>[
  BBTheme('clean', 'Clean', 0xFF4F46E5, 0xFF8B8CF8, 0xFF17171A, 0xFFF6F6F7, 0xFF0C0C0E),
  BBTheme('classic', 'Classic', 0xFF007AFF, 0xFF0A84FF, 0xFF1C1C1E, 0xFFF2F2F7, 0xFF000000),
  BBTheme('ocean', 'Ocean', 0xFF0E7C9B, 0xFF35B6D6, 0xFF17272F, 0xFFEAF4F8, 0xFF0F1C22),
  BBTheme('forest', 'Forest', 0xFF2E7D52, 0xFF4FBF82, 0xFF18261D, 0xFFEBF4EE, 0xFF101A14),
  BBTheme('sunset', 'Sunset', 0xFFD9552B, 0xFFFF7F50, 0xFF2E1D14, 0xFFFCF0E8, 0xFF21150F),
  BBTheme('royal', 'Royal', 0xFF6D3FD0, 0xFF9B7BF0, 0xFF241C38, 0xFFF2EEFA, 0xFF181325),
  BBTheme('rose', 'Rose', 0xFFC9285F, 0xFFF0608F, 0xFF2B1821, 0xFFFBEEF3, 0xFF22141A),
  BBTheme('gold', 'Marigold', 0xFFB7791F, 0xFFF2B544, 0xFF2A2316, 0xFFFBF5E6, 0xFF1E190F),
  BBTheme('slate', 'Slate', 0xFF4A5C70, 0xFF93A8BD, 0xFF25282C, 0xFFEEF0F3, 0xFF1B1D20),
  BBTheme('midnight', 'Midnight', 0xFF2563EB, 0xFF60A5FA, 0xFF111827, 0xFFEEF2F7, 0xFF0B1220),
  BBTheme('mint', 'Mint', 0xFF0F9D7A, 0xFF34D3A6, 0xFF16241F, 0xFFEAF7F2, 0xFF0F1A16),
  BBTheme('lavender', 'Lavender', 0xFF7C5CC4, 0xFFB49CFF, 0xFF221D2E, 0xFFF4F0FB, 0xFF17131F),
  BBTheme('saffron', 'Saffron', 0xFFE07000, 0xFFFFA733, 0xFF2B2112, 0xFFFFF5E6, 0xFF1F170C),
  BBTheme('crimson', 'Crimson', 0xFFB91C1C, 0xFFF87171, 0xFF2A1616, 0xFFFBEFEF, 0xFF1E1010),
  BBTheme('coffee', 'Coffee', 0xFF7A4E2D, 0xFFC9925E, 0xFF2A211B, 0xFFF6EFE8, 0xFF1C1612),
  BBTheme('graphite', 'Graphite', 0xFF1F2937, 0xFFE5E7EB, 0xFF1C1C1E, 0xFFF2F2F3, 0xFF000000),
  BBTheme('teal', 'Teal', 0xFF0F766E, 0xFF2DD4BF, 0xFF132826, 0xFFE9F6F4, 0xFF0D1A19),
  BBTheme('sky', 'Sky', 0xFF0284C7, 0xFF38BDF8, 0xFF132634, 0xFFEAF5FC, 0xFF0B1A24),
  BBTheme('emerald', 'Emerald', 0xFF047857, 0xFF34D399, 0xFF13261D, 0xFFE8F6EF, 0xFF0B1913),
  BBTheme('plum', 'Plum', 0xFF86198F, 0xFFE879F9, 0xFF2A1A2E, 0xFFF8EEF9, 0xFF1C1020),
  BBTheme('sand', 'Sand', 0xFF8A6A3B, 0xFFD6B37A, 0xFF2A241B, 0xFFF7F2E9, 0xFF1C1812),
  BBTheme('peacock', 'Peacock', 0xFF006D77, 0xFF4FD1C5, 0xFF14292B, 0xFFE6F4F5, 0xFF0B1A1C),
  BBTheme('cherry', 'Cherry', 0xFF9F1239, 0xFFFB7185, 0xFF2D1820, 0xFFFCEEF2, 0xFF1E0F14),
  BBTheme('olive', 'Olive', 0xFF556B2F, 0xFFA3C46B, 0xFF232918, 0xFFF2F4EA, 0xFF161A0F),
];

/// Colours from docs/DESIGN_SYSTEM.md. They follow the theme and light/dark mode chosen in Settings › Appearance
/// (`Palette.apply`). The old names are kept: `teal` is the accent, `turmeric` the warning, `brick` the negative and
/// `leaf` the positive role. Each text colour has at least 4.5:1 contrast on its card and page colour.
class Palette {
  static BBTheme theme = kThemes.first;
  static bool dark = false;
  static void apply(BBTheme t, bool isDark) {
    theme = t;
    dark = isDark;
  }

  static Color get ink => dark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B); // text
  static Color get teal => Color(dark ? theme.accentDark : theme.accent); // accent
  static Color get paper => Color(dark ? theme.pageDark : theme.page); // page
  static Color get card => dark ? Color(theme.cardDark) : Palette.card; // panels, tables, fields
  static Color get turmeric => dark ? const Color(0xFFFB923C) : const Color(0xFFC2410C); // warning: not printed, expiring, low stock
  static Color get brick => dark ? const Color(0xFFF87171) : const Color(0xFFDC2626); // negative: due, loss, errors
  static Color get leaf => dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D); // positive: profit, paid
  static Color get info => dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB); // notices, bills to print
  static Color get line => dark ? const Color(0xFF2F2F35) : const Color(0xFFE4E4E7); // borders and dividers
  static Color get muted => dark ? const Color(0xFFA1A1AA) : const Color(0xFF6B6B74); // secondary text
  static Color get hint => dark ? const Color(0xFF8A8A93) : const Palette.hint;
  /// Table heading band: the accent at 6% (10% in dark) over the panel colour.
  static Color get headerBand => Color.alphaBlend(teal.withValues(alpha: dark ? .10 : .06), card);
  /// Navigation sidebar: stays dark in both modes (white text on it).
  static Color get sidebar => dark ? const Color(0xFF09090B) : const Color(0xFF18181B);
  /// Text and icons on an accent-filled surface.
  static Color get onAccent => teal.computeLuminance() > .45 ? const Color(0xFF18181B) : Palette.card;
}

/// Theme and light/dark choice for this computer, kept in `<data folder>/appearance.json` (like the iPhone's
/// `theme` and `appearance` settings, which are per device too).
class Appearance extends ChangeNotifier {
  Appearance._();
  static final instance = Appearance._();
  String themeId = 'clean';
  String mode = 'auto'; // auto | light | dark
  File? _file;

  BBTheme get theme => kThemes.firstWhere((t) => t.id == themeId, orElse: () => kThemes.first);

  void load(String dataDir) {
    try {
      _file = File('$dataDir${Platform.pathSeparator}appearance.json');
      if (_file!.existsSync()) {
        final j = jsonDecode(_file!.readAsStringSync()) as Map<String, dynamic>;
        themeId = '${j['theme'] ?? 'clean'}';
        mode = const ['auto', 'light', 'dark'].contains(j['appearance']) ? j['appearance'] as String : 'auto';
      }
    } catch (e) {
      debugPrint('appearance.json not read: $e'); // falls back to Clean, automatic
    }
  }

  void set({String? theme, String? appearance}) {
    themeId = theme ?? themeId;
    mode = appearance ?? mode;
    notifyListeners();
    try {
      _file?.writeAsStringSync(jsonEncode({'theme': themeId, 'appearance': mode}));
    } catch (e) {
      debugPrint('appearance.json not saved: $e');
    }
  }
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
/// Built from `Palette`, so call `Palette.apply` first; light or dark follows `Palette.dark`.
ThemeData buildTheme() {
  final b = Palette.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: Palette.teal, brightness: b, surface: Palette.paper)
      .copyWith(primary: Palette.teal, onPrimary: Palette.onAccent, error: Palette.brick, surface: Palette.paper, onSurface: Palette.ink, outline: Palette.line);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(kRadius), borderSide: BorderSide(color: Palette.line));
  final inputTheme = InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: Palette.card,
    constraints: const BoxConstraints(minHeight: kFieldH, maxHeight: kFieldH),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: BorderSide(color: Palette.teal, width: 1.6)),
    errorBorder: border.copyWith(borderSide: BorderSide(color: Palette.brick)),
    focusedErrorBorder: border.copyWith(borderSide: BorderSide(color: Palette.brick, width: 1.6)),
    labelStyle: TextStyle(color: Palette.muted, fontSize: 14),
    floatingLabelBehavior: FloatingLabelBehavior.auto,
    hintStyle: TextStyle(color: Palette.hint, fontSize: 14),
  );
  final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius));
  const btnSize = Size(64, kFieldH);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    visualDensity: VisualDensity.compact,
    textTheme: (Palette.dark ? Typography.whiteCupertino : Typography.blackCupertino).apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    inputDecorationTheme: inputTheme,
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: inputTheme,
      textStyle: const TextStyle(fontSize: 14),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Palette.card),
        surfaceTintColor: WidgetStatePropertyAll(Palette.card),
        maximumSize: const WidgetStatePropertyAll(Size(520, 360)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: btnSize, shape: btnShape, padding: const EdgeInsets.symmetric(horizontal: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: btnSize, shape: btnShape, side: BorderSide(color: Palette.line), foregroundColor: Palette.teal, padding: const EdgeInsets.symmetric(horizontal: 16))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 40), shape: btnShape, foregroundColor: Palette.teal)),
    cardTheme: CardThemeData(color: Palette.card, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DS.radiusCard), side: BorderSide(color: Palette.line))),
    dialogTheme: DialogThemeData(backgroundColor: Palette.card, surfaceTintColor: Palette.card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dividerTheme: DividerThemeData(color: Palette.line, space: 1, thickness: 1),
    // tables: the heading band tinted with the accent, upper-case small semibold labels in the secondary colour
    dataTableTheme: DataTableThemeData(
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: Palette.muted, fontSize: 12, letterSpacing: .4),
      dataTextStyle: TextStyle(color: Palette.ink, fontSize: 13.5),
      headingRowColor: WidgetStatePropertyAll(Palette.headerBand),
      dividerThickness: .6,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: btnShape),
    // keyboard focus (Fluent): a visible accent ring on the focused control
    focusColor: Palette.teal.withValues(alpha: .18),
    popupMenuTheme: PopupMenuThemeData(color: Palette.card, surfaceTintColor: Palette.card),
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
                    ? Center(child: Text('Nothing matches', style: TextStyle(color: Palette.muted)))
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
        content: Text(msg), backgroundColor: error ? Palette.brick : null, behavior: SnackBarBehavior.floating, width: math.min(520.0, MediaQuery.sizeOf(c).width - 32)));
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
  final Color? color;
  const Stat(this.label, this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 210,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(DS.radiusCard), border: Border(left: BorderSide(color: color ?? Palette.teal, width: 4), top: BorderSide(color: Palette.line), right: BorderSide(color: Palette.line), bottom: BorderSide(color: Palette.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Palette.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: tabular.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.ink)),
        ]),
      );
}

/// Data table in a bordered card. Scrolls sideways on small windows; long cell text is cut with an ellipsis.
/// Click a heading to sort by that column (again to reverse); amounts and dd-mm-yyyy dates sort by value.
Widget table(List<String> cols, List<List<Widget>> rows, {Set<int> numeric = const {}, double maxCell = 280}) =>
    SortTable(cols: cols, rows: rows, numeric: numeric, maxCell: maxCell);

class SortTable extends StatefulWidget {
  final List<String> cols;
  final List<List<Widget>> rows;
  final Set<int> numeric;
  final double maxCell;
  const SortTable({super.key, required this.cols, required this.rows, this.numeric = const {}, this.maxCell = 280});
  @override
  State<SortTable> createState() => _SortTableState();
}

class _SortTableState extends State<SortTable> {
  int? _col;
  bool _asc = true;

  @override
  void didUpdateWidget(SortTable old) {
    super.didUpdateWidget(old);
    if (_col != null && _col! >= widget.cols.length) _col = null;
  }

  /// The text a cell shows (Text, a pill, or the first Text inside a small wrapper), for sorting.
  static String _text(Widget w) {
    if (w is Text) return w.data ?? w.textSpan?.toPlainText() ?? '';
    if (w is StatusPill) return w.text;
    if (w is Padding && w.child != null) return _text(w.child!);
    if (w is Align && w.child != null) return _text(w.child!);
    if (w is SizedBox && w.child != null) return _text(w.child!);
    if (w is Tooltip && w.child != null) return _text(w.child!);
    return '';
  }

  static final _date = RegExp(r'^(\d{2})-(\d{2})-(\d{4})');
  static final _num = RegExp(r'^-?[₹\s]*-?[\d,]*\.?\d+');

  static Comparable _key(Widget w) {
    final s = _text(w).trim();
    final d = _date.firstMatch(s);
    if (d != null) return '${d[3]}${d[2]}${d[1]}${s.substring(d.end)}';
    final m = _num.firstMatch(s);
    if (m != null && m.end >= s.length - 4) {
      final v = double.tryParse(m[0]!.replaceAll(RegExp(r'[₹,\s]'), ''));
      if (v != null) return v;
    }
    return s.toLowerCase();
  }

  static int _cmp(Comparable a, Comparable b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is num) return -1; // numbers before text (e.g. "Never")
    if (b is num) return 1;
    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    var rows = widget.rows;
    final c = _col;
    if (c != null) {
      // a closing "Total" row stays at the bottom
      final pinned = rows.isNotEmpty && rows.last.isNotEmpty && _text(rows.last.first).trim().toLowerCase().startsWith('total');
      final body = pinned ? rows.sublist(0, rows.length - 1) : rows;
      final keyed = [for (final r in body) (c < r.length ? _key(r[c]) : '', r)];
      keyed.sort((x, y) => _asc ? _cmp(x.$1, y.$1) : _cmp(y.$1, x.$1));
      rows = [for (final k in keyed) k.$2, if (pinned) rows.last];
    }
    return Card(
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
              sortColumnIndex: c,
              sortAscending: _asc,
              columns: [
                for (var i = 0; i < widget.cols.length; i++)
                  DataColumn(
                    label: Text(widget.cols[i].toUpperCase()),
                    numeric: widget.numeric.contains(i),
                    onSort: widget.cols[i].trim().isEmpty ? null : (i, asc) => setState(() {
                          _col = i;
                          _asc = asc;
                        }),
                  )
              ],
              rows: [
                for (final r in rows)
                  DataRow(cells: [for (final cell in r) DataCell(ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxCell), child: cell))])
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
  return d?.toIso8601String().substring(0, 10);
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
          color: Palette.card,
          borderRadius: BorderRadius.circular(DS.radiusCard),
          border: Border.all(color: Palette.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Flexible(child: Text(title!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.ink))),
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
        decoration: BoxDecoration(color: Palette.card, borderRadius: BorderRadius.circular(DS.radiusCard), border: Border.all(color: Palette.line)),
        child: Wrap(spacing: 18, runSpacing: DS.s8, children: [
          for (final it in items)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 104),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(it.label, style: TextStyle(color: Palette.muted, fontSize: 12)),
                Text(it.value, style: tabular.copyWith(fontSize: 14.5, fontWeight: it.strong ? FontWeight.w700 : FontWeight.w500, color: it.tint ?? Palette.ink)),
              ]),
            ),
        ]),
      );
}

/// A small coloured label for a state (Sale, Not yet, Retailer…).
class StatusPill extends StatelessWidget {
  final String text;
  final Color? tint;
  const StatusPill(this.text, {super.key, this.tint});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final c = tint ?? Palette.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.s8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: DS.tint), borderRadius: BorderRadius.circular(999)),
      child: Text(text, maxLines: 1, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
