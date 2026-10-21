import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../models.dart';
import 'charts.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart';
import 'insights.dart';
import 'repository.dart';

// Revenue and orders on the dashboard: live orders from the order desk when it has any, otherwise the dummy demo
// orders (clearly labelled). Headline numbers for the chosen period with the change against the period before, a
// revenue-and-orders chart by day, orders by status, best-selling products, payment methods and revenue by city.

/// One order, reduced to what the charts need; made from a live [Order] or a demo record.
class OrderPoint {
  const OrderPoint({required this.at, required this.status, required this.total, required this.city, required this.payment, required this.items, required this.refundDue});
  final DateTime at;
  final String status; // placed | confirmed | packed | shipped | out_for_delivery | delivered | cancelled
  final int total;
  final String city, payment;
  final List<(String, int, int)> items; // name, quantity, line total
  final bool refundDue;

  bool get counts => status != 'placed' && status != 'cancelled';

  factory OrderPoint.fromOrder(Order o) => OrderPoint(
    at: o.createdAt.toLocal(),
    status: o.status.api,
    total: o.totals.total,
    city: o.address.city.isEmpty ? 'Unknown' : o.address.city,
    payment: o.payment.method == 'cod' ? 'Cash on delivery' : 'Online (Razorpay)',
    items: [for (final i in o.items) (i.name, i.quantity, i.lineTotal)],
    refundDue: o.needsRefund,
  );

  factory OrderPoint.fromDemo(Map<String, dynamic> j) => OrderPoint(
    at: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
    status: '${j['status']}',
    total: (j['total'] as num?)?.round() ?? 0,
    city: '${j['city'] ?? 'Unknown'}',
    payment: '${j['payment'] ?? 'Online'}',
    items: [for (final i in (j['items'] as List? ?? const [])) ('${i['name']}', (i['quantity'] as num?)?.round() ?? 1, (i['lineTotal'] as num?)?.round() ?? 0)],
    refundDue: j['refund'] == 'pending',
  );
}

const _statusLabels = {
  'placed': 'Awaiting payment',
  'confirmed': 'To pack',
  'packed': 'Packed',
  'shipped': 'Shipped',
  'out_for_delivery': 'Out for delivery',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
};

const _statusColors = {
  'placed': Color(0xFFD29B2B),
  'confirmed': Color(0xFF8E79B0),
  'packed': Color(0xFF4A90A4),
  'shipped': Color(0xFF3E9A86),
  'out_for_delivery': Color(0xFF0F766E),
  'delivered': Color(0xFF0B5B4E),
  'cancelled': Color(0xFFB3261E),
};

class RevenueSection extends StatefulWidget {
  const RevenueSection({super.key, required this.repo, this.onOpenOrders});
  final ModuleRepository repo;

  /// Opens the order desk (when the app has one to open).
  final VoidCallback? onOpenOrders;

  @override
  State<RevenueSection> createState() => _RevenueSectionState();
}

