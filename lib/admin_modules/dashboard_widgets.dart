import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'dashboard_images.dart';
import 'charts.dart' show SegmentRing;
import 'chart_switch.dart';
import 'insights.dart';
import 'package:piax_orders_admin/palette.dart';

// The dashboard's building blocks, laid out like a modern commerce admin (big stat cards with a change badge, an
// activity line chart with a period picker, a half-circle gauge, a ring with a list, progress bars, a step funnel and
// a share bar), in the app's own colours and font: PIAX brand green in shades, no new typeface.

const ink = TColor(0xFF0C1C19);
const muted = TColor(0xFF5A6C68);
const line = TColor(0xFFE6EEEB);
const up = TColor(0xFF0F8A5F);
const down = TColor(0xFFB3261E);

/// Brand green, darkest to lightest: the one-colour family the charts use.
/// For ordered steps only (funnel stages, star ratings), darkest first; checked as an ordinal ramp (one hue, even
/// steps, the lightest still 2.2:1 on white). The last one is a background tint for tracks, never a data colour.
const greens = [TColor(0xFF0B5B4E), TColor(0xFF0F766E), TColor(0xFF2E8F7B), TColor(0xFF4FA48F), TColor(0xFF79BBA8), TColor(0xFFDCEFE8)];

/// A white dashboard card: title on the left, an optional control on the right, then the content.
class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.title, required this.child, this.trailing, this.subtitle, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20)});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ChartSwitchHost(id: title, builder: (context, button) => Container(
    padding: padding,
    decoration: BoxDecoration(color: TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: ink))),
            ?trailing,
            ?button,
          ],
        ),
        if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: const TextStyle(color: muted, fontSize: 12.5))],
        const SizedBox(height: 16),
        Expanded(child: child),
      ],
    ),
  ));
}

/// "See all" link for a card's corner.
class SeeAll extends StatelessWidget {
  const SeeAll({super.key, required this.onTap, this.label = 'See all'});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
    child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

/// "+12.5%" in green or "−4.0%" in red, with what it's compared against under it.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge(this.delta, {super.key, this.boxed = false});
  final Delta delta;

  /// On a tinted pill (the member card), instead of plain text.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final color = delta.up ? up : down;
    final text = Text(delta.text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        boxed
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: text,
              )
            : text,
        const SizedBox(height: 2),
        Text(delta.caption, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    );
  }
}

/// A big number card: label and icon on top, the value and its change below. The first one is highlighted.
class HeadlineStatCard extends StatelessWidget {
  const HeadlineStatCard({super.key, required this.card, this.onTap, this.highlight = false});
  final HeadlineCard card;

  /// Opens what the number is about; without it the card isn't tappable.
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Material(
    color: highlight ? const TColor(0xFFDDF3EC) : TColor(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: highlight ? const TColor(0xFFBFE3D6) : line)),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(card.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 14))),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: highlight ? brand : const TColor(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: highlight ? null : Border.all(color: line),
                  ),
                  child: Icon(card.icon, size: 19, color: highlight ? Colors.white : const TColor(0xFF34443F)),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(card.value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: ink, letterSpacing: -.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomRight, child: DeltaBadge(card.delta))),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A pill menu button in brand green ("Last 12 weeks ▾"), like a dashboard period picker.
class PillPicker<T> extends StatelessWidget {
  const PillPicker({super.key, required this.value, required this.options, required this.label, required this.onChanged});
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: 'Change',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(label(o)))],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label(value), style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFFFFFF), size: 18),
      ]),
    ),
  );
}

/// Activity line chart: a solid line (everything) and a dashed one (what members did), weekly, with a picker for
/// how many weeks to show and a highlighted band under the touched week.
class ActivityCard extends StatefulWidget {
  const ActivityCard({super.key, required this.all, required this.members, this.now});
  final List<int> all, members;
  final DateTime? now;

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final at = widget.now ?? DateTime.now();
    final monday = DateTime(at.year, at.month, at.day).subtract(Duration(days: at.weekday - 1));
    final all = widget.all.sublist(12 - _weeks), members = widget.members.sublist(12 - _weeks);
    String week(int i) => DateFormat('d MMM').format(monday.subtract(Duration(days: 7 * (_weeks - 1 - i))));
    final top = math.max(1, [...all, ...members].fold<int>(0, math.max));
    final step = top <= 4 ? 1.0 : (top / 4).ceilToDouble();
    final peak = all.indexOf(all.reduce(math.max));

