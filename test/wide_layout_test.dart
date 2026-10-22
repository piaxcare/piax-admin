import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/admin_shell.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The overview on big desktop screens and a phone: draws and scrolls to the end without layout errors.
void main() {
  setUp(forgetQueries);
  for (final size in const [Size(2560, 1400), Size(1920, 1080), Size(1280, 800), Size(390, 844)]) {
    testWidgets('overview at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AdminShell(api: AdminApi.demo())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final list = find.descendant(of: find.byKey(const Key('overview-scroll')), matching: find.byType(Scrollable)).first;
      for (var i = 0; i < 40; i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scroll step $i');
      }
    });
  }

  for (final size in const [Size(1920, 1080), Size(390, 844)]) {
    testWidgets('analytics: charts for every dataset at ${size.width.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(api: AdminApi.demo())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Every dataset'), 600, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.textContaining('All groups ('), findsOneWidget);
      for (var i = 0; i < 60; i++) {
        await tester.drag(list, const Offset(0, -700));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scroll step $i');
      }
    });
  }
}
