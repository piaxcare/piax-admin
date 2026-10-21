import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/admin_shell.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The app frame after sign-in: opens on the Admin overview, keeps the sidebar on every page, and folds or opens it on
// new pages as Settings says.
void main() {
  Future<void> open(WidgetTester tester, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminShell(api: AdminApi('http://127.0.0.1:9', token: 't'))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the overview, and the sidebar stays on a module page', (tester) async {
    await open(tester, {});
    expect(find.byType(AdminSidebar), findsOneWidget);
    expect(find.text('Subscription income'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AdminSidebar), matching: find.text('Doctors')));
    await tester.pumpAndSettle();
    expect(find.text('Add doctor'), findsWidgets); // the doctors list
    expect(find.byType(AdminSidebar), findsOneWidget); // still beside it
    expect(tester.takeException(), isNull);
  });

  testWidgets('“folded” setting: new pages open with the sidebar folded to icons', (tester) async {
    await open(tester, {'sidebar_on_new_page': 'closed'});
    expect(tester.getSize(find.byType(AdminSidebar)).width, 76);
    await tester.tap(find.byTooltip('Open the sidebar'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AdminSidebar)).width, 250);

    await tester.tap(find.descendant(of: find.byType(AdminSidebar), matching: find.text('Doctors')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AdminSidebar)).width, 76); // folded again on the new page
    expect(tester.takeException(), isNull);
  });
}
