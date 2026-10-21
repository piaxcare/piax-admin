import 'package:url_launcher/url_launcher.dart';

import 'format.dart';
import 'models.dart';

/// A ready-made customer message. Where there's an approved WhatsApp Business template for it ([template]), the
/// website can send it through the API; otherwise (or when the API isn't set up) the app opens WhatsApp with the text
/// typed in and the admin presses send. The wording matches the templates (docs/whatsapp-templates.md in the website).
enum CustomerMessage {
  confirmed('Order confirmed', OrderStatus.confirmed, 'order_confirmation'),
  packed('Packed', OrderStatus.packed, null),
  shipped('Shipped', OrderStatus.shipped, 'order_shipped'),
  outForDelivery('Out for delivery', OrderStatus.outForDelivery, 'out_for_delivery'),
  delayed('Delay notice', OrderStatus.confirmed, 'order_delayed'),
  deliveryFailed('Missed delivery', OrderStatus.shipped, 'delivery_failed'),
  delivered('Delivered', OrderStatus.delivered, 'order_delivered'),
  cancelled('Order cancelled', OrderStatus.cancelled, null),
  refunded('Refund issued', OrderStatus.cancelled, null);

  const CustomerMessage(this.label, this.step, this.template);
  final String label;

  /// The step this message announces (for Delay notice / Missed delivery: the earliest step it makes sense from).
  final OrderStatus step;

  /// The approved WhatsApp Business template the website sends for it, if there is one.
  final String? template;

  /// Its name on the website (the order's customerMessages).
  String get api => switch (this) {
    refunded => 'refunded',
    delayed => 'delayed',
    deliveryFailed => 'delivery_failed',
    _ => step.api,
  };

  /// Delay notices and missed-delivery messages can go out more than once; the step messages once.
  bool get repeatable => this == delayed || this == deliveryFailed;

  /// These need details from the admin first (a reason and new date, or the courier's note).
  bool get needsDetails => this == delayed || this == deliveryFailed;

  /// When it was sent to this order's customer, if it was.
  DateTime? sentAt(Order order) => order.messagesSent[api];

  /// Whether it fits where the order is now (no "Shipped" before it ships, no delay notice once delivered).
  bool reached(Order order) {
    if (this == refunded) return order.payment.status == 'refunded';
    if (this == cancelled) return order.status == OrderStatus.cancelled;
    if (this == delayed) {
      return const [OrderStatus.confirmed, OrderStatus.packed, OrderStatus.shipped, OrderStatus.outForDelivery].contains(order.status);
    }
    if (this == deliveryFailed) return order.status == OrderStatus.shipped || order.status == OrderStatus.outForDelivery;
    final at = OrderStatus.steps.indexOf(order.status);
    return at >= 0 && OrderStatus.steps.indexOf(step) <= at;
  }

  /// The message for an order that has just reached [status] (none while it's still awaiting payment).
  static CustomerMessage? forStatus(OrderStatus status) => switch (status) {
    OrderStatus.confirmed => confirmed,
    OrderStatus.packed => packed,
    OrderStatus.shipped => shipped,
    OrderStatus.outForDelivery => outForDelivery,
    OrderStatus.delivered => delivered,
    OrderStatus.cancelled => cancelled,
    OrderStatus.placed => null,
  };

  /// The text, as the matching template reads. [details]: reason and newDate (Delay notice) or note (Missed delivery).
  String textFor(Order order, {Map<String, String> details = const {}}) {
    final name = order.customerName.split(' ').first;
    final hi = name.isEmpty ? 'Hi' : 'Hi $name';
    final items = order.items.map((i) => '${i.quantity} × ${i.name}').join(', ');
    final link = 'https://piax.co.in/account/orders/${order.id}';
    switch (this) {
      case confirmed:
        return [
          '$hi, thank you for your order! 💚',
          '',
          'Your PIAX order *${order.id}* is confirmed.',
          '🛍️ $items',
          '💳 Total: ${rupees(order.totals.total)}',
          '',
          'We’ll pack it in plain, discreet packaging and message you when it ships.',
          '',
          'Track your order: $link',
        ].join('\n');
      case packed:
        return [
          '$hi, your PIAX order *${order.id}* is packed 📦',
          'It’s in plain, discreet packaging and will be handed to our courier partner soon. We’ll message you when it ships.',
        ].join('\n');
      case shipped:
        final t = order.tracking;
        return [
          'Good news${name.isEmpty ? '' : ', $name'}! 📦 Your PIAX order *${order.id}* is on its way.',
          '',
          '🚚 Courier: ${t?.courier ?? 'Our courier partner'}',
          '🔢 Tracking number: ${t?.number ?? 'Shared soon'}',
          if (order.deliverBy != null) '📅 Expected by: ${shortDate(order.deliverBy!)}',
          '',
          'Track your order: $link',
        ].join('\n');
      case outForDelivery:
        return [
          '$hi, your PIAX order *${order.id}* is out for delivery today 🚚',
          '',
          'Please keep your phone nearby so our delivery partner can reach you.',
        ].join('\n');
      case delayed:
        return [
          '$hi, we’re sorry: your PIAX order *${order.id}* is running late ⏳',
          '',
          'Reason: ${details['reason'] ?? ''}',
          'New expected date: ${details['newDate'] ?? ''}',
          '',
          'We’re on it and will keep you posted.',
          '',
          'Track your order: $link',
        ].join('\n');
      case deliveryFailed:
        return [
          '$hi, we tried to deliver your PIAX order *${order.id}* but couldn’t reach you 📭',
          '',
          'Note from our delivery partner: ${details['note'] ?? ''}',
          '',
          'Reply to this message and we’ll arrange the next attempt.',
        ].join('\n');
      case delivered:
        return [
          '$hi, your PIAX order *${order.id}* has been delivered ✅',
          '',
          'We hope you feel the difference. How did we do?',
        ].join('\n');
      case cancelled:
        return [
          '$hi, we’re sorry: your PIAX order *${order.id}* has been cancelled.',
          if (order.cancelReason != null && order.cancelReason!.isNotEmpty) 'Reason: ${order.cancelReason}',
          if (order.payment.status == 'refund_pending') ...[
            '',
            'Your payment of ${rupees(order.totals.total)} will be refunded to your original payment method.',
          ],
        ].join('\n');
      case refunded:
        final r = order.payment.refund;
        return [
          '$hi, your refund for PIAX order *${order.id}* has been issued 💚',
          '',
          'Amount: ${rupees(r?.amount ?? order.totals.total)}',
          'It goes back to your original payment method. Banks usually take 5–7 working days to show it.',
        ].join('\n');
    }
  }
}

/// The number in the international form wa.me wants: 91 and the 10-digit Indian mobile number, digits only.
String? whatsappNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length == 10) return '91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return digits;
  return digits.length >= 11 ? digits : null;
}

/// Opens WhatsApp on a chat with [phone], with [text] typed in. Returns false when WhatsApp (or a browser) can't open.
Future<bool> openWhatsApp(String phone, String text) async {
  final number = whatsappNumber(phone);
  if (number == null) return false;
  final uri = Uri.https('wa.me', '/$number', {if (text.isNotEmpty) 'text': text});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> callNumber(String phone) => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')));

/// Google Maps at the pinned location when the customer shared one, else a search for the address.
Future<bool> openMaps(Address address) {
  final query = address.lat != null && address.lng != null ? '${address.lat},${address.lng}' : address.oneLine;
  return launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': query}), mode: LaunchMode.externalApplication);
}
