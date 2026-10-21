// Website orders as /api/admin/orders returns them (the site's WebOrder shape in src/lib/webOrders.ts, minus the
// buyer's access key).

enum OrderStatus {
  placed('placed', 'Awaiting payment'),
  confirmed('confirmed', 'Confirmed'),
  packed('packed', 'Packed'),
  shipped('shipped', 'Shipped'),
  outForDelivery('out_for_delivery', 'Out for delivery'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled');

  const OrderStatus(this.api, this.label);
  final String api;
  final String label;

  static OrderStatus parse(String? raw) => OrderStatus.values.firstWhere((s) => s.api == raw, orElse: () => OrderStatus.placed);

  bool get isFinal => this == delivered || this == cancelled;

  /// The delivery steps in order. Orders only move forward along them (the server enforces this too).
  static const steps = [confirmed, packed, shipped, outForDelivery, delivered];
}

/// The app's sign-in (username and password, kept on the website as a hash).
class AdminAccount {
  AdminAccount({required this.username, required this.defaultPassword, this.updatedAt});
  final String username;

  /// Still the factory admin / admin password.
  final bool defaultPassword;
  final DateTime? updatedAt;

  factory AdminAccount.fromJson(Map<String, dynamic>? j) => AdminAccount(
    username: _s(j?['username']),
    defaultPassword: j?['defaultPassword'] == true,
    updatedAt: DateTime.tryParse(_s(j?['updatedAt'])),
  );
}

class Contact {
  Contact({required this.name, required this.phone, required this.email});
  final String name, phone, email;

  factory Contact.fromJson(Map<String, dynamic>? j) => Contact(name: _s(j?['name']), phone: _s(j?['phone']), email: _s(j?['email']));
}

class Address {
  Address({
    required this.name,
    required this.phone,
    required this.line1,
    required this.line2,
    required this.landmark,
    required this.city,
    required this.state,
    required this.pincode,
    required this.type,
    this.lat,
    this.lng,
  });

  final String name, phone, line1, line2, landmark, city, state, pincode, type;
  final double? lat, lng;

  factory Address.fromJson(Map<String, dynamic>? j) {
    final location = j?['location'] as Map<String, dynamic>?;
    return Address(
      name: _s(j?['name']),
      phone: _s(j?['phone']),
      line1: _s(j?['line1']),
      line2: _s(j?['line2']),
      landmark: _s(j?['landmark']),
      city: _s(j?['city']),
      state: _s(j?['state']),
      pincode: _s(j?['pincode']),
      type: _s(j?['type']),
      lat: (location?['lat'] as num?)?.toDouble(),
      lng: (location?['lng'] as num?)?.toDouble(),
    );
  }

  /// The address as a courier label: one part per line.
  List<String> get lines => [
    line1,
    line2,
    if (landmark.isNotEmpty) 'Landmark: $landmark',
    [city, state].where((p) => p.isNotEmpty).join(', ') + (pincode.isNotEmpty ? ' - $pincode' : ''),
  ].where((l) => l.trim().isNotEmpty).toList();

  String get oneLine => [line1, line2, landmark, city, state, pincode].where((p) => p.isNotEmpty).join(', ');
}

class OrderItem {
  OrderItem({
    required this.name,
    required this.subtitle,
    required this.quantity,
    required this.price,
    required this.lineTotal,
    required this.mix,
  });
  final String name, subtitle;
  final int quantity, price, lineTotal;
  final Map<String, int> mix;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    name: _s(j['name']),
    subtitle: _s(j['subtitle']),
    quantity: _i(j['quantity']),
    price: _i(j['price']),
    lineTotal: _i(j['lineTotal']),
    mix: ((j['mix'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, _i(v))),
  );
}

class Totals {
  Totals({required this.subtotal, required this.discount, required this.delivery, required this.total});
  final int subtotal, discount, delivery, total;

  factory Totals.fromJson(Map<String, dynamic>? j) =>
      Totals(subtotal: _i(j?['subtotal']), discount: _i(j?['couponDiscount']), delivery: _i(j?['delivery']), total: _i(j?['total']));
}

class Payment {
  Payment({required this.method, required this.status, this.paymentId, this.paidAt, this.refund, this.failedRefund});
  final String method; // razorpay | cod
  final String status; // pending | paid | failed | refund_pending | refunding | refunded | not_required
  final String? paymentId;
  final DateTime? paidAt;

  /// Set once the website has refunded the order: Razorpay's refund id, amount in rupees, when, Razorpay's status
  /// (pending / processed / failed), the bank reference (ARN) once there is one, and when it was last checked.
  final Refund? refund;

  /// A refund Razorpay reported as failed (the order is back to "refund due").
  final ({String id, DateTime at})? failedRefund;

  bool get isPaid => status == 'paid' || method == 'cod';

