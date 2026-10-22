import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dashboard_images.dart';
import 'insights.dart';
import 'package:piax_orders_admin/palette.dart';

// The dashboard's charts (fl_chart, plus a hand-drawn bar list): a donut with a legend, ranked horizontal bars, a
// column chart and a smooth multi-line trend. All animate in, show exact numbers on touch, and say "no data yet"
// instead of drawing an empty frame.

const _muted = TColor(0xFF5A6C68);
const _grid = TColor(0xFFE6EEEB);

/// A white card with a title and an optional one-line note, holding one chart.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, this.note, required this.child, this.trailing, this.fill = false});
  final String title;
  final String? note;
  final Widget child;
  final Widget? trailing;

  /// In an [EqualRows] row: the chart is centred in the card's spare height instead of leaving it empty below.
  final bool fill;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: TColor(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: TColor(0x0F0B5B4E), blurRadius: 18, offset: Offset(0, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5))),
            ?trailing,
          ],
        ),
        if (note != null) ...[const SizedBox(height: 3), Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12.5))],
        const SizedBox(height: 14),
        if (fill) Expanded(child: Center(child: child)) else child,
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text('No data yet', style: TextStyle(color: _muted))),
  );
}

/// A ring of [slices]: segments on a light track, a small surface gap between them, drawn in with a sweep. Touching
/// or hovering a segment selects it ([onSelect]); the selected one thickens and the others fade. [center] sits inside.
class SegmentRing extends StatelessWidget {
  const SegmentRing({super.key, required this.slices, required this.size, this.selected, this.onSelect, this.center});
  final List<Slice> slices;
  final double size;
  final int? selected;
  final ValueChanged<int?>? onSelect;
  final Widget? center;

  int? _hit(Offset p) {
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    if (total == 0) return null;
    final c = Offset(size / 2, size / 2), d = p - c;
    final r = d.distance, outer = size / 2, inner = outer - size * 0.2;
    if (r < inner || r > outer) return null;
    var angle = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    var acc = 0.0;
    for (final (i, s) in slices.indexed) {
      acc += s.count / total * 2 * math.pi;
      if (angle <= acc) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 700);
    return SizedBox(
      width: size,
      height: size,
      child: MouseRegion(
        onHover: onSelect == null ? null : (e) => onSelect!(_hit(e.localPosition)),
        onExit: onSelect == null ? null : (_) => onSelect!(null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSelect == null ? null : (e) {
            final hit = _hit(e.localPosition);
            onSelect!(hit == selected ? null : hit);
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion,
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => CustomPaint(painter: _RingPainter(slices, t, selected), child: child),
            child: Center(child: center),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.slices, this.progress, this.selected);
  final List<Slice> slices;
  final double progress;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    final stroke = size.width * 0.13;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - size.width * 0.1);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const TColor(0xFFEEF2F1));
    if (total == 0) return;
    final shown = slices.where((s) => s.count > 0).length;
    final gap = shown > 1 ? 0.035 : 0.0; // radians of surface between segments
    var start = -math.pi / 2;
    for (final (i, s) in slices.indexed) {
      final sweep = s.count / total * 2 * math.pi * progress;
      if (s.count > 0 && sweep > gap) {
        final on = selected == null || selected == i;
        canvas.drawArc(rect, start + gap / 2, sweep - gap, false, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected == i ? stroke + 6 : stroke
          ..color = on ? s.color : s.color.withValues(alpha: 0.28));
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.selected != selected || old.slices != slices;
}

/// A ring of [slices] with the total in the middle and a legend table (count and share) beside or below it. Selecting
/// a part, on the ring or in the legend, shows its count and share in the middle.
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.slices, this.centerLabel = 'total', this.size = 148, this.horizontal});
  final List<Slice> slices;
  final String centerLabel;
  final double size;

  /// Legend beside the ring (true) or below it (false). Null: decided from the space available.
  final bool? horizontal;

  /// Whether a card [width] wide has room for the legend beside a ring of [size].
  static bool fitsBeside(double width, {double size = 148}) => width >= size + 220;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final slices = distinctSlices(widget.slices);
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    if (total == 0) return const _Empty();
    final focus = _selected != null && _selected! < slices.length ? slices[_selected!] : null;
    final ring = SegmentRing(
      slices: slices,
      size: widget.size,
      selected: _selected,
      onSelect: (i) => setState(() => _selected = i),
      center: SizedBox(
        width: widget.size * 0.56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${focus?.count ?? total}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.1, color: TColor(0xFF0C1C19))),
          ),
          const SizedBox(height: 2),
          Text(
            focus == null ? widget.centerLabel : '${focus.label} · ${(focus.count * 100 / total).round()}%',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.25),
          ),
        ]),
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, s) in slices.indexed)
          MouseRegion(
            onEnter: (_) => setState(() => _selected = i),
            onExit: (_) => setState(() => _selected = null),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _selected = _selected == i ? null : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: _selected == i ? const TColor(0xFFF1F6F4) : null, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: TColor(0xFF34443F)))),
                    const SizedBox(width: 8),
                    Text('${s.count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19), fontFeatures: [FontFeature.tabularFigures()])),
                    SizedBox(
                      width: 46,
                      child: Text('${(s.count * 100 / total).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: _muted, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    Widget lay(bool beside) => beside
        ? Row(children: [ring, const SizedBox(width: 24), Expanded(child: legend)])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: ring), const SizedBox(height: 16), legend]);
    if (widget.horizontal != null) return lay(widget.horizontal!);
    return LayoutBuilder(builder: (context, box) => lay(box.maxWidth >= widget.size + 220));
  }
}

