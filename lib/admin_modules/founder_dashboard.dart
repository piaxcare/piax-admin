import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'charts.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart';
import 'insights.dart' show Delta, Slice, chartPalette, otherColor;
import 'nav_pages.dart' show navPageSpecs, rowsFor;
import 'repository.dart';
import 'revenue_section.dart' show OrderPoint;

// The Founder Overview's sales part: revenue first, then orders, with one set of filters (dates, channel, customer
// segment, order status) over every number, chart and table here. Sections in between (alerts, operations, customers)
// come from the overview and aren't filtered.
//
// Two independent labels on every order: the platform it came through (channel) and who bought it (segment). An order
// counts once in each, so the channel × segment table adds up to the same totals. Missing labels show as "Unknown".
//
// What the money figures mean (orders past checkout only):
//   Net revenue           paid orders that weren't cancelled.
//   Cash collected        payments received, less refunds already sent back.
//   Gross profit          net revenue less the cost of the boxes sold (Finance › Product Costing cost sheets); revenue
//                         from products without a cost sheet is left out and said so.
//   Outstanding receivables  unpaid B2B invoices (Finance › Customer Receivables); not date-filtered.

const channels = ['Web', 'Mobile App', 'B2B Direct', 'Marketplace', 'Vending', 'Other', 'Unknown'];
const segments = ['B2B', 'B2C', 'Unknown'];

/// The platform an order came through, in the report's words; missing → Unknown, anything unrecognised → Other.
String normalizeChannel(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  if (v.isEmpty || v == 'unknown') return 'Unknown';
  if (const {'web', 'website', 'site', 'd2c', 'online'}.contains(v)) return 'Web';
  if (const {'app', 'mobile', 'mobile app', 'android', 'ios'}.contains(v)) return 'Mobile App';
  if (const {'b2b', 'b2b direct', 'direct', 'institutional'}.contains(v)) return 'B2B Direct';
  if (const {'marketplace', 'amazon', 'flipkart', 'nykaa', 'meesho', 'bigbasket'}.contains(v)) return 'Marketplace';
  if (v == 'vending' || v.startsWith('vm-')) return 'Vending';
  return 'Other';
}

/// Who bought it: B2B, B2C or Unknown (never guessed).
String normalizeSegment(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
  'b2b' => 'B2B',
  'b2c' => 'B2C',
  _ => 'Unknown',
};

const _statusLabels = {
  'placed': 'Awaiting payment',
  'confirmed': 'To pack',
  'packed': 'Packed',
  'shipped': 'Shipped',
  'out_for_delivery': 'Out for delivery',
  'delivered': 'Delivered',
  'cancelled': 'Cancelled',
};

enum DateRange { d7, d30, d90, d365, all, custom }

const _rangeLabels = {DateRange.d7: '7 days', DateRange.d30: '30 days', DateRange.d90: '90 days', DateRange.d365: '12 months', DateRange.all: 'All time', DateRange.custom: 'Custom'};

class SalesFilter {
  const SalesFilter({this.range = DateRange.d30, this.from, this.to, this.channels = const {}, this.segments = const {}, this.statuses = const {}});
  final DateRange range;
  final DateTime? from, to;
  final Set<String> channels, segments, statuses;

  SalesFilter copyWith({DateRange? range, DateTime? from, DateTime? to, Set<String>? channels, Set<String>? segments, Set<String>? statuses}) => SalesFilter(
    range: range ?? this.range,
    from: from ?? this.from,
    to: to ?? this.to,
    channels: channels ?? this.channels,
    segments: segments ?? this.segments,
    statuses: statuses ?? this.statuses,
  );

  /// The period [start, end), and the same length just before it (null for all time).
  (DateTime?, DateTime, DateTime?) window(DateTime now) {
    final end = DateTime(now.year, now.month, now.day + 1);
    final days = switch (range) {
      DateRange.d7 => 7,
      DateRange.d30 => 30,
      DateRange.d90 => 90,
      DateRange.d365 => 365,
      _ => 0,
    };
    if (range == DateRange.all) return (null, end, null);
    if (range == DateRange.custom && from != null && to != null) {
      final s = DateTime(from!.year, from!.month, from!.day), e = DateTime(to!.year, to!.month, to!.day + 1);
      return (s, e, s.subtract(e.difference(s)));
    }
    final start = end.subtract(Duration(days: days));
    return (start, end, start.subtract(Duration(days: days)));
  }

