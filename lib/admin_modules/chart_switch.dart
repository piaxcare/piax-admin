import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart' show brand;
import 'insights.dart' show Slice;
import 'package:piax_orders_admin/palette.dart';

// Every chart in the admin can be redrawn as another kind: the chart-type button at the top right of its card (or of
// the chart itself, outside a card) offers pie, donut, bars, line, area and scatter, or the chart as designed. The
// choice is kept per card on this device.
//
// A chart widget passes its numbers to [SwitchableChart]; the card around it ([ChartSwitchHost], used by DashCard and
// ChartCard) shows the button once a switchable chart is inside it.

enum ChartKind {
  original('As designed', Icons.auto_graph),
  pie('Pie', Icons.pie_chart),
  donut('Donut', Icons.donut_large),
  bar('Bars', Icons.bar_chart),
  barH('Horizontal bars', Icons.align_horizontal_left),
  line('Line', Icons.show_chart),
  area('Area', Icons.area_chart),
  scatter('Scatter', Icons.scatter_plot);

  const ChartKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What a chart's numbers are, which decides the kinds that make sense for them.
enum ChartShape {
  /// Parts of a whole, in no particular order (channels, statuses, cities): pie, donut, bars.
  parts,

  /// Points in time, in order (days, weeks, months): bars, line, area, scatter. Never a pie: a week isn't a share.
  series,

  /// Steps one after another (a funnel): bars, line, area.
  stages,
}

/// A chart's numbers, whatever it looks like as designed: one value per label, each with its colour.
class ChartData {
  const ChartData({required this.labels, required this.values, this.colors = const [], this.format, this.shape = ChartShape.parts, this.looksLike});
  final List<String> labels;
  final List<num> values;
  final List<Color> colors;
  final String Function(num value)? format;
  final ChartShape shape;

  /// The kind the chart already looks like as designed, left out of the choices (no point switching to it).
  final ChartKind? looksLike;

  ChartData.slices(List<Slice> slices, {String Function(int)? format, this.looksLike})
    : labels = [for (final s in slices) s.label],
      values = [for (final s in slices) s.count],
      colors = [for (final s in slices) s.color],
      format = format == null ? null : ((v) => format(v.round())),
      shape = ChartShape.parts;

  bool get isEmpty => values.isEmpty || values.every((v) => v == 0);

  /// The kinds these numbers can be drawn as, "as designed" first. Only that one when there's too little to chart
  /// (fewer than two values, or all zero), so no button shows.
  List<ChartKind> get kinds {
    final nonZero = values.where((v) => v != 0).length;
    if (values.length < 2 || nonZero == 0) return const [ChartKind.original];
    // A pie needs parts that add up to a whole: at least two of them, none negative, and few enough to tell apart.
    final pie = shape == ChartShape.parts && nonZero >= 2 && values.length <= 12 && !values.any((v) => v < 0);
    // Lines join points in order: only for time and steps, with at least three points.
    final ordered = shape != ChartShape.parts && values.length >= 3;
    return [
      ChartKind.original,
      for (final k in ChartKind.values.skip(1))
        if (k != looksLike &&
            switch (k) {
              ChartKind.pie || ChartKind.donut => pie,
              ChartKind.bar => true,
              ChartKind.barH => shape != ChartShape.series,
              ChartKind.line || ChartKind.area => ordered,
              ChartKind.scatter => shape == ChartShape.series && values.length >= 3,
              ChartKind.original => false,
            })
          k,
    ];
  }

  static const _palette = [
    TColor(0xFF0F8A6F), TColor(0xFF5B3F73), TColor(0xFFE0A33A), TColor(0xFF3C7DC4), TColor(0xFFC8553D),
    TColor(0xFF6BBF9F), TColor(0xFF9A7BB8), TColor(0xFF2F4858), TColor(0xFFB8860B), TColor(0xFF7A8C88),
  ];

  Color color(int i) => i < colors.length ? colors[i] : _palette[i % _palette.length];