  /// Paid for real (cash on delivery counts once it's collected): when the invoice is ready.
  bool get settled => status == 'paid';
  String get methodLabel => method == 'cod' ? 'Cash on delivery' : 'Online (Razorpay)';
  String get statusLabel => switch (status) {
    'paid' => 'Paid',
    'pending' => 'Pending',
    'failed' => 'Failed',
    'refund_pending' => 'Refund pending',
    'refunding' => 'Refund being sent',
    'refunded' => 'Refunded',
    'not_required' => 'Collect on delivery',
    _ => status,
  };

  factory Payment.fromJson(Map<String, dynamic>? j) => Payment(
    method: _s(j?['method']),
    status: _s(j?['status']),
    paymentId: j?['paymentId'] as String?,
    paidAt: DateTime.tryParse(_s(j?['paidAt'])),
    refund: switch (j?['refund']) {
      final Map<String, dynamic> r => Refund.fromJson(r),
      _ => null,
    },
    failedRefund: switch (j?['failedRefund']) {
      final Map<String, dynamic> f => (id: _s(f['id']), at: DateTime.tryParse(_s(f['at'])) ?? DateTime.now()),
      _ => null,
    },
  );
}

class Refund {
  Refund({
    required this.id,
    required this.amount,
    required this.at,
    required this.status,
    required this.arn,
    required this.checkedAt,
    required this.test,
  });
  final String id;
  final int amount;
  final DateTime at;

  /// Razorpay's word for it: pending, processed or failed ('' before it was ever checked).
  final String status;
  final String? arn;
  final DateTime? checkedAt;
  final bool test;

  /// Razorpay has sent the money to the customer's bank.
  bool get processed => status == 'processed';

  String get statusLabel => switch (status) {
    'processed' => 'Processed by Razorpay',
    'pending' => 'Pending at Razorpay',
    'failed' => 'Failed at Razorpay',
    _ => 'Sent to Razorpay',
  };

  factory Refund.fromJson(Map<String, dynamic> r) => Refund(
    id: _s(r['id']),
    amount: _i(r['amount']),
    at: DateTime.tryParse(_s(r['at'])) ?? DateTime.now(),
    status: _s(r['razorpayStatus']),
    arn: r['arn'] as String?,
    checkedAt: DateTime.tryParse(_s(r['checkedAt'])),
    test: r['test'] == true,
  );
}

class HistoryStep {
  HistoryStep({required this.status, required this.at, this.note});
  final OrderStatus status;
  final DateTime at;
  final String? note;

  factory HistoryStep.fromJson(Map<String, dynamic> j) => HistoryStep(
    status: OrderStatus.parse(j['status'] as String?),
    at: DateTime.tryParse(_s(j['at'])) ?? DateTime.now(),
    note: j['note'] as String?,
  );
}

class Tracking {
  Tracking({required this.courier, required this.number});
  final String courier, number;
}

class Order {
  Order({
    required this.id,
    required this.createdAt,
    required this.contact,
    required this.address,
    required this.items,
    required this.totals,
    required this.payment,
    required this.status,
    required this.history,
    required this.tracking,
    required this.deliverBy,
    required this.messagesSent,
    this.cancelReason,
  });

  final String id;
  final DateTime createdAt;
  final Contact contact;
  final Address address;
  final List<OrderItem> items;
  final Totals totals;
  final Payment payment;
  final OrderStatus status;
  final List<HistoryStep> history;
  final Tracking? tracking;
  final DateTime? deliverBy;
  final String? cancelReason;

  /// WhatsApp updates already sent to the customer from this app: the message's API name → when.
  final Map<String, DateTime> messagesSent;

  /// The short code the WhatsApp desk accepts too: PX-261015-TMVGS → TMVGS.
  String get shortId => id.split('-').last;

  /// Who to message: the buyer's own number, else the delivery contact's.
  String get customerName => contact.name.isNotEmpty ? contact.name : address.name;
  String get customerPhone => contact.phone.isNotEmpty ? contact.phone : address.phone;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Cancelled after it was paid online, and the money hasn't gone back yet: the admin can refund it.
  bool get needsRefund => status == OrderStatus.cancelled && payment.method == 'razorpay' && payment.status == 'refund_pending';

  /// Its invoice can be downloaded: paid and not cancelled (the website's rule, lib/invoiceReady.js).
  bool get invoiceReady => status != OrderStatus.cancelled && payment.settled;

  /// The next delivery step, if the order can take one: unpaid online orders can only be cancelled.
  OrderStatus? get nextStep {
    if (status.isFinal || !payment.isPaid) return null;
    final index = OrderStatus.steps.indexOf(status);
    if (index < 0 || index + 1 >= OrderStatus.steps.length) return null;
    return OrderStatus.steps[index + 1];
  }

