import 'package:flutter/material.dart';

import '../format.dart';
import 'admin_search.dart';
import 'nav_widgets.dart';

// The phone's side menu: the admin console's 12 sections (nav_config.dart), as on the big-screen sidebar.

class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key, required this.nav, required this.server, this.onSignOut});
  final AdminNav nav;
  final String server;

  /// Shown only when there's a sign-in to leave (the demo app has none).
  final VoidCallback? onSignOut;

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
                const Expanded(child: Text('PIAX Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              ]),
            ),
            // The 12 sections, the same tree as the big-screen sidebar; the drawer closes as a page opens.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: NavTree(nav: nav, dark: false, beforeOpen: () => Navigator.of(context).pop()),
            ),
            const Divider(height: 28),
            tile(Icons.settings_outlined, 'Settings', nav.settings),
            if (onSignOut != null) tile(Icons.logout, 'Sign out', onSignOut),
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