  /// The same numbers in [palette]'s colours, one per value in turn.
  ChartData recolored(List<Color> palette) => ChartData(
    labels: labels,
    values: values,
    colors: [for (var i = 0; i < values.length; i++) palette[i % palette.length]],
    format: format,
    shape: shape,
    looksLike: looksLike,
  );

  /// Whether a colour scheme can be applied while the chart stays as designed: it's redrawn as [looksLike] in the new
  /// colours. Charts that don't look like one of the kinds keep their own colours until another kind is picked.
  bool get recolorable => looksLike != null && kinds.length > 1;
  String show(num v) => format?.call(v) ?? NumberFormat.compact(locale: 'en_IN').format(v);
}

/// A named set of chart colours, picked in the chart-type menu.
class ChartPalette {
  const ChartPalette(this.key, this.label, this.colors);
  final String key, label;
  final List<Color> colors;

  /// Shades of one colour the team picked: the colour itself, then darker and lighter steps, alternating so
  /// neighbouring parts stay easy to tell apart.
  factory ChartPalette.custom(Color c) {
    final h = HSLColor.fromColor(c);
    double l(double d) => (h.lightness + d).clamp(.12, .88);
    return ChartPalette('custom:${c.toARGB32().toRadixString(16).padLeft(8, '0')}', 'Custom', [
      for (final d in const [0.0, -.16, .16, -.28, .28, -.08, .08, .22]) h.withLightness(l(d)).toColor(),
    ]);
  }

  static ChartPalette? byKey(String? key) {
    if (key == null) return null;
    if (key.startsWith('custom:')) {
      final v = int.tryParse(key.substring(7), radix: 16);
      return v == null ? null : ChartPalette.custom(Color(v));
    }
    return chartPalettes.where((p) => p.key == key).firstOrNull;
  }
}

const chartPalettes = [
  ChartPalette('brand', 'PIAX green', [Color(0xFF0B5B4E), Color(0xFF0F8A6F), Color(0xFF3FA98B), Color(0xFF6BBF9F), Color(0xFF1F3D36), Color(0xFFA3D9C5)]),
  ChartPalette('ocean', 'Ocean', [Color(0xFF1D4E89), Color(0xFF3C7DC4), Color(0xFF0B7A75), Color(0xFF5FA8D3), Color(0xFF2E5266), Color(0xFF8CC9E8)]),
  ChartPalette('sunset', 'Sunset', [Color(0xFFC8553D), Color(0xFFE0A33A), Color(0xFFD1495B), Color(0xFFF28F3B), Color(0xFF8A5A00), Color(0xFFF6C667)]),
  ChartPalette('berry', 'Berry', [Color(0xFF5B3F73), Color(0xFFC05299), Color(0xFF9A7BB8), Color(0xFF7E2E84), Color(0xFF3D2645), Color(0xFFD4A5D6)]),
  ChartPalette('vivid', 'Vivid', [Color(0xFF0F8A6F), Color(0xFF3C7DC4), Color(0xFFE0A33A), Color(0xFFC8553D), Color(0xFF5B3F73), Color(0xFF2F4858)]),
  ChartPalette('mono', 'Graphite', [Color(0xFF2F3E3B), Color(0xFF6F827E), Color(0xFF4F625E), Color(0xFF93A39F), Color(0xFF1C2624), Color(0xFFB9C6C3)]),
];

/// Which kind and colours each card shows (by its title), kept on this device.
class ChartPrefs extends ChangeNotifier {
  ChartPrefs._() {
    SharedPreferences.getInstance().then((p) {
      try {
        final j = jsonDecode(p.getString(_key) ?? '{}') as Map<String, dynamic>;
        for (final e in j.entries) {
          final k = ChartKind.values.where((k) => k.name == e.value).firstOrNull;
          if (k != null) _kinds.putIfAbsent(e.key, () => k); // a choice made while loading wins
        }
        final c = jsonDecode(p.getString(_colorKey) ?? '{}') as Map<String, dynamic>;
        for (final e in c.entries) {
          _colors.putIfAbsent(e.key, () => '${e.value}');
        }
        if (_kinds.isNotEmpty || _colors.isNotEmpty) notifyListeners();
      } catch (_) {
        // Unreadable: every chart as designed.
      }
    }).catchError((_) {});
  }
  static const _colorKey = 'chart_colours';
  final _colors = <String, String>{};

