import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/discounts.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';

// Each product's own discount: worked out, checked and previewed.
void main() {
  final now = DateTime(2026, 10, 22, 12);

  test('the Products module has a Discount section', () {
    final products = modules.firstWhere((m) => m.key == 'products');
    expect(products.sections, contains('Discount'));
    expect(products.field('discountType')!.options, discountTypes);
  });

  test('percent and amount off; the price never drops below ₹1', () {
    expect(priceNow({'price': 100, 'discountType': 'Percent off', 'discountValue': 15}, now: now), 85);
    expect(priceNow({'price': 129, 'discountType': 'Amount off (₹)', 'discountValue': 20}, now: now), 109);
    expect(priceNow({'price': 99, 'discountType': 'No discount', 'discountValue': 50}, now: now), 99);
    expect(const ProductDiscount(percent: false, value: 500).priceFrom(99), 1);
  });

  test('dates: scheduled and ended discounts don’t change the price', () {
    final scheduled = {'price': 100, 'discountType': 'Percent off', 'discountValue': 20, 'discountStarts': '2026-11-01T00:00:00Z'};
    final ended = {'price': 100, 'discountType': 'Percent off', 'discountValue': 20, 'discountEnds': '2026-10-01T00:00:00Z'};
    expect(priceNow(scheduled, now: now), 100);
    expect(priceNow(ended, now: now), 100);
    expect(discountOf(scheduled)!.stateAt(now), DiscountState.scheduled);
    expect(discountOf(ended)!.stateAt(now), DiscountState.ended);
  });

  test('the form refuses discounts that don’t make sense', () {
    expect(discountProblem({'discountType': 'No discount'}), isNull);
    expect(discountProblem({'price': 100, 'discountType': 'Percent off', 'discountValue': 95}), contains('at most 90%'));
    expect(discountProblem({'price': 100, 'discountType': 'Amount off (₹)', 'discountValue': 100}), contains('less than the selling price'));
    expect(discountProblem({'price': 100, 'discountType': 'Percent off', 'discountValue': 0}), contains('more than 0'));
    expect(discountProblem({'price': 100, 'discountType': 'Percent off', 'discountValue': 10, 'discountStarts': '2026-11-02T00:00:00Z', 'discountEnds': '2026-11-01T00:00:00Z'}), contains('end after'));
    expect(discountProblem({'price': 100, 'discountType': 'Percent off', 'discountValue': 10}), isNull);
    expect(discountSummary({'discountType': 'Amount off (₹)', 'discountValue': 20, 'discountMinBoxes': 2, 'discountLabel': 'Night pack deal'}), '₹20 off · from 2 boxes · Night pack deal');
  });

  testWidgets('the preview shows the price after the discount and the saving', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiscountPreview(now: now, product: const {'price': 99, 'mrp': 129, 'discountType': 'Percent off', 'discountValue': 10, 'discountLabel': 'Launch offer'})),
    ));
    expect(find.text('Launch offer'), findsOneWidget);
    expect(find.text('Running now'), findsOneWidget);
    expect(find.text('₹89'), findsOneWidget);
    expect(find.textContaining('save ₹10'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DiscountPreview(now: now, product: const {'price': 99, 'discountType': 'Percent off', 'discountValue': 95}))));
    expect(find.textContaining('at most 90%'), findsOneWidget);
  });
}