class _RevenueSectionState extends State<RevenueSection> {
  List<OrderPoint>? _points;
  bool _live = false;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<OrderPoint> points = const [];
    var live = false;
    try {
      final orders = await widget.repo.api.orders(status: 'all').timeout(const Duration(seconds: 8));
      if (orders.isNotEmpty) {
        points = [for (final o in orders) OrderPoint.fromOrder(o)];
        live = true;
      }
    } catch (_) {
      // No order desk to ask (offline, a demo build): the demo orders below.
    }
    if (!live) points = [for (final o in widget.repo.records('ordersDemo')) OrderPoint.fromDemo(o)];
    if (mounted) setState(() => (_points = points, _live = live));
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (points == null) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: _days - 1));
    final prevStart = start.subtract(Duration(days: _days));
    bool inPeriod(OrderPoint p) => !p.at.isBefore(start);
    bool inPrev(OrderPoint p) => !p.at.isBefore(prevStart) && p.at.isBefore(start);
    final period = points.where(inPeriod).toList();
    final prev = points.where(inPrev).toList();

    int revenue(Iterable<OrderPoint> list) => list.where((p) => p.counts).fold(0, (a, p) => a + p.total);
    final rev = revenue(period), revPrev = revenue(prev);
    final count = period.where((p) => p.status != 'placed').length, countPrev = prev.where((p) => p.status != 'placed').length;
    final paidCount = period.where((p) => p.counts).length;
    final aov = paidCount == 0 ? 0 : rev ~/ paidCount;
    final prevPaid = prev.where((p) => p.counts).length;
    final aovPrev = prevPaid == 0 ? 0 : revPrev ~/ prevPaid;
    final cancelled = period.where((p) => p.status == 'cancelled').length;
    final cancelRate = count == 0 ? 0.0 : cancelled * 100 / count;
    final refundsDue = points.where((p) => p.refundDue).toList();
    final open = points.where((p) => const {'confirmed', 'packed', 'shipped', 'out_for_delivery'}.contains(p.status)).length;

    Delta change(num now, num before) {
      if (before == 0) return Delta(now == 0 ? 'no change' : 'new', now > 0, caption: 'vs previous $_days days');
      final pct = (now - before) * 100 / before;
      return Delta('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%', pct >= 0, caption: 'vs previous $_days days');
    }

    // Revenue and orders per day (or per week for 90 days).
    final bucket = _days <= 30 ? 1 : 7;
    final buckets = (_days / bucket).ceil();
    final revBy = List<int>.filled(buckets, 0), ordersBy = List<int>.filled(buckets, 0);
    for (final p in period) {
      final i = DateTime(p.at.year, p.at.month, p.at.day).difference(start).inDays ~/ bucket;
      if (i < 0 || i >= buckets) continue;
      if (p.status != 'placed') ordersBy[i]++;
      if (p.counts) revBy[i] += p.total;
    }
    String label(int i) => DateFormat('d MMM').format(start.add(Duration(days: i * bucket)));

    final byStatus = [
      for (final e in _statusLabels.entries) Slice(e.value, period.where((p) => p.status == e.key).length, _statusColors[e.key]!),
    ];
    final productRevenue = <String, int>{}, productUnits = <String, int>{};
    for (final p in period.where((p) => p.counts)) {
      for (final (name, qty, line) in p.items) {
        productRevenue[name] = (productRevenue[name] ?? 0) + line;
        productUnits[name] = (productUnits[name] ?? 0) + qty;
      }
    }
    final products = productRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final productImages = {for (final x in widget.repo.records('products')) '${x['name']}': recordImage('products', x)};
    final topProducts = [
      for (final (i, e) in products.take(5).indexed) Slice('${e.key} · ${productUnits[e.key]} boxes', e.value, greens[i], image: productImages[e.key]),
    ];
    final payments = countBy(period.where((p) => p.counts).map((p) => p.payment), top: 5);
    final cityRevenue = <String, int>{};
    for (final p in period.where((p) => p.counts)) {
      cityRevenue[p.city] = (cityRevenue[p.city] ?? 0) + p.total;
    }
    final cities = (cityRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => Slice(e.key, e.value, brand)).toList();

    final heads = [
      HeadlineCard(label: 'Revenue', value: rupees(rev), icon: Icons.payments_outlined, module: 'orders', delta: change(rev, revPrev)),
      HeadlineCard(label: 'Orders', value: NumberFormat.decimalPattern('en_IN').format(count), icon: Icons.receipt_long_outlined, module: 'orders', delta: change(count, countPrev)),
      HeadlineCard(label: 'Average order', value: rupees(aov), icon: Icons.shopping_bag_outlined, module: 'orders', delta: change(aov, aovPrev)),
      HeadlineCard(
        label: 'Cancelled',
        value: '${cancelRate.toStringAsFixed(1)}%',
        icon: Icons.cancel_outlined,
        module: 'orders',
        delta: Delta('$cancelled of $count', cancelRate < 10, caption: 'orders in the period'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final wide = w >= 1100, medium = w >= 700;
        const gap = 18.0;
        final chart = DashCard(
          title: 'Revenue & orders',
          subtitle: bucket == 1 ? 'By day. Revenue counts paid orders that weren’t cancelled.' : 'By week. Revenue counts paid orders that weren’t cancelled.',
          trailing: PillPicker<int>(value: _days, options: const [7, 30, 90], label: (d) => 'Last $d days', onChanged: (d) => setState(() => _days = d)),
          child: _RevenueChart(revenue: revBy, orders: ordersBy, label: label),
        );
        final statusCard = DashCard(
          title: 'Orders by status',
          subtitle: '$open on their way to customers now',
          trailing: widget.onOpenOrders == null ? null : SeeAll(onTap: widget.onOpenOrders!, label: 'Open desk'),
          child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: DonutChart(slices: byStatus, centerLabel: 'orders', size: 150, horizontal: false)),
        );
        final productsCard = DashCard(
          title: 'Best sellers',
          subtitle: 'Revenue by product in the period.',
          child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: BarList(slices: topProducts, format: rupees)),
        );
        final paymentCard = DashCard(
          title: 'How customers pay',
          child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: ShareBar(slices: [for (final (i, s) in payments.indexed) Slice(s.label, s.count, greens[(i * 2).clamp(0, 4)])])),
        );
        final cityCard = DashCard(
          title: 'Revenue by city',
          child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: BarList(slices: cities, format: rupees)),
        );
        final refundsCard = DashCard(
          title: 'Refunds waiting',
          subtitle: 'Cancelled orders paid online whose money hasn’t gone back yet.',
          trailing: widget.onOpenOrders == null ? null : SeeAll(onTap: widget.onOpenOrders!, label: 'Review'),
          child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${refundsDue.length}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: ink)),
            Text(refundsDue.isEmpty ? 'Nothing to refund.' : '${rupees(refundsDue.fold(0, (a, p) => a + p.total))} to send back', style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(12)),
              child: Text('$open open orders · ${period.where((p) => p.status == 'delivered').length} delivered in the period', style: const TextStyle(color: Color(0xFF26413B), fontSize: 12.5)),
            ),
          ])),
        );

        Widget row(double h, List<(int, Widget)> parts) => SizedBox(
          height: h,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (flex, child)) in parts.indexed) ...[if (i > 0) const SizedBox(width: gap), Expanded(flex: flex, child: child)],
          ]),
        );
        Widget fixed(double h, Widget child) => SizedBox(height: h, child: child);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
              const Text('Revenue & orders', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _live ? const Color(0xFFDDF3EC) : const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(999)),
                child: Text(_live ? 'Live from the order desk' : 'Demo orders: no live orders to show', style: TextStyle(color: _live ? brand : const Color(0xFF7F5300), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('The last $_days days against the $_days before.', style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 12),
            EqualRows(columns: wide ? 4 : medium ? 2 : 1, gap: 14, children: [for (final (i, h) in heads.indexed) HeadlineStatCard(card: h, highlight: i == 0, onTap: widget.onOpenOrders ?? () {})]),
            const SizedBox(height: gap),
            if (wide) ...[
              row(400, [(2, chart), (1, statusCard)]),
              const SizedBox(height: gap),
              row(360, [(1, productsCard), (1, paymentCard), (1, cityCard), (1, refundsCard)]),
            ] else if (medium) ...[
              fixed(360, chart),
              const SizedBox(height: gap),
              row(440, [(1, statusCard), (1, productsCard)]),
              const SizedBox(height: gap),
              row(340, [(1, paymentCard), (1, cityCard)]),
              const SizedBox(height: gap),
              fixed(220, refundsCard),
            ] else ...[
              fixed(330, chart),
              const SizedBox(height: gap),
              fixed(470, statusCard),
              const SizedBox(height: gap),
              fixed(380, productsCard),
              const SizedBox(height: gap),
              fixed(340, paymentCard),
              const SizedBox(height: gap),
              fixed(360, cityCard),
              const SizedBox(height: gap),
              fixed(220, refundsCard),
            ],
          ],
        );
      },
    );
  }
}