    LineChartBarData series(List<int> v, Color c, {bool dashed = false}) => LineChartBarData(
      spots: [for (final (i, n) in v.indexed) FlSpot(i.toDouble(), n.toDouble())],
      isCurved: true,
      preventCurveOverShooting: true,
      curveSmoothness: 0.35,
      color: c,
      barWidth: 2,
      dashArray: dashed ? [6, 5] : null,
      dotData: FlDotData(checkToShowDot: (spot, bar) => !dashed && spot.x.toInt() == peak, getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: c, strokeWidth: 2, strokeColor: Colors.white)),
      belowBarData: BarAreaData(show: !dashed, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: 0.10), c.withValues(alpha: 0)])),
    );

    return DashCard(
      title: 'Activity',
      trailing: PillPicker<int>(value: _weeks, options: const [4, 8, 12], label: (w) => 'Last $w weeks', onChanged: (w) => setState(() => _weeks = w)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 18, runSpacing: 6, children: [
            _legend(chartPalette[0], 'Everything', false),
            _legend(chartPalette[1], 'Member actions', true),
          ]),
          const SizedBox(height: 14),
          Expanded(
            child: SwitchableChart(
              id: 'Activity',
              data: ChartData(labels: [for (var i = 0; i < all.length; i++) week(i)], values: all, shape: ChartShape.series, looksLike: ChartKind.line),
              original: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: top * 1.25,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(drawVerticalLine: false, horizontalInterval: step, getDrawingHorizontalLine: (_) => const FlLine(color: line, strokeWidth: 1)),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: step,
                        getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(v.toInt().toString(), style: const TextStyle(color: muted, fontSize: 11))),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: _weeks <= 4 ? 1 : _weeks <= 8 ? 2 : 3,
                        getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(week(v.toInt()), style: const TextStyle(color: muted, fontSize: 11))),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator: (bar, spots) => [
                      for (final _ in spots)
                        TouchedSpotIndicatorData(
                          FlLine(color: brand.withValues(alpha: 0.07), strokeWidth: 44),
                          FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: brand, strokeWidth: 2, strokeColor: Colors.white)),
                        ),
                    ],
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => TColor(0xFFFFFFFF),
                      tooltipBorder: const BorderSide(color: line),
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipItems: (spots) => [
                        for (final (i, s) in spots.indexed)
                          LineTooltipItem(
                            '${i == 0 ? 'Week of ${week(s.x.toInt())}\n' : ''}${s.barIndex == 0 ? 'Everything' : 'Members'}: ${s.y.toInt()}',
                            TextStyle(color: i == 0 ? ink : muted, fontSize: 12, fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [series(all, chartPalette[0]), series(members, chartPalette[1], dashed: true)],
                ),
                duration: const Duration(milliseconds: 450),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String text, bool dashed) => Row(mainAxisSize: MainAxisSize.min, children: [
    dashed
        ? Row(children: [for (var i = 0; i < 3; i++) Container(width: 4, height: 2.5, margin: const EdgeInsets.only(right: 2), color: c)])
        : Container(width: 14, height: 2.5, color: c),
    const SizedBox(width: 6),
    Text(text, style: const TextStyle(color: muted, fontSize: 12.5)),
  ]);
}

/// Half-circle gauge of a percentage, with the number in the middle.
class Gauge extends StatelessWidget {
  const Gauge({super.key, required this.percent, required this.caption, this.size = 210});
  final double percent;
  final String caption;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 0.6,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, f, _) => CustomPaint(
        painter: _GaugePainter(f),
        child: Align(
          alignment: const Alignment(0, 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(f * 100).round()}%', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: ink)),
            Text(caption, style: const TextStyle(color: muted, fontSize: 11.5)),
          ]),
        ),
      ),
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height - 6), radius: size.width / 2 - stroke / 2);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p(greens[5]));
    if (fraction > 0) canvas.drawArc(rect, math.pi, math.pi * fraction, false, p(brand));
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}

/// Two numbers side by side on a tinted strip (under the gauge).
class SplitStat extends StatelessWidget {
  const SplitStat({super.key, required this.left, required this.right});
  final (String, String) left, right;