  bool keeps(OrderPoint p) =>
      (channels.isEmpty || channels.contains(normalizeChannel(p.channel))) &&
      (segments.isEmpty || segments.contains(normalizeSegment(p.segment))) &&
      (statuses.isEmpty || statuses.contains(p.status));
}

/// The money figures for a set of orders.
class SalesTotals {
  SalesTotals(Iterable<OrderPoint> orders, Map<String, double> unitCost) {
    for (final p in orders) {
      if (p.status == 'placed') continue; // not paid yet: not a sale
      count++;
      if (p.status == 'cancelled') {
        cancelled++;
        if (p.refunded) refunds += p.total;
        continue;
      }
      net += p.total;
      for (final (name, qty, line) in p.items) {
        units += qty;
        final cost = unitCost[name];
        if (cost == null) {
          uncosted += line;
        } else {
          cogs += cost * qty;
          costedRevenue += line;
        }
      }
    }
    // Money received and not sent back: net revenue plus cancelled orders still awaiting their refund.
    collected = net + _heldForRefund(orders);
  }

  int count = 0, cancelled = 0, net = 0, refunds = 0, units = 0, uncosted = 0, costedRevenue = 0;
  double cogs = 0;
  late final int collected;

  /// Cancelled orders whose money hasn't gone back yet are still cash in hand.
  int _heldForRefund(Iterable<OrderPoint> orders) => orders.where((p) => p.status == 'cancelled' && !p.refunded && p.refundDue).fold(0, (a, p) => a + p.total);

  int get grossProfit => (costedRevenue - cogs).round();
  int get average => count - cancelled == 0 ? 0 : net ~/ (count - cancelled);
  double get cancelRate => count == 0 ? 0 : cancelled * 100 / count;
}

Delta _change(num now, num before, String caption) {
  if (before == 0) return Delta(now == 0 ? 'no change' : 'new', now >= 0, caption: caption);
  final pct = (now - before) * 100 / before.abs();
  return Delta('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%', pct >= 0, caption: caption);
}

/// A titled block of the overview, with an optional note (what it covers, or that filters don't apply).
class DashSection extends StatelessWidget {
  const DashSection({super.key, required this.title, required this.child, this.note});
  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 30),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink)),
      if (note != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(note!, style: const TextStyle(color: muted, fontSize: 13))),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

/// The Founder Overview's sales part (see the top of this file). [middle] goes between the orders section and the
/// recent transactions: the overview's alerts, operations and customer sections.
class FounderDashboard extends StatefulWidget {
  const FounderDashboard({super.key, required this.repo, this.middle = const [], this.onOpenOrders});
  final ModuleRepository repo;
  final List<Widget> middle;
  final VoidCallback? onOpenOrders;

  @override
  State<FounderDashboard> createState() => _FounderDashboardState();
}

