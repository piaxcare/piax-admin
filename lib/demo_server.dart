import 'dart:convert';

import 'package:flutter/services.dart';

// The app runs without signing in, on dummy data only (no admin session, so no real customer data ever reaches it).
// This answers the order desk's requests (/api/admin/...) in the website's own JSON shapes, from the made-up orders and
// members bundled in the app (assets/mock/admin_modules.json). Changes (status, refunds) are kept in memory until the
// app closes. Invoices and WhatsApp messages need the real website, so they say so.

class DemoException implements Exception {
  DemoException(this.message, {this.status = 400});
  final String message;
  final int status;
}

class DemoServer {
  DemoServer._();
  static final instance = DemoServer._();

  List<Map<String, dynamic>>? _orders;
  List<Map<String, dynamic>> _members = const [];

  static const _states = {
    'Chennai': 'Tamil Nadu', 'Vellore': 'Tamil Nadu', 'Ranipet': 'Tamil Nadu', 'Walajapet': 'Tamil Nadu', 'Coimbatore': 'Tamil Nadu',
    'Madurai': 'Tamil Nadu', 'Bengaluru': 'Karnataka', 'Hyderabad': 'Telangana', 'Kochi': 'Kerala', 'Pune': 'Maharashtra',
    'Mumbai': 'Maharashtra', 'Delhi': 'Delhi',
  };

