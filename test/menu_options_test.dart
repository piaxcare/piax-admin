import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/menu_options_screen.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/option_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Dropdown menus: "Other…" in a form adds a value to its menu and selects it; Settings lists and edits every menu.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await OptionStore.instance.load();
    for (final key in ['nav:purchase-orders.Supplier', 'nav:purchase-orders.Status']) {
      await OptionStore.instance.reset(key);
    }
  });

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DemoRowForm(spec: navPageSpecs['purchase-orders']!, pageKey: 'nav:purchase-orders')));
    await tester.pumpAndSettle();
  }

  testWidgets('“Other…” asks for a new value, adds it to the menu and selects it', (tester) async {
    await openForm(tester);
    await tester.tap(find.byType(ChoiceDropdown).first); // Supplier
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Velan Nonwovens');
    await tester.tap(find.text('Add and select'));
    await tester.pumpAndSettle();

    expect(find.text('Velan Nonwovens'), findsOneWidget); // selected in the field
    expect(OptionStore.instance.options('nav:purchase-orders.Supplier', const []), contains('Velan Nonwovens'));
    expect(OptionStore.instance.isCustomized('nav:purchase-orders.Supplier'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling “Other…” leaves the field as it was', (tester) async {
    await openForm(tester);
    final before = (tester.widget(find.byType(ChoiceDropdown).first) as ChoiceDropdown).value;
    await tester.tap(find.byType(ChoiceDropdown).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Other…'), findsNothing); // not left showing in the field
    expect(find.text(before!), findsWidgets);
  });

  testWidgets('Settings: every menu is listed; one can be edited and reset', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: MenuOptionsScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'purchase orders');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Purchase Orders › Status'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'New value'), 'Awaiting invoice');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting invoice'), findsOneWidget);
    expect(OptionStore.instance.options('nav:purchase-orders.Status', const []).last, 'Awaiting invoice');

    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Awaiting invoice'), findsNothing);
    expect(OptionStore.instance.isCustomized('nav:purchase-orders.Status'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the gear item opens this menu’s editor; a value added there shows in the field’s menu', (tester) async {
    await openForm(tester);
    await tester.tap(find.byType(ChoiceDropdown).first); // Supplier
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit this menu…').last);
    await tester.pumpAndSettle();
    expect(find.text('Drag the handle to reorder. A menu keeps at least one value.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'New value'), 'Kaveri Polymers');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(DemoRowForm), findsOneWidget); // back on the form, the field unchanged
    await tester.tap(find.byType(ChoiceDropdown).first);
    await tester.pumpAndSettle();
    expect(find.text('Kaveri Polymers'), findsWidgets); // in the menu now
    expect(tester.takeException(), isNull);
  });
}