  /// The colour scheme picked for a card, or null for the chart's own colours.
  ChartPalette? paletteOf(String id) => debugPalette ?? ChartPalette.byKey(_colors[id]);

  /// Tests: every chart in this colour scheme.
  ChartPalette? debugPalette;

  void setPalette(String id, ChartPalette? palette) {
    palette == null ? _colors.remove(id) : _colors[id] = palette.key;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_colorKey, jsonEncode(_colors))).catchError((_) => false);
  }
  static final instance = ChartPrefs._();
  static const _key = 'chart_kinds';
  final _kinds = <String, ChartKind>{};

  ChartKind of(String id) => debugForce ?? _kinds[id] ?? ChartKind.original;

  /// Tests: every chart asked to draw as this kind (each still falls back where the kind doesn't fit its data).
  ChartKind? debugForce;

  void set(String id, ChartKind kind) {
    kind == ChartKind.original ? _kinds.remove(id) : _kinds[id] = kind;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode({for (final e in _kinds.entries) e.key: e.value.name})))
        .catchError((_) => false);
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.host, required this.kind, required this.palette, required super.child});
  final _ChartSwitchHostState host;
  final ChartKind kind;
  final ChartPalette? palette;

  @override
  bool updateShouldNotify(_Scope old) => old.kind != kind || old.palette?.key != palette?.key;
}

/// Around a card: builds it with the chart-type button for its header ([button] is null until a switchable chart is
/// inside), and tells the charts inside which kind to draw.
class ChartSwitchHost extends StatefulWidget {
  const ChartSwitchHost({super.key, required this.id, required this.builder});

  /// Names the card (its title) for the kept choice.
  final String id;
  final Widget Function(BuildContext context, Widget? button) builder;

  @override
  State<ChartSwitchHost> createState() => _ChartSwitchHostState();
}

class _ChartSwitchHostState extends State<ChartSwitchHost> {
  /// The kinds each chart in the card can be drawn as, while it's on screen.
  final _charts = <Object, List<ChartKind>>{};
  final _recolorable = <Object>{};

  /// The kinds every chart in the card shares, and whether colours can be changed on the chart as designed.
  List<ChartKind> _available = const [ChartKind.original];
  bool _colorable = false;
  bool _settling = false;

  void _collect(Object chart, List<ChartKind> kinds, {required bool recolorable}) {
    final was = _recolorable.contains(chart);
    if (listEquals(_charts[chart], kinds) && was == recolorable) return;
    _charts[chart] = kinds;
    recolorable ? _recolorable.add(chart) : _recolorable.remove(chart);
    _later();
  }

  void _remove(Object chart) {
    _recolorable.remove(chart);
    if (_charts.remove(chart) != null) _later();
  }

  // After the frame: the charts tell the card while they build.
  void _later() {
    if (_settling) return;
    _settling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settling = false;
      if (!mounted) return;
      final shared = _charts.values.fold<List<ChartKind>?>(null, (a, k) => a == null ? k : [for (final x in a) if (k.contains(x)) x]) ?? const [ChartKind.original];
      final colorable = _recolorable.isNotEmpty;
      if (!listEquals(shared, _available) || colorable != _colorable) {
        setState(() => (_available = shared, _colorable = colorable));
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ChartPrefs.instance,
    builder: (context, _) {
      final available = _available;
      // A kept choice that doesn't fit the data shown now (after a filter, say) falls back to the chart as designed.
      final saved = ChartPrefs.instance.of(widget.id);
      final kind = available.contains(saved) ? saved : ChartKind.original;
      final palette = ChartPrefs.instance.paletteOf(widget.id);
      // Colours can be changed once there's a chart to colour: another kind is picked, or the chart as designed can
      // be redrawn in new colours.
      final colors = kind != ChartKind.original || _colorable;
      return _Scope(
        host: this,
        kind: kind,
        palette: palette,
        child: Builder(
          builder: (context) => widget.builder(
            context,
            available.length < 2 && !colors
                ? null
                : ChartKindButton(
                    kind: kind,
                    kinds: available,
                    palette: colors ? palette : null,
                    canColor: colors,
                    onSelected: (k) => ChartPrefs.instance.set(widget.id, k),
                    onPalette: (p) => ChartPrefs.instance.setPalette(widget.id, p),
                  ),
          ),
        ),
      );
    },
  );
}

/// The chart-type button: a menu of the kinds that fit the data (the current one ticked), then the colour schemes,
/// with a custom colour of the team's own.
class ChartKindButton extends StatelessWidget {
  const ChartKindButton({
    super.key,
    required this.kind,
    required this.onSelected,
    this.kinds = ChartKind.values,
    this.palette,
    this.canColor = false,
    this.onPalette,
  });
  final ChartKind kind;
  final ValueChanged<ChartKind> onSelected;

