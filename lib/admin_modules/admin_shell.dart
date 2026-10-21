import 'package:flutter/material.dart';

import '../api.dart';
import '../screens/analytics_screen.dart';
import '../screens/login_screen.dart' show signOut;
import '../screens/orders_screen.dart';
import '../screens/refunds_screen.dart';
import '../screens/settings_screen.dart';
import '../session.dart';
import '../widgets/brand.dart';
import 'admin_search.dart';
import 'modules_screens.dart';
import 'schema.dart';

// The app's frame after sign-in: the sidebar on the left on every page, and the pages beside it in their own
// navigator, so opening a module, a record or a form keeps the sidebar in place. The first page is the Admin
// overview. On phones the sidebar becomes the side drawer each page offers.
//
// When a page opens, the sidebar follows the choice in Settings: always open, always folded to icons, or as it was.

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api});
  final AdminApi api;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late AdminApi _api = widget.api;
  var _pages = GlobalKey<NavigatorState>();
  final _home = GlobalKey<ModulesHomeScreenState>();
  late final _observer = _PageObserver(onChange: _pageChanged);

  bool _open = true;
  String _mode = 'open';

  /// The sidebar item for the page on top: 'overview', 'modules', 'orders', 'module:products'…
  String _active = 'overview';

  @override
  void initState() {
    super.initState();
    Future.wait([Session.sidebarMode(), Session.sidebarOpen()]).then((v) {
      if (!mounted) return;
      final mode = v[0] as String;
      setState(() => (_mode = mode, _open = mode == 'closed' ? false : mode == 'open' ? true : v[1] as bool));
    });
  }

  void _pageChanged(String? name, {required bool opened}) {
    if (!mounted) return;
    setState(() {
      if (name != null) _active = name;
      if (opened && _mode != 'remember') _open = _mode == 'open';
    });
  }

  void _toggle() {
    setState(() => _open = !_open);
    Session.saveSidebarOpen(_open);
  }

  NavigatorState get _nav => _pages.currentState!;
  void _home0() => _nav.popUntil((route) => route.isFirst);

  void _push(String name, Widget page) {
    _home0();
    _nav.push(MaterialPageRoute(settings: RouteSettings(name: name), builder: (_) => page));
  }

  Future<void> _settings() async {
    _home0();
    final api = await _nav.push<AdminApi>(MaterialPageRoute(settings: const RouteSettings(name: 'settings'), builder: (_) => SettingsScreen(api: _api)));
    final mode = await Session.sidebarMode();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      // A new server: start again from the overview, on that server.
      if (api != null) (_api = api, _pages = GlobalKey<NavigatorState>(), _active = 'overview');
    });
  }

  late final AdminNav nav = AdminNav(
    orders: () => _push('orders', OrdersScreen(api: _api, nav: nav, embedded: true)),
    analytics: () => _push('analytics', AnalyticsScreen(api: _api)),
    refunds: () => _push('refunds', RefundsScreen(api: _api)),
    settings: _settings,
    overview: () {
      _home0();
      _home.currentState?.setTab(0);
    },
    allModules: () {
      _home0();
      _home.currentState?.setTab(1);
    },
    module: (key, {status, create = false}) {
      _home0();
      _home.currentState?.open(key, status: status, create: create);
    },
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final pages = NavigatorPopHandler(
      onPopWithResult: (_) => _pages.currentState?.maybePop(),
      child: Navigator(
        key: _pages,
        observers: [_observer],
        onGenerateInitialRoutes: (_, _) => [
          MaterialPageRoute(
            settings: const RouteSettings(name: 'overview'),
            builder: (_) => ModulesHomeScreen(key: _home, api: _api, appNav: nav, showSidebar: false, onTab: (tab) => _pageChanged(tab == 0 ? 'overview' : 'modules', opened: false)),
          ),
        ],
      ),
    );
    if (!wide) return pages;
    return Material(
      color: const Color(0xFFF4F7F6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSidebar(nav: nav, active: _active, collapsed: !_open, onToggle: _toggle, onSignOut: () => signOut(context)),
          Expanded(child: pages),
        ],
      ),
    );
  }
}

class _PageObserver extends NavigatorObserver {
  _PageObserver({required this.onChange});
  final void Function(String? name, {required bool opened}) onChange;

