import 'package:flutter/material.dart';

import '../format.dart';
import 'admin_search.dart';
import 'schema.dart';

// The phone's side menu: every page of the app and every admin module, grouped as on the big-screen sidebar.

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key, required this.nav, required this.server, required this.onSignOut});
  final AdminNav nav;
  final String server;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, VoidCallback? go, {bool dense = false}) => ListTile(
      dense: dense,
      visualDensity: dense ? VisualDensity.compact : null,
      leading: Icon(icon, color: brand, size: dense ? 20 : 22),
      title: Text(label, style: TextStyle(fontWeight: dense ? FontWeight.w500 : FontWeight.w600)),
      onTap: go == null
          ? null
          : () {
              Navigator.of(context).pop();
              go();
            },
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
    );
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Image.asset('assets/brand/icon.png', height: 34),
                const SizedBox(width: 12),
                const Expanded(child: Text('PIAX Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ]),
            ),
            tile(Icons.dashboard_outlined, 'Orders', nav.orders),
            tile(Icons.insights_outlined, 'Analytics', nav.analytics),
            tile(Icons.currency_exchange, 'Refunds', nav.refunds),
            heading('Admin'),
            tile(Icons.space_dashboard_outlined, 'Overview', nav.overview),
            tile(Icons.apps_outlined, 'All modules', nav.allModules),
            for (final group in moduleGroups) ...[
              heading(group),
              for (final m in modules.where((m) => m.group == group)) tile(m.icon, m.title, () => nav.module(m.key), dense: true),
            ],
            const Divider(height: 28),
            tile(Icons.settings_outlined, 'Settings', nav.settings),
            tile(Icons.logout, 'Sign out', onSignOut),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(server.replaceFirst(RegExp(r'^https?://'), ''), style: const TextStyle(color: Color(0xFF8DA19C), fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