class _FounderDashboardState extends State<FounderDashboard> {
  List<OrderPoint>? _orders;
  String? _error;
  bool _live = false;
  SalesFilter _f = const SalesFilter();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final orders = await widget.repo.api.orders(status: 'all').timeout(const Duration(seconds: 8));
      var points = [for (final o in orders) OrderPoint.fromOrder(o)];
      final live = !widget.repo.api.isDemo && points.isNotEmpty;
      if (points.isEmpty) points = [for (final o in widget.repo.records('ordersDemo')) OrderPoint.fromDemo(o)];
      if (mounted) setState(() => (_orders = points, _live = live));
    } catch (_) {
      // Can't reach the order desk: the labelled demo orders, if bundled; else the error.
      final demo = [for (final o in widget.repo.records('ordersDemo')) OrderPoint.fromDemo(o)];
      if (!mounted) return;
      setState(() {
        if (demo.isEmpty) {
          _error = 'Couldn’t load orders.';
        } else {
          _orders = demo;
        }
      });
    }
  }

  void _set(SalesFilter f) => setState(() => (_f = f, _page = 0));

  /// Cost of one box of each product: the average landed cost on its cost sheets (material + conversion + packaging).
  Map<String, double> get _unitCost {
    final spec = navPageSpecs['product-costing'];
    if (spec == null) return const {};
    final sums = <String, (double, int)>{};
    for (final r in rowsFor('product-costing', spec)) {
      final cost = ((r['Material'] as num?) ?? 0) + ((r['Conversion'] as num?) ?? 0) + ((r['Packaging'] as num?) ?? 0);
      final name = '${r['Product']}';
      final (sum, n) = sums[name] ?? (0.0, 0);
      sums[name] = (sum + cost, n + 1);
    }
    return {for (final e in sums.entries) e.key: e.value.$1 / e.value.$2};
  }

  /// Unpaid B2B invoices (Finance › Customer Receivables): (amount, how many, overdue amount).
  (int, int, int) get _receivables {
    final spec = navPageSpecs['receivables'];
    if (spec == null) return (0, 0, 0);
    if (_f.segments.isNotEmpty && !_f.segments.contains('B2B')) return (0, 0, 0);
    if (_f.channels.isNotEmpty && !_f.channels.contains('B2B Direct')) return (0, 0, 0);
    var amount = 0, n = 0, overdue = 0;
    for (final r in rowsFor('receivables', spec)) {
      final st = '${r['Status']}';
      if (st == 'Paid') continue;
      final a = (r['Amount'] as num?)?.round() ?? 0;
      amount += a;
      n++;
      if (st == 'Overdue') overdue += a;
    }
    return (amount, n, overdue);
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    if (_error != null) {
      return _State(icon: Icons.cloud_off_outlined, text: _error!, action: TextButton(onPressed: _load, child: const Text('Try again')));
    }
    if (orders == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));

    final now = DateTime.now();
    final (start, end, prevStart) = _f.window(now);
    bool inRange(OrderPoint p, DateTime? s, DateTime e) => (s == null || !p.at.isBefore(s)) && p.at.isBefore(e);
    final kept = orders.where(_f.keeps).toList();
    final period = [for (final p in kept) if (inRange(p, start, end)) p]..sort((a, b) => b.at.compareTo(a.at));
    final prev = prevStart == null ? <OrderPoint>[] : [for (final p in kept) if (inRange(p, prevStart, start!)) p];
    final unitCost = _unitCost;
    final t = SalesTotals(period, unitCost), tp = SalesTotals(prev, unitCost);
    final (recv, recvCount, recvOverdue) = _receivables;
    final cmp = prevStart == null ? 'all time' : 'vs previous ${_rangeLabels[_f.range]!.toLowerCase()}';

    final first = start ?? (period.isEmpty ? now : period.last.at);
    final b = _Buckets(period, first, end);
    final kpis = [
      MiniStat(highlight: true, icon: Icons.payments_outlined, value: rupees(t.net), label: 'Net revenue', delta: _change(t.net, tp.net, cmp), trend: b.net),
      MiniStat(icon: Icons.account_balance_wallet_outlined, tone: const Color(0xFF2B3A5C), value: rupees(t.collected), label: 'Cash collected', delta: _change(t.collected, tp.collected, cmp), trend: b.cash),
      MiniStat(
        icon: Icons.trending_up,
        tone: const Color(0xFF3E5E3C),
        value: unitCost.isEmpty ? '—' : rupees(t.grossProfit),
        label: 'Gross profit',
        delta: unitCost.isEmpty
            ? const Delta('no cost sheets', false, caption: 'add them in Finance')
            : Delta('${t.costedRevenue == 0 ? 0 : (t.grossProfit * 100 / t.costedRevenue).round()}% margin', t.grossProfit >= 0, caption: t.uncosted > 0 ? 'excl. ${rupees(t.uncosted)} uncosted' : 'from cost sheets'),
      ),
      MiniStat(
        icon: Icons.request_quote_outlined,
        tone: const Color(0xFF8E4A30),
        value: rupees(recv),
        label: 'Outstanding receivables',
        delta: Delta('${rupees(recvOverdue)} overdue', recvOverdue == 0, caption: '$recvCount unpaid B2B invoices'),
      ),
    ];

    return LayoutBuilder(builder: (context, box) {
      final medium = box.maxWidth >= 700, wide = box.maxWidth >= 1400;
      const gap = 16.0;
      final byChannel = _sumBy(period, (p) => normalizeChannel(p.channel), channels);
      final bySegment = _sumBy(period, (p) => normalizeSegment(p.segment), segments);
      final segmentColors = {'B2B': chartPalette[0], 'B2C': chartPalette[1], 'Unknown': otherColor};

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _FilterBar(filter: _f, onChanged: _set, live: _live),
        if (period.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 18), child: _State(icon: Icons.filter_alt_off_outlined, text: 'No orders match these filters in this period.')),
        DashSection(
          title: 'Revenue',
          note: 'Orders past checkout. Net revenue excludes cancelled orders; cash collected is net of refunds sent.',
          child: TilesWithChart(
            tiles: kpis,
            chart: _ChartBox(title: 'Revenue trend', trailing: '${rupees(t.net)} · ${b.unit}', child: AreaTrend(bars: [for (final (i, l) in b.labels.indexed) (l, b.net[i])], second: b.cash, names: ('Net revenue', 'Cash collected'), format: _compact, details: b.details)),
          ),
        ),
        const SizedBox(height: gap),
        () {
          final sold = [for (final p in period) if (p.counts) p];
          final net = math.max(1, sold.fold(0, (a, p) => a + p.total));
          String share(int v) => '${(v * 100 / net).round()}%';
          final channelOrders = _countOf(sold, (p) => normalizeChannel(p.channel));
          final segmentOrders = _countOf(sold, (p) => normalizeSegment(p.segment));
          final channelCard = SmallCard(
            title: 'Revenue by sales channel',
            subtitle: 'Net revenue by platform, with orders and share.',
            child: BarList(dense: true, slices: [for (final s in byChannel) if (s.count > 0) s], format: rupees, detail: (s) => '${channelOrders[s.label] ?? 0} orders · ${share(s.count)}'),
          );
          final segmentCard = SmallCard(
            title: 'Revenue by customer segment',
            subtitle: 'Businesses (B2B) or people (B2C).',
            child: SplitBar(slices: [for (final s in bySegment) Slice('${s.label} · ${segmentOrders[s.label] ?? 0} orders', s.count, segmentColors[s.label]!)], format: rupees),
          );
          final matrix = SmallCard(title: 'Channel × segment', subtitle: 'Net revenue per platform, split by customer type. Hover a part for its figures.', child: _Matrix(orders: period));

          // By city and by payment method: net revenue, with orders.
          final cityRevenue = <String, int>{}, cityOrders = _countOf(sold, (p) => p.city.isEmpty ? 'Unknown' : p.city);
          final payRevenue = <String, int>{}, payOrders = _countOf(sold, (p) => p.payment.isEmpty ? 'Unknown' : p.payment);
          for (final p in sold) {
            final c = p.city.isEmpty ? 'Unknown' : p.city, m = p.payment.isEmpty ? 'Unknown' : p.payment;
            cityRevenue[c] = (cityRevenue[c] ?? 0) + p.total;
            payRevenue[m] = (payRevenue[m] ?? 0) + p.total;
          }
          List<MapEntry<String, int>> top(Map<String, int> m) => (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
          final cityCard = SmallCard(
            title: 'Revenue by city',
            subtitle: 'Top 5 delivery cities.',
            child: BarList(dense: true, slices: [for (final e in top(cityRevenue)) Slice(e.key, e.value, brand)], format: rupees, detail: (s) => '${cityOrders[s.label] ?? 0} orders'),
          );
          final payCard = SmallCard(
            title: 'How customers pay',
            subtitle: 'Net revenue by payment method.',
            child: SplitBar(slices: [for (final (i, e) in top(payRevenue).indexed) Slice('${e.key} · ${payOrders[e.key]} orders', e.value, e.key == 'Unknown' ? otherColor : chartPalette[i])], format: rupees),
          );
          final cancelled = [for (final p in period) if (p.status == 'cancelled') p];
          final waiting = [for (final p in cancelled) if (!p.refunded && p.refundDue) p];
          final unpaid = [for (final p in period) if (p.status == 'placed') p];
          int sum(Iterable<OrderPoint> l) => l.fold(0, (a, p) => a + p.total);
          final refundCard = SmallCard(
            title: 'Cancellations & refunds',
            subtitle: 'In the period, with the same filters.',
            child: _Facts(rows: [
              ('Cancelled orders', '${cancelled.length}', '${t.cancelRate.toStringAsFixed(1)}% of orders · ${rupees(sum(cancelled))}', cancelled.isEmpty),
              ('Refunds sent', rupees(t.refunds), '${cancelled.where((p) => p.refunded).length} orders', true),
              ('Refunds waiting', '${waiting.length}', waiting.isEmpty ? 'nothing to send back' : '${rupees(sum(waiting))} to send back', waiting.isEmpty),
              ('Awaiting payment', '${unpaid.length}', unpaid.isEmpty ? 'no open checkouts' : '${rupees(sum(unpaid))} not paid yet (not counted)', true),
            ]),
          );
          Widget three(List<(int, Widget)> parts) => IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, (flex, w)) in parts.indexed) ...[if (i > 0) const SizedBox(width: gap), Expanded(flex: flex, child: w)],
            ]),
          );
          // Desktop: three across; narrower: two, with the table on its own.
          if (wide) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              three([(1, channelCard), (1, segmentCard), (1, matrix)]),
              const SizedBox(height: gap),
              three([(1, cityCard), (1, payCard), (1, refundCard)]),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            EqualRows(columns: medium ? 2 : 1, gap: gap, children: [channelCard, segmentCard]),
            const SizedBox(height: gap),
            matrix,
            const SizedBox(height: gap),
            EqualRows(columns: medium ? 2 : 1, gap: gap, children: [cityCard, payCard]),
            const SizedBox(height: gap),
            refundCard,
          ]);
        }(),
        DashSection(
          title: 'Orders & sales performance',
          note: 'The same filters and period.',
          child: _OrdersPerformance(totals: t, previous: tp, orders: period, cmp: cmp, counts: b.count, medium: medium, onOpenOrders: widget.onOpenOrders),
        ),
        ...widget.middle,
        DashSection(
          title: 'Recent transactions',
          note: 'Newest first, with the filters above. ${_live ? 'Live from the order desk.' : 'Demo orders.'}',
          child: _Transactions(orders: period, page: _page, onPage: (p) => setState(() => _page = p), wide: medium),
        ),
      ]);
    });
  }
}