  factory Order.fromJson(Map<String, dynamic> j) {
    final tracking = j['tracking'] as Map<String, dynamic>?;
    final estimate = j['estimatedDelivery'] as Map<String, dynamic>?;
    return Order(
      id: _s(j['id']),
      createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
      contact: Contact.fromJson(j['contact'] as Map<String, dynamic>?),
      address: Address.fromJson(j['address'] as Map<String, dynamic>?),
      items: ((j['items'] as List?) ?? []).map((i) => OrderItem.fromJson(i as Map<String, dynamic>)).toList(),
      totals: Totals.fromJson(j['totals'] as Map<String, dynamic>?),
      payment: Payment.fromJson(j['payment'] as Map<String, dynamic>?),
      status: OrderStatus.parse(j['status'] as String?),
      history: ((j['history'] as List?) ?? []).map((h) => HistoryStep.fromJson(h as Map<String, dynamic>)).toList(),
      tracking: tracking == null ? null : Tracking(courier: _s(tracking['courier']), number: _s(tracking['number'])),
      deliverBy: DateTime.tryParse(_s(estimate?['latest'])),
      messagesSent: ((j['customerMessages'] as Map<String, dynamic>?) ?? {}).map(
        (k, v) => MapEntry(k, DateTime.tryParse(_s(v)) ?? DateTime.now()),
      ),
      cancelReason: j['cancelReason'] as String?,
    );
  }
}

String _s(Object? v) => v == null ? '' : v.toString();
int _i(Object? v) => v is num ? v.round() : int.tryParse(_s(v)) ?? 0;

/// Everything the website knows about the customer behind an order (GET /api/admin/orders/[id]/customer): their PIAX
/// account if they have one, and their order history linked by account or mobile number.
class CustomerProfile {
  CustomerProfile({
    required this.account,
    required this.orderCount,
    required this.completed,
    required this.delivered,
    required this.cancelled,
    required this.unpaid,
    required this.spent,
    required this.average,
    required this.firstAt,
    required this.lastAt,
    required this.topProducts,
    required this.recent,
    required this.addresses,
    required this.otherPhones,
  });

  final CustomerAccount? account;
  final int orderCount, completed, delivered, cancelled, unpaid, spent, average;
  final DateTime? firstAt, lastAt;
  final List<(String name, int quantity)> topProducts;
  final List<PastOrder> recent;
  final List<String> addresses;
  final List<String> otherPhones;

  bool get returning => completed > 1;

  factory CustomerProfile.fromJson(Map<String, dynamic> j) {
    final o = (j['orders'] as Map<String, dynamic>?) ?? {};
    return CustomerProfile(
      account: j['account'] == null ? null : CustomerAccount.fromJson(j['account'] as Map<String, dynamic>),
      orderCount: _i(o['count']),
      completed: _i(o['completed']),
      delivered: _i(o['delivered']),
      cancelled: _i(o['cancelled']),
      unpaid: _i(o['unpaid']),
      spent: _i(o['spent']),
      average: _i(o['average']),
      firstAt: DateTime.tryParse(_s(o['firstAt'])),
      lastAt: DateTime.tryParse(_s(o['lastAt'])),
      topProducts: ((o['topProducts'] as List?) ?? []).map((p) => (_s((p as Map)['name']), _i(p['quantity']))).toList(),
      recent: ((o['recent'] as List?) ?? []).map((p) => PastOrder.fromJson(p as Map<String, dynamic>)).toList(),
      addresses: ((j['addresses'] as List?) ?? []).map(_s).toList(),
      otherPhones: ((j['otherPhones'] as List?) ?? []).map(_s).toList(),
    );
  }
}

class CustomerAccount {
  CustomerAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.lastLoginAt,
    required this.signInMethods,
    required this.savedAddresses,
    required this.cartItems,
    required this.savedItems,
  });

  final String name, email, phone;
  final DateTime? createdAt, lastLoginAt;
  final List<String> signInMethods;
  final int savedAddresses, cartItems, savedItems;

  /// "Google, mobile OTP": how they sign in, in plain words.
  String get signInLabel => signInMethods
      .map(
        (m) => switch (m) {
          'google' => 'Google',
          'phone' => 'mobile OTP',
          'email' => 'email code',
          'password' => 'password',
          _ => m,
        },
      )
      .toSet()
      .join(', ');

  factory CustomerAccount.fromJson(Map<String, dynamic> j) => CustomerAccount(
    name: _s(j['name']),
    email: _s(j['email']),
    phone: _s(j['phone']),
    createdAt: DateTime.tryParse(_s(j['createdAt'])),
    lastLoginAt: DateTime.tryParse(_s(j['lastLoginAt'])),
    signInMethods: ((j['signInMethods'] as List?) ?? []).map(_s).toList(),
    savedAddresses: _i(j['savedAddresses']),
    cartItems: _i(j['cartItems']),
    savedItems: _i(j['savedItems']),
  );
}

class PastOrder {
  PastOrder({required this.id, required this.createdAt, required this.status, required this.total, required this.items});
  final String id;
  final DateTime createdAt;
  final OrderStatus status;
  final int total, items;

  factory PastOrder.fromJson(Map<String, dynamic> j) => PastOrder(
    id: _s(j['id']),
    createdAt: DateTime.tryParse(_s(j['createdAt'])) ?? DateTime.now(),
    status: OrderStatus.parse(j['status'] as String?),
    total: _i(j['total']),
    items: _i(j['items']),
  );
}
