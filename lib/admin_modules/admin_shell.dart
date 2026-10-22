import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../screens/analytics_screen.dart';
import '../screens/login_screen.dart' show signOut;
import '../screens/orders_screen.dart';
import '../screens/refunds_screen.dart';
import '../screens/settings_screen.dart';
import '../session.dart';
import '../widgets/brand.dart';
import 'admin_search.dart';
import 'schema.dart' show modules;
import 'modules_screens.dart';
import 'nav_config.dart';
import 'nav_widgets.dart';

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



  /// The menu item (nav_config.dart) for the page on top, highlighted in the sidebar; null for pages outside the menu.
  String? _active = 'founder-overview';

  /// The route name of the page on top, for naming pages outside the menu in the page tree.
  String? _route = 'overview';

  /// The menu item last opened from the sidebar: when two items open the same module, it's the one highlighted.
  String? _clicked;

  @override
  void initState() {
    super.initState();
    Future.wait([Session.sidebarMode(), Session.sidebarOpen()]).then((v) {
      if (!mounted) return;
      final mode = v[0] as String;
      setState(() => (_mode = mode, _open = mode == 'closed' ? false : mode == 'open' ? true : v[1] as bool));
    });
  }

  /// The menu item for a page's route name: `nav:item-id`, `module:key`, or one of the app's pages.
  String? _itemFor(String name) {
    if (name.startsWith('nav:')) return name.substring(4);
    final clicked = _clicked == null ? null : navItemById(_clicked!)?.$2;
    if (name.startsWith('module:')) {
      final key = name.substring(7);
      if (clicked?.target case ModuleTarget(module: final m) when m == key) return clicked!.id;
      return navItemForModule(key)?.id;
    }
    final page = const {'overview': AppPage.overview, 'orders': AppPage.orders, 'analytics': AppPage.analytics, 'refunds': AppPage.refunds, 'settings': AppPage.settings}[name];
    if (page == null) return null;
    if (clicked?.target case PageTarget(page: final p) when p == page) return clicked!.id;
    return navItemForPage(page)?.id;
  }

  void _pageChanged(String? name, {required bool opened}) {
    if (!mounted) return;
    setState(() {
      if (name != null) (_active = _itemFor(name), _route = name);
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
      if (api != null) (_api = api, _pages = GlobalKey<NavigatorState>(), _active = 'founder-overview');
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
    item: _openItem,
  );

  /// Opens a sidebar menu item: its page or module, or its demonstration page if it isn't built yet.
  void _openItem(String id) {
    final found = navItemById(id);
    if (found == null) return;
    final item = found.$2;
    _clicked = id;
    if (item.target is DemoTarget || item.target is ScreenTarget) return _push('nav:$id', NavDemoPage(itemId: id, nav: nav));
    openNavItem(context, AdminNav(orders: nav.orders, analytics: nav.analytics, refunds: nav.refunds, settings: nav.settings, overview: nav.overview, allModules: nav.allModules, module: nav.module), item);
    // Founder Overview is the first page, so no route change tells the sidebar: highlight it here.
    setState(() => (_active = id, _route = null));
  }

  /// A name for a page that isn't in the menu.
  String? _fallbackName(String? route) => switch (route) {
    'modules' => 'All modules',
    'settings' => 'Settings',
    final r? when r.startsWith('module:') => modules.where((m) => m.key == r.substring(7)).firstOrNull?.title,
    _ => null,
  };

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
    // Each page shows the page tree at the top of its content (PageTreeSlot); this says where they are.
    final scoped = AdminNavScope(
      nav: nav,
      child: PageTreeScope(nav: nav, itemId: _active, fallback: _fallbackName(_route), child: pages),
    );
    if (!wide) return scoped;
    // Big screens: search is a pop-up (pages, modules, features), opened anywhere with Ctrl / ⌘ + K. Each list keeps
    // its own search for its records, above the list.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showCommandPalette(context, nav),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => showCommandPalette(context, nav),
      },
      child: Focus(
        autofocus: true, // so the shortcut works before anything on the page has been clicked
        child: Material(
          color: const Color(0xFFF4F7F6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminSidebar(nav: nav, activeItemId: _active, collapsed: !_open, onToggle: _toggle, onSignOut: _api.isDemo ? null : () => signOut(context)),
              Expanded(child: scoped),
            ],
          ),
        ),
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

/// The sidebar, in the order desk's dark brand-green style: the white PIAX logo, the 12 numbered sections with their
/// folding submenus (nav_config.dart), then Settings and Sign out. Folded, it's a slim rail of section icons, each
/// opening a menu of its pages (names on hover).
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({super.key, required this.nav, this.onSignOut, this.activeItemId, this.collapsed = false, this.onToggle});
  final AdminNav nav;
  final String? activeItemId;

  /// Shown only when there's a sign-in to leave (the demo app has none).
  final VoidCallback? onSignOut;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    width: collapsed ? 76 : 280,
    clipBehavior: Clip.hardEdge,
    decoration: const BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B5B4E), Color(0xFF083F37)]),
    ),
    // Laid out for the width it has right now, so nothing overflows while it opens or folds.
    child: LayoutBuilder(builder: (context, box) => _content(context, box.maxWidth < 170)),
  );

  Widget _content(BuildContext context, bool folded) {
    Widget footer(IconData icon, String label, VoidCallback? onTap, {bool isActive = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: folded ? label : '',
        child: Material(
          color: isActive ? Colors.white.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            focusColor: const Color(0x29FFFFFF),
            onTap: onTap,
            child: Container(
              height: 42,
              padding: EdgeInsets.symmetric(horizontal: folded ? 0 : 12),
              child: Row(
                mainAxisAlignment: folded ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: isActive ? Colors.white : const Color(0xFFB9D6CF)),
                  if (!folded) ...[
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB9D6CF), fontSize: 14, fontWeight: FontWeight.w600))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(folded ? 10 : 12, 18, folded ? 10 : 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: folded ? 0 : 8, bottom: 14),
            child: folded
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
                            Text('ADMIN CONSOLE', style: TextStyle(color: Color(0xFFB9D6CF), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2)),
                          ],
                        ),
                      ),
                      if (onToggle != null) IconButton(tooltip: 'Fold the sidebar', onPressed: onToggle, icon: const Icon(Icons.keyboard_double_arrow_left, color: Color(0xFFB9D6CF))),
                    ],
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: folded ? NavRail(nav: nav, activeItemId: activeItemId) : NavTree(nav: nav, activeItemId: activeItemId),
            ),
          ),
          const Divider(height: 20, color: Color(0x33FFFFFF)),
          if (nav.settings != null) footer(Icons.settings_outlined, 'Settings', nav.settings),
          if (onSignOut != null) footer(Icons.logout, 'Sign out', onSignOut),
        ],
      ),
    );
  }
}