  /// The kinds that fit the chart's data.
  final List<ChartKind> kinds;

  /// The colour scheme in use (null: the chart's own), whether colours can be changed, and how to change them.
  final ChartPalette? palette;
  final bool canColor;
  final ValueChanged<ChartPalette?>? onPalette;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ChartKind>(
    tooltip: 'Chart type & colours',
    initialValue: kind,
    onSelected: onSelected,
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
    itemBuilder: (_) => [
      if (kinds.length > 1) ...[
        const _MenuHeading('Chart type'),
        for (final k in kinds)
          PopupMenuItem(
            value: k,
            height: 40,
            child: Row(children: [
              Icon(k.icon, size: 18, color: k == kind ? brand : const TColor(0xFF5A6C68)),
              const SizedBox(width: 10),
              Expanded(child: Text(k.label, style: TextStyle(fontWeight: k == kind ? FontWeight.w700 : FontWeight.w500))),
              if (k == kind) const Icon(Icons.check, size: 16, color: brand),
            ]),
          ),
      ],
      if (canColor && onPalette != null) ...[
        if (kinds.length > 1) const PopupMenuDivider(),
        _PaletteRow(palette: palette, onPalette: onPalette!),
      ],
    ],
    child: Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: palette?.colors.first ?? brand,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: (palette?.colors.first ?? brand).withValues(alpha: .25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Icon(kind.icon, size: 17, color: Colors.white),
    ),
  );
}

class _MenuHeading extends PopupMenuEntry<ChartKind> {
  const _MenuHeading(this.text);
  final String text;

  @override
  double get height => 30;
  @override
  bool represents(ChartKind? value) => false;
  @override
  State<_MenuHeading> createState() => _MenuHeadingState();
}

class _MenuHeadingState extends State<_MenuHeading> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Text(widget.text.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: TColor(0xFF7A8C88))),
  );
}

/// The colour schemes in the menu: the chart's own colours, each scheme as a swatch, and a custom colour.
class _PaletteRow extends PopupMenuEntry<ChartKind> {
  const _PaletteRow({required this.palette, required this.onPalette});
  final ChartPalette? palette;
  final ValueChanged<ChartPalette?> onPalette;

  @override
  double get height => 120;
  @override
  bool represents(ChartKind? value) => false;
  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  void _pick(ChartPalette? p) {
    widget.onPalette(p);
    Navigator.pop(context);
  }

  Future<void> _custom() async {
    final nav = Navigator.of(context);
    final start = widget.palette?.key.startsWith('custom:') == true ? widget.palette!.colors.first : brand;
    nav.pop();
    final picked = await showDialog<Color>(context: nav.context, builder: (_) => _ColorDialog(initial: start));
    if (picked != null) widget.onPalette(ChartPalette.custom(picked));
  }

