import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/field_store.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The team's own input fields: added, edited and removed in the Edit fields panel on the right of a page, then shown
// in that page's forms and table.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    forgetQueries();
  });

  test('a module gets the team’s fields after its own, in their own section', () async {
    final store = FieldStore.instance;
    for (final f in store.fields('module:stores')) {
      await store.remove('module:stores', f.id);
    }
    final base = modules.firstWhere((m) => m.key == 'stores');
    expect(withCustomFields(base).fields.length, base.fields.length);
    await store.add('module:stores', const CustomField(id: 'x1', label: 'Shelf space', type: CustomType.choice, options: ['Small', 'Large'], required: true));
    final merged = withCustomFields(base);
    final f = merged.fields.last;
    expect((f.key, f.label, f.type, f.required, f.section), ('cf_x1', 'Shelf space', FieldType.choice, true, customSection));
    expect(f.options, ['Small', 'Large']);
    await store.remove('module:stores', 'x1');
    expect(withCustomFields(base).fields.length, base.fields.length);
  });

  test('a field added once shows once: merging again adds nothing, and the same field isn’t stored twice', () async {
    final store = FieldStore.instance;
    final base = modules.firstWhere((m) => m.key == 'doctors');
    const f = CustomField(id: 'dup1', label: 'Clinic hours', type: CustomType.text);
    await store.add('module:doctors', f);
    await store.add('module:doctors', f); // a double click
    await store.add('module:doctors', const CustomField(id: 'dup2', label: 'clinic hours', type: CustomType.text));
    expect(store.fields('module:doctors').where((x) => x.label.toLowerCase() == 'clinic hours'), hasLength(1));
    final once = withCustomFields(base), twice = withCustomFields(withCustomFields(once));
    expect(once.fields.where((x) => x.label == 'Clinic hours'), hasLength(1));
    expect(twice.fields.length, once.fields.length); // the list screen hands its merged module to the form
    await store.remove('module:doctors', 'dup1');
  });

  testWidgets('Edit fields: add a field on the right; it shows in the table and the form; rename and remove it', (tester) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = 'sops-documents';
    await tester.pumpWidget(MaterialApp(home: NavModulePage(itemId: id, spec: navPageSpecs[id]!)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Add a field')).dx, greaterThan(1000)); // on the right
    expect(find.text('SOP document'), findsWidgets); // the built-in fields are listed

    await tester.tap(find.text('Add a field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Field name *'), 'Reviewer');
    await tester.tap(find.widgetWithText(FilledButton, 'Add field'));
    await tester.pumpAndSettle();
    expect(FieldStore.instance.fields('nav:$id').map((f) => f.label), ['Reviewer']);

    // A name already on the page is refused.
    await tester.tap(find.text('Add a field'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Field name *'), 'owner');
    await tester.tap(find.widgetWithText(FilledButton, 'Add field'));
    await tester.pumpAndSettle();
    expect(find.text('This page already has a field with that name.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to the fields'));
    await tester.pumpAndSettle();

    // Rename it.
    await tester.tap(find.byTooltip('Edit Reviewer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Field name *'), 'Checked by');
    await tester.tap(find.widgetWithText(FilledButton, 'Save field'));
    await tester.pumpAndSettle();
    expect(FieldStore.instance.fields('nav:$id').single.label, 'Checked by');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // The page's table and add form have it.
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('Checked by')), findsOneWidget);
    expect(specWithCustom(id, navPageSpecs[id]!).columns.last.label, 'Checked by');

    // Remove it.
    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Checked by'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(FieldStore.instance.fields('nav:$id'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('built-in fields: rename one; delete required ones (a new record saves without them); restore them', (tester) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = 'sops-documents';
    await tester.pumpWidget(MaterialApp(home: NavModulePage(itemId: id, spec: navPageSpecs[id]!)));
    await tester.pumpAndSettle();
    Finder header(String t) => find.descendant(of: find.byType(DataTable), matching: find.text(t));
    expect(header('Owner'), findsOneWidget);
    final before = rowsFor(id, navPageSpecs[id]!).length;

    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit Owner'));
    await tester.pumpAndSettle();
    expect(find.text('Fixed for built-in fields.'), findsOneWidget); // the kind can't change
    await tester.enterText(find.widgetWithText(TextFormField, 'Field name *'), 'Process owner');
    await tester.tap(find.widgetWithText(FilledButton, 'Save field'));
    await tester.pumpAndSettle();
    // Required fields can be deleted too: the status and the SOP document.
    for (final name in ['Status', 'SOP document', 'Area']) {
      await tester.tap(find.byTooltip('Delete $name'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
    }
    expect(find.text('DELETED FIELDS (3)'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last); // the panel's (on top)
    await tester.pumpAndSettle();

    expect(header('Process owner'), findsOneWidget);
    for (final gone in ['Owner', 'Area', 'Status', 'SOP document']) {
      expect(header(gone), findsNothing, reason: gone);
    }
    expect(rowsFor(id, navPageSpecs[id]!).first.containsKey('Owner'), isTrue); // values stay under the built-in key

    // A new SOP saves without the deleted (once required) fields.
    await tester.tap(find.text('Add sop'));
    await tester.pumpAndSettle();
    expect(find.text('SOP document *'), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.text('Add')).last);
    await tester.pumpAndSettle();
    expect(rowsFor(id, navPageSpecs[id]!).length, before + 1);

    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    for (final name in ['Status', 'SOP document', 'Area']) {
      await tester.tap(find.bySemanticsLabel('Restore $name'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Edit Process owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to original'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last); // the panel's (on top)
    await tester.pumpAndSettle();
    for (final back in ['Owner', 'Area', 'Status', 'SOP document']) {
      expect(header(back), findsOneWidget, reason: back);
    }
    expect(tester.takeException(), isNull);
  });

  test('a module without its deleted fields: the form leaves them out and no longer requires them', () async {
    final store = FieldStore.instance;
    final base = modules.firstWhere((m) => m.key == 'stores');
    await store.setBuiltin('module:stores', base.titleField, const BuiltinOverride(hidden: true));
    final merged = withCustomFields(base);
    expect(merged.fields.firstWhere((f) => f.key == base.titleField).hidden, isTrue);
    expect(merged.fields.length, base.fields.length); // still known to the page, just not shown
    await store.setBuiltin('module:stores', base.titleField, const BuiltinOverride());
  });

  testWidgets('reordering fields: the table’s columns follow the order set in the panel', (tester) async {
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = 'sops-documents';
    await tester.pumpWidget(MaterialApp(home: NavModulePage(itemId: id, spec: navPageSpecs[id]!)));
    await tester.pumpAndSettle();
    List<String> headers() => [for (final c in tester.widget<DataTable>(find.byType(DataTable)).columns) (c.label as Text).data!];
    expect(headers().take(3), ['ID', 'Area', 'Version']);

    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to top'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move Area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(headers().take(3), ['ID', 'Status', 'Version']); // the ID stays first
    expect(headers().last, 'Area');

    await tester.tap(find.text('Edit fields'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(headers().take(3), ['ID', 'Area', 'Version']);
    expect(tester.takeException(), isNull);
  });

  test('a module’s fields follow the team’s order too', () async {
    final store = FieldStore.instance;
    final base = modules.firstWhere((m) => m.key == 'staff');
    final last = base.fields.last.key;
    await store.setOrder('module:staff', [builtinOrderKey(last)]);
    expect(withCustomFields(base).fields.first.key, last);
    await store.resetOrder('module:staff');
    expect(withCustomFields(base).fields.first.key, base.fields.first.key);
  });

  testWidgets('the Edit fields button is the app’s primary button: brand green with white text', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(actions: [EditFieldsButton(onPressed: () {})]))));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style!.backgroundColor!.resolve({}), const Color(0xFF0B5B4E));
    expect(button.style!.foregroundColor!.resolve({}), Colors.white);
  });
}