  @override
  Widget build(BuildContext context) {
    Widget half((String, String) v) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(children: [
          Text(v.$1, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 3),
          Text(v.$2, style: const TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: const TColor(0xFFEFF7F4), borderRadius: BorderRadius.circular(12)),
      child: IntrinsicHeight(
        child: Row(children: [half(left), const VerticalDivider(width: 1, color: TColor(0xFFFFFFFF), thickness: 2), half(right)]),
      ),
    );
  }
}

/// A ring with gaps between parts and the total in the middle, then a list: dot, name (picture if any), value.
class RingWithList extends StatelessWidget {
  const RingWithList({super.key, required this.slices, required this.centerLabel, required this.centerValue, this.format, this.ring = 190});
  final List<Slice> slices;
  final String centerLabel, centerValue;
  final String Function(int)? format;
  final double ring;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'RingWithList', data: ChartData.slices(slices, format: format, looksLike: ChartKind.donut), original: _chart(context));

  Widget _chart(BuildContext context) {
    final slices = distinctSlices(this.slices);
    return Column(
      children: [
        SizedBox(
          width: ring,
          height: ring,
          child: Stack(alignment: Alignment.center, children: [
            SegmentRing(slices: slices, size: ring),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(centerLabel, style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 2),
              Text(centerValue, style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        const SizedBox(height: 18),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2.5))),
              const SizedBox(width: 10),
              if (s.image != null) ...[AssetThumb(s.image!, size: 26, radius: 7, fit: BoxFit.contain), const SizedBox(width: 8)],
              Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 13.5))),
              Text(format?.call(s.count) ?? '${s.count}', style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}

/// Label and share on one line, a thin progress bar under it (members by city…).
class ProgressRows extends StatelessWidget {
  const ProgressRows({super.key, required this.slices});
  final List<Slice> slices;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'ProgressRows', data: ChartData.slices(slices, looksLike: ChartKind.barH), original: _chart(context));

  Widget _chart(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final total = math.max(1, slices.fold<int>(0, (a, s) => a + s.count));
    return Column(
      children: [
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 13.5))),
                Text('${(s.count * 100 / total).toStringAsFixed(s.count * 100 % total == 0 ? 0 : 1)}%', style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Stack(children: [
                  Container(height: 7, color: greens[5]),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: s.count / total),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (context, f, _) => FractionallySizedBox(widthFactor: f, child: Container(height: 7, decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(99)))),
                  ),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Steps side by side, each with its number and a note, over stepped bars that shrink from left to right.
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.steps});
  final List<FunnelStep> steps;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'FunnelChart', data: ChartData(labels: [for (final s in steps) s.label], values: [for (final s in steps) s.value], shape: ChartShape.stages, looksLike: ChartKind.bar), original: _chart(context));

  Widget _chart(BuildContext context) {
    final top = math.max(1, steps.fold<int>(0, (a, s) => math.max(a, s.value)));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, s) in steps.indexed)
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: line))),
              padding: EdgeInsets.only(left: i == 0 ? 0 : 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(height: 34, child: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12, height: 1.3))),
                      const SizedBox(height: 8),
                      Text(NumberFormat.decimalPattern('en_IN').format(s.value), style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: (s.bad ? down : up).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(s.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.bad ? down : up, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  // The bars fill whatever height the card leaves, so the funnel never overflows.
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: s.value / top),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, f, _) => FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: math.max(0.05, f),
                          child: Container(
                            decoration: BoxDecoration(
                              // Stages in one hue, darkest first; "Blocked" in the status red, with its label.
                              color: s.bad ? const TColor(0xFFD03B3B) : greens[math.min(i, greens.length - 2)],
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
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

/// One bar cut into blocks by share, then the list with each part's percentage (like traffic sources).
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.slices});
  final List<Slice> slices;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'ShareBar', data: ChartData.slices(slices), original: _chart(context));

  Widget _chart(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final shown = [for (final s in slices) if (s.count > 0) s];
    final total = math.max(1, shown.fold<int>(0, (a, s) => a + s.count));
    return Column(
      children: [
        SizedBox(
          height: 50,
          child: Row(children: [
            for (final (i, s) in shown.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: s.count,
                child: Tooltip(
                  message: '${s.label}: ${(s.count * 100 / total).round()}%',
                  child: Container(decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2.5))),
              const SizedBox(width: 10),
              Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 13.5))),
              Text('${(s.count * 100 / total).round()}%', style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- small charts, in the order desk's style

/// A tiny trend line with a soft fill and a dot on the latest value: the shape only, no axes. Sits inside a stat tile.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = brand, this.width = 64, this.height = 26});
  final List<num> values;
  final Color color;
  final double width, height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: values.length < 2 ? null : CustomPaint(painter: _SparkPainter(values, color)),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.fold<num>(0, math.max).toDouble();
    final lo = values.fold<num>(top, math.min).toDouble();
    final span = top - lo == 0 ? 1.0 : top - lo;
    Offset at(int i) => Offset(i * size.width / (values.length - 1), 3 + (1 - (values[i] - lo) / span) * (size.height - 6));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
    canvas.drawCircle(last, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}

/// A KPI card in the deployed admin's style: the label with its icon box on top, the big number and its change
/// below (the first card on a row is highlighted in mint). [trend] is kept for callers; the card doesn't draw it.
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.icon, required this.value, required this.label, this.delta, this.hint, this.tone = brand, this.trend, this.onTap, this.highlight = false});
  final IconData icon;
  final String value, label;
  final Delta? delta;
  final String? hint;
  final Color tone;
  final List<num>? trend;
  final VoidCallback? onTap;
  final bool highlight;

  static const height = 136.0;

  @override
  Widget build(BuildContext context) => Material(
    color: highlight ? const TColor(0xFFDDF3EC) : TColor(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: highlight ? const TColor(0xFFBFE3D6) : line)),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 14))),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: highlight ? brand : const TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(10), border: highlight ? null : Border.all(color: line)),
              child: Icon(icon, size: 19, color: highlight ? Colors.white : const TColor(0xFF34443F)),
            ),
          ]),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: ink, letterSpacing: -.5)),
              ),
            ),
            const SizedBox(width: 8),
            if (delta != null)
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomRight, child: DeltaBadge(delta!)))
            else if (hint != null)
              Flexible(child: Text(hint!, maxLines: 2, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11.5))),
          ]),
        ]),
      ),
    ),
  );
}

