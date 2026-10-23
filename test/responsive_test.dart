import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/admin_modules/admin_shell.dart';
import 'package:piax_orders_admin/admin_modules/competitors.dart';
import 'package:piax_orders_admin/admin_modules/menu_options_screen.dart';
import 'package:piax_orders_admin/admin_modules/modules_screens.dart';
import 'package:piax_orders_admin/admin_modules/nav_pages.dart';
import 'package:piax_orders_admin/admin_modules/record_filter.dart';
import 'package:piax_orders_admin/admin_modules/repository.dart';
import 'package:piax_orders_admin/admin_modules/schema.dart';
import 'package:piax_orders_admin/admin_modules/site_builder.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/analytics_screen.dart';
import 'package:piax_orders_admin/screens/orders_screen.dart';
import 'package:piax_orders_admin/screens/refunds_screen.dart';
import 'package:piax_orders_admin/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends AdminApi {
  _FakeApi() : super('http://127.0.0.1:9', token: 't');
  @override
  Future<AdminAccount> account() async => AdminAccount(username: 'admin', defaultPassword: true);
}

/// Every screen class the admin is used on: phones, tablets (both ways round), laptops, desktops and wide monitors.
const sizes = <String, Size>{
  'small phone': Size(360, 740),
  'phone': Size(390, 844),
  'tablet': Size(768, 1024),
  'tablet landscape': Size(1024, 768),
  'laptop': Size(1280, 800),
  'laptop HD': Size(1440, 900),
  'desktop': Size(1920, 1080),
  'QHD monitor': Size(2560, 1440),
  'ultrawide': Size(3440, 1440),
};

// Each page draws, and scrolls to its end, without overflowing at every screen size.
void main() {
  setUp(() {
    forgetQueries();
    SharedPreferences.setMockInitialValues({});
  });

  /// Shows [page] at [size], scrolls its main list down [scrolls] times, and fails with every layout error and the
  /// widget that caused it.
  Future<void> check(WidgetTester tester, Size size, Widget page, {int scrolls = 12, Future<void> Function()? then}) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.toDiagnosticsNode().toStringDeep();
      final where = RegExp(r'\w+:file:///\S+/lib/\S+').firstMatch(text)?.group(0) ?? '';
      // Where in the app it happened, when the error isn't a layout one with its widget named.
      final frame = RegExp(r'package:piax_orders_admin/(\S+)').firstMatch(d.stack.toString())?.group(1) ?? '';
      errors.add('${d.exceptionAsString().split('\n').first} $frame ${where.replaceAll(RegExp(r'file:///\S+/lib/'), 'lib/')}');
    };
    try {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pumpAndSettle();
      if (then != null) await then();
      final scroll = find.byType(Scrollable);
      if (scroll.evaluate().isNotEmpty) {
        for (var i = 0; i < scrolls; i++) {
          await tester.drag(scroll.first, const Offset(0, -700), warnIfMissed: false);
          await tester.pump();
        }
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors.toSet(), isEmpty);
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      testWidgets('app frame and Founder Overview', (tester) async {
        await check(tester, size, AdminShell(api: AdminApi.demo()), scrolls: 40);
      });
      testWidgets('order desk', (tester) async {
        await check(tester, size, OrdersScreen(api: AdminApi.demo()));
      });
      testWidgets('all modules', (tester) async {
        await check(tester, size, ModulesHomeScreen(api: AdminApi.demo(), showAllModules: true));
      });
      testWidgets('every module list, with a record open', (tester) async {
        final repo = (await tester.runAsync(() => ModuleRepository.open(AdminApi.demo())))!;
        for (final m in modules) {
          await check(tester, size, ModuleListScreen(key: ValueKey(m.key), repo: repo, module: m), scrolls: 3, then: () async {
            final cards = find.byType(InkWell);
            if (cards.evaluate().length > 8) {
              await tester.tap(cards.at(8), warnIfMissed: false);
              await tester.pumpAndSettle();
            }
          });
        }
      });
      testWidgets('every menu page', (tester) async {
        for (final id in navPageSpecs.keys) {
          await check(tester, size, NavModulePage(key: ValueKey(id), itemId: id, spec: navPageSpecs[id]!), scrolls: 3);
        }
      });
      testWidgets('analytics', (tester) async {
        await check(tester, size, AnalyticsScreen(api: AdminApi.demo()), scrolls: 30);
      });
      testWidgets('refunds', (tester) async {
        await check(tester, size, RefundsScreen(api: AdminApi.demo()));
      });
      testWidgets('settings', (tester) async {
        await check(tester, size, SettingsScreen(api: _FakeApi()), scrolls: 20);
      });
      testWidgets('site builder', (tester) async {
        await check(tester, size, const SiteBuilderScreen());
      });
      testWidgets('competitor comparison', (tester) async {
        await check(tester, size, const CompetitorComparisonScreen(), scrolls: 20);
      });
      testWidgets('menu options', (tester) async {
        await check(tester, size, const MenuOptionsScreen());
      });
    });
  }
}
