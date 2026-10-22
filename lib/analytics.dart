// The Analytics page's numbers, worked out from the website's anonymous order facts (GET /api/admin/analytics).
// Pure logic, no Flutter, so it can be tested on its own.
//
// Counting rules, used everywhere on the page:
//   - an order counts once it's past checkout (not "placed", which is an unpaid checkout);
//   - revenue is what was paid, for orders that weren't cancelled (cash on delivery counts once it's collected);
//   - packs are the boxes in those orders (cancelled ones left out).

import 'models.dart';

class OrderFact {
  OrderFact({
    required this.day,
    required this.status,
    required this.method,
    required this.paid,
    required this.total,
    required this.city,
    required this.state,
    required this.items,
    required this.deliveredInDays,
  });

  final DateTime day;
  final OrderStatus status;
  final String method; // razorpay | cod
  final bool paid;
  final int total;
  final String city, state;
  final List<(String product, int quantity, int amount)> items;
  final int? deliveredInDays;

  bool get counted => status != OrderStatus.placed;
  bool get earns => paid && status != OrderStatus.cancelled;

  factory OrderFact.fromJson(Map<String, dynamic> j) {
    final parts = (j['day'] as String? ?? '').split('-').map(int.tryParse).toList();
    return OrderFact(
      day: parts.length == 3 && !parts.contains(null) ? DateTime(parts[0]!, parts[1]!, parts[2]!) : DateTime.now(),
      status: OrderStatus.parse(j['status'] as String?),
      method: (j['method'] as String?) ?? 'razorpay',
      paid: j['paid'] == true,
      total: (j['total'] as num?)?.round() ?? 0,
      city: _title((j['city'] as String?) ?? ''),
      state: _title((j['state'] as String?) ?? ''),
      items: ((j['items'] as List?) ?? [])
          .map(
            (i) =>
                ((i as Map)['product']?.toString() ?? 'other', (i['quantity'] as num?)?.round() ?? 0, (i['amount'] as num?)?.round() ?? 0),
          )
          .toList(),
      deliveredInDays: (j['deliveredInDays'] as num?)?.round(),
    );
  }
}

String _title(String s) =>
    s.trim().isEmpty ? 'Not given' : s.trim().split(RegExp(r'\s+')).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');

/// The date ranges the page offers. `days == null` is all time.
enum AnalyticsRange {
  week('7 days', 7),
  month('30 days', 30),
  quarter('90 days', 90),
  year('12 months', 365),
  all('All time', null);

  const AnalyticsRange(this.label, this.days);
  final String label;
  final int? days;
}

enum Bucket { day, week, month }

/// One point on a time chart.
class Point {
  Point(this.start, this.label, {this.orders = 0, this.revenue = 0});
  final DateTime start;
  final String label;
  int orders;
  int revenue;

  /// What the point is made of, for the charts' hover text: revenue by product (id) and orders by status.
  final Map<String, int> revenueByProduct = {};
  final Map<String, int> ordersByStatus = {};
}

class Kpis {
  Kpis({
    required this.revenue,
    required this.orders,
    required this.paidOrders,
    required this.packs,
    required this.delivered,
    required this.cancelled,
  });
  final int revenue, orders, paidOrders, packs, delivered, cancelled;

  /// Average order value: revenue over the orders it came from.
  int get average => paidOrders == 0 ? 0 : (revenue / paidOrders).round();
  double get deliveredShare => orders == 0 ? 0 : delivered / orders;
  double get cancelledShare => orders == 0 ? 0 : cancelled / orders;

  static Kpis of(Iterable<OrderFact> facts) {
    final counted = facts.where((f) => f.counted).toList();
    return Kpis(
      revenue: counted.where((f) => f.earns).fold(0, (sum, f) => sum + f.total),
      orders: counted.length,
      paidOrders: counted.where((f) => f.earns).length,
      packs: counted.where((f) => f.status != OrderStatus.cancelled).fold(0, (sum, f) => sum + f.items.fold(0, (n, i) => n + i.$2)),
      delivered: counted.where((f) => f.status == OrderStatus.delivered).length,
      cancelled: counted.where((f) => f.status == OrderStatus.cancelled).length,
    );
  }
}

/// Change from [before] to [now] as a fraction (0.12 = +12%), or null when there's nothing to compare with.
double? change(num now, num before) => before == 0 ? (now == 0 ? 0 : null) : (now - before) / before;

class Analytics {
  Analytics._({
    required this.range,
    required this.from,
    required this.to,
    required this.kpis,
    required this.previous,
    required this.bucket,
    required this.series,
    required this.places,
    required this.states,
    required this.products,
    required this.statuses,
    required this.payments,
    required this.averageDaysToDeliver,
  });

  final AnalyticsRange range;
  final DateTime from, to;
  final Kpis kpis;

  /// The same figures for the period just before (same length), for the change arrows. Null for all time.
  final Kpis? previous;
  final Bucket bucket;
  final List<Point> series;

  /// Top places by orders: (name, orders, revenue).
  final List<(String, int, int)> places;
  final List<(String, int, int)> states;