final _compactFormat = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _compact(int v) => _compactFormat.format(v);

/// A small white chart card with a title and a figure on the right; the chart fills the rest.
class _ChartBox extends StatelessWidget {
  const _ChartBox({required this.title, required this.child, this.trailing});
  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16.5, color: ink))),
        if (trailing != null) Text(trailing!, style: const TextStyle(color: muted, fontSize: 13)),
      ]),
      const SizedBox(height: 12),
      Expanded(child: child),
    ]),
  );
}

/// The period cut into days, weeks or months: net revenue, cash collected and orders in each.
class _Buckets {
  _Buckets(List<OrderPoint> orders, DateTime start, DateTime end) {
    final step = _bucketDays(start, end);
    final n = math.max(1, (end.difference(start).inDays / step).ceil());
    net = List<int>.filled(n, 0);
    cash = List<int>.filled(n, 0);
    count = List<int>.filled(n, 0);
    byChannel = [for (var i = 0; i < n; i++) <String, int>{}];
    bySegment = [for (var i = 0; i < n; i++) <String, int>{}];
    for (final p in orders) {
      final i = p.at.difference(start).inDays ~/ step;
      if (i < 0 || i >= n || p.status == 'placed') continue;
      final t = SalesTotals([p], const {});
      net[i] += t.net;
      cash[i] += t.collected;
      count[i]++;
      if (t.net > 0) {
        final c = normalizeChannel(p.channel), g = normalizeSegment(p.segment);
        byChannel[i][c] = (byChannel[i][c] ?? 0) + t.net;
        bySegment[i][g] = (bySegment[i][g] ?? 0) + t.net;
      }
    }
    final fmt = DateFormat(step >= 28 ? 'MMM' : 'd MMM');
    labels = [for (var i = 0; i < n; i++) fmt.format(start.add(Duration(days: i * step)))];
    unit = step >= 28 ? 'by month' : step >= 7 ? 'by week' : 'by day';
  }