/// A short axis figure: 950, 9.9K, 1.2L (rupees with ₹).
String _axis(double v, {bool money = false}) {
  final p = money ? '₹' : '';
  if (v >= 100000) return '$p${(v / 100000).toStringAsFixed(v >= 1000000 ? 0 : 1)}L';
  if (v >= 1000) return '$p${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}K';
  return '$p${v.round()}';
}

/// A trend over time in the deployed admin's style: a smooth line with a soft gradient area, the peak dotted, an
/// optional dashed second line ([second], e.g. cash against revenue), axes when there's room, and a hover tooltip
/// with the point's breakdown by category ([details]). One measure per chart axis: both lines share a scale.
class AreaTrend extends StatelessWidget {
  const AreaTrend({super.key, required this.bars, this.format, this.details, this.second, this.names});
  final List<(String, int)> bars;
  final String Function(int)? format;

  /// Shown under each point's figure on hover: its breakdown by category (see [breakdownText]).
  final List<String>? details;

  /// A dashed comparison line on the same scale, and the two lines' names for the legend.
  final List<int>? second;
  final (String, String)? names;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'AreaTrend', data: ChartData(labels: [for (final (l, _) in bars) l], values: [for (final (_, v) in bars) v], format: format == null ? null : (v) => format!(v.round()), shape: ChartShape.series, looksLike: ChartKind.area), original: _chart(context));

  Widget _chart(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final roomy = box.maxHeight >= 120 && box.maxWidth >= 220;
    final values = [for (final (_, v) in bars) v];
    final two = second != null && second!.length == values.length;
    final top = math.max(1, [...values, if (two) ...second!].fold<int>(0, math.max)).toDouble();
    final step = top <= 4 ? 1.0 : top / 4;
    final peak = values.isEmpty ? -1 : values.indexOf(values.reduce(math.max));
    String f(num v) => format?.call(v.round()) ?? NumberFormat.compact(locale: 'en_IN').format(v);
    final every = math.max(1, (bars.length / (box.maxWidth / 90)).ceil());
    LineChartBarData series(List<int> v, Color c, {bool dashed = false}) => LineChartBarData(
      spots: [for (final (i, n) in v.indexed) FlSpot(i.toDouble(), n.toDouble())],
      isCurved: true,
      preventCurveOverShooting: true,
      curveSmoothness: 0.35,
      color: c,
      barWidth: 2,
      dashArray: dashed ? [6, 5] : null,
      dotData: FlDotData(
        checkToShowDot: (spot, _) => !dashed && spot.x.toInt() == peak,
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: c, strokeWidth: 2, strokeColor: Colors.white),
      ),
      belowBarData: BarAreaData(show: !dashed, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: 0.14), c.withValues(alpha: 0)])),
    );
    Widget legend(Color c, String text, bool dashed) => Row(mainAxisSize: MainAxisSize.min, children: [
      dashed
          ? Row(children: [for (var i = 0; i < 3; i++) Container(width: 4, height: 2.5, margin: const EdgeInsets.only(right: 2), color: c)])
          : Container(width: 14, height: 2.5, color: c),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: muted, fontSize: 12.5)),
    ]);
    final chart = LineChart(
      LineChartData(
        minY: 0,
        maxY: top * 1.25,
        minX: 0,
        maxX: math.max(1, bars.length - 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: roomy, drawVerticalLine: false, horizontalInterval: step, getDrawingHorizontalLine: (_) => const FlLine(color: line, strokeWidth: 1)),
        titlesData: FlTitlesData(
          show: roomy,
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: roomy,
              reservedSize: 52,
              interval: step,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(_axis(v, money: format != null), maxLines: 1, softWrap: false, style: const TextStyle(color: muted, fontSize: 11)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: roomy,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (v != v.roundToDouble() || i < 0 || i >= bars.length || (bars.length - 1 - i) % every != 0) return const SizedBox.shrink();
                return SideTitleWidget(meta: meta, child: Text(bars[i].$1, style: const TextStyle(color: muted, fontSize: 11)));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (bar, spots) => [
            for (final _ in spots)
              TouchedSpotIndicatorData(
                FlLine(color: brand.withValues(alpha: 0.07), strokeWidth: roomy ? 36 : 14),
                FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: brand, strokeWidth: 2, strokeColor: Colors.white)),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => TColor(0xFFFFFFFF),
            tooltipBorder: const BorderSide(color: line),
            tooltipBorderRadius: BorderRadius.circular(10),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 260,
            getTooltipItems: (spots) => [
              for (final (k, s) in spots.indexed)
                LineTooltipItem(
                  k == 0
                      ? '${bars[s.x.round()].$1}\n${names?.$1 ?? ''}${names == null ? '' : ': '}${f(s.y)}${details == null || s.x.round() >= details!.length ? '' : details![s.x.round()]}'
                      : '${names?.$2 ?? ''}${names == null ? '' : ': '}${f(s.y)}',
                  TextStyle(color: k == 0 ? ink : muted, fontSize: 12, fontWeight: k == 0 ? FontWeight.w600 : FontWeight.w500),
                  textAlign: TextAlign.left,
                ),
            ],
          ),
        ),
        lineBarsData: [series(values, chartPalette[0]), if (two) series(second!, chartPalette[1], dashed: true)],
      ),
      duration: const Duration(milliseconds: 450),
    );
    if (names == null || !roomy) return chart;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 18, runSpacing: 6, children: [legend(chartPalette[0], names!.$1, false), if (two) legend(chartPalette[1], names!.$2, true)]),
      const SizedBox(height: 10),
      Expanded(child: chart),
    ]);
  });
}