  Widget _swatch({required String tip, required bool on, required VoidCallback onTap, required Widget child}) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? brand : Colors.transparent, width: 2)),
        child: ClipOval(child: SizedBox.expand(child: child)),
      ),
    ),
  );

  /// A scheme's swatch: its first three colours as equal slices of a circle.
  Widget _wheel(List<Color> colors) {
    final c = colors.take(3).toList();
    return DecoratedBox(
      key: const ValueKey('palette-swatch'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          transform: const GradientRotation(-math.pi / 2), // the first slice starts at the top
          colors: [for (final x in c) ...[x, x]],
          stops: [for (var i = 0; i < c.length; i++) ...[i / c.length, (i + 1) / c.length]],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.palette?.key;
    final custom = current?.startsWith('custom:') == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('COLOURS', style: TextStyle(fontSize: 10.5, letterSpacing: .8, fontWeight: FontWeight.w700, color: TColor(0xFF7A8C88))),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 4, children: [
          _swatch(
            tip: 'Chart’s own colours',
            on: current == null,
            onTap: () => _pick(null),
            child: const ColoredBox(color: TColor(0xFFF1F4F3), child: Icon(Icons.format_color_reset_outlined, size: 16, color: TColor(0xFF5A6C68))),
          ),
          for (final p in chartPalettes) _swatch(tip: p.label, on: current == p.key, onTap: () => _pick(p), child: _wheel(p.colors)),
          _swatch(
            tip: 'Custom colour…',
            on: custom,
            onTap: _custom,
            child: custom
                ? _wheel(widget.palette!.colors)
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SweepGradient(colors: [Color(0xFFE53935), Color(0xFFFDD835), Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFF8E24AA), Color(0xFFE53935)]),
                    ),
                    child: Icon(Icons.add, size: 16, color: Colors.white),
                  ),
          ),
        ]),
      ]),
    );
  }
}

/// Picks one colour for a custom scheme: a grid of colours, or a hex code, with a preview of the shades it makes.
class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late Color _color = widget.initial;
  late final _hex = TextEditingController(text: _hexOf(widget.initial));

  static String _hexOf(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  static const _choices = [
    Color(0xFF0B5B4E), Color(0xFF0F8A6F), Color(0xFF2E7D32), Color(0xFF558B2F), Color(0xFF00838F), Color(0xFF0277BD),
    Color(0xFF1D4E89), Color(0xFF283593), Color(0xFF4527A0), Color(0xFF5B3F73), Color(0xFF6A1B9A), Color(0xFFAD1457),
    Color(0xFFC62828), Color(0xFFC8553D), Color(0xFFD84315), Color(0xFFEF6C00), Color(0xFFE0A33A), Color(0xFF9E7700),
    Color(0xFF5D4037), Color(0xFF455A64), Color(0xFF2F3E3B), Color(0xFF37474F), Color(0xFF16302B), Color(0xFF000000),
  ];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(Color c) => setState(() {
    _color = c;
    _hex.text = _hexOf(c);
  });

  @override
  Widget build(BuildContext context) {
    final shades = ChartPalette.custom(_color).colors;
    return AlertDialog(
      title: const Text('Custom chart colour'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _choices)
              InkWell(
                onTap: () => _set(c),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.toARGB32() == _color.toARGB32() ? const TColor(0xFF0C1C19) : Colors.white, width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3)],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _hex,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Hex code', prefixText: '#', counterText: '', isDense: true),
            onChanged: (v) {
              final n = int.tryParse(v.trim(), radix: 16);
              if (v.trim().length == 6 && n != null) setState(() => _color = Color(0xFF000000 | n));
            },
          ),
          const SizedBox(height: 14),
          const Text('Shades used in the chart', style: TextStyle(fontSize: 12, color: TColor(0xFF5A6C68))),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 22,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in shades) Expanded(child: ColoredBox(color: c))]),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Use colour')),
      ],
    );
  }
}

/// A chart that can be redrawn as another kind: [original] as designed, else [data] drawn as the card's choice.
/// Outside a card it carries its own chart-type button.
class SwitchableChart extends StatelessWidget {
  const SwitchableChart({super.key, required this.id, required this.data, required this.original});

  /// Names the chart for the kept choice when it's outside a card.
  final String id;
  final ChartData data;
  final Widget original;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    if (scope == null) {
      return ChartSwitchHost(
        id: id,
        builder: (context, button) => Stack(children: [
          Padding(padding: EdgeInsets.only(top: button == null ? 0 : 40), child: _Drawn(data: data, original: original)),
          if (button != null) Positioned(top: 0, right: 0, child: button),
        ]),
      );
    }
    return _Drawn(data: data, original: original);
  }
}

