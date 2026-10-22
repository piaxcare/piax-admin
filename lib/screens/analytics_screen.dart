import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../admin_modules/nav_config.dart' show AppPage;

import '../admin_modules/data_charts.dart';
import '../admin_modules/nav_widgets.dart' show PageTreeSlot, menuTitle;
import '../admin_modules/dashboard_widgets.dart' show breakdownText;
import 'package:intl/intl.dart';

import '../analytics.dart';
import '../admin_modules/admin_search.dart' show globalSearchActions;
import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/brand.dart';
import 'login_screen.dart' show signOut;

// Chart colours. Products keep one colour each in every chart (a fixed order, checked for colour-blind separation);
// single-series charts use the brand teal; order steps use one teal ramp, light to dark, with grey for cancelled.
// Text never takes a series colour: values and labels stay in the ink colours.
const _ink = Color(0xFF0C1C19);
const _muted = Color(0xFF5B6B67);
const _grid = Color(0xFFE6ECEA);
const _series = Color(0xFF0F766E);
const _up = Color(0xFF0F766E);
const _down = Color(0xFFD9582B);
const productColours = {
  'vera': Color(0xFF4C9A2A),
  'luma': Color(0xFFB784E6),
  'nocte': Color(0xFF2C4FA8),
  'seren': Color(0xFFEB6834),
  'cycle': Color(0xFF12A58A),
  'other': Color(0xFF8A8F8C),
};
const productNames = {
  'vera': 'VERA 240mm',
  'luma': 'LUMA 290mm',
  'nocte': 'NOCTE 330mm',
  'seren': 'SEREN 360mm',
  'cycle': 'Cycle Pack',
  'other': 'Other',
};
const _stepColours = {
  OrderStatus.confirmed: Color(0xFFA7E0D3),
  OrderStatus.packed: Color(0xFF6FC7B4),
  OrderStatus.shipped: Color(0xFF34A68F),
  OrderStatus.outForDelivery: Color(0xFF16806F),
  OrderStatus.delivered: Color(0xFF0B5B4E),
  OrderStatus.cancelled: Color(0xFFB9B4AC),
};

final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _money(num v) => v.abs() >= 100000 ? _compact.format(v) : rupees(v.round());
String _pct(double v) => '${(v * 100).abs() >= 10 ? (v * 100).round() : (v * 100).toStringAsFixed(1)}%';

