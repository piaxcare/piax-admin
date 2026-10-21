import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/order_detail_screen.dart';

Order _order({String method = 'razorpay', String payment = 'paid', String recipient = 'Asha Kumar'}) => Order.fromJson({
  'id': 'PX-261016-EAGP9',
  'createdAt': '2026-10-16T07:00:21.030Z',
  'contact': {'name': 'Asha Kumar', 'phone': '9876543210', 'email': 'asha.kumar.longemail@example.com'},
  'address': {
    'name': recipient,
    'phone': '9876543210',
    'line1': 'No. 12, 3rd Cross Street, Sri Lakshmi Apartments, Flat 4B',
    'line2': 'Navalpur',
    'landmark': 'near Apollo Hospital',
    'city': 'Ranipet',
    'state': 'Tamil Nadu',
    'pincode': '632401',
    'type': 'Home',
    'location': {'lat': 12.93, 'lng': 79.33},
  },
  'items': [
    {'name': 'PIAX LUMA', 'subtitle': '290mm', 'quantity': 2, 'price': 199, 'lineTotal': 398},
  ],
  'totals': {'subtotal': 398, 'couponDiscount': 0, 'delivery': 0, 'total': 398},
  'payment': {'method': method, 'status': payment},
  'status': 'packed',
  'history': [
    {'status': 'packed', 'at': '2026-10-16T07:00:43.560Z'},
  ],
  'tracking': null,
  'estimatedDelivery': {'earliest': '2026-10-18T00:00:00.000Z', 'latest': '2026-10-20T00:00:00.000Z'},
});

Future<void> _show(WidgetTester tester, Order order) async {
  tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // No server in tests: the screen keeps the order it was opened with.
  final api = AdminApi('http://127.0.0.1:9', token: 't');
  await tester.pumpWidget(
    MaterialApp(
      home: OrderDetailScreen(api: api, orderId: order.id, initial: order),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('customer and delivery cards lay out on a phone and say what to collect', (tester) async {
    await _show(tester, _order());
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Asha Kumar'), findsWidgets);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(find.text('Delivery address'), findsOneWidget);
    expect(find.text('Flat, house no., building, street'), findsOneWidget);
    expect(find.text('632401'), findsOneWidget);
    expect(find.text('Prepaid: nothing to collect'), findsOneWidget);
    expect(find.textContaining('pinned the exact spot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash on delivery shows the amount to collect, and a different receiver is pointed out', (tester) async {
    await _show(tester, _order(method: 'cod', payment: 'not_required', recipient: 'Meena R'));
    expect(find.text('Collect ₹398 in cash'), findsOneWidget);
    expect(find.textContaining('Someone else receives this parcel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unpaid online order warns not to send it', (tester) async {
    await _show(tester, _order(payment: 'pending'));
    expect(find.text('Not paid yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
