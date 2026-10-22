import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'package:piax_orders_admin/palette.dart';

// Each product's own discount (Products › Discount section): a percentage or an amount off the selling price, with
// optional dates, a minimum number of boxes, an offer label and where it applies. The admin sets and previews it here;
// the shop and the app apply it once the website reads these fields (not wired yet: the product records here are the
// admin's demo data).

const discountTypes = ['No discount', 'Percent off', 'Amount off (₹)'];
const discountWhere = ['Website & app', 'Website only', 'App only'];

/// The largest percentage allowed, so a typo can't give products away.
const maxDiscountPercent = 90;

enum DiscountState { none, scheduled, active, ended }

class ProductDiscount {
  const ProductDiscount({required this.percent, required this.value, this.starts, this.ends, this.minBoxes, this.label, this.where});
  final bool percent;
  final num value;
  final DateTime? starts, ends;
  final int? minBoxes;
  final String? label, where;

  /// The price after this discount (never below ₹1).
  int priceFrom(int price) {
    final off = percent ? price * value / 100 : value;
    return (price - off).round().clamp(1, price);
  }

  DiscountState stateAt(DateTime now) {
    if (starts != null && now.isBefore(starts!)) return DiscountState.scheduled;
    if (ends != null && !now.isBefore(ends!)) return DiscountState.ended;
    return DiscountState.active;
  }
}

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d.\-]'), ''));
DateTime? _date(Object? v) => v is DateTime ? v : DateTime.tryParse('${v ?? ''}')?.toLocal();

/// A product's discount, or null when it has none (or no amount).
ProductDiscount? discountOf(Map<String, dynamic> product) {
  final type = '${product['discountType'] ?? ''}';
  final value = _num(product['discountValue']);
  if (type.isEmpty || type == discountTypes.first || value == null || value <= 0) return null;
  final label = '${product['discountLabel'] ?? ''}'.trim();
  return ProductDiscount(
    percent: type == discountTypes[1],
    value: value,
    starts: _date(product['discountStarts']),
    ends: _date(product['discountEnds']),
    minBoxes: _num(product['discountMinBoxes'])?.round(),
    label: label.isEmpty ? null : label,
    where: product['discountWhere'] as String?,
  );
}

/// What a customer pays now: the selling price less the discount when it's running; null without a price.
int? priceNow(Map<String, dynamic> product, {DateTime? now}) {
  final price = _num(product['price'])?.round();
  if (price == null) return null;
  final d = discountOf(product);
  return d != null && d.stateAt(now ?? DateTime.now()) == DiscountState.active ? d.priceFrom(price) : price;
}

/// What's wrong with a product's discount, for the form; null when it's fine.
String? discountProblem(Map<String, dynamic> product) {
  final type = '${product['discountType'] ?? ''}';
  if (type.isEmpty || type == discountTypes.first) return null;
  final value = _num(product['discountValue']);
  if (value == null || value <= 0) return 'Enter the discount: more than 0.';
  if (type == discountTypes[1] && value > maxDiscountPercent) return 'A percentage discount can be at most $maxDiscountPercent%.';
  final price = _num(product['price']);
  if (type == discountTypes[2] && price != null && value >= price) return 'The amount off must be less than the selling price (${rupees(price.round())}).';
  final starts = _date(product['discountStarts']), ends = _date(product['discountEnds']);
  if (starts != null && ends != null && !ends.isAfter(starts)) return 'The discount must end after it starts.';
  final min = _num(product['discountMinBoxes']);
  if (min != null && (min < 1 || min != min.roundToDouble())) return 'Minimum boxes is a whole number, 1 or more.';
  return null;
}

/// A short line for lists: "15% off · Diwali offer", "₹20 off from 3 boxes", or null.
String? discountSummary(Map<String, dynamic> product) {
  final d = discountOf(product);
  if (d == null) return null;
  final amount = d.percent ? '${NumberFormat('#,##0.#').format(d.value)}% off' : '${rupees(d.value.round())} off';
  return [amount, if (d.minBoxes != null && d.minBoxes! > 1) 'from ${d.minBoxes} boxes', ?d.label].join(' · ');
}

/// The discount at a glance: selling price struck through, the price after it, the saving and when it runs.
class DiscountPreview extends StatelessWidget {
  const DiscountPreview({super.key, required this.product, this.now});
  final Map<String, dynamic> product;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final price = _num(product['price'])?.round();
    final d = discountOf(product);
    final problem = discountProblem(product);
    final at = now ?? DateTime.now();
    final date = DateFormat('d MMM yyyy');
    Widget box(Color bg, Color border, List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
    if (problem != null) {
      return box(const TColor(0xFFFBE7E5), const TColor(0xFFF0B8B3), [
        Row(children: [const Icon(Icons.error_outline, size: 18, color: TColor(0xFFB3261E)), const SizedBox(width: 8), Expanded(child: Text(problem, style: const TextStyle(color: TColor(0xFF8B2E2E), fontWeight: FontWeight.w600)))]),
      ]);
    }
    if (d == null || price == null) {
      return box(const TColor(0xFFF4F8F6), const TColor(0xFFE1E8E6), [
        Text(price == null ? 'Set the selling price to preview a discount.' : 'No discount: customers pay ${rupees(price)}.', style: const TextStyle(color: TColor(0xFF5A6C68))),
      ]);
    }
    final after = d.priceFrom(price);
    final state = d.stateAt(at);
    final (stateText, stateColor) = switch (state) {
      DiscountState.active => ('Running now', const TColor(0xFF0F8A5F)),
      DiscountState.scheduled => ('Starts ${date.format(d.starts!)}', const TColor(0xFF8A5A00)),
      DiscountState.ended => ('Ended ${date.format(d.ends!)}', const TColor(0xFF8B2E2E)),
      DiscountState.none => ('', Colors.transparent),
    };
    return box(const TColor(0xFFEFF7F4), const TColor(0xFFBFE3D6), [
      Row(children: [
        const Icon(Icons.local_offer_outlined, size: 18, color: brand),
        const SizedBox(width: 8),
        Expanded(child: Text(d.label ?? 'Discount', style: const TextStyle(fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19)))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: stateColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
          child: Text(stateText, style: TextStyle(color: stateColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 4, children: [
        Text(rupees(after), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19), height: 1)),
        Text(rupees(price), style: const TextStyle(fontSize: 15, color: TColor(0xFF8A9A96), decoration: TextDecoration.lineThrough)),
        Text('save ${rupees(price - after)} (${((price - after) * 100 / price).round()}%)', style: const TextStyle(fontSize: 13, color: TColor(0xFF0F8A5F), fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      Text(
        [
          d.where ?? discountWhere.first,
          if (d.minBoxes != null && d.minBoxes! > 1) 'from ${d.minBoxes} boxes in one order',
          if (d.starts != null || d.ends != null) '${d.starts == null ? 'now' : date.format(d.starts!)} – ${d.ends == null ? 'until changed' : date.format(d.ends!)}',
        ].join(' · '),
        style: const TextStyle(color: TColor(0xFF26413B), fontSize: 12.5),
      ),
      if (_num(product['mrp']) case final mrp? when mrp > price)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Against MRP ${rupees(mrp.round())}: ${((mrp - after) * 100 / mrp).round()}% off in all.', style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12)),
        ),
    ]);
  }
}
