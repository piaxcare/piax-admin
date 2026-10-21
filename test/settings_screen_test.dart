import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piax_orders_admin/api.dart';
import 'package:piax_orders_admin/models.dart';
import 'package:piax_orders_admin/screens/settings_screen.dart';

class _FakeApi extends AdminApi {
  _FakeApi() : super('http://127.0.0.1:9', token: 't');
  @override
  Future<AdminAccount> account() async => AdminAccount(username: 'admin', defaultPassword: true);
}

void main() {
  for (final (name, size) in [('phone', const Size(390, 2000)), ('desktop', const Size(1440, 1400))]) {
    testWidgets('settings renders on $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: _FakeApi())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Change password'), findsWidgets);
    });
  }
}
