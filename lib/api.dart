import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'analytics.dart';
import 'models.dart';

class SignedIn {
  SignedIn(this.token, this.account);
  final String token;
  final AdminAccount account;
}

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0});
  final String message;
  final int status;

  bool get signedOut => status == 401;

  @override
  String toString() => message;
}

/// The website's admin API (src/app/api/admin in the website repo). Every call but [login] sends the session token.
class AdminApi {
  AdminApi(String server, {this.token}) : base = server.replaceAll(RegExp(r'/+$'), '');

  final String base;
  final String? token;

  static const _timeout = Duration(seconds: 20);

  /// Signs in with the username and password (admin / admin until changed in Settings). Returns a 7-day session.
  Future<SignedIn> login(String username, String password) async =>
      _signedIn(await _send('POST', '/api/admin/app/login', body: {'username': username, 'password': password}));

  Future<AdminAccount> account() async =>
      AdminAccount.fromJson((await _send('GET', '/api/admin/app/account'))['account'] as Map<String, dynamic>?);

  /// Changes the username and/or password. Every other device is signed out; the reply has a new session for this one.
  Future<SignedIn> updateAccount({required String currentPassword, String? username, String? newPassword}) async => _signedIn(
    await _send(
      'PATCH',
      '/api/admin/app/account',
      body: {'currentPassword': currentPassword, 'username': ?username, 'newPassword': ?newPassword},
    ),
  );

  SignedIn _signedIn(Map<String, dynamic> data) {
    final token = data['token'];
    if (token is! String || token.isEmpty) throw ApiException('The server didn’t return a session. Check the website address.');
    return SignedIn(token, AdminAccount.fromJson(data['account'] as Map<String, dynamic>?));
  }

  /// [status] is `open` (not yet delivered or cancelled), `all`, or one status's API name.
  Future<List<Order>> orders({String status = 'open', String query = ''}) async {
    final data = await _send('GET', '/api/admin/orders', query: {'status': status, if (query.isNotEmpty) 'q': query});
    return ((data['orders'] as List?) ?? []).map((o) => Order.fromJson(o as Map<String, dynamic>)).toList();
  }

  Future<Order> order(String id) async {
    final data = await _send('GET', '/api/admin/orders/${Uri.encodeComponent(id)}');
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  /// Moves the order to [status]. A cancel needs [note] (the reason the customer sees); shipping can carry tracking.
  Future<Order> updateStatus(String id, OrderStatus status, {String? note, String? courier, String? trackingNumber}) async {
    final data = await _send(
      'PATCH',
      '/api/admin/orders/${Uri.encodeComponent(id)}',
      body: {
        'status': status.api,
        if (note != null && note.isNotEmpty) 'note': note,
        if (trackingNumber != null && trackingNumber.isNotEmpty) 'tracking': {'courier': courier ?? '', 'number': trackingNumber},
      },
    );
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  /// Everything the website knows about the customer behind order [id]: account and order history.
  Future<CustomerProfile> customer(String id) async {
    final data = await _send('GET', '/api/admin/orders/${Uri.encodeComponent(id)}/customer');
    return CustomerProfile.fromJson(data['customer'] as Map<String, dynamic>);
  }

  /// A 5-minute link to order [id]'s invoice PDF, to open in the browser or PDF viewer.
  Future<Uri> invoiceLink(String id) async {
    final data = await _send('POST', '/api/admin/orders/${Uri.encodeComponent(id)}/invoice');
    final url = Uri.tryParse(data['url']?.toString() ?? '');
    if (url == null) throw ApiException('The website didn’t return an invoice link.');
    return url;
  }

  /// Refunds cancelled, paid order [id] in full through Razorpay; the website emails the customer.
  Future<Order> refund(String id) async {
    final data = await _send('POST', '/api/admin/orders/${Uri.encodeComponent(id)}/refund');
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  /// Checks order [id]'s refund with Razorpay (processed / pending / failed, bank reference) and returns the order.
  Future<Order> checkRefund(String id) async {
    final data = await _send('GET', '/api/admin/orders/${Uri.encodeComponent(id)}/refund');
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  /// Whether the website can send WhatsApp Business templates (api) and sends the step updates by itself (automatic).
  Future<({bool api, bool automatic})> whatsappStatus() async {
    final data = await _send('GET', '/api/admin/whatsapp');
    return (api: data['api'] == true, automatic: data['automatic'] == true);
  }

  /// Has the website send WhatsApp template [template] to order [id]'s customer; [details] fills its blanks.
  Future<Order> sendTemplate(String id, String template, {Map<String, String> details = const {}}) async {
    final data = await _send('POST', '/api/admin/orders/${Uri.encodeComponent(id)}/whatsapp', body: {'template': template, ...details});
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  /// Every order as anonymous facts (day, status, payment, total, place, products) for the Analytics page.
  Future<List<OrderFact>> analytics() async {
    final data = await _send('GET', '/api/admin/analytics');
    return ((data['orders'] as List?) ?? []).map((o) => OrderFact.fromJson(o as Map<String, dynamic>)).toList();
  }

  /// Notes on the website that [message] (its API name) was sent to the customer, so every admin device shows it.
  Future<Order> markMessageSent(String id, String message) async {
    final data = await _send('POST', '/api/admin/orders/${Uri.encodeComponent(id)}/messages', body: {'message': message});
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- admin modules (mock-up)
  // The local website's development-only dummy data for the Admin modules (website: /api/admin/mock). Deployed builds
  // don't call these; they use the dummy data bundled in the app (lib/admin_modules/repository.dart).

  /// Every module's records: { module: [record, …] }. 404 when the website doesn't serve mock data (production).
  Future<Map<String, dynamic>> mockModules() async =>
      (await _send('GET', '/api/admin/mock'))['modules'] as Map<String, dynamic>? ?? {};

  Future<Map<String, dynamic>> mockCreate(String module, Map<String, dynamic> record) async =>
      (await _send('POST', '/api/admin/mock/$module', body: {'record': record}))['record'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> mockUpdate(String module, String id, Map<String, dynamic> changes) async =>
      (await _send('PATCH', '/api/admin/mock/$module', body: {'id': id, 'changes': changes}))['record'] as Map<String, dynamic>;

  Future<void> mockDelete(String module, String id) async => _send('DELETE', '/api/admin/mock/$module', query: {'id': id});

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final Uri uri;
    try {
      uri = Uri.parse('$base$path').replace(queryParameters: query);
    } on FormatException {
      throw ApiException('That website address doesn’t look right.');
    }
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(_timeout));
    } on TimeoutException {
      throw ApiException('The website took too long to answer. Check your connection and try again.');
    } catch (_) {
      throw ApiException('Can’t reach $base. Check your connection and the website address.');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final error = data['error'];
    throw ApiException(
      error is String && error.isNotEmpty
          ? error
          : response.statusCode == 404
          ? 'Not found. Is the website address right, and does it have the orders admin API?'
          : 'Something went wrong (${response.statusCode}). Please try again.',
      status: response.statusCode,
    );
  }
}
