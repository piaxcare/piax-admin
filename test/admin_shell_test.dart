import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/admin_shell.dart';
import 'package:piax_orders_admin/admin_modules/nav_config.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/nav_widgets.dart' show PageTree;
import 'package:piax_orders_admin/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The app frame after sign-in: opens on the Founder Overview, with the 12-section sidebar on every page; sections
// fold open one at a time; built items open their screen and the rest a labelled demonstration page.
void main() {
  setUp(forgetQueries); // each test starts with no remembered filters
  Future<void> open(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminShell(api: AdminApi('http://127.0.0.1:9', token: 't'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
  }

  Finder inSidebar(String text) => find.descendant(of: find.byType(AdminSidebar), matching: find.text(text));

  Future<void> tapInSidebar(WidgetTester tester, String text) async {
    await tester.ensureVisible(inSidebar(text));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar(text));
    await tester.pumpAndSettle();
  }

  test('the menu: 12 numbered sections in order, items with unique ids', () {
    expect(navSections.map((s) => s.number), [for (var i = 1; i <= 12; i++) i]);
    expect(navSections.first.label, 'Executive Command Centre');
    expect(navSections.last.label, 'Technology, IAM & Integrations');
    expect(navSections.firstWhere((s) => s.id == 'vending').items, hasLength(18));
    final ids = [for (final s in navSections) for (final i in s.items) i.id];
    expect(ids.toSet(), hasLength(ids.length));
  });

  testWidgets('opens on the Founder Overview with every section, and each section holds all its items', (tester) async {
    await open(tester, {});
    expect(find.text('Subscription income'), findsOneWidget);
    for (final s in navSections) {
      expect(inSidebar(s.label), findsOneWidget);
    }
    expect(inSidebar('Founder Overview'), findsOneWidget); // its section is open: it's the current page

    for (final s in navSections) {
      if (inSidebar(s.items.first.label).evaluate().isEmpty) await tapInSidebar(tester, s.label); // open it (if not already)
      for (final item in s.items) {
        expect(inSidebar(item.label), findsOneWidget, reason: '${s.label} › ${item.label}');
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sections toggle independently; a built item opens with the sidebar still beside it', (tester) async {
    await open(tester, {});
    await tapInSidebar(tester, 'Website, App & Content');
    expect(inSidebar('Founder Overview'), findsOneWidget); // opening another section leaves this one open
    await tapInSidebar(tester, 'Store Locations');
    expect(find.text('Add store'), findsWidgets);
    expect(find.byType(AdminSidebar), findsOneWidget);
    expect(inSidebar('Founder Overview'), findsOneWidget);
    expect(inSidebar('Store Locations'), findsOneWidget);

    await tapInSidebar(tester, 'Executive Command Centre');
    expect(inSidebar('Founder Overview'), findsNothing); // only the tapped section folds
    expect(inSidebar('Store Locations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an item without its own screen opens its content page (demo data), with the breadcrumb', (tester) async {
    await open(tester, {});
    await tapInSidebar(tester, 'Vending Machine Operations');
    await tapInSidebar(tester, 'Machine Register & Asset Passport');
    expect(find.byType(NavModulePage), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('06 Vending Machine Operations'), findsOneWidget); // the page tree
    expect(find.byType(AdminSidebar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a page opened from the sidebar takes the name of the item clicked', (tester) async {
    await open(tester, {});
    // The page's own title: the name, outside the sidebar and the page tree.
    int titles(String t) =>
        find.text(t).evaluate().length - inSidebar(t).evaluate().length - find.descendant(of: find.byType(PageTree), matching: find.text(t)).evaluate().length;
    expect(titles('Founder Overview'), 1);

    await tapInSidebar(tester, 'Website, App & Content');
    for (final name in ['Website CMS', 'Blogs & Education Hub', 'Reviews & Publishing Queue', 'Product Pages & Catalogue']) {
      await tapInSidebar(tester, name);
      expect(titles(name), 1, reason: name); // two items on the articles module each keep their own name
    }
    await tapInSidebar(tester, 'Business Health & KPIs'); // its section is still open
    expect(titles('Business Health & KPIs'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page tree is above every page, and each name in it opens its page', (tester) async {
    await open(tester, {});
    Finder inTree(String text) => find.descendant(of: find.byType(PageTree), matching: find.text(text));
    expect(inTree('Founder Overview'), findsOneWidget);

    await tapInSidebar(tester, 'Vending Machine Operations');
    await tapInSidebar(tester, 'Machine Register & Asset Passport');
    expect(inTree('Machine Register & Asset Passport'), findsOneWidget);

    // The section lists its pages: pick another one.
    await tester.tap(inTree('06 Vending Machine Operations'));
    await tester.pumpAndSettle();
    final other = navSections.firstWhere((s) => s.id == 'vending').items.firstWhere((i) => i.label != 'Machine Register & Asset Passport').label;
    await tester.tap(find.descendant(of: find.byType(CheckedPopupMenuItem<NavItem>), matching: find.text(other)).last);
    await tester.pumpAndSettle();
    expect(inTree(other), findsOneWidget);

    // Admin goes back to the Founder Overview.
    await tester.tap(inTree('Admin'));
    await tester.pumpAndSettle();
    expect(inTree('Founder Overview'), findsOneWidget);
    expect(find.text('Subscription income'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('“folded” setting: pages open with the icon rail; a section icon lists its pages', (tester) async {
    await open(tester, {'sidebar_on_new_page': 'closed'});
    expect(tester.getSize(find.byType(AdminSidebar)).width, 76);
    await tester.tap(find.byTooltip('12 Technology, IAM & Integrations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audit Logs'));
    await tester.pumpAndSettle();
    expect(find.text('Audit log'), findsWidgets);
    expect(tester.getSize(find.byType(AdminSidebar)).width, 76); // still folded on the new page

    await tester.tap(find.byTooltip('Open the sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AdminSidebar)).width, 280);
    expect(inSidebar('Audit Logs'), findsOneWidget); // its section opened by itself
    expect(tester.takeException(), isNull);
  });

  testWidgets('search is a Ctrl + K pop-up (no bar at the top); typing filters it and Enter opens the result', (tester) async {
    await open(tester, {});
    expect(find.byType(SearchBar), findsNothing); // no separate bar at the top
    await tapInSidebar(tester, 'Website, App & Content');
    await tapInSidebar(tester, 'Store Locations');
    expect(find.byType(SearchBar), findsNothing);
    expect(find.text('Search store locations'), findsOneWidget); // the page's own search, above its list

    Future<void> ctrlK() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await ctrlK();
    expect(find.text('PAGES'), findsOneWidget); // the pop-up, pages first
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('PAGES'), findsNothing);

    await ctrlK();
    await tester.enterText(find.widgetWithText(TextField, 'Search pages, modules and features'), 'doctors');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Add doctor'), findsWidgets); // the doctors list opened
    expect(tester.takeException(), isNull);
  });
}
