import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/admin_shell.dart';
import 'package:piax_orders_admin/admin_modules/chart_switch.dart';
import 'package:piax_orders_admin/admin_modules/modules_screens.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/repository.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Every chart in the admin, switched to every kind: each draws (or stays as designed where the kind doesn't fit its
// data) without a layout error, on a laptop and on a phone.
void main() {
  setUp(() {
    forgetQueries();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => (ChartPrefs.instance.debugForce = null, ChartPrefs.instance.debugPalette = null));

  Future<void> check(WidgetTester tester, Size size, Widget page, String what, {int scrolls = 6}) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.toDiagnosticsNode().toStringDeep();
      final where = RegExp(r'\w+:file:///\S+/lib/\S+').firstMatch(text)?.group(0)?.replaceAll(RegExp(r'file:///\S+/lib/'), 'lib/') ?? '';
      // Where in the app it happened, when the error isn't a layout one with its widget named.
      final frame = RegExp(r'package:piax_orders_admin/(\S+)').firstMatch(d.stack.toString())?.group(1) ?? '';
      errors.add('${d.exceptionAsString().split('\n').first} $frame $where');
    };
    try {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
      final scroll = find.byType(Scrollable);
      for (var i = 0; i < scrolls && scroll.evaluate().isNotEmpty; i++) {
        await tester.drag(scroll.first, const Offset(0, -700), warnIfMissed: false);
        await tester.pump();
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors.toSet(), isEmpty, reason: what);
  }

  for (final kind in ChartKind.values.skip(1)) {
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      final at = '${kind.name} at ${size.width.toInt()}';
      testWidgets('overview: $at', (tester) async {
        ChartPrefs.instance.debugForce = kind;
        await check(tester, size, AdminShell(api: AdminApi.demo()), 'overview', scrolls: 40);
      });
      testWidgets('analytics: $at', (tester) async {
        ChartPrefs.instance.debugForce = kind;
        await check(tester, size, AnalyticsScreen(api: AdminApi.demo()), 'analytics', scrolls: 30);
      });
      testWidgets('module dashboards: $at', (tester) async {
        ChartPrefs.instance.debugForce = kind;
        final repo = (await tester.runAsync(() => ModuleRepository.open(AdminApi.demo())))!;
        for (final m in modules) {
          await check(tester, size, ModuleListScreen(key: ValueKey(m.key), repo: repo, module: m), m.key, scrolls: 2);
        }
      });
      testWidgets('menu pages: $at', (tester) async {
        ChartPrefs.instance.debugForce = kind;
        for (final id in navPageSpecs.keys) {
          await check(tester, size, NavModulePage(key: ValueKey(id), itemId: id, spec: navPageSpecs[id]!), id, scrolls: 2);
        }
      });
    }
  }

  // Every chart in a colour scheme, left as designed: those that can be are redrawn in the new colours.
  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    final at = 'recoloured at ${size.width.toInt()}';
    testWidgets('overview: $at', (tester) async {
      ChartPrefs.instance.debugPalette = chartPalettes[1];
      await check(tester, size, AdminShell(api: AdminApi.demo()), 'overview', scrolls: 40);
    });
    testWidgets('analytics: $at', (tester) async {
      ChartPrefs.instance.debugPalette = ChartPalette.custom(const Color(0xFFAD1457));
      await check(tester, size, AnalyticsScreen(api: AdminApi.demo()), 'analytics', scrolls: 30);
    });
    testWidgets('menu pages: $at', (tester) async {
      ChartPrefs.instance.debugPalette = chartPalettes[2];
      for (final id in navPageSpecs.keys) {
        await check(tester, size, NavModulePage(key: ValueKey(id), itemId: id, spec: navPageSpecs[id]!), id, scrolls: 2);
      }
    });
  }
}