  Future<void> _ready() async {
    if (_orders != null) return;
    final raw = jsonDecode(await rootBundle.loadString('assets/mock/admin_modules.json')) as Map<String, dynamic>;
    final modules = (raw['modules'] as Map<String, dynamic>?) ?? {};
    _members = [for (final m in (modules['members'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
    final demo = [for (final o in (modules['ordersDemo'] as List? ?? const [])) Map<String, dynamic>.from(o as Map)];
    _orders = [for (final (i, o) in demo.indexed) _order(o, _members.isEmpty ? null : _members[i % _members.length])];
  }

  /// A demo record as a full website order: contact, address, items, totals, payment, history, tracking.
  Map<String, dynamic> _order(Map<String, dynamic> o, Map<String, dynamic>? m) {
    final created = DateTime.tryParse('${o['createdAt']}') ?? DateTime.now();
    final status = '${o['status']}';
    final total = (o['total'] as num?)?.round() ?? 0;
    final items = [
      for (final i in (o['items'] as List? ?? const []))
        {
          'name': '${i['name']}',
          'subtitle': '',
          'quantity': (i['quantity'] as num?)?.round() ?? 1,
          'price': (((i['lineTotal'] as num?) ?? 0) / ((i['quantity'] as num?) ?? 1)).round(),
          'lineTotal': (i['lineTotal'] as num?)?.round() ?? 0,
        },
    ];
    final subtotal = items.fold<int>(0, (a, i) => a + (i['lineTotal'] as int));
    final city = '${m?['city'] ?? o['city'] ?? ''}';
    String at(Duration d) => created.add(d).toUtc().toIso8601String();
    const steps = ['confirmed', 'packed', 'shipped', 'out_for_delivery', 'delivered'];
    const offsets = [Duration(minutes: 5), Duration(hours: 20), Duration(hours: 36), Duration(hours: 70), Duration(hours: 80)];
    final reached = steps.indexOf(status);
    final history = <Map<String, dynamic>>[
      {'status': 'placed', 'at': at(Duration.zero)},
      if (status != 'placed') {'status': 'confirmed', 'at': at(offsets[0])},
      for (var s = 1; s <= reached; s++) {'status': steps[s], 'at': at(offsets[s])},
      if (status == 'cancelled') {'status': 'cancelled', 'at': at(const Duration(hours: 6)), 'note': 'Temporary technical issue'},
    ];
    final refunded = status == 'cancelled' && o['refund'] == 'refunded';
    return {
      'id': '${o['id']}',
      'createdAt': created.toUtc().toIso8601String(),
      'demo': true,
      if (o['channel'] != null) 'channel': o['channel'],
      if (o['segment'] != null) 'segment': o['segment'],
      'contact': {'name': '${m?['name'] ?? 'Demo customer'}', 'phone': '${m?['phone'] ?? ''}', 'email': '${m?['email'] ?? ''}'},
      'address': {
        'name': '${m?['name'] ?? 'Demo customer'}',
        'phone': '${m?['phone'] ?? ''}',
        'line1': '${m?['address'] ?? ''}'.split(', ').first,
        'line2': '${m?['address'] ?? ''}'.split(', ').skip(1).take(1).join(),
        'landmark': '',
        'city': city,
        'state': _states[city] ?? '',
        'pincode': '${m?['pincode'] ?? ''}',
        'type': 'home',
      },
      'items': items,
      'totals': {'subtotal': subtotal, 'couponDiscount': 0, 'delivery': total - subtotal, 'total': total},
      'payment': {
        'method': 'razorpay',
        'status': status == 'placed' ? 'pending' : status == 'cancelled' ? (refunded ? 'refunded' : 'refund_pending') : 'paid',
        if (status != 'placed') 'paymentId': 'pay_DEMO${o['id']}',
        if (status != 'placed') 'paidAt': at(const Duration(minutes: 5)),
        if (refunded) 'refund': {'id': 'rfnd_DEMO${o['id']}', 'amount': total, 'at': at(const Duration(hours: 8)), 'razorpayStatus': 'processed', 'test': true},
      },
      'status': status,
      'history': history,
      if (reached >= 2) 'tracking': {'courier': 'Delhivery', 'number': 'DEMO${o['id']}'},
      'estimatedDelivery': {'latest': at(const Duration(days: 5))},
      'customerMessages': <String, dynamic>{},
      if (status == 'cancelled') 'cancelReason': 'Temporary technical issue',
    };
  }

  Map<String, dynamic> _find(String id) =>
      _orders!.firstWhere((o) => o['id'] == id, orElse: () => throw DemoException('That order isn’t in the demo data.', status: 404));

  /// Answers one request like the website's admin API would.
  Future<Map<String, dynamic>> handle(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    await _ready();
    final orders = _orders!;
    final parts = path.split('/').where((p) => p.isNotEmpty).toList(); // api, admin, …
    final route = parts.skip(2).toList();
    final now = DateTime.now().toUtc().toIso8601String();

    switch ((method, route)) {
      case ('GET', ['app', 'account']):
        return {'account': {'username': 'demo', 'defaultPassword': false}};
      case (_, ['app', ...]):
        throw DemoException('There’s no sign-in in this app: it runs on dummy data only.');

      case ('GET', ['orders']):
        final status = query?['status'] ?? 'open';
        final q = (query?['q'] ?? '').trim().toLowerCase();
        final list = orders.where((o) {
          final s = '${o['status']}';
          final pay = '${(o['payment'] as Map)['status']}';
          final keep = switch (status) {
            'all' => true,
            'open' => s != 'delivered' && s != 'cancelled',
            'refunds' => s == 'cancelled' && (pay == 'refund_pending' || pay == 'refunded'),
            _ => s == status,
          };
          if (!keep) return false;
          if (q.isEmpty) return true;
          final c = o['contact'] as Map, a = o['address'] as Map;
          return ['${o['id']}', '${c['name']}', '${c['phone']}', '${a['pincode']}'].any((v) => v.toLowerCase().contains(q));
        }).toList()
          ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
        return {'orders': list};

      case ('GET', ['orders', final id]):
        return {'order': _find(id)};

      case ('PATCH', ['orders', final id]):
        final o = _find(id);
        final next = '${body?['status'] ?? ''}';
        if (next.isEmpty) throw DemoException('Choose a status.');
        o['status'] = next;
        (o['history'] as List).add({'status': next, 'at': now, if (body?['note'] != null) 'note': body!['note']});
        if (next == 'cancelled') {
          o['cancelReason'] = body?['note'] ?? 'Temporary technical issue';
          final pay = o['payment'] as Map<String, dynamic>;
          if (pay['status'] == 'paid') pay['status'] = 'refund_pending';
        }
        if (body?['tracking'] case final Map t) o['tracking'] = {'courier': '${t['courier']}', 'number': '${t['number']}'};
        return {'order': o};

      case ('GET', ['orders', final id, 'customer']):
        final o = _find(id);
        final phone = '${(o['contact'] as Map)['phone']}';
        final mine = orders.where((x) => '${(x['contact'] as Map)['phone']}' == phone).toList()
          ..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
        final member = _members.where((m) => '${m['phone']}' == phone).firstOrNull;
        final done = mine.where((x) => x['status'] != 'placed' && x['status'] != 'cancelled').toList();
        final spent = done.fold<int>(0, (a, x) => a + ((x['totals'] as Map)['total'] as int));
        final products = <String, int>{};
        for (final x in done) {
          for (final i in x['items'] as List) {
            products['${i['name']}'] = (products['${i['name']}'] ?? 0) + (i['quantity'] as int);
          }
        }
        final top = products.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return {
          'customer': {
            'account': member == null
                ? null
                : {
                    'name': member['name'], 'email': member['email'], 'phone': member['phone'], 'createdAt': member['joinedAt'],
                    'lastLoginAt': now, 'signInMethods': ['phone'], 'savedAddresses': 1, 'cartItems': 0, 'savedItems': 0,
                  },
            'orders': {
              'count': mine.length,
              'completed': done.length,
              'delivered': mine.where((x) => x['status'] == 'delivered').length,
              'cancelled': mine.where((x) => x['status'] == 'cancelled').length,
              'unpaid': mine.where((x) => x['status'] == 'placed').length,
              'spent': spent,
              'average': done.isEmpty ? 0 : spent ~/ done.length,
              'firstAt': mine.isEmpty ? null : mine.last['createdAt'],
              'lastAt': mine.isEmpty ? null : mine.first['createdAt'],
              'topProducts': [for (final e in top.take(3)) {'name': e.key, 'quantity': e.value}],
              'recent': [
                for (final x in mine.take(5))
                  {'id': x['id'], 'createdAt': x['createdAt'], 'status': x['status'], 'total': (x['totals'] as Map)['total'], 'items': (x['items'] as List).length},
              ],
            },
            'addresses': {for (final x in mine) [(x['address'] as Map)['line1'], (x['address'] as Map)['city'], (x['address'] as Map)['pincode']].where((p) => '$p'.isNotEmpty).join(', ')}.toList(),
            'otherPhones': <String>[],
          },
        };

      case ('POST', ['orders', final id, 'refund']):
        final o = _find(id);
        final pay = o['payment'] as Map<String, dynamic>;
        if (pay['status'] != 'refund_pending') throw DemoException('This order has nothing to refund.');
        pay['status'] = 'refunded';
        pay['refund'] = {'id': 'rfnd_DEMO$id', 'amount': (o['totals'] as Map)['total'], 'at': now, 'razorpayStatus': 'processed', 'test': true, 'checkedAt': now};
        return {'order': o};
      case ('GET', ['orders', final id, 'refund']):
        return {'order': _find(id)};

      case ('POST', ['orders', final id, 'messages']):
        final o = _find(id);
        (o['customerMessages'] as Map)['${body?['message']}'] = now;
        return {'order': o};

      case ('POST', ['orders', _, 'invoice']):
        throw DemoException('Invoices come from the real website; this app runs on dummy orders only.');
      case ('GET', ['whatsapp']):
        return {'api': false, 'automatic': false};
      case ('POST', ['orders', _, 'whatsapp']):
        throw DemoException('WhatsApp messages need the real website; this app runs on dummy orders only.');

      case ('GET', ['analytics']):
        return {
          'orders': [
            for (final o in orders)
              {
                'day': '${o['createdAt']}'.substring(0, 10),
                'status': o['status'],
                'method': 'razorpay',
                'paid': const {'paid', 'refunded', 'refund_pending'}.contains((o['payment'] as Map)['status']),
                'total': (o['totals'] as Map)['total'],
                'city': (o['address'] as Map)['city'],
                'state': (o['address'] as Map)['state'],
                'items': [for (final i in o['items'] as List) {'product': i['name'], 'quantity': i['quantity'], 'amount': i['lineTotal']}],
                if (o['status'] == 'delivered') 'deliveredInDays': 4,
              },
          ],
        };

      default:
        // The admin modules' data comes from the bundled file directly (repository.dart); anything else isn't here.
        throw DemoException('Not available in this demo app.', status: 404);
    }
  }
}
