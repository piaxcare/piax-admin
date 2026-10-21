import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/order_detail_screen.dart';
import 'package:piax_orders_admin/whatsapp.dart';

Order _cancelled({String payment = 'refund_pending', String method = 'razorpay', Map<String, dynamic>? refund}) =>
    Order.fromJson(_cancelledJson(payment: payment, method: method, refund: refund));

Map<String, dynamic> _cancelledJson({String payment = 'refund_pending', String method = 'razorpay', Map<String, dynamic>? refund}) => {
  'id': 'PX-261016-EAGP9',
  'createdAt': '2026-10-16T07:00:21.030Z',
  'contact': {'name': 'Asha Kumar', 'phone': '9876543210', 'email': 'asha@example.com'},
  'address': {
    'name': 'Asha Kumar',
    'phone': '9876543210',
    'line1': '12 Lake Road',
    'line2': '',
    'landmark': '',
    'city': 'Ranipet',
    'state': 'Tamil Nadu',
    'pincode': '632401',
    'type': 'Home',
  },
  'items': [
    {'name': 'PIAX LUMA', 'subtitle': '290mm', 'quantity': 2, 'price': 199, 'lineTotal': 398},
  ],
  'totals': {'subtotal': 398, 'couponDiscount': 0, 'delivery': 0, 'total': 398},
  'payment': {'method': method, 'status': payment, 'paymentId': 'pay_123', 'refund': ?refund},
  'status': 'cancelled',
  'cancelReason': 'Out of stock',
  'history': [
    {'status': 'cancelled', 'at': '2026-10-16T08:00:00.000Z', 'note': 'Cancelled: Out of stock'},
  ],
  'tracking': null,
  'estimatedDelivery': {'earliest': '2026-10-18T00:00:00.000Z', 'latest': '2026-10-20T00:00:00.000Z'},
};

Future<void> _show(WidgetTester tester, Order order) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: OrderDetailScreen(
        api: AdminApi('http://127.0.0.1:9', token: 't'),
        orderId: order.id,
        initial: order,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  test('refund data and the "needs refund" rule', () {
    expect(_cancelled().needsRefund, isTrue);
    expect(
      _cancelled(method: 'cod', payment: 'not_required').needsRefund,
      isFalse,
      reason: 'cash on delivery: nothing paid online',
    );
    final done = _cancelled(payment: 'refunded', refund: {'id': 'rfnd_1', 'amount': 398, 'at': '2026-10-17T03:58:06.187Z', 'test': true});
    expect(done.needsRefund, isFalse);
    expect(done.payment.statusLabel, 'Refunded');
    expect(done.payment.refund!.amount, 398);
    expect(done.payment.refund!.test, isTrue);
  });

  test('the "Refund issued" message is only sendable once refunded', () {
    expect(CustomerMessage.refunded.api, 'refunded');
    expect(CustomerMessage.refunded.reached(_cancelled()), isFalse);
    final done = _cancelled(payment: 'refunded', refund: {'id': 'rfnd_1', 'amount': 398, 'at': '2026-10-17T03:58:06.187Z'});
    expect(CustomerMessage.refunded.reached(done), isTrue);
    expect(CustomerMessage.refunded.textFor(done), contains('₹398'));
  });

  testWidgets('a cancelled, paid order shows the refund due with its button', (tester) async {
    await _show(tester, _cancelled());
    expect(find.text('Refund due: ₹398'), findsOneWidget);
    expect(find.text('Refund ₹398 now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refunded order says so, with no refund button', (tester) async {
    await _show(tester, _cancelled(payment: 'refunded', refund: {'id': 'rfnd_1', 'amount': 398, 'at': '2026-10-17T03:58:06.187Z'}));
    expect(find.textContaining('Refunded ₹398'), findsOneWidget);
    expect(find.text('Refund ₹398 now'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cancel dialog starts with "Temporary technical issue" as the reason', (tester) async {
    final paid = Order.fromJson({
      ..._cancelledJson(),
      'status': 'confirmed',
      'payment': {'method': 'razorpay', 'status': 'paid', 'paymentId': 'pay_1'},
      'cancelReason': null,
    });
    await _show(tester, paid);
    await tester.tap(find.text('Cancel order'));
    await tester.pumpAndSettle();
    // The default is filled in already (the website and WhatsApp use the same one); another chip replaces it.
    expect(find.widgetWithText(TextField, 'Temporary technical issue'), findsOneWidget);
    await tester.tap(find.text('Out of stock'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Out of stock'), findsOneWidget);
    expect(find.text('Cancel and refund'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