/// A grid whose cards in each row share the tallest card's height, so rows line up with no ragged gaps.
class EqualRows extends StatelessWidget {
  const EqualRows({super.key, required this.columns, required this.children, this.gap = 14});
  final int columns;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i += columns) ...[
        if (i > 0) SizedBox(height: gap),
        if (columns == 1)
          children[i]
        else
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: gap),
                  Expanded(child: i + j < children.length ? children[i + j] : const SizedBox()),
                ],
              ],
            ),
          ),
      ],
    ],
  );
}

/// Ranked horizontal bars, biggest first: "which city / plan / article has the most". One measure, so one colour
/// ([color], brand teal): the bars differ by length, and each is labelled. [format] writes the values.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.slices, this.format, this.color = const TColor(0xFF0F8A6F), this.dense = false, this.detail});
  final List<Slice> slices;
  final String Function(int value)? format;
  final Color color;

  /// Thinner bars, smaller pictures and type: for the overview's small cards.
  final bool dense;

  /// A short extra after the value, in grey ("12 orders · 34%").
  final String Function(Slice slice)? detail;

  @override
  Widget build(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final top = slices.fold<int>(0, (a, s) => s.count > a ? s.count : a);
    if (top == 0) return const _Empty();
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    return Column(
      children: [
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Tooltip(
              message: '${s.label}: ${format?.call(s.count) ?? s.count} (${(s.count * 100 / total).round()}%)',
              child: Row(
                children: [
                  if (s.image != null) ...[AssetThumb(s.image!, size: dense ? 32 : 38, radius: 10), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      if (detail != null) Text('${detail!(s)}  ', style: const TextStyle(fontSize: 11.5, color: TColor(0xFF5A6C68))),
                      Text(format?.call(s.count) ?? '${s.count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: const TColor(0xFFEDF2F0)),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: s.count / top),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, f, _) => FractionallySizedBox(
                            widthFactor: f,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(color: s.label == 'Other' ? otherColor : s.color, borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Thin stacked bar of a module's statuses (used on the module summary cards).
class StackedBar extends StatelessWidget {
  const StackedBar({super.key, required this.slices, this.height = 8});
  final List<Slice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final shown = [for (final s in slices) if (s.count > 0) s];
    if (shown.isEmpty) return Container(height: height, decoration: BoxDecoration(color: const TColor(0xFFEDF2F0), borderRadius: BorderRadius.circular(99)));
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Row(
        children: [
          for (final (i, s) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(flex: s.count, child: Tooltip(message: '${s.label}: ${s.count}', child: Container(height: height, color: s.color))),
          ],
        ],
      ),
    );
  }
}

/// Vertical columns with rounded, gradient tops and a touch tooltip (e.g. ratings by stars).
class ColumnChart extends StatelessWidget {
  const ColumnChart({super.key, required this.slices, this.height = 180});
  final List<Slice> slices;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final top = slices.fold<int>(0, (a, s) => s.count > a ? s.count : a);
    if (top == 0) return const _Empty();
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top * 1.2,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(drawVerticalLine: false, horizontalInterval: top <= 4 ? 1 : (top / 4).ceilToDouble(), getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 1)),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: top <= 4 ? 1 : (top / 4).ceilToDouble(),
                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: const TextStyle(color: _muted, fontSize: 11))),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(slices[v.toInt()].label, style: const TextStyle(color: _muted, fontSize: 11.5))),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const TColor(0xFF1E293B),
              getTooltipItem: (group, _, rod, _) => BarTooltipItem('${slices[group.x].label}: ${rod.toY.toInt()}', const TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ),
          barGroups: [
            for (final (i, s) in slices.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: s.count.toDouble(),
                  width: 22,
                  color: s.color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        ),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }
}

/// Smooth weekly lines with soft fills and a legend: [series] is (name, colour, 12 weekly counts, oldest first).
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.series, this.height = 210, this.now});
  final List<(String, Color, List<int>)> series;
  final double height;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final top = series.expand((s) => s.$3).fold<int>(0, (a, b) => b > a ? b : a);
    if (top == 0) return const _Empty();
    final at = now ?? DateTime.now();
    final monday = DateTime(at.year, at.month, at.day).subtract(Duration(days: at.weekday - 1));
    String week(int i) => DateFormat('d MMM').format(monday.subtract(Duration(days: 7 * (11 - i))));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 4, decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(9))),
                const SizedBox(width: 6),
                Text('${s.$1} ${s.$3.fold<int>(0, (a, b) => a + b)}', style: const TextStyle(fontSize: 12.5)),
              ]),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: top * 1.25,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(drawVerticalLine: false, horizontalInterval: top <= 4 ? 1 : (top / 4).ceilToDouble(), getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 1)),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: top <= 4 ? 1 : (top / 4).ceilToDouble(),
                    getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: const TextStyle(color: _muted, fontSize: 11))),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 3,
                    getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(week(v.toInt()), style: const TextStyle(color: _muted, fontSize: 11))),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const TColor(0xFF1E293B),
                  getTooltipItems: (spots) => [
                    for (final (i, s) in spots.indexed)
                      LineTooltipItem(
                        '${i == 0 ? 'Week of ${week(s.x.toInt())}\n' : ''}${series[s.barIndex].$1}: ${s.y.toInt()}',
                        TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [for (final (i, v) in s.$3.indexed) FlSpot(i.toDouble(), v.toDouble())],
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: s.$2,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [s.$2.withValues(alpha: 0.10), s.$2.withValues(alpha: 0)]),
                    ),
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 500),
          ),
        ),
      ],
    );
  }
}