/// Charts of every website order: revenue, orders and growth over time, where orders come from, what sells, how
/// orders are moving and how people pay. Built from anonymous order facts (no customer details).
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.api});
  final AdminApi api;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<OrderFact>? _facts;
  String? _error;
  AnalyticsRange _range = AnalyticsRange.month;
  bool _byState = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final facts = await widget.api.analytics();
      if (mounted) setState(() => (_facts = facts, _error = null));
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F6F5),
        title: Text(menuTitle(context, 'Analytics', page: AppPage.analytics), style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          ...globalSearchActions(context),
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: facts == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Try again')),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(builder: (context, constraints) => _body(Analytics.compute(facts, _range), constraints.maxWidth)),
            ),
    );
  }

  Widget _body(Analytics a, double width) {
    final wide = width >= Breakpoints.desktop;
    final pad = width >= Breakpoints.tablet ? 28.0 : 16.0;
    // Two cards side by side on wide screens (aligned at the top: the charts inside size themselves, so the row can't
    // ask them for an "intrinsic" height), stacked otherwise.
    Widget pair(Widget left, Widget right) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          )
        : Column(children: [left, const SizedBox(height: 16), right]);
    final per = switch (a.bucket) {
      Bucket.day => 'day',
      Bucket.week => 'week',
      Bucket.month => 'month',
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
      children: [
        const PageTreeSlot(),
        PageWidth(
          maxWidth: 1400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filters(a),
              const SizedBox(height: 16),
              _kpis(a, width),
              const SizedBox(height: 16),
              pair(
                _Card(title: 'Revenue', subtitle: 'Paid orders, not cancelled · per $per', child: _revenueChart(a)),
                _Card(title: 'Orders', subtitle: 'Orders past checkout · per $per', child: _ordersChart(a)),
              ),
              const SizedBox(height: 16),
              _Card(
                title: 'Market growth',
                subtitle: 'Revenue change from one $per to the next',
                trailing: _growthSummary(a),
                child: _growthChart(a, per),
              ),
              const SizedBox(height: 16),
              pair(
                _Card(
                  title: 'Orders by place',
                  subtitle: 'Where orders are delivered',
                  trailing: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: false, label: Text('City')),
                      ButtonSegment(value: true, label: Text('State')),
                    ],
                    selected: {_byState},
                    onSelectionChanged: (v) => setState(() => _byState = v.first),
                  ),
                  child: _places(_byState ? a.states : a.places),
                ),
                _Card(title: 'Products', subtitle: 'Packs sold, by product', child: _products(a)),
              ),
              const SizedBox(height: 16),
              pair(
                _Card(title: 'Order progress', subtitle: 'Where this period’s orders are now', child: _progress(a)),
                _Card(title: 'Payment', subtitle: 'How customers paid', child: _payments(a)),
              ),
              const SizedBox(height: 16),
              Text(
                'Showing ${DateFormat('d MMM yyyy').format(a.from)} – ${DateFormat('d MMM yyyy').format(a.to)}. '
                'Revenue counts paid orders that weren’t cancelled; orders count everything past checkout.',
                style: const TextStyle(color: _muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        // Every other set of records in the admin app, each with its own small charts (full width).
        AllDataCharts(api: widget.api),
      ],
    );
  }

  // ---------------------------------------------------------------- filters and headline numbers

  Widget _filters(Analytics a) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final r in AnalyticsRange.values)
        ChoiceChip(label: Text(r.label), selected: _range == r, onSelected: (_) => setState(() => _range = r)),
    ],
  );

  Widget _kpis(Analytics a, double width) {
    final k = a.kpis;
    final p = a.previous;
    final vs = a.range.days == null ? null : 'vs previous ${a.range.label}';
    final tiles = [
      _Kpi(
        icon: Icons.currency_rupee,
        label: 'Revenue',
        value: _money(k.revenue),
        change: p == null ? null : change(k.revenue, p.revenue),
        vs: vs,
      ),
      _Kpi(
        icon: Icons.receipt_long_outlined,
        label: 'Orders',
        value: '${k.orders}',
        change: p == null ? null : change(k.orders, p.orders),
        vs: vs,
      ),
      _Kpi(
        icon: Icons.shopping_bag_outlined,
        label: 'Average order',
        value: rupees(k.average),
        change: p == null ? null : change(k.average, p.average),
        vs: vs,
      ),
      _Kpi(
        icon: Icons.inventory_2_outlined,
        label: 'Packs sold',
        value: '${k.packs}',
        change: p == null ? null : change(k.packs, p.packs),
        vs: vs,
      ),
      _Kpi(
        icon: Icons.check_circle_outline,
        label: 'Delivered',
        value: _pct(k.deliveredShare),
        detail: '${k.delivered} of ${k.orders} orders',
      ),
      _Kpi(
        icon: Icons.cancel_outlined,
        label: 'Cancelled',
        value: _pct(k.cancelledShare),
        detail: '${k.cancelled} orders',
        lowerIsBetter: true,
      ),
    ];
    final across = width >= 1300
        ? 6
        : width >= 760
        ? 3
        : 2;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final w = (c.maxWidth - gap * (across - 1)) / across;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }

  Widget? _growthSummary(Analytics a) {
    final p = a.previous;
    if (p == null) return null;
    final g = change(a.kpis.revenue, p.revenue);
    if (g == null) return null;
    return _ChangeChip(value: g, label: 'this ${a.range.label}');
  }

  // ---------------------------------------------------------------- time charts

  FlTitlesData _titles(Analytics a, {required String Function(double) left}) {
    final n = a.series.length;
    final every = n <= 8 ? 1 : (n / 6).ceil();
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 52,
          getTitlesWidget: (v, meta) => v == meta.max
              ? const SizedBox.shrink()
              : SideTitleWidget(
                  meta: meta,
                  child: Text(left(v), style: const TextStyle(color: _muted, fontSize: 11)),
                ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= n || i % every != 0 || v != i) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              child: Text(a.series[i].label, style: const TextStyle(color: _muted, fontSize: 11)),
            );
          },
        ),
      ),
    );
  }

  FlGridData get _gridLines =>
      FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: _grid, strokeWidth: 1));

  Widget _revenueChart(Analytics a) {
    if (a.series.every((p) => p.revenue == 0)) return const _Empty('No revenue in this period yet.');
    final top = a.series.map((p) => p.revenue).reduce((x, y) => x > y ? x : y).toDouble();
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: top * 1.15,
          gridData: _gridLines,
          borderData: FlBorderData(show: false),
          titlesData: _titles(a, left: (v) => _money(v)),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.white,
              tooltipBorder: const BorderSide(color: _grid),
              fitInsideHorizontally: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${a.series[s.x.round()].label}\n',
                    const TextStyle(color: _muted, fontSize: 12),
                    textAlign: TextAlign.left,
                    children: [
                      TextSpan(
                        text: rupees(s.y.round()),
                        style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      TextSpan(
                        text: breakdownText({
                          for (final e in a.series[s.x.round()].revenueByProduct.entries) productNames[e.key] ?? e.key: e.value,
                        }, title: 'By product', format: rupees),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < a.series.length; i++) FlSpot(i.toDouble(), a.series[i].revenue.toDouble())],
              isCurved: true,
              preventCurveOverShooting: true,
              color: _series,
              barWidth: 2,
              dotData: FlDotData(
                show: a.series.length <= 14,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: _series, strokeColor: Colors.white, strokeWidth: 2),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_series.withValues(alpha: .22), _series.withValues(alpha: .02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ordersChart(Analytics a) {
    if (a.series.every((p) => p.orders == 0)) return const _Empty('No orders in this period yet.');
    final top = a.series.map((p) => p.orders).reduce((x, y) => x > y ? x : y).toDouble();
    final barWidth = (220 / a.series.length).clamp(6, 22).toDouble();
    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: (top * 1.2).ceilToDouble(),
          gridData: _gridLines,
          borderData: FlBorderData(show: false),
          titlesData: _titles(a, left: (v) => v == v.roundToDouble() ? '${v.round()}' : ''),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.white,
              tooltipBorder: const BorderSide(color: _grid),
              fitInsideHorizontally: true,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${a.series[group.x].label}\n',
                const TextStyle(color: _muted, fontSize: 12),
                textAlign: TextAlign.left,
                    children: [
                  TextSpan(
                    text: '${rod.toY.round()} orders',
                    style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  TextSpan(
                    text: breakdownText(a.series[group.x].ordersByStatus, title: 'By status'),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < a.series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: a.series[i].orders.toDouble(),
                    color: _series,
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _growthChart(Analytics a, String per) {
    final growth = a.growth;
    final values = growth.whereType<double>().toList();
    if (values.length < 2) {
      return _Empty('Growth shows once there are at least three ${per}s of sales to compare. Try a longer range.');
    }
    final extent = values.map((v) => v.abs()).reduce((x, y) => x > y ? x : y).clamp(.1, 5.0) * 1.25;
    final barWidth = (220 / growth.length).clamp(6, 22).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              minY: -extent,
              maxY: extent,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? const Color(0xFFB9C4C1) : _grid, strokeWidth: v == 0 ? 1.4 : 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: _titles(a, left: (v) => '${(v * 100).round()}%'),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.white,
                  tooltipBorder: const BorderSide(color: _grid),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, _, rod, _) {
                    final g = growth[group.x];
                    final point = a.series[group.x];
                    return BarTooltipItem(
                      '${point.label} · ${rupees(point.revenue)}\n',
                      const TextStyle(color: _muted, fontSize: 12),
                      children: [
                        TextSpan(
                          text: g == null ? 'No sales the $per before' : '${g >= 0 ? '▲' : '▼'} ${_pct(g)} on the $per before',
                          style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < growth.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (growth[i] ?? 0).clamp(-extent, extent),
                        color: (growth[i] ?? 0) >= 0 ? _up : _down,
                        width: barWidth,
                        borderRadius: (growth[i] ?? 0) >= 0
                            ? const BorderRadius.vertical(top: Radius.circular(4))
                            : const BorderRadius.vertical(bottom: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _LegendDot(color: _up, label: '▲ Revenue up'),
            _LegendDot(color: _down, label: '▼ Revenue down'),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- breakdowns

  Widget _places(List<(String, int, int)> rows) {
    if (rows.isEmpty) return const _Empty('No orders in this period yet.');
    final shown = rows.take(8).toList();
    final others = rows.skip(8).fold(0, (n, r) => n + r.$2);
    final top = shown.first.$2;
    final total = rows.fold(0, (n, r) => n + r.$2);
    return Column(
      children: [
        for (final (name, orders, revenue) in shown)
          Tooltip(
            message: '$name: $orders orders · ${rupees(revenue)}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          height: 14,
                          width: (c.maxWidth * orders / top).clamp(4, c.maxWidth),
                          decoration: const BoxDecoration(
                            color: _series,
                            borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 92,
                    child: Text(
                      '$orders · ${_pct(orders / total)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (others > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+ $others orders from ${rows.length - 8} other places', style: const TextStyle(color: _muted, fontSize: 12.5)),
          ),
      ],
    );
  }

  Widget _products(Analytics a) {
    if (a.products.isEmpty) return const _Empty('No packs sold in this period yet.');
    final total = a.products.fold(0, (n, p) => n + p.$2);
    final chart = SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 58,
              startDegreeOffset: -90,
              sections: [
                for (final (id, packs, _) in a.products)
                  PieChartSectionData(value: packs.toDouble(), color: productColours[id], radius: 34, showTitle: false),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const Text('packs', style: TextStyle(color: _muted, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
    // The legend carries the numbers (share, packs, revenue), so nothing depends on telling colours apart.
    final legend = Column(
      children: [
        for (final (id, packs, revenue) in a.products)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: productColours[id], borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    productNames[id] ?? id,
                    style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  _pct(packs / total),
                  style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    '$packs packs · ${_money(revenue)}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: _muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 480
          ? Row(
              children: [
                chart,
                const SizedBox(width: 24),
                Expanded(child: legend),
              ],
            )
          : Column(children: [chart, const SizedBox(height: 16), legend]),
    );
  }

  Widget _progress(Analytics a) {
    final steps = [
      OrderStatus.confirmed,
      OrderStatus.packed,
      OrderStatus.shipped,
      OrderStatus.outForDelivery,
      OrderStatus.delivered,
      OrderStatus.cancelled,
    ];
    final total = steps.fold(0, (n, s) => n + (a.statuses[s] ?? 0));
    if (total == 0) return const _Empty('No orders in this period yet.');
    final waiting = (a.statuses[OrderStatus.confirmed] ?? 0) + (a.statuses[OrderStatus.packed] ?? 0);
    final onTheWay = (a.statuses[OrderStatus.shipped] ?? 0) + (a.statuses[OrderStatus.outForDelivery] ?? 0);
    final done = a.statuses[OrderStatus.delivered] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Stat(label: 'To process', value: '$waiting', hint: 'confirmed or packed'),
            _Stat(label: 'On the way', value: '$onTheWay', hint: 'shipped or out'),
            _Stat(
              label: 'Delivered',
              value: '$done',
              hint: a.averageDaysToDeliver == null ? '' : 'in ${a.averageDaysToDeliver!.toStringAsFixed(1)} days on average',
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                for (final (i, s) in steps.where((s) => (a.statuses[s] ?? 0) > 0).indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: a.statuses[s]!,
                    child: Tooltip(
                      message: '${s.label}: ${a.statuses[s]} orders',
                      child: Container(color: _stepColours[s]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [for (final s in steps) _LegendDot(color: _stepColours[s]!, label: '${s.label} ${a.statuses[s] ?? 0}')],
        ),
      ],
    );
  }

  Widget _payments(Analytics a) {
    final (online, cod) = a.payments;
    final total = online + cod;
    if (total == 0) return const _Empty('No orders in this period yet.');
    const onlineColour = Color(0xFF0F766E);
    const codColour = Color(0xFFE0A21A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                if (online > 0)
                  Expanded(
                    flex: online,
                    child: Tooltip(
                      message: 'Online: $online orders',
                      child: Container(color: onlineColour),
                    ),
                  ),
                if (online > 0 && cod > 0) const SizedBox(width: 2),
                if (cod > 0)
                  Expanded(
                    flex: cod,
                    child: Tooltip(
                      message: 'Cash on delivery: $cod orders',
                      child: Container(color: codColour),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PaymentRow(color: onlineColour, label: 'Online (Razorpay)', count: online, share: online / total),
        _PaymentRow(color: codColour, label: 'Cash on delivery', count: cod, share: cod / total),
      ],
    );
  }
}

// ---------------------------------------------------------------- small pieces

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.subtitle, required this.child, this.trailing});
  final String title, subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1E8E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: _ink, fontSize: 16.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12.5)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.label, required this.value, this.change, this.vs, this.detail, this.lowerIsBetter = false});
  final IconData icon;
  final String label, value;
  final double? change;
  final String? vs, detail;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE1E8E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _series),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        if (change != null)
          _ChangeChip(value: change!, label: vs ?? '', lowerIsBetter: lowerIsBetter)
        else
          Text(detail ?? (vs == null ? 'All time' : 'Nothing to compare yet'), style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    ),
  );
}

/// A change with an arrow and a word, never colour alone.
class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.value, required this.label, this.lowerIsBetter = false});
  final double value;
  final String label;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final flat = value.abs() < .005;
    final good = flat ? null : (value > 0) != lowerIsBetter;
    final color = good == null
        ? _muted
        : good
        ? const Color(0xFF1E7B45)
        : const Color(0xFFB3261E);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          flat
              ? Icons.remove
              : value > 0
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          flat ? 'No change' : _pct(value),
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.hint});
  final String label, value, hint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFF2F6F5), borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: const TextStyle(color: _ink, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        if (hint.isNotEmpty) Text(hint, style: const TextStyle(color: _muted, fontSize: 11.5)),
      ],
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: _ink, fontSize: 12.5)),
    ],
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.color, required this.label, required this.count, required this.share});
  final Color color;
  final String label;
  final int count;
  final double share;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          '$count · ${_pct(share)}',
          style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFFF6F9F8), borderRadius: BorderRadius.circular(12)),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _muted, fontSize: 13.5),
    ),
  );
}