/// Revenue as columns and orders as a line over them, sharing the time axis.
class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.revenue, required this.orders, required this.label});
  final List<int> revenue, orders;
  final String Function(int) label;

  @override
  Widget build(BuildContext context) {
    final topRev = math.max(1, revenue.fold<int>(0, math.max));
    final topOrders = math.max(1, orders.fold<int>(0, math.max));
    // Orders drawn on the revenue scale: each order counts as topRev / topOrders.
    final scale = topRev / topOrders;
    final every = revenue.length <= 7 ? 1 : revenue.length <= 14 ? 2 : (revenue.length / 6).ceil();
    final compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 16, runSpacing: 6, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: greens[3], borderRadius: BorderRadius.circular(3))), const SizedBox(width: 6), Text('Revenue ${rupees(revenue.fold(0, (a, b) => a + b))}', style: const TextStyle(color: muted, fontSize: 12.5))]),
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 14, height: 3, color: greens[0]), const SizedBox(width: 6), Text('Orders ${orders.fold(0, (a, b) => a + b)}', style: const TextStyle(color: muted, fontSize: 12.5))]),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Stack(children: [
            BarChart(
              BarChartData(
                maxY: topRev * 1.2,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(drawVerticalLine: false, horizontalInterval: topRev / 4, getDrawingHorizontalLine: (_) => const FlLine(color: line, strokeWidth: 1, dashArray: [4, 4])),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 46, interval: topRev / 4, getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(compact.format(v), style: const TextStyle(color: muted, fontSize: 10.5))))),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) => v.toInt() % every == 0 ? SideTitleWidget(meta: meta, child: Text(label(v.toInt()), style: const TextStyle(color: muted, fontSize: 10.5))) : const SizedBox.shrink(),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1E293B),
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      '${label(group.x)}\n${rupees(rod.toY.round())} · ${orders[group.x]} orders',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                barGroups: [
                  for (final (i, v) in revenue.indexed)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: v.toDouble(),
                        width: revenue.length > 20 ? 7 : 16,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [greens[4], greens[3]]),
                      ),
                    ]),
                ],
              ),
            ),
            // The orders line, over the columns, on the same horizontal positions.
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(left: 46, bottom: 24),
                child: LineChart(
                  LineChartData(
                    minX: -0.5,
                    maxX: orders.length - 0.5,
                    minY: 0,
                    maxY: topRev * 1.2,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [for (final (i, n) in orders.indexed) FlSpot(i.toDouble(), n * scale)],
                        isCurved: true,
                        preventCurveOverShooting: true,
                        color: greens[0],
                        barWidth: 2.4,
                        dotData: FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 2.6, color: Colors.white, strokeWidth: 2, strokeColor: greens[0])),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