  late final List<int> net, cash, count;

  /// Each bucket's net revenue by channel and by segment, for the chart's hover text.
  late final List<Map<String, int>> byChannel, bySegment;

  List<String> get details => [
    for (var i = 0; i < net.length; i++)
      '  ·  ${count[i]} orders${breakdownText(byChannel[i], title: 'By channel', format: rupees)}${breakdownText(bySegment[i], title: 'By segment', format: rupees)}',
  ];
  late final List<String> labels;
  late final String unit;
}

int _bucketDays(DateTime s, DateTime e) => e.difference(s).inDays <= 31 ? 1 : e.difference(s).inDays <= 180 ? 7 : 30;

List<Slice> _sumBy(List<OrderPoint> orders, String Function(OrderPoint) key, List<String> order) {
  final sums = {for (final k in order) k: 0};
  for (final p in orders) {
    if (p.status == 'placed' || p.status == 'cancelled') continue;
    sums[key(p)] = (sums[key(p)] ?? 0) + p.total;
  }
  return [for (final k in order) if (sums[k]! > 0 || k != 'Unknown') Slice(k, sums[k]!, k == 'Unknown' ? otherColor : chartPalette[0])];
}

Map<String, int> _countOf(Iterable<OrderPoint> orders, String Function(OrderPoint) key) {
  final m = <String, int>{};
  for (final p in orders) {
    m[key(p)] = (m[key(p)] ?? 0) + 1;
  }
  return m;
}

