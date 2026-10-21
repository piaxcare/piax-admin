import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/order_detail_screen.dart';
import 'package:piax_orders_admin/screens/refunds_screen.dart';

Order _order(String id, String payment, {Map<String, dynamic>? refund, Map<String, dynamic>? failed}) => Order.fromJson({
  'id': id,
  'createdAt': '2026-10-16T07:00:21.030Z',
  'contact': {'name': 'Asha Kumar', 'phone': '9876543210', 'email': ''},
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
  'payment': {'method': 'razorpay', 'status': payment, 'paymentId': 'pay_1', 'refund': ?refund, 'failedRefund': ?failed},
  'status': 'cancelled',
  'cancelReason': 'Out of stock',
  'history': [
    {'status': 'cancelled', 'at': '2026-10-16T08:00:00.000Z'},
  ],
  'tracking': null,
  'estimatedDelivery': {'earliest': '2026-10-18T00:00:00.000Z', 'latest': '2026-10-20T00:00:00.000Z'},
});

final _due = _order('PX-1-DUEAA', 'refund_pending', failed: {'id': 'rfnd_old', 'at': '2026-10-16T09:00:00.000Z'});
final _pending = _order(
  'PX-1-PENDB',
  'refunded',
  refund: {'id': 'rfnd_2', 'amount': 398, 'at': '2026-10-16T09:00:00.000Z', 'razorpayStatus': 'pending'},
);
final _processed = _order(
  'PX-1-DONEC',
  'refunded',
  refund: {'id': 'rfnd_3', 'amount': 398, 'at': '2026-10-15T09:00:00.000Z', 'razorpayStatus': 'processed', 'arn': '74836291023847'},
);

class _FakeApi extends AdminApi {
  _FakeApi() : super('http://127.0.0.1:9', token: 't');
  final checked = <String>[];
  @override
  Future<List<Order>> orders({String status = 'open', String query = ''}) async => status == 'refunds' ? [_due, _pending, _processed] : [];
  @override
  Future<Order> checkRefund(String id) async {
    checked.add(id);
    return [_due, _pending, _processed].firstWhere((o) => o.id == id);
  }
}

void main() {
  for (final (name, size) in [('phone', const Size(390, 2600)), ('desktop', const Size(1440, 1600))]) {
    testWidgets('refunds page groups refunds and checks the unfinished ones on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      await tester.pumpWidget(MaterialApp(home: RefundsScreen(api: api)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Due (1)'), findsOneWidget);
      expect(find.text('In progress (1)'), findsOneWidget);
      expect(find.text('Completed (1)'), findsOneWidget);
      expect(find.text('Last refund failed'), findsOneWidget);
      expect(find.text('Refund now'), findsOneWidget);
      expect(find.textContaining('Bank reference (ARN): 74836291023847'), findsOneWidget);
      expect(api.checked, ['PX-1-PENDB'], reason: 'only the refund that isn’t processed yet is checked with Razorpay');
    });
  }

  testWidgets('the order panel shows Razorpay’s status, the bank reference and the check button', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailScreen(api: _FakeApi(), orderId: _processed.id, initial: _processed),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Processed by Razorpay'), findsOneWidget);
    expect(find.textContaining('74836291023847'), findsOneWidget);
    expect(find.text('Check with Razorpay'), findsOneWidget);
    expect(find.text('Copy ARN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