/// Shares as a ring with the total in the middle, then a line per part with its value and share: the deployed
/// admin's donut. (Sized by its content, so it sits in rows of equal-height cards.)
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.slices, this.format, this.ring = 150, this.centerLabel = 'total'});
  final List<Slice> slices;
  final String Function(int)? format;
  final double ring;
  final String centerLabel;

  @override
  Widget build(BuildContext context) => SwitchableChart(id: 'SplitBar', data: ChartData.slices(slices, format: format, looksLike: ChartKind.donut), original: _chart(context));

  Widget _chart(BuildContext context) {
    final slices = distinctSlices(this.slices);
    final shown = [for (final s in slices) if (s.count > 0) s];
    final total = shown.fold<int>(0, (a, s) => a + s.count);
    if (total == 0) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nothing to show yet.', style: TextStyle(color: muted)));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: ring,
        height: ring,
        child: Stack(alignment: Alignment.center, children: [
          SegmentRing(slices: shown, size: ring),
          Padding(
            padding: EdgeInsets.all(ring * .2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(centerLabel, style: const TextStyle(color: muted, fontSize: 11.5)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(format?.call(total) ?? NumberFormat.decimalPattern('en_IN').format(total), style: const TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w600))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      for (final s in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Tooltip(
            message: '${s.label}: ${format?.call(s.count) ?? s.count} (${(s.count * 100 / total).round()}%)',
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2.5))),
              const SizedBox(width: 10),
              if (s.image != null) ...[AssetThumb(s.image!, size: 26, radius: 7, fit: BoxFit.contain), const SizedBox(width: 8)],
              Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TColor(0xFF34443F), fontSize: 13.5))),
              Text(format?.call(s.count) ?? '${s.count}', style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
              SizedBox(width: 46, child: Text('${(s.count * 100 / total).round()}%', textAlign: TextAlign.right, style: const TextStyle(color: muted, fontSize: 12.5))),
            ]),
          ),
        ),
    ]);
  }
}