  // After the frame: the navigator is mid-update while these are called.
  void _later(String? name, {required bool opened}) => WidgetsBinding.instance.addPostFrameCallback((_) => onChange(name, opened: opened));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _later(route.settings.name, opened: true);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _later(previousRoute?.settings.name, opened: false);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _later(newRoute?.settings.name, opened: true);
}

/// The sidebar, in the order desk's dark brand-green style: the white PIAX logo, the overview, the app's pages, then
/// every admin module by group. The current page is a soft white highlight. Folded, it's a slim rail of icons (each
/// with its name on hover), still one tap from anywhere.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key, required this.nav, required this.active, required this.onSignOut, this.collapsed = false, this.onToggle});
  final AdminNav nav;
  final String active;
  final VoidCallback onSignOut;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    width: collapsed ? 76 : 250,
    clipBehavior: Clip.hardEdge,
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B5B4E), Color(0xFF083F37)]),
    ),
    // Laid out for the width it has right now, so nothing overflows while it opens or folds.
    child: LayoutBuilder(builder: (context, box) => _content(box.maxWidth < 170)),
  );

  Widget _content(bool collapsed) {
    Widget item(IconData icon, String label, VoidCallback? onTap, {bool isActive = false, bool small = false}) {
      final fg = isActive ? Colors.white : const Color(0xFFB9D6CF);
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: collapsed ? label : '',
          preferBelow: false,
          child: Material(
            color: isActive ? Colors.white.withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                height: small ? 38 : 44,
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 14),
                child: Row(
                  mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(icon, size: small ? 19 : 21, color: fg),
                    if (!collapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: small ? 13.5 : 14.5, fontWeight: isActive ? FontWeight.w700 : FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget heading(String text) => collapsed
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10), child: Divider(height: 1, color: Color(0x33FFFFFF)))
        : Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 8, 6),
            child: Text(text.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8DB8AE), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 10 : 14, 18, collapsed ? 10 : 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: collapsed ? 0 : 8, bottom: 16),
            child: collapsed
                ? Column(children: [
                    // The folded logo: the PIAX mark with rounded corners inside a rounded white tile.
                    Container(
                      width: 46,
                      height: 46,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset('assets/brand/icon.png', fit: BoxFit.cover, semanticLabel: 'PIAX', errorBuilder: (_, _, _) => const SizedBox()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (onToggle != null) IconButton(tooltip: 'Open the sidebar', onPressed: onToggle, icon: const Icon(Icons.keyboard_double_arrow_right, color: Color(0xFFB9D6CF))),
                  ])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrandLogo(height: 40),
                            SizedBox(height: 6),
                            Text('ADMIN', style: TextStyle(color: Color(0xFFB9D6CF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
                          ],
                        ),
                      ),
                      if (onToggle != null) IconButton(tooltip: 'Fold the sidebar', onPressed: onToggle, icon: const Icon(Icons.keyboard_double_arrow_left, color: Color(0xFFB9D6CF))),
                    ],
                  ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                item(Icons.space_dashboard_outlined, 'Overview', nav.overview, isActive: active == 'overview'),
                item(Icons.apps_outlined, 'All modules', nav.allModules, isActive: active == 'modules'),
                if (nav.orders != null) item(Icons.receipt_long_outlined, 'Orders', nav.orders, isActive: active == 'orders'),
                if (nav.analytics != null) item(Icons.insights_outlined, 'Analytics', nav.analytics, isActive: active == 'analytics'),
                if (nav.refunds != null) item(Icons.currency_exchange, 'Refunds', nav.refunds, isActive: active == 'refunds'),
                for (final group in moduleGroups) ...[
                  heading(group),
                  for (final m in modules.where((m) => m.group == group)) item(m.icon, m.title, () => nav.module(m.key), small: true, isActive: active == 'module:${m.key}'),
                ],
              ],
            ),
          ),
          const Divider(height: 20, color: Color(0x33FFFFFF)),
          if (nav.settings != null) item(Icons.settings_outlined, 'Settings', nav.settings, isActive: active == 'settings'),
          item(Icons.logout, 'Sign out', onSignOut),
        ],
      ),
    );
  }
}