class _Drawn extends StatefulWidget {
  const _Drawn({required this.data, required this.original});
  final ChartData data;
  final Widget original;

  @override
  State<_Drawn> createState() => _DrawnState();
}

class _DrawnState extends State<_Drawn> {
  _ChartSwitchHostState? _host;

  @override
  void dispose() {
    _host?._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final original = widget.original;
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    final kinds = widget.data.kinds;
    if (!identical(_host, scope?.host)) _host?._remove(this);
    _host = scope?.host;
    _host?._collect(this, kinds, recolorable: widget.data.recolorable);
    final palette = scope?.palette;
    final data = palette == null ? widget.data : widget.data.recolored(palette.colors);
    final kind = scope?.kind ?? ChartKind.original;
    if (kind == ChartKind.original || !kinds.contains(kind)) {
      // As designed, in new colours: redrawn as the kind it looks like.
      if (palette != null && widget.data.recolorable) return _FillBox(child: AnyChart(kind: widget.data.looksLike!, data: data));
      return original;
    }
    return _FillBox(child: AnyChart(kind: kind, data: data));
  }
}

/// Gives a redrawn chart all the room it's offered, or 240 px of height where the height is open (a card sized to
/// its content). Unlike a LayoutBuilder it can be measured, so it works in rows sized to their tallest card
/// (IntrinsicHeight).
class _FillBox extends SingleChildRenderObjectWidget {
  const _FillBox({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillBox();
}

class _RenderFillBox extends RenderProxyBox {
  static const _height = 240.0, _width = 320.0;

  @override
  double computeMinIntrinsicHeight(double width) => _height;
  @override
  double computeMaxIntrinsicHeight(double width) => _height;
  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => _width;

  @override
  void performLayout() {
    final c = constraints;
    size = c.constrain(Size(c.hasBoundedWidth ? c.maxWidth : _width, c.hasBoundedHeight ? c.maxHeight : _height));
    child?.layout(BoxConstraints.tight(size));
  }
}

/// [data] drawn as [kind], filling the space it's given. Laid out for the room it has: axis labels thin out so
/// they never collide, figures on the axis are compact (₹4.8L), long names are shortened, and a pie's legend shows
/// the biggest parts with "+n more".
class AnyChart extends StatelessWidget {
  const AnyChart({super.key, required this.kind, required this.data});
  final ChartKind kind;
  final ChartData data;

  static const _muted = TColor(0xFF7A8C88);
  static const _grid = TColor(0xFFE9EFED);
  static const _tipBg = Color(0xFF16302B);
  static const _tipText = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500, height: 1.35);
  static const _axisText = TextStyle(fontSize: 10.5, color: _muted);
  static const _anim = Duration(milliseconds: 350);

  /// Parts each keep their colour; points in time or steps share one, so the eye follows the trend.
  Color _c(int i) => data.shape == ChartShape.parts ? data.color(i) : data.color(0);

  bool get _money => data.labels.isNotEmpty && data.show(1).contains('₹');

  /// A figure for an axis: short, so the axis stays narrow.
  String _axis(num v) => _money
      ? NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v)
      : NumberFormat.compact(locale: 'en_IN').format(v);

  static String _short(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => switch (kind) {
      ChartKind.pie || ChartKind.donut => _pie(box),
      ChartKind.barH => _barsAcross(box),
      ChartKind.bar => _bars(box),
      ChartKind.scatter => _scatter(box),
      _ => _line(box, area: kind == ChartKind.area),
    },
  );

