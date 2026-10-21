import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/whatsapp.dart';

Map<String, dynamic> _order({String status = 'confirmed', String payment = 'paid'}) => {
  'id': 'PX-261015-TMVGS',
  'createdAt': '2026-10-15T10:00:00.000Z',
  'contact': {'name': 'Asha Kumar', 'phone': '98765 43210', 'email': 'asha@example.com'},
  'address': {
    'name': 'Asha Kumar',
    'phone': '9876543210',
    'line1': '12 Lake Road',
    'line2': '',
    'landmark': 'Near temple',
    'city': 'Ranipet',
    'state': 'Tamil Nadu',
    'pincode': '632401',
    'type': 'Home',
  },
  'items': [
    {'name': 'PIAX LUMA', 'subtitle': '290mm', 'quantity': 2, 'price': 199, 'lineTotal': 398},
  ],
  'totals': {'subtotal': 398, 'couponDiscount': 0, 'delivery': 0, 'total': 398},
  'payment': {'method': 'razorpay', 'status': payment},
  'status': status,
  'history': [
    {'status': status, 'at': '2026-10-15T10:00:00.000Z'},
  ],
  'tracking': {'courier': 'Delhivery', 'number': '123456'},
  'estimatedDelivery': {'earliest': '2026-10-18T00:00:00.000Z', 'latest': '2026-10-20T00:00:00.000Z'},
};

void main() {
  test('parses an order from the admin API', () {
    final order = Order.fromJson(_order());
    expect(order.status, OrderStatus.confirmed);
    expect(order.shortId, 'TMVGS');
    expect(order.itemCount, 2);
    expect(order.address.lines.last, 'Ranipet, Tamil Nadu - 632401');
  });

  test('next step follows the delivery steps, and unpaid orders have none', () {
    expect(Order.fromJson(_order()).nextStep, OrderStatus.packed);
    expect(Order.fromJson(_order(status: 'out_for_delivery')).nextStep, OrderStatus.delivered);
    expect(Order.fromJson(_order(status: 'delivered')).nextStep, isNull);
    expect(Order.fromJson(_order(status: 'placed', payment: 'pending')).nextStep, isNull);
  });

  test('WhatsApp numbers get the 91 country code', () {
    expect(whatsappNumber('98765 43210'), '919876543210');
    expect(whatsappNumber('+91 98765-43210'), '919876543210');
    expect(whatsappNumber('09876543210'), '919876543210');
    expect(whatsappNumber('123'), isNull);
  });

  test('messages carry the order number and tracking', () {
    final order = Order.fromJson(_order(status: 'shipped'));
    expect(CustomerMessage.confirmed.textFor(order), contains('PX-261015-TMVGS* is confirmed'));
    final shipped = CustomerMessage.shipped.textFor(order);
    expect(shipped, contains('Good news, Asha!'));
    expect(shipped, contains('Tracking number: 123456'));
    expect(CustomerMessage.forStatus(OrderStatus.packed), CustomerMessage.packed);
    expect(CustomerMessage.forStatus(OrderStatus.delivered), CustomerMessage.delivered);
    expect(CustomerMessage.forStatus(OrderStatus.placed), isNull);
  });

  test('delay and missed-delivery messages use the admin’s details and can be sent again', () {
    final order = Order.fromJson(_order(status: 'shipped'));
    final delayed = CustomerMessage.delayed.textFor(order, details: const {'reason': 'Heavy rain in your area', 'newDate': 'Mon, 20 Oct'});
    expect(delayed, contains('Reason: Heavy rain in your area'));
    expect(delayed, contains('New expected date: Mon, 20 Oct'));
    final missed = CustomerMessage.deliveryFailed.textFor(order, details: const {'note': 'No one at home'});
    expect(missed, contains('Note from our delivery partner: No one at home'));
    expect(CustomerMessage.delayed.repeatable && CustomerMessage.deliveryFailed.repeatable, isTrue);
    expect(CustomerMessage.delayed.needsDetails && !CustomerMessage.shipped.needsDetails, isTrue);
    expect(CustomerMessage.deliveryFailed.api, 'delivery_failed');
  });

  test('a cancelled paid order mentions the reason and the refund', () {
    final json = _order(status: 'cancelled', payment: 'refund_pending')..['cancelReason'] = 'Out of stock';
    final text = CustomerMessage.cancelled.textFor(Order.fromJson(json));
    expect(text, contains('Reason: Out of stock'));
    expect(text, contains('₹398 will be refunded'));
  });

  test('reads the sign-in account and the default-password flag', () {
    final fresh = AdminAccount.fromJson({'username': 'admin', 'defaultPassword': true, 'updatedAt': null});
    expect(fresh.defaultPassword, isTrue);
    expect(fresh.updatedAt, isNull);
    final changed = AdminAccount.fromJson({'username': 'piaxdesk', 'defaultPassword': false, 'updatedAt': '2026-10-16T06:28:56.046Z'});
    expect(changed.username, 'piaxdesk');
    expect(changed.defaultPassword, isFalse);
    expect(changed.updatedAt, isNotNull);
  });

  test('message buttons follow the steps and remember what was sent', () {
    final packed = Order.fromJson(_order(status: 'packed')..['customerMessages'] = {'confirmed': '2026-10-15T11:00:00.000Z'});
    expect(CustomerMessage.confirmed.sentAt(packed), isNotNull);
    expect(CustomerMessage.packed.sentAt(packed), isNull);
    expect(CustomerMessage.packed.reached(packed), isTrue);
    expect(CustomerMessage.shipped.reached(packed), isFalse);
    expect(CustomerMessage.cancelled.reached(packed), isFalse);
    expect(CustomerMessage.cancelled.reached(Order.fromJson(_order(status: 'cancelled'))), isTrue);
  });
}