/// Label, figure and a grey note, one per line: a compact list of facts.
class _Facts extends StatelessWidget {
  const _Facts({required this.rows});
  final List<(String, String, String, bool)> rows; // label, value, note, fine (else amber)

  @override
  Widget build(BuildContext context) => Column(children: [
    for (final (i, (label, value, note, fine)) in rows.indexed)
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEDF2F0)))),
        child: Row(children: [
          Icon(fine ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: fine ? up : const Color(0xFF8A5A00)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ink)),
              Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: muted)),
            ]),
          ),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
        ]),
      ),
  ]);
}

/// Loading, empty and error messages.
class _State extends StatelessWidget {
  const _State({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
    child: Column(children: [Icon(icon, color: muted), const SizedBox(height: 8), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: muted)), ?action]),
  );
}

/// Dates, channels, segments and order statuses: one row of filters for the whole sales part.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onChanged, required this.live});
  final SalesFilter filter;
  final ValueChanged<SalesFilter> onChanged;
  final bool live;

  Widget _multi(BuildContext context, String label, List<String> options, Set<String> selected, ValueChanged<Set<String>> set, {Map<String, String>? names}) =>
      PopupMenuButton<String>(
        tooltip: label,
        onSelected: (o) {
          if (o == '') return set({});
          final next = {...selected};
          next.contains(o) ? next.remove(o) : next.add(o);
          set(next);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text('All ${label.toLowerCase()}s')),
          for (final o in options) CheckedPopupMenuItem(value: o, checked: selected.contains(o), child: Text(names?[o] ?? o)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected.isEmpty ? Colors.white : const Color(0xFFDDF3EC),
            border: Border.all(color: selected.isEmpty ? const Color(0xFFCBD5D1) : brand),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(selected.isEmpty ? '$label: all' : '$label: ${selected.length == 1 ? (names?[selected.single] ?? selected.single) : '${selected.length} selected'}',
                style: TextStyle(color: selected.isEmpty ? const Color(0xFF34443F) : brand, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final active = f.channels.isNotEmpty || f.segments.isNotEmpty || f.statuses.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final r in DateRange.values)
          ChoiceChip(
            label: Text(r == DateRange.custom && f.range == DateRange.custom && f.from != null
                ? '${DateFormat('d MMM').format(f.from!)} – ${DateFormat('d MMM').format(f.to!)}'
                : _rangeLabels[r]!),
            selected: f.range == r,
            onSelected: (_) async {
              if (r != DateRange.custom) return onChanged(f.copyWith(range: r));
              final now = DateTime.now();
              final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1), initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now));
              if (picked != null) onChanged(f.copyWith(range: DateRange.custom, from: picked.start, to: picked.end));
            },
          ),
        const SizedBox(width: 6),
        _multi(context, 'Channel', channels, f.channels, (v) => onChanged(f.copyWith(channels: v))),
        _multi(context, 'Segment', segments, f.segments, (v) => onChanged(f.copyWith(segments: v))),
        _multi(context, 'Status', _statusLabels.keys.toList(), f.statuses, (v) => onChanged(f.copyWith(statuses: v)), names: _statusLabels),
        if (active) TextButton(onPressed: () => onChanged(SalesFilter(range: f.range, from: f.from, to: f.to)), child: const Text('Clear filters')),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: live ? const Color(0xFFDDF3EC) : const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(999)),
          child: Text(live ? 'Live orders' : 'Demo data', style: TextStyle(color: live ? brand : const Color(0xFF7F5300), fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// Channel × segment as one small chart: a bar per channel (as long as its net revenue), cut by segment, with its
/// total and orders beside it; segment totals underneath. Each order is in exactly one part.
class _Matrix extends StatelessWidget {
  const _Matrix({required this.orders});
  final List<OrderPoint> orders;

  static final _colors = {'B2B': chartPalette[0], 'B2C': chartPalette[1], 'Unknown': otherColor};

  @override
  Widget build(BuildContext context) {
    final cell = <(String, String), (int, int)>{};
    for (final p in orders) {
      if (!p.counts) continue;
      final k = (normalizeChannel(p.channel), normalizeSegment(p.segment));
      final (v, n) = cell[k] ?? (0, 0);
      cell[k] = (v + p.total, n + 1);
    }
    if (cell.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No sales in this period.', style: TextStyle(color: muted)));
    (int, int) sum(bool Function((String, String)) keep) =>
        cell.entries.where((e) => keep(e.key)).fold((0, 0), (a, e) => (a.$1 + e.value.$1, a.$2 + e.value.$2));
    final rows = [for (final c in channels) if (sum((k) => k.$1 == c).$2 > 0) c];
    final top = rows.fold(0, (a, c) => math.max(a, sum((k) => k.$1 == c).$1));
    final total = sum((_) => true);
    Widget dot(Color c) => Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (final s in segments)
          if (sum((k) => k.$2 == s).$2 > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [dot(_colors[s]!), const SizedBox(width: 6), Text(s, style: const TextStyle(fontSize: 12, color: muted))]),
      ]),
      const SizedBox(height: 10),
      for (final c in rows)
        () {
          final (v, n) = sum((k) => k.$1 == c);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 92, child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFF34443F)))),
              Expanded(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: top == 0 ? 0 : math.max(0.02, v / top),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(children: [
                      for (final (i, s) in [for (final s in segments) if ((cell[(c, s)]?.$1 ?? 0) > 0) s].indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: math.max(1, cell[(c, s)]!.$1),
                          child: Tooltip(
                            message: '$c · $s: ${rupees(cell[(c, s)]!.$1)} · ${cell[(c, s)]!.$2} orders',
                            child: Container(height: 12, color: _colors[s]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 108,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(rupees(v), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ink)),
                  Text('$n orders', style: const TextStyle(fontSize: 11, color: muted)),
                ]),
              ),
            ]),
          );
        }(),
      const Divider(height: 18, color: Color(0xFFEDF2F0)),
      Wrap(spacing: 16, runSpacing: 6, children: [
        for (final s in segments)
          if (sum((k) => k.$2 == s).$2 > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              dot(_colors[s]!),
              const SizedBox(width: 6),
              Text('$s ${rupees(sum((k) => k.$2 == s).$1)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
              Text(' · ${sum((k) => k.$2 == s).$2} orders', style: const TextStyle(fontSize: 11.5, color: muted)),
            ]),
        Text('Total ${rupees(total.$1)} · ${total.$2} orders', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brand)),
      ]),
    ]);
  }
}

