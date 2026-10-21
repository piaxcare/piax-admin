import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/modules_screens.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';
import 'package:piax_orders_admin/api.dart';

// The Admin modules mock-up on the bundled dummy data (a server that can't be reached falls back to it, as a
// deployed build always uses it).
void main() {
  setUp(forgetQueries); // each test starts with no remembered filters
  Future<void> openHome(WidgetTester tester, {bool all = true, Size size = const Size(1400, 2600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ModulesHomeScreen(api: AdminApi('http://127.0.0.1:9', token: 't'), showAllModules: all)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
  }

  testWidgets('home lists every module group and module, on the bundled dummy data', (tester) async {
    await openHome(tester);
    expect(find.textContaining('dummy data bundled in the app'), findsOneWidget);
    for (final group in moduleGroups) {
      await tester.scrollUntilVisible(find.text(group.toUpperCase()).last, 300, scrollable: find.byType(Scrollable).last);
      expect(find.text(group.toUpperCase()), findsWidgets);
    }
    for (final module in modules) {
      await tester.scrollUntilVisible(find.text(module.title).last, 300, scrollable: find.byType(Scrollable).last);
      expect(find.text(module.title), findsWidgets); // in the sidebar too
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a module: list, filter, details, an action, edit', (tester) async {
    await openHome(tester);
    await tester.tap(find.text('Products & pads').last);
    await tester.pumpAndSettle();
    expect(find.text('PIAX LUMA'), findsOneWidget);
    expect(find.text('By status'), findsOneWidget); // the module's dashboard

    await tester.enterText(find.widgetWithText(TextField, 'Search products & pads'), 'nocte');
    await tester.pumpAndSettle();
    expect(find.text('PIAX NOCTE'), findsOneWidget);
    expect(find.text('PIAX LUMA'), findsNothing);

    await tester.tap(find.text('PIAX NOCTE'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget); // desktop record details use the order-style side panel, closed at the right end
    final hide = find.text('Hide from shop');
    final show = find.text('Show in shop');
    expect(hide.evaluate().isNotEmpty || show.evaluate().isNotEmpty, isTrue);
    await tester.tap(hide.evaluate().isNotEmpty ? hide : show);
    await tester.pumpAndSettle();
    expect(find.textContaining('Product: '), findsOneWidget); // the confirmation

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Boxes in stock *'), '321');
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Save')));
    await tester.pumpAndSettle();
    expect(find.text('321'), findsWidgets); // the number card and the field
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit product'), findsOneWidget); // editable records can also be edited from their list cards
    await tester.tap(find.byTooltip('Edit product'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Product name *'), 'PIAX NOCTE revised');
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Save')));
    await tester.pumpAndSettle();
    expect(find.text('PIAX NOCTE revised'), findsWidgets); // in the list and in the side panel

    // Edit again, then close the form: the whole panel closes, details too.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleFormScreen), findsOneWidget);
    final close = find.byTooltip('Close');
    expect(tester.getTopRight(close).dx, greaterThan(tester.getTopLeft(find.byType(ModuleFormScreen)).dx + 300)); // at the right end
    // Full screen and back, while editing.
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleFormScreen), findsOneWidget);
    expect(find.text('By status'), findsNothing); // the list and its dashboard are hidden
    await tester.tap(find.byTooltip('Back to side panel'));
    await tester.pumpAndSettle();
    expect(find.text('By status'), findsOneWidget);

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleFormScreen), findsNothing);
    expect(find.byType(ModuleDetailScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('health data is read-only', (tester) async {
    await openHome(tester);
    await tester.scrollUntilVisible(find.text('Cycles').last, 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Cycles').last);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.textContaining('Member #').first);
    await tester.pumpAndSettle();
    expect(find.text('Health data: anonymised and read-only.'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('overview: headline numbers, what needs attention (opens filtered), charts and quick actions', (tester) async {
    await openHome(tester, all: false);
    for (final title in ['Subscription income', 'Activity', 'Health', 'Stock by product', 'Members by city', 'Member journey', 'Learn views by topic']) {
      expect(find.text(title), findsOneWidget);
    }
    final list = find.descendant(of: find.byKey(const Key('overview-scroll')), matching: find.byType(Scrollable)).first;
    // Revenue and orders: the demo orders here (no order desk to ask in a test), labelled as such.
    await tester.scrollUntilVisible(find.text('Best sellers'), 300, scrollable: list);
    expect(find.text('Demo orders: no live orders to show'), findsOneWidget);
    expect(find.text('Average order'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Needs attention'), 300, scrollable: list);
    expect(find.text('Everything else at a glance'), findsOneWidget);

    // Keys about to expire are flagged; tapping the line opens the credentials, filtered to them.
    final expiring = find.descendant(of: find.byKey(const Key('overview-scroll')), matching: find.textContaining('keys expiring soon'));
    expect(expiring, findsOneWidget);
    await tester.tap(expiring);
    await tester.pumpAndSettle();
    expect(find.text('Credentials & integrations'), findsWidgets);
    expect(find.textContaining('Showing '), findsOneWidget);
    expect(find.text('WhatsApp Business API'), findsOneWidget); // expiring: listed
    expect(find.text('Razorpay payments'), findsNothing); // connected: filtered out
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds pages, modules and features, and opens them', (tester) async {
    await openHome(tester, all: false);
    await tester.tap(find.byType(SearchBar));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'verify');
    await tester.pumpAndSettle();
    expect(find.text('FEATURES'), findsOneWidget);
    await tester.tap(find.text('Verify · doctor'));
    await tester.pumpAndSettle();
    expect(find.text('Doctors'), findsWidgets);
    expect(find.textContaining('Showing '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a list sorts by a number, and the phone layout fits', (tester) async {
    await openHome(tester, size: const Size(390, 844));
    await tester.scrollUntilVisible(find.text('Products & pads').last, 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Products & pads').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sort'), 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    // Open the sort menu (the floating "Add" button can sit over it on a phone).
    tester.state<PopupMenuButtonState<String>>(find.ancestor(of: find.text('Sort'), matching: find.byType(PopupMenuButton<String>))).showButtonMenu();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product name').last);
    await tester.pumpAndSettle();
    expect(find.text('Product name ↑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a product collects everything the shop needs, section by section, with checks', (tester) async {
    await openHome(tester);
    await tester.tap(find.text('Products & pads').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final form = find.descendant(of: find.byKey(const Key('form-scroll')), matching: find.byType(Scrollable)).first;
    for (final section in ['Basics', 'Product details', 'Pricing & tax', 'Stock', 'Photos', 'Shipping', 'Search listing', 'Visibility']) {
      await tester.scrollUntilVisible(find.text(section), 300, scrollable: form);
      expect(find.text(section), findsOneWidget);
    }
    // Saving empty: the needed boxes are flagged, nothing is added.
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')));
    await tester.pumpAndSettle();
    expect(find.text('Some boxes need a look. They’re marked in red.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Enter the product name.'), -300, scrollable: form);
    expect(find.text('Enter the product name.'), findsOneWidget);

    // A bad web address is explained.
    await tester.scrollUntilVisible(find.widgetWithText(TextFormField, 'Web address *'), 300, scrollable: form);
    await tester.enterText(find.widgetWithText(TextFormField, 'Web address *'), 'Bad Slug!');
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('small letters, numbers and dashes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product details show every section, the features as chips and what each field is for', (tester) async {
    await openHome(tester);
    await tester.tap(find.text('Products & pads').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIAX LUMA'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: find.byKey(const Key('detail-scroll')), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Key features'), 300, scrollable: list);
    expect(find.text('Soft top sheet'), findsWidgets);
    await tester.scrollUntilVisible(find.text('HSN code'), 300, scrollable: list);
    expect(find.text('96190010'), findsOneWidget);
    expect(find.text('The tax code printed on invoices.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('members: letter avatars, badges and order numbers; opening one shows its profile and charts', (tester) async {
    await openHome(tester);
    await tester.scrollUntilVisible(find.text('Members').last, 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Members').last);
    await tester.pumpAndSettle();
    expect(find.text('Delivered'), findsWidgets);
    expect(find.text('Refunded'), findsWidgets);
    expect(find.text('Repeat buyer'), findsWidgets);

    await tester.tap(find.text('Nandini Pillai').first);
    await tester.pumpAndSettle();
    expect(find.text('How their orders ended'), findsOneWidget);
    expect(find.text('Orders, last 6 months'), findsOneWidget);
    expect(find.text('Total spent'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