  Widget _legend(List<int> order, int max) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      for (final i in order.take(max))
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: data.color(i), borderRadius: BorderRadius.circular(2.5))),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${data.labels[i]}  ', style: const TextStyle(color: _muted)),
                TextSpan(text: data.show(data.values[i]), style: const TextStyle(fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19))),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ]),
      if (order.length > max) Text('+${order.length - max} more', style: const TextStyle(fontSize: 11.5, color: _muted)),
    ],
  );

  Widget _pie(BoxConstraints box) {
    final total = data.values.fold<num>(0, (a, v) => a + v);
    // Biggest first in the legend; the slices keep their order around the ring.
    final order = [for (var i = 0; i < data.values.length; i++) if (data.values[i] > 0) i]..sort((a, b) => data.values[b].compareTo(data.values[a]));
    final beside = box.maxWidth >= 360 && box.maxWidth > box.maxHeight * 1.25;
    final ring = math.max(80.0, math.min(beside ? box.maxHeight : box.maxHeight - 56, beside ? box.maxWidth * .48 : box.maxWidth));
    final donut = kind == ChartKind.donut;
    final chart = SizedBox(
      width: ring,
      height: ring,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(
          duration: _anim,
          curve: Curves.easeOutCubic,
          PieChartData(
            sectionsSpace: data.values.length > 1 ? 2 : 0,
            centerSpaceRadius: donut ? ring * .3 : 0,
            startDegreeOffset: -90,
            sections: [
              for (final i in [for (var i = 0; i < data.values.length; i++) i])
                if (data.values[i] > 0)
                  PieChartSectionData(
                    value: data.values[i].toDouble(),
                    color: data.color(i),
                    radius: donut ? ring * .18 : ring / 2,
                    // A share only where the slice is big enough to hold it.
                    title: total == 0 || data.values[i] / total < .08 || ring < 120 ? '' : '${(data.values[i] * 100 / total).round()}%',
                    titlePositionPercentageOffset: donut ? .5 : .62,
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
            ],
          ),
        ),
        if (donut && ring >= 120)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_axis(total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: TColor(0xFF0C1C19))),
            const Text('total', style: TextStyle(fontSize: 10.5, color: _muted)),
          ]),
      ]),
    );
    final legendRows = beside ? math.max(2, (box.maxHeight / 24).floor()) : math.max(2, ((box.maxHeight - ring - 12) / 22).floor() * 2);
    final legend = _legend(order, math.min(legendRows, 8));
    return beside
        ? Row(children: [chart, const SizedBox(width: 20), Expanded(child: Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(child: legend)))])
        : Column(children: [Center(child: chart), const SizedBox(height: 12), Expanded(child: SingleChildScrollView(child: legend))]);
  }

  Widget _barsAcross(BoxConstraints box) {
    final top = math.max<num>(1, data.values.fold<num>(0, math.max));
    final labelW = (box.maxWidth * .28).clamp(64.0, 170.0);
    final valueW = (box.maxWidth * .18).clamp(48.0, 96.0);
    final rows = data.values.length;
    final rowH = (box.maxHeight / math.max(1, rows)).clamp(26.0, 40.0);
    return SingleChildScrollView(
      child: Column(children: [
        for (final (i, v) in data.values.indexed)
          SizedBox(
            height: rowH,
            child: Row(children: [
              SizedBox(width: labelW, child: Text(data.labels[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
              const SizedBox(width: 10),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: v / top),
                  duration: _anim,
                  curve: Curves.easeOutCubic,
                  builder: (context, f, _) => Stack(children: [
                    Container(height: 10, decoration: BoxDecoration(color: const TColor(0xFFEDF2F0), borderRadius: BorderRadius.circular(99))),
                    FractionallySizedBox(
                      widthFactor: f.clamp(0.0, 1.0),
                      child: Container(height: 10, decoration: BoxDecoration(color: _c(i), borderRadius: BorderRadius.circular(99))),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: valueW,
                child: Text(data.show(v), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ]),
    );
  }

  double get _top {
    final top = math.max<num>(1, data.values.fold<num>(0, math.max)).toDouble();
    return top * 1.12;
  }

  double get _bottom {
    final low = data.values.fold<num>(0, math.min).toDouble();
    return low < 0 ? low * 1.12 : 0;
  }

  /// Axis titles that fit: as many bottom labels as there's room for (about 64 px each), names shortened to fit.
  FlTitlesData _titles(BoxConstraints box) {
    // Too small for axes (a sparkline in a summary card): the shape alone, figures on hover.
    if (box.maxHeight < 130 || box.maxWidth < 200) return const FlTitlesData(show: false);
    final n = data.labels.length;
    final room = math.max(1, (box.maxWidth - 48) ~/ 64);
    final every = math.max(1, (n / room).ceil());
    final chars = math.max(4, ((box.maxWidth - 48) / math.min(n, room) / 6.2).floor());
    final span = _top - _bottom;
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: span <= 4 ? 1 : span / 4,
          getTitlesWidget: (v, meta) => v == meta.max ? const SizedBox.shrink() : Text(_axis(v), style: _axisText),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if ((v - i).abs() > .01 || i < 0 || i >= n || i % every != 0) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 7), child: Text(_short(data.labels[i], chars), style: _axisText));
          },
        ),
      ),
    );
  }

  FlGridData get _gridData => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: (_top - _bottom) <= 4 ? 1 : (_top - _bottom) / 4,
    getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 1, dashArray: [4, 4]),
  );

  String _tip(int i) => '${data.labels[i]}\n${data.show(data.values[i])}';

  Widget _bars(BoxConstraints box) {
    final n = math.max(1, data.values.length);
    final width = ((box.maxWidth - 60) / n * .55).clamp(4.0, 34.0);
    return BarChart(
      duration: _anim,
      curve: Curves.easeOutCubic,
      BarChartData(
        maxY: _top,
        minY: _bottom,
        alignment: BarChartAlignment.spaceAround,
        gridData: _gridData,
        borderData: FlBorderData(show: false),
        titlesData: _titles(box),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => _tipBg,
            tooltipBorderRadius: BorderRadius.circular(10),
            getTooltipItem: (g, _, _, _) => BarTooltipItem(_tip(g.x), _tipText),
          ),
        ),
        barGroups: [
          for (final (i, v) in data.values.indexed)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: v.toDouble(),
                width: width,
                borderRadius: BorderRadius.vertical(top: Radius.circular(math.min(6, width / 2))),
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [_c(i).withValues(alpha: .75), _c(i)]),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _line(BoxConstraints box, {required bool area}) {
    final c = data.color(0);
    final dots = data.values.length <= math.max(8, box.maxWidth ~/ 40);
    return LineChart(
      duration: _anim,
      curve: Curves.easeOutCubic,
      LineChartData(
        minY: _bottom,
        maxY: _top,
        minX: 0,
        maxX: math.max(1, data.values.length - 1).toDouble(),
        gridData: _gridData,
        borderData: FlBorderData(show: false),
        titlesData: _titles(box),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => _tipBg,
            tooltipBorderRadius: BorderRadius.circular(10),
            getTooltipItems: (spots) => [for (final s in spots) LineTooltipItem(_tip(s.x.round()), _tipText)],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final (i, v) in data.values.indexed) FlSpot(i.toDouble(), v.toDouble())],
            isCurved: true,
            curveSmoothness: .3,
            preventCurveOverShooting: true,
            color: c,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: dots, getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3.5, color: Colors.white, strokeWidth: 2, strokeColor: c)),
            belowBarData: BarAreaData(
              show: area,
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: .32), c.withValues(alpha: .02)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scatter(BoxConstraints box) => ScatterChart(
    duration: _anim,
    curve: Curves.easeOutCubic,
    ScatterChartData(
      minY: _bottom,
      maxY: _top,
      minX: -0.5,
      maxX: data.values.length - .5,
      gridData: _gridData,
      borderData: FlBorderData(show: false),
      titlesData: _titles(box),
      scatterTouchData: ScatterTouchData(
        touchTooltipData: ScatterTouchTooltipData(
          getTooltipColor: (_) => _tipBg,
          tooltipBorderRadius: BorderRadius.circular(10),
          getTooltipItems: (s) => ScatterTooltipItem(_tip(s.x.round()), textStyle: _tipText),
        ),
      ),
      scatterSpots: [
        for (final (i, v) in data.values.indexed)
          ScatterSpot(i.toDouble(), v.toDouble(), dotPainter: FlDotCirclePainter(radius: data.values.length > 30 ? 4 : 6.5, color: _c(i).withValues(alpha: .9), strokeWidth: 2, strokeColor: Colors.white)),
      ],
    ),
  );
}
