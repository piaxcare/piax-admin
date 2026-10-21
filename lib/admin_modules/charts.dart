import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dashboard_images.dart';
import 'insights.dart';

// The dashboard's charts (fl_chart, plus a hand-drawn bar list): a donut with a legend, ranked horizontal bars, a
// column chart and a smooth multi-line trend. All animate in, show exact numbers on touch, and say "no data yet"
// instead of drawing an empty frame.

const _muted = Color(0xFF5A6C68);
const _grid = Color(0xFFE6EEEB);

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
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: Color(0x0F0B5B4E), blurRadius: 18, offset: Offset(0, 6))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
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

/// Donut of [slices] with the total in the middle and a legend (count and share) beside or below it.
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.slices, this.centerLabel = 'total', this.size = 148, this.horizontal});
  final List<Slice> slices;
  final String centerLabel;
  final double size;

  /// Legend beside the ring (true) or below it (false). Null: decided from the space available.
  final bool? horizontal;

  /// Whether a card [width] wide has room for the legend beside a ring of [size].
  static bool fitsBeside(double width, {double size = 148}) => width >= size + 190;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<int>(0, (a, s) => a + s.count);
    if (total == 0) return const _Empty();
    final shown = [for (final s in widget.slices) if (s.count > 0) s];
    final focus = _touched != null && _touched! < shown.length ? shown[_touched!] : null;
    final ring = widget.size;
    final donut = SizedBox(
      width: ring,
      height: ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 2.5,
              centerSpaceRadius: ring * 0.31,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) => setState(() {
                  _touched = event.isInterestedForInteractions ? response?.touchedSection?.touchedSectionIndex : null;
                  if (_touched != null && _touched! < 0) _touched = null;
                }),
              ),
              sections: [
                for (final (i, s) in shown.indexed)
                  PieChartSectionData(value: s.count.toDouble(), color: s.color, radius: ring * (i == _touched ? 0.19 : 0.16), showTitle: false),
              ],
            ),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${focus?.count ?? total}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
              SizedBox(
                width: ring * 0.55,
                child: Text(focus?.label ?? widget.centerLabel, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in widget.slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Flexible(child: Text(s.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                const SizedBox(width: 8),
                Text('${s.count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('  ${(s.count * 100 / total).round()}%', style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ),
      ],
    );
    Widget lay(bool beside) => beside
        ? Row(children: [donut, const SizedBox(width: 22), Flexible(child: legend)])
        : Column(children: [donut, const SizedBox(height: 14), legend]);
    if (widget.horizontal != null) return lay(widget.horizontal!);
    return LayoutBuilder(builder: (context, box) => lay(box.maxWidth >= ring + 190));
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

/// Ranked horizontal bars, biggest first: "which city / plan / article has the most". [format] writes the values.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.slices, this.format});
  final List<Slice> slices;
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
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
                  if (s.image != null) ...[AssetThumb(s.image!, size: 38, radius: 10), const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      Text(format?.call(s.count) ?? '${s.count}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Stack(
                      children: [
                        Container(height: 8, color: const Color(0xFFEDF2F0)),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: s.count / top),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, f, _) => FractionallySizedBox(
                            widthFactor: f,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                gradient: LinearGradient(colors: [s.color.withValues(alpha: 0.75), s.color]),
                              ),
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
    final shown = [for (final s in slices) if (s.count > 0) s];
    if (shown.isEmpty) return Container(height: height, decoration: BoxDecoration(color: const Color(0xFFEDF2F0), borderRadius: BorderRadius.circular(99)));
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
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItem: (group, _, rod, _) => BarTooltipItem('${slices[group.x].label}: ${rod.toY.toInt()}', const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ),
          barGroups: [
            for (final (i, s) in slices.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: s.count.toDouble(),
                  width: 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [s.color.withValues(alpha: 0.65), s.color]),
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
              gridData: FlGridData(drawVerticalLine: false, horizontalInterval: top <= 4 ? 1 : (top / 4).ceilToDouble(), getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 1, dashArray: [4, 4])),
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
                  getTooltipColor: (_) => const Color(0xFF1E293B),
                  getTooltipItems: (spots) => [
                    for (final (i, s) in spots.indexed)
                      LineTooltipItem(
                        '${i == 0 ? 'Week of ${week(s.x.toInt())}\n' : ''}${series[s.barIndex].$1}: ${s.y.toInt()}',
                        TextStyle(color: Colors.white, fontSize: 12, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500),
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
                    barWidth: 2.6,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [s.$2.withValues(alpha: 0.16), s.$2.withValues(alpha: 0)]),
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