/// Orders, average order, cancellations and boxes sold, then orders by status and best sellers.
class _OrdersPerformance extends StatelessWidget {
  const _OrdersPerformance({required this.totals, required this.previous, required this.orders, required this.cmp, required this.counts, required this.medium, this.onOpenOrders});
  final SalesTotals totals, previous;
  final List<OrderPoint> orders;
  final List<int> counts;
  final String cmp;
  final bool medium;
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final t = totals, p = previous;
    final number = NumberFormat.decimalPattern('en_IN');
    final delivered = orders.where((o) => o.status == 'delivered').length;
    final inProgress = orders.where((o) => const {'confirmed', 'packed', 'shipped', 'out_for_delivery'}.contains(o.status)).length;
    final tiles = [
      MiniStat(highlight: true, icon: Icons.receipt_long_outlined, value: number.format(t.count), label: 'Orders', delta: _change(t.count, p.count, cmp), trend: counts, onTap: onOpenOrders),
      MiniStat(icon: Icons.shopping_bag_outlined, tone: const Color(0xFF5B3F73), value: rupees(t.average), label: 'Average order', delta: _change(t.average, p.average, cmp)),
      MiniStat(icon: Icons.inventory_2_outlined, tone: const Color(0xFF2B3A5C), value: number.format(t.units), label: 'Boxes sold', delta: _change(t.units, p.units, cmp)),
      MiniStat(icon: Icons.cancel_outlined, tone: const Color(0xFFB3261E), value: '${t.cancelRate.toStringAsFixed(1)}%', label: 'Cancelled', delta: Delta('${t.cancelled} of ${t.count}', t.cancelRate < 10, caption: 'refunds sent ${rupees(t.refunds)}')),
      MiniStat(
        icon: Icons.local_shipping_outlined,
        tone: const Color(0xFF8A5A00),
        value: number.format(inProgress),
        label: 'In progress',
        hint: 'To pack, packed or on the way',
        onTap: onOpenOrders,
      ),
      MiniStat(
        icon: Icons.check_circle_outline,
        tone: const Color(0xFF3E5E3C),
        value: number.format(delivered),
        label: 'Delivered',
        hint: t.count == 0 ? 'No orders yet' : '${(delivered * 100 / t.count).round()}% of orders',
      ),
    ];
    final statusSlices = [
      for (final (i, e) in _statusLabels.entries.indexed)
        Slice(e.value, orders.where((o) => o.status == e.key).length, e.key == 'cancelled' ? const Color(0xFFD03B3B) : e.key == 'placed' ? const Color(0xFFE39A00) : greens[math.min(i, 4)]),
    ];
    final units = <String, int>{}, revenue = <String, int>{};
    for (final o in orders.where((o) => o.status != 'placed' && o.status != 'cancelled')) {
      for (final (name, qty, line) in o.items) {
        units[name] = (units[name] ?? 0) + qty;
        revenue[name] = (revenue[name] ?? 0) + line;
      }
    }
    final best = (revenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => Slice('${e.key} · ${units[e.key]} boxes', e.value, chartPalette[0], image: productImageFor(e.key))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MiniStatGrid(tiles: tiles, across: 6),
      const SizedBox(height: 16),
      EqualRows(columns: medium ? 2 : 1, gap: 16, children: [
        SmallCard(
          title: 'Orders by status',
          subtitle: '${orders.length} orders in the period, including unpaid checkouts.',
          trailing: onOpenOrders == null ? null : SeeAll(onTap: onOpenOrders!, label: 'Order desk'),
          child: SplitBar(slices: statusSlices, centerLabel: 'orders'),
        ),
        SmallCard(title: 'Best sellers', subtitle: 'Net revenue by product, with boxes sold.', child: BarList(dense: true, slices: best, format: rupees)),
      ]),
    ]);
  }
}

