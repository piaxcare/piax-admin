import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/dashboard_view.dart';
import 'package:piax_orders_admin/screens/order_detail_screen.dart';
import 'package:piax_orders_admin/screens/orders_screen.dart' show OrderFilter;

final _now = DateTime(2026, 10, 16, 15);

Order _o(String id, String status, {int daysAgo = 0, int total = 398, String pay = 'paid', List<Map<String, String>>? history}) =>
    Order.fromJson({
      'id': id,
      'createdAt': _now.subtract(Duration(days: daysAgo)).toUtc().toIso8601String(),
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
      'totals': {'subtotal': total, 'couponDiscount': 0, 'delivery': 0, 'total': total},
      'payment': {'method': 'razorpay', 'status': pay},
      'status': status,
      'history':
          history ??
          [
            {'status': status, 'at': _now.toUtc().toIso8601String()},
          ],
      'tracking': null,
      'estimatedDelivery': {'earliest': _now.toUtc().toIso8601String(), 'latest': _now.toUtc().toIso8601String()},
    });

final _orders = [
  _o('PX-261016-AAAAA', 'confirmed'),
  _o('PX-261016-BBBBB', 'confirmed', total: 597),
  _o('PX-261015-CCCCC', 'packed', daysAgo: 1),
  _o('PX-261014-DDDDD', 'shipped', daysAgo: 2),
  _o('PX-261014-EEEEE', 'out_for_delivery', daysAgo: 2),
  _o('PX-261013-FFFFF', 'delivered', daysAgo: 3),
  _o('PX-261016-GGGGG', 'placed', pay: 'pending', total: 1000),
  _o('PX-261012-HHHHH', 'cancelled', daysAgo: 4, pay: 'refund_pending', total: 5000),
  _o('PX-260901-IIIII', 'delivered', daysAgo: 45),
];

void main() {
  // The dashboard remembers whether its sidebar is open; tests use an empty in-memory store.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the sidebar closes and reopens', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: _dashboard()));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Close the sidebar'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open the sidebar'), findsOneWidget);
    expect(find.text('Settings').hitTestable(), findsNothing, reason: 'the closed sidebar is out of view');
    await tester.tap(find.byTooltip('Open the sidebar'));
    await tester.pumpAndSettle();
    expect(find.text('Settings').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('dashboard numbers come from the orders', () {
    final s = DashboardStats(_orders, now: _now);
    expect(s.toPack, 2);
    expect(s.readyToShip, 1);
    expect(s.inTransit, 2);
    expect(s.awaitingPayment, 1);
    // Both delivered orders' "delivered" step is dated today in these fixtures; one delivered yesterday doesn't count.
    expect(s.deliveredToday, 2);
    final yesterday = _now.subtract(const Duration(days: 1)).toUtc().toIso8601String();
    expect(
      DashboardStats([
        _o(
          'PX-1',
          'delivered',
          daysAgo: 3,
          history: [
            {'status': 'delivered', 'at': yesterday},
          ],
        ),
      ], now: _now).deliveredToday,
      0,
    );
    // Last 7 days, not unpaid, not cancelled: 398 + 597 + 398 + 398 + 398 + 398.
    expect(s.revenue7d, 2587);
    // Per day, oldest first: the cancelled order still counts as an order; unpaid and 45-day-old ones don't.
    expect(s.perDay, [0, 0, 1, 1, 2, 1, 2]);
  });

  for (final (name, size, open) in [
    ('tablet', const Size(820, 1180), false),
    ('desktop', const Size(1920, 1080), false),
    ('desktop with an order open', const Size(1440, 1000), true),
  ]) {
    testWidgets('dashboard lays out on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: _dashboard(selectedId: open ? _orders.first.id : null)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Orders, last 7 days'), findsOneWidget);
      expect(find.text('To pack'), findsWidgets);
      expect(find.text('PX-261016-BBBBB'), findsOneWidget);
      // The order panel is there only while an order is open; otherwise the dashboard has the full width.
      expect(find.text('Select an order'), findsNothing);
      expect(find.byType(OrderDetailScreen), size.width >= splitMinWidth && open ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

OrdersDashboard _dashboard({String? selectedId}) => OrdersDashboard(
  api: AdminApi('http://127.0.0.1:9', token: 't'),
  all: _orders,
  orders: _orders.where((o) => !o.status.isFinal).toList(),
  loading: false,
  error: null,
  filter: OrderFilter.open,
  search: TextEditingController(),
  fresh: {_orders.first.id},
  defaultPassword: true,
  selectedId: selectedId,
  onFilter: (_) {},
  onSearch: (_) {},
  onRefresh: () async {},
  onOpen: (_, {required split}) {},
  onCloseOrder: () {},
  onOrderChanged: () {},
  onSettings: () {},
  onSignOut: () {},
  onAnalytics: () {},
  onRefunds: () {},
  onModules: () {},
);
