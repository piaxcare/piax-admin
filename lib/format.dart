import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'package:piax_orders_admin/palette.dart';

final _rupees = NumberFormat.decimalPattern('en_IN');
String rupees(int amount) => '₹${_rupees.format(amount)}';

String shortDate(DateTime at) => DateFormat('EEE, d MMM').format(at.toLocal());
String dateTime(DateTime at) => DateFormat('d MMM, h:mm a').format(at.toLocal());
String weekdayDate(DateTime at) => DateFormat('EEEE, d MMMM').format(at.toLocal());
String weekdayShort(DateTime at) => DateFormat('EEE').format(at.toLocal());
String timeOnly(DateTime at) => DateFormat('h:mm a').format(at.toLocal());
String monthYear(DateTime at) => DateFormat('MMM yyyy').format(at.toLocal());

/// Like [ago], but just the day ("15 Oct") once it's over a day old, for narrow table columns.
String agoShort(DateTime at) => DateTime.now().difference(at).inHours < 24 ? ago(at) : DateFormat('d MMM').format(at.toLocal());

/// "5 min ago", "3 h ago", else the date.
String ago(DateTime at) {
  final gap = DateTime.now().difference(at);
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  return dateTime(at);
}

// PIAX brand colours (the website's --color-brand family and the soft tone palette).
const brand = TColor(0xFF0B5B4E);
const brand2 = TColor(0xFF0F766E);
const mist = TColor(0xFFF8FAFC);

/// Background and text colour for a status badge.
(Color, Color) statusColors(OrderStatus status) => switch (status) {
  OrderStatus.placed => (const TColor(0xFFFFF4D6), const TColor(0xFF8A5A00)),
  OrderStatus.confirmed => (const TColor(0xFFDDF3EC), brand),
  OrderStatus.packed => (const TColor(0xFFEDE6F3), const TColor(0xFF5B3F73)),
  OrderStatus.shipped => (const TColor(0xFFE1EAF7), const TColor(0xFF2B3A5C)),
  OrderStatus.outForDelivery => (const TColor(0xFFF7E6DE), const TColor(0xFF8E4A30)),
  OrderStatus.delivered => (const TColor(0xFFE3EDE2), const TColor(0xFF3E5E3C)),
  OrderStatus.cancelled => (const TColor(0xFFF3E3E3), const TColor(0xFF8B2E2E)),
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.label,
        style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
