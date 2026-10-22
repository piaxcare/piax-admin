import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/nav_config.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';

// The menu pages without a screen of their own: every one has content, and the page's search, filter and sort work.
void main() {
  setUp(forgetQueries); // each test starts with no remembered filters
  test('every menu item without a screen has a content spec, and every spec belongs to a menu item', () {
    final demoItems = [for (final s in navSections) for (final i in s.items) if (i.target is DemoTarget) i.id];
    expect(demoItems.where((id) => !navPageSpecs.containsKey(id)), isEmpty);
    expect(navPageSpecs.keys.where((id) => navItemById(id) == null), isEmpty);
    for (final e in navPageSpecs.entries) {
      final labels = [for (final c in e.value.columns) c.label];
      expect(labels.toSet(), hasLength(labels.length), reason: '${e.key}: column names must be unique');
    }
  });

  test('rows are the same every time, with a value in every column', () {
    final spec = navPageSpecs['purchase-orders']!;
    final a = demoRows('purchase-orders', spec), b = demoRows('purchase-orders', spec);
    expect(a.length, spec.rows);
    expect(a.map((r) => r['ID']), b.map((r) => r['ID']));
    expect(a.map((r) => r['Value']), b.map((r) => r['Value']));
    for (final c in spec.columns) {
      expect(a.every((r) => r[c.label] != null), isTrue, reason: c.label);
    }
  });

  Future<void> show(WidgetTester tester, String id, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: NavModulePage(itemId: id, spec: navPageSpecs[id]!)));
    await tester.pumpAndSettle();
  }

  testWidgets('every content page draws without errors, on a desktop and on a phone', (tester) async {
    for (final id in navPageSpecs.keys) {
      for (final size in const [Size(1500, 1400), Size(390, 1400)]) {
        await show(tester, id, size);
        expect(tester.takeException(), isNull, reason: '$id at ${size.width}');
      }
    }
  });

  testWidgets('a page: header, numbers, charts, then a table that searches, filters and sorts', (tester) async {
    await show(tester, 'purchase-orders', const Size(1500, 2600));
    expect(find.text('All purchase orders'), findsWidgets);
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.textContaining('Showing all 32'), findsOneWidget);

    final list = find.descendant(of: find.byKey(const Key('nav-page-scroll')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byType(DataTable), 400, scrollable: list);
    await tester.enterText(find.widgetWithText(TextField, 'Search purchase orders'), 'PO-1001');
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing 1 of 32'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search purchase orders'), '');
    await tester.pumpAndSettle();
    final received = find.byWidgetPredicate((w) => w is FilterChip && (w.label as Text).data!.startsWith('Received '));
    await tester.tap(received);
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing all 32'), findsNothing);

    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every table fills the full width of its card on wide screens', (tester) async {
    for (final id in navPageSpecs.keys) {
      await show(tester, id, const Size(1500, 3200));
      final list = find.descendant(of: find.byKey(const Key('nav-page-scroll')), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byType(DataTable), 500, scrollable: list);
      final table = tester.getSize(find.byType(DataTable)).width;
      final card = tester.getSize(find.ancestor(of: find.byType(DataTable), matching: find.byType(Material)).first).width;
      expect(table, greaterThanOrEqualTo(card - 1), reason: id);
    }
  });

  testWidgets('add, edit and delete a record; the counts follow', (tester) async {
    await show(tester, 'supplier-quotations', const Size(1500, 3000));
    final list = find.descendant(of: find.byKey(const Key('nav-page-scroll')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.textContaining('Showing all 32'), 400, scrollable: list);

    // Add (the floating button): the form checks the numbers, then the new one is listed first.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the quoted price.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Quoted price'), '45000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Lead time'), '12');
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')));
    await tester.pumpAndSettle();
    expect(find.text('Quotation added.'), findsOneWidget);
    expect(find.textContaining('Showing all 33'), findsOneWidget);
    // The new one is listed and open in the side panel; edit it there, change the price, save.
    expect(find.text('QT-1033'), findsWidgets);
    expect(find.byType(RowDetail), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Quoted price'), '47000');
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Save')));
    await tester.pumpAndSettle();
    expect(find.text('₹47,000'), findsWidgets);

    // Delete it from the panel (still open on it).
    await tester.tap(find.descendant(of: find.byType(RowDetail), matching: find.text('Delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('QT-1033'), findsNothing);
    expect(find.textContaining('Showing all 32'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a floating Add button sits in the bottom-right corner, 24 px in, and opens the add form', (tester) async {
    await show(tester, 'purchase-orders', const Size(1200, 900));
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    final corner = tester.getBottomRight(fab);
    expect(corner.dx, closeTo(1200 - 24, 1));
    expect(corner.dy, closeTo(900 - 24, 1));
    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.text('Add purchase order'), findsWidgets);
    expect(find.byType(DemoRowForm), findsOneWidget);
  });

  testWidgets('the side panel goes full screen and back, for details and for editing', (tester) async {
    await show(tester, 'purchase-orders', const Size(1500, 1200));
    final list = find.descendant(of: find.byKey(const Key('nav-page-scroll')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('PO-1001'), 400, scrollable: list);
    await tester.drag(list, const Offset(0, -300)); // up from the bottom edge
    await tester.pumpAndSettle();
    await tester.tap(find.text('PO-1001'));
    await tester.pumpAndSettle();
    expect(find.byType(RowDetail), findsOneWidget);
    expect(find.byKey(const Key('nav-page-scroll')), findsOneWidget); // the list beside it

    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-page-scroll')), findsNothing); // the panel has the page
    expect(find.byType(RowDetail), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoRowForm), findsOneWidget);
    expect(find.byKey(const Key('nav-page-scroll')), findsNothing); // still full screen while editing

    await tester.tap(find.byTooltip('Back to side panel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav-page-scroll')), findsOneWidget);
    expect(find.byType(DemoRowForm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
