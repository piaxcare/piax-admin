import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/founder_dashboard.dart';
import 'package:piax_orders_admin/admin_modules/revenue_section.dart';

// The Founder Overview's sums: two independent labels, each order counted once, money figures kept apart.
void main() {
  OrderPoint o(String status, int total, {String? channel, String? segment, bool refunded = false, bool refundDue = false}) => OrderPoint(
    at: DateTime(2026, 10, 20),
    status: status,
    total: total,
    city: 'Chennai',
    payment: 'UPI',
    items: [('PIAX LUMA', 1, total)],
    refundDue: refundDue,
    channel: channel,
    segment: segment,
    refunded: refunded,
  );

  test('channels and segments: known names, missing ones Unknown, never guessed', () {
    expect(normalizeChannel('website'), 'Web');
    expect(normalizeChannel('Amazon'), 'Marketplace');
    expect(normalizeChannel(null), 'Unknown');
    expect(normalizeChannel('telephone'), 'Other');
    expect(normalizeSegment('b2b'), 'B2B');
    expect(normalizeSegment(''), 'Unknown');
    expect(normalizeSegment('enterprise'), 'Unknown');
  });

  test('net revenue, cash collected and refunds are kept apart', () {
    final t = SalesTotals([
      o('delivered', 500),
      o('placed', 300), // not paid: not a sale
      o('cancelled', 200, refunded: true), // money sent back
      o('cancelled', 100, refundDue: true), // money still held
    ], {'PIAX LUMA': 150});
    expect(t.count, 3);
    expect(t.net, 500);
    expect(t.collected, 600); // 500 + 100 still held
    expect(t.refunds, 200);
    expect(t.grossProfit, 350); // 500 − 1 box × 150
  });

  test('revenue from products without a cost sheet is left out of gross profit, and counted', () {
    final t = SalesTotals([o('delivered', 400)], const {});
    expect(t.grossProfit, 0);
    expect(t.uncosted, 400);
  });

  test('a filter by channel and segment keeps each order once', () {
    final orders = [o('delivered', 100, channel: 'Web', segment: 'B2C'), o('delivered', 200, channel: 'B2B Direct', segment: 'B2B'), o('delivered', 50)];
    const f = SalesFilter(channels: {'Web', 'Unknown'});
    expect(orders.where(f.keeps).map((p) => p.total), [100, 50]);
    const g = SalesFilter(segments: {'B2B'});
    expect(orders.where(g.keeps).map((p) => p.total), [200]);
  });
}