/// The period's orders, newest first, ten to a page.
class _Transactions extends StatelessWidget {
  const _Transactions({required this.orders, required this.page, required this.onPage, required this.wide});
  final List<OrderPoint> orders;
  final int page;
  final ValueChanged<int> onPage;
  final bool wide;

  static const _per = 10;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const _State(icon: Icons.receipt_long_outlined, text: 'No orders in this period.');
    final pages = (orders.length / _per).ceil();
    final p = page.clamp(0, pages - 1);
    final rows = orders.skip(p * _per).take(_per).toList();
    final date = DateFormat('d MMM, h:mm a');
    Widget chip(String status) {
      final bad = status == 'cancelled', waiting = status == 'placed';
      final (bg, fg) = bad
          ? (const Color(0xFFF3E3E3), const Color(0xFF8B2E2E))
          : waiting
          ? (const Color(0xFFFFF4D6), const Color(0xFF8A5A00))
          : (const Color(0xFFDDF3EC), brand);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(_statusLabels[status] ?? status, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      );
    }

    final table = wide
        ? Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: line)),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(Color(0xFFF4F8F6)),
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF34443F), fontSize: 13),
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Order')),
                      DataColumn(label: Text('Channel')),
                      DataColumn(label: Text('Segment')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Payment')),
                      DataColumn(label: Text('Amount'), numeric: true),
                    ],
                    rows: [
                      for (final o in rows)
                        DataRow(cells: [
                          DataCell(Text(date.format(o.at))),
                          DataCell(Text(o.id, style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(normalizeChannel(o.channel))),
                          DataCell(Text(normalizeSegment(o.segment))),
                          DataCell(chip(o.status)),
                          DataCell(Text(o.payment)),
                          DataCell(Text(rupees(o.total), style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Column(children: [
            for (final o in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(o.id, style: const TextStyle(fontWeight: FontWeight.w600))), Text(rupees(o.total), style: const TextStyle(fontWeight: FontWeight.w600))]),
                  const SizedBox(height: 6),
                  Text('${date.format(o.at)} · ${normalizeChannel(o.channel)} · ${normalizeSegment(o.segment)} · ${o.payment}', style: const TextStyle(color: muted, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  chip(o.status),
                ]),
              ),
          ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      table,
      const SizedBox(height: 10),
      PageControls(page: p, pages: pages, total: orders.length, per: _per, onPage: onPage),
    ]);
  }
}

/// "11–20 of 140" with previous and next.
class PageControls extends StatelessWidget {
  const PageControls({super.key, required this.page, required this.pages, required this.total, required this.per, required this.onPage});
  final int page, pages, total, per;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
    Text('${page * per + 1}–${math.min(total, (page + 1) * per)} of $total', style: const TextStyle(color: muted, fontSize: 13)),
    const SizedBox(width: 8),
    IconButton(tooltip: 'Previous page', onPressed: page > 0 ? () => onPage(page - 1) : null, icon: const Icon(Icons.chevron_left)),
    IconButton(tooltip: 'Next page', onPressed: page < pages - 1 ? () => onPage(page + 1) : null, icon: const Icon(Icons.chevron_right)),
  ]);
}
