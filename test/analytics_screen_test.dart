import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/analytics.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/screens/analytics_screen.dart';

class _FakeApi extends AdminApi {
  _FakeApi(this.facts) : super('http://127.0.0.1:9', token: 't');
  final List<OrderFact> facts;
  @override
  Future<List<OrderFact>> analytics() async => facts;
}

List<OrderFact> _facts() {
  final today = DateTime.now();
  final statuses = ['confirmed', 'packed', 'shipped', 'out_for_delivery', 'delivered', 'cancelled'];
  final products = ['vera', 'luma', 'nocte', 'seren', 'cycle'];
  return [
    for (var i = 0; i < 60; i++)
      OrderFact.fromJson({
        'day': today.subtract(Duration(days: i % 40)).toIso8601String().substring(0, 10),
        'status': statuses[i % statuses.length],
        'method': i % 4 == 0 ? 'cod' : 'razorpay',
        'paid': i % 4 != 0,
        'total': 199 + (i % 5) * 100,
        'city': ['Chennai', 'Vellore', 'Ranipet', 'Walajapet'][i % 4],
        'state': 'Tamil Nadu',
        'items': [
          {'product': products[i % 5], 'quantity': 1 + i % 3, 'amount': 199},
        ],
        'deliveredInDays': i % 6 == 4 ? 3 : null,
      }),
  ];
}

void main() {
  for (final (name, size) in [('phone', const Size(390, 3000)), ('tablet', const Size(820, 3000)), ('desktop', const Size(1440, 3000))]) {
    testWidgets('analytics page renders on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(api: _FakeApi(_facts()))));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.text('Market growth'), findsOneWidget);
      expect(find.text('Orders by place'), findsOneWidget);
    });
  }
}
