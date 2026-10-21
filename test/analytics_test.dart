import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/analytics.dart';

final _now = DateTime(2026, 10, 16);

OrderFact _f(
  int daysAgo,
  String status, {
  bool paid = true,
  int total = 400,
  String method = 'razorpay',
  String city = 'chennai',
  List<(String, int, int)>? items,
  int? deliveredIn,
}) => OrderFact.fromJson({
  'day': _now.subtract(Duration(days: daysAgo)).toIso8601String().substring(0, 10),
  'status': status,
  'method': method,
  'paid': paid,
  'total': total,
  'city': city,
  'state': 'tamil nadu',
  'items': [
    for (final (p, q, a) in items ?? [('luma', 2, 398)]) {'product': p, 'quantity': q, 'amount': a},
  ],
  'deliveredInDays': deliveredIn,
});

void main() {
  final facts = [
    _f(0, 'confirmed'),
    _f(1, 'delivered', deliveredIn: 3, items: [('vera', 1, 199), ('cycle', 1, 249)], total: 448),
    _f(2, 'cancelled', total: 1000), // paid then cancelled: an order, but no revenue
    _f(3, 'placed', paid: false, total: 5000), // unpaid checkout: not an order
    _f(5, 'shipped', method: 'cod', paid: false, city: 'walajapet'), // cash not collected yet: an order, no revenue
    _f(40, 'delivered', total: 300, deliveredIn: 5), // previous 30 days
  ];

  test('headline numbers follow the counting rules', () {
    final a = Analytics.compute(facts, AnalyticsRange.month, now: _now);
    expect(a.kpis.orders, 4, reason: 'unpaid checkout and the order from 40 days ago left out');
    expect(a.kpis.revenue, 400 + 448, reason: 'paid and not cancelled only');
    expect(a.kpis.average, 424);
    expect(a.kpis.cancelled, 1);
    expect(a.kpis.delivered, 1);
    expect(a.kpis.packs, 2 + 2 + 2, reason: 'cancelled order’s packs left out');
    expect(a.previous!.revenue, 300);
    expect(change(a.kpis.revenue, a.previous!.revenue), closeTo(1.8267, .001));
  });

  test('time series, places, products, steps and payment', () {
    final a = Analytics.compute(facts, AnalyticsRange.month, now: _now);
    expect(a.bucket, Bucket.day);
    expect(a.series.length, 30);
    expect(a.series.last.orders, 1);
    expect(a.series.fold(0, (n, p) => n + p.revenue), 848);
    expect(a.places.first, ('Chennai', 3, 848));
    expect(a.products.map((p) => p.$1).toList(), ['vera', 'luma', 'cycle'], reason: 'fixed product order, so colours never move');
    expect(a.statuses[OrderStatus.cancelled], 1);
    expect(a.payments, (3, 1));
    expect(a.averageDaysToDeliver, 3);
  });

  test('longer ranges group by week, then month; all time has no comparison', () {
    expect(Analytics.compute(facts, AnalyticsRange.quarter, now: _now).bucket, Bucket.week);
    expect(Analytics.compute(facts, AnalyticsRange.year, now: _now).bucket, Bucket.month);
    final all = Analytics.compute(facts, AnalyticsRange.all, now: _now);
    expect(all.previous, isNull);
    expect(all.kpis.orders, 5);
  });

  test('growth compares each period with the one before', () {
    final a = Analytics.compute(facts, AnalyticsRange.week, now: _now);
    final g = a.growth;
    expect(g.first, isNull);
    expect(g.length, a.series.length);
  });
}