/// A white card that sizes to its content (unlike [DashCard], which fills a fixed height).
class SmallCard extends StatelessWidget {
  const SmallCard({super.key, required this.title, required this.child, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ChartSwitchHost(id: title, builder: (context, button) => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    decoration: BoxDecoration(color: TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: ink))),
        ?trailing,
        ?button,
      ]),
      if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: const TextStyle(color: muted, fontSize: 12.5))],
      const SizedBox(height: 16),
      child,
    ]),
  ));
}

/// Tiles in a grid with a chart beside them as tall as the grid (the order desk's layout); on narrow widths the
/// chart goes underneath.
class TilesWithChart extends StatelessWidget {
  const TilesWithChart({super.key, required this.tiles, required this.chart, this.gap = 12});
  final List<Widget> tiles;
  final Widget chart;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final w = box.maxWidth;
    final side = w >= 760;
    final across = side ? 2 : (w >= 520 ? 2 : 1);
    final rows = (tiles.length / across).ceil();
    final gridHeight = rows * MiniStat.height + (rows - 1) * gap;
    final chartHeight = math.max(gridHeight, 180.0);
    Widget grid(double width) {
      final tileWidth = (width - gap * (across - 1)) / across;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: tileWidth, height: MiniStat.height, child: t)]);
    }

    if (side) {
      final gridWidth = (w - 16) * 0.55;
      return SizedBox(
        height: chartHeight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: gridWidth, child: grid(gridWidth)),
          const SizedBox(width: 16),
          Expanded(child: SizedBox(height: chartHeight, child: chart)),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [grid(w), SizedBox(height: gap + 4), SizedBox(height: 170, child: chart)]);
  });
}

/// A grid of [MiniStat]s, [across] to a row (fewer on narrow widths).
class MiniStatGrid extends StatelessWidget {
  const MiniStatGrid({super.key, required this.tiles, this.across = 4, this.gap = 12});
  final List<Widget> tiles;
  final int across;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
    final n = box.maxWidth >= (across > 4 ? 1400 : 1000) ? across : box.maxWidth >= 700 ? math.min(3, across) : box.maxWidth >= 420 ? math.min(2, across) : 1;
    final tileWidth = (box.maxWidth - gap * (n - 1)) / n;
    return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: tileWidth, height: MiniStat.height, child: t)]);
  });
}

/// A chart part's breakdown for its hover text: a heading, then one line per category, biggest first, with its share.
/// Empty when there's nothing to break down.
String breakdownText(Map<String, int> parts, {required String title, String Function(int)? format}) {
  final shown = [for (final e in parts.entries) if (e.value > 0) e]..sort((a, b) => b.value.compareTo(a.value));
  if (shown.isEmpty) return '';
  final total = shown.fold(0, (a, e) => a + e.value);
  return '\n\n$title${[for (final e in shown) '\n•  ${e.key}: ${format?.call(e.value) ?? e.value} (${(e.value * 100 / total).round()}%)'].join()}';
}