/// The floating "Add" button: bottom right of the list (not over a side panel), 24 px in from both edges.
Widget floatingAdd(String label, VoidCallback onPressed, Widget list) => Stack(
  children: [
    Positioned.fill(child: list),
    Positioned(
      right: 24,
      bottom: 24,
      child: FloatingActionButton.extended(heroTag: null, onPressed: onPressed, icon: const Icon(Icons.add), label: Text(label)),
    ),
  ],
);

/// Around a right-hand side panel (details, add or edit): whether it's full screen, and how to switch. Panels read it
/// to show the full-screen button beside their close button.
class PanelScope extends InheritedWidget {
  const PanelScope({super.key, required this.expanded, required this.onToggle, required super.child});
  final bool expanded;
  final VoidCallback onToggle;

  static PanelScope? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PanelScope>();

  @override
  bool updateShouldNotify(PanelScope old) => old.expanded != expanded;
}

/// The full-screen / back-to-panel button for a side panel's top bar; nothing outside a side panel.
Widget? panelExpandButton(BuildContext context) {
  final scope = PanelScope.of(context);
  if (scope == null) return null;
  return IconButton(
    tooltip: scope.expanded ? 'Back to side panel' : 'Full screen',
    icon: Icon(scope.expanded ? Icons.close_fullscreen : Icons.open_in_full, size: 20),
    onPressed: scope.onToggle,
  );
}