  /// Products by packs sold: (product id, packs, revenue), in the range's fixed order (see [productOrder]).
  final List<(String, int, int)> products;

  /// Orders at each step (counted orders only).
  final Map<OrderStatus, int> statuses;

  /// Orders by payment method: (online, cash on delivery).
  final (int, int) payments;
  final double? averageDaysToDeliver;

  /// Products in a fixed order, so each keeps its colour whatever the range.
  static const productOrder = ['vera', 'luma', 'nocte', 'seren', 'cycle', 'other'];

  static Analytics compute(List<OrderFact> all, AnalyticsRange range, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    final earliest = all.isEmpty ? today : all.map((f) => f.day).reduce((a, b) => a.isBefore(b) ? a : b);
    final from = range.days == null ? earliest : today.subtract(Duration(days: range.days! - 1));
    final inRange = all.where((f) => !f.day.isBefore(from) && !f.day.isAfter(today)).toList();
    Kpis? previous;
    if (range.days != null) {
      final prevFrom = from.subtract(Duration(days: range.days!));
      previous = Kpis.of(all.where((f) => !f.day.isBefore(prevFrom) && f.day.isBefore(from)));
    }

    final spanDays = today.difference(from).inDays + 1;
    final bucket = spanDays <= 45
        ? Bucket.day
        : spanDays <= 120
        ? Bucket.week
        : Bucket.month;
    final series = _series(inRange, from, today, bucket);

    final counted = inRange.where((f) => f.counted).toList();
    List<(String, int, int)> groupBy(String Function(OrderFact) key) {
      final map = <String, (int, int)>{};
      for (final f in counted) {
        final k = key(f);
        final (o, r) = map[k] ?? (0, 0);
        map[k] = (o + 1, r + (f.earns ? f.total : 0));
      }
      return map.entries.map((e) => (e.key, e.value.$1, e.value.$2)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    }

    final productMap = <String, (int, int)>{};
    for (final f in counted.where((f) => f.status != OrderStatus.cancelled)) {
      for (final (product, quantity, amount) in f.items) {
        final id = productOrder.contains(product) ? product : 'other';
        final (q, a) = productMap[id] ?? (0, 0);
        productMap[id] = (q + quantity, a + amount);
      }
    }
    final products = [
      for (final id in productOrder)
        if (productMap.containsKey(id)) (id, productMap[id]!.$1, productMap[id]!.$2),
    ];

    final statuses = {
      for (final s in OrderStatus.values.where((s) => s != OrderStatus.placed)) s: counted.where((f) => f.status == s).length,
    };
    final online = counted.where((f) => f.method != 'cod').length;
    final delivered = counted.map((f) => f.deliveredInDays).whereType<int>().toList();

    return Analytics._(
      range: range,
      from: from,
      to: today,
      kpis: Kpis.of(inRange),
      previous: previous,
      bucket: bucket,
      series: series,
      places: groupBy((f) => f.city),
      states: groupBy((f) => f.state),
      products: products,
      statuses: statuses,
      payments: (online, counted.length - online),
      averageDaysToDeliver: delivered.isEmpty ? null : delivered.reduce((a, b) => a + b) / delivered.length,
    );
  }

  /// Revenue change from each bucket to the next (null when the earlier one had none): the growth chart.
  List<double?> get growth => [for (var i = 0; i < series.length; i++) i == 0 ? null : change(series[i].revenue, series[i - 1].revenue)];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<Point> _series(List<OrderFact> facts, DateTime from, DateTime to, Bucket bucket) {
    DateTime startOf(DateTime d) => switch (bucket) {
      Bucket.day => d,
      Bucket.week => d.subtract(Duration(days: d.weekday - 1)),
      Bucket.month => DateTime(d.year, d.month),
    };
    DateTime next(DateTime d) => switch (bucket) {
      Bucket.day => d.add(const Duration(days: 1)),
      Bucket.week => d.add(const Duration(days: 7)),
      Bucket.month => DateTime(d.year, d.month + 1),
    };
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String label(DateTime d) => switch (bucket) {
      Bucket.day => '${d.day} ${months[d.month - 1]}',
      Bucket.week => '${d.day} ${months[d.month - 1]}',
      Bucket.month => "${months[d.month - 1]} '${d.year % 100}",
    };
    final points = <Point>[];
    for (var d = startOf(from); !d.isAfter(to); d = next(d)) {
      points.add(Point(d, label(d)));
    }
    for (final f in facts.where((f) => f.counted)) {
      final start = startOf(f.day);
      final point = points.where((p) => p.start == start).firstOrNull;
      if (point == null) continue;
      point.orders++;
      point.ordersByStatus[f.status.label] = (point.ordersByStatus[f.status.label] ?? 0) + 1;
      if (f.earns) {
        point.revenue += f.total;
        for (final (product, _, amount) in f.items) {
          point.revenueByProduct[product] = (point.revenueByProduct[product] ?? 0) + amount;
        }
      }
    }
    return points;
  }
}
