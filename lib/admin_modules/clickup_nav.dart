import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_mode.dart';
import 'admin_search.dart';
import 'nav_config.dart';
import 'schema.dart' show modules;

import 'package:piax_orders_admin/palette.dart';
import 'package:piax_orders_admin/app_layout.dart';

// The big-screen frame in ClickUp's style (clickup.com): a white top bar with the logo, mega menus that open on click
// (Workspace, Spaces: icon tiles with a line on each), direct links, search with Ctrl / ⌘ + K, a gradient + New,
// favourite this page, inbox, help and profile; a slim icon rail of the main places, and a light sidebar with
// Favorites and Spaces (the 12 sections, nav_config.dart). Phones keep the side drawer each page offers.

const _bar = Colors.white, _barText = TColor(0xFF292D34), _ink2 = TColor(0xFF646464), _brand = TColor(0xFF0B5B4E), _line = TColor(0xFFE6ECEA);

/// The pages starred in the sidebar's Favorites, kept on this device.
class Favorites extends ChangeNotifier {
  Favorites._() {
    SharedPreferences.getInstance()
        .then((p) {
          ids.addAll(p.getStringList(_key) ?? const []);
          notifyListeners();
        })
        .catchError((_) {});
  }
  static final instance = Favorites._();
  static const _key = 'nav_favorites';
  final ids = <String>[];

  bool has(String id) => ids.contains(id);
  void toggle(String id) {
    has(id) ? ids.remove(id) : ids.add(id);
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setStringList(_key, ids)).catchError((_) => false);
  }
}

/// Home's pages in the wide panel, ordered like any section's (Settings › Navigation, or the panel's gear menu).
const homeSection = NavSection(
  id: 'home',
  number: 0,
  label: 'Home',
  icon: Icons.home_outlined,
  purpose: '',
  items: [
    NavItem('founder-overview', 'Founder Overview', PageTarget(AppPage.overview)),
    NavItem('home-orders', 'Orders', PageTarget(AppPage.orders)),
    NavItem('home-analytics', 'Analytics', PageTarget(AppPage.analytics)),
    NavItem('home-refunds', 'Refunds', PageTarget(AppPage.refunds)),
    NavItem('home-modules', 'All modules'),
  ],
);

const _homeIcons = {
  'founder-overview': Icons.space_dashboard_outlined,
  'home-orders': Icons.inbox_outlined,
  'home-analytics': Icons.insights_outlined,
  'home-refunds': Icons.currency_exchange,
  'home-modules': Icons.grid_view,
};

IconData _iconOf(NavSection sec, NavItem i) {
  if (_homeIcons[i.id] case final icon?) return icon;
  if (HomeStore.target(i.id) case (final s, final item)) return item == null ? s.icon : navItemIcon(item, s.icon);
  return navItemIcon(i, sec.icon);
}

/// The Home panel as the team set it up: pages added from any section (a main page or a sub-page), its own names
/// for any entry, and built-in entries taken off. Kept on this device; the order lives in [NavOrder] like a section's.
class HomeStore extends ChangeNotifier {
  HomeStore._() {
    SharedPreferences.getInstance()
        .then((p) {
          added.addAll(p.getStringList('$_k.added') ?? const []);
          removed.addAll(p.getStringList('$_k.removed') ?? const []);
          for (final e in p.getStringList('$_k.names') ?? const <String>[]) {
            final i = e.indexOf('=');
            if (i > 0) names[e.substring(0, i)] = e.substring(i + 1);
          }
          notifyListeners();
        })
        .catchError((_) {});
  }
  static final instance = HomeStore._();
  static const _k = 'home_panel';

  /// Entry ids: `add:<item id>` for a sub-page, `add:section:<section id>` for a main page.
  final added = <String>[];
  final removed = <String>{};
  final names = <String, String>{};

  /// The section (and sub-page, or null for the main page) an added entry opens.
  static (NavSection, NavItem?)? target(String id) {
    if (!id.startsWith('add:')) return null;
    final ref = id.substring(4);
    if (ref.startsWith('section:')) {
      final sec = navSections.where((s) => s.id == ref.substring(8)).firstOrNull;
      return sec == null ? null : (sec, null);
    }
    final found = navItemById(ref);
    return found == null ? null : (found.$1, found.$2);
  }

  static String defaultName(String id) =>
      homeSection.items.where((i) => i.id == id).firstOrNull?.label ??
      switch (target(id)) {
        (final s, null) => s.label,
        (_, final i?) => i.label,
        _ => id,
      };

  String nameOf(String id) => names[id] ?? defaultName(id);

  /// Home's entries (before ordering): built-ins not taken off, then the added pages.
  List<NavItem> get entries => [
    for (final i in homeSection.items)
      if (!removed.contains(i.id)) NavItem(i.id, nameOf(i.id), i.target),
    for (final id in added)
      if (target(id) != null) NavItem(id, nameOf(id)),
  ];

  bool has(String id) => added.contains(id) || (homeSection.items.any((i) => i.id == id) && !removed.contains(id));

  void add(String id) {
    if (homeSection.items.any((i) => i.id == id)) {
      removed.remove(id);
    } else if (!added.contains(id)) {
      added.add(id);
    }
    _save();
  }

  void remove(String id) {
    added.remove(id) || removed.add(id);
    _save();
  }

  void rename(String id, String name) {
    final n = name.trim();
    n.isEmpty || n == defaultName(id) ? names.remove(id) : names[id] = n;
    _save();
  }

  void reset() {
    added.clear();
    removed.clear();
    names.clear();
    _save();
    NavOrder.instance.reset(homeSection);
  }

  void _save() {
    notifyListeners();
    NavOrder.instance.notifyListeners();
    SharedPreferences.getInstance()
        .then((p) async {
          await p.setStringList('$_k.added', added);
          await p.setStringList('$_k.removed', removed.toList());
          await p.setStringList('$_k.names', [for (final e in names.entries) '${e.key}=${e.value}']);
        })
        .catchError((_) {});
  }
}

/// The order the team dragged the rail's sections and each section's pages into, kept on this device.
class NavOrder extends ChangeNotifier {
  NavOrder._() {
    SharedPreferences.getInstance()
        .then((p) {
          for (final key in p.getKeys().where((k) => k.startsWith(_prefix))) {
            _order[key.substring(_prefix.length)] = p.getStringList(key) ?? const [];
          }
          notifyListeners();
        })
        .catchError((_) {});
  }
  static final instance = NavOrder._();
  static const _prefix = 'nav_order:', _rail = '_rail';
  final _order = <String, List<String>>{};

  /// [items] in the saved order (by [id]); new ones go at the end.
  List<T> _sorted<T>(String key, List<T> items, String Function(T) id) {
    final saved = _order[key];
    if (saved == null) return items;
    final rank = {for (final (i, k) in saved.indexed) k: i};
    return [...items]..sort((a, b) => (rank[id(a)] ?? 1 << 20).compareTo(rank[id(b)] ?? 1 << 20));
  }

  List<NavSection> get sections => _sorted(_rail, navSections, (s) => s.id);

  /// The rail's sections, without the ones hidden in Settings.
  List<NavSection> get visibleSections => [
    for (final s in sections)
      if (!isHidden(s)) s,
  ];

  static const _hiddenKey = '_hidden';
  bool isHidden(NavSection s) => _order[_hiddenKey]?.contains(s.id) ?? false;
  void setHidden(NavSection s, bool hide) {
    final ids = [...?_order[_hiddenKey]]..remove(s.id);
    if (hide) ids.add(s.id);
    _order[_hiddenKey] = ids;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setStringList('$_prefix$_hiddenKey', ids)).catchError((_) => false);
  }

  void moveSection(int from, int to) => _move(_rail, [for (final s in sections) s.id], from, to);

  /// The rail back to every section, in the built-in order.
  void resetRail() {
    _order
      ..remove(_rail)
      ..remove(_hiddenKey);
    notifyListeners();
    SharedPreferences.getInstance().then((p) => Future.wait([p.remove('$_prefix$_rail'), p.remove('$_prefix$_hiddenKey')])).catchError((_) => <bool>[]);
  }

  List<NavItem> items(NavSection s) => _sorted(s.id, s.id == homeSection.id ? HomeStore.instance.entries : s.items, (i) => i.id);

  void _move(String key, List<String> ids, int from, int to) {
    ids.insert(to, ids.removeAt(from));
    _order[key] = ids;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setStringList('$_prefix$key', ids)).catchError((_) => false);
  }

  /// Back to the section's built-in order.
  void reset(NavSection s) {
    _order.remove(s.id);
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.remove('$_prefix${s.id}')).catchError((_) => false);
  }

  void moveItem(NavSection s, int from, int to) => _move(s.id, [for (final i in items(s)) i.id], from, to);
}

class ClickTopBar extends StatelessWidget {
  const ClickTopBar({super.key, required this.nav, required this.activeItemId, required this.onToggle, required this.onBack, this.onSignOut});
  final AdminNav nav;
  final String? activeItemId;
  final VoidCallback onToggle, onBack;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    Widget icon(IconData i, String tip, VoidCallback? onTap, {Color color = _barText}) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      iconSize: 19,
      visualDensity: VisualDensity.compact,
      icon: Icon(i, color: color),
    );
    final ctrl = Theme.of(context).platform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: _bar,
        border: Border(bottom: BorderSide(color: TColor(0xFFE8EAED))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          icon(Icons.menu, 'Show or hide the sidebar', onToggle),
          icon(Icons.arrow_back, 'Back', onBack),
          const SizedBox(width: 6),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: _gradient, borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'P',
              style: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'PIAX',
            style: TextStyle(color: _barText, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: -.3),
          ),
          const SizedBox(width: 18),
          _MegaMenu(
            label: 'Workspace',
            columns: 2,
            tiles: [
              _Tile(Icons.home_outlined, 'Home', 'Founder Overview: revenue, orders and alerts', nav.overview),
              _Tile(Icons.inbox_outlined, 'Orders', 'The order desk: status, refunds, invoices', nav.orders),
              _Tile(Icons.insights_outlined, 'Analytics', 'Charts for every dataset', nav.analytics),
              _Tile(Icons.currency_exchange, 'Refunds', 'Requests waiting for a decision', nav.refunds),
              _Tile(Icons.grid_view, 'All modules', 'Every set of records in one place', nav.allModules),
              _Tile(Icons.settings_outlined, 'Settings', 'Sidebar, server and preferences', nav.settings),
            ],
          ),
          _MegaMenu(
            label: 'Spaces',
            columns: 3,
            tiles: [
              for (final sec in navSections)
                if (sec.items.isNotEmpty) _Tile(sec.icon, sec.label, sec.purpose, () => nav.item?.call(sec.items.first.id)),
            ],
          ),
          if (MediaQuery.sizeOf(context).width >= 1400) ...[_Link('Orders', nav.orders), _Link('Analytics', nav.analytics)],
          const SizedBox(width: 12),
          // Search: the command palette (pages, modules, features); it gives up width first on smaller screens.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SizedBox(
                  height: 32,
                  child: Material(
                    color: const TColor(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => showCommandPalette(context, nav),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 17, color: _barText),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Search', style: TextStyle(color: _barText, fontSize: 13)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: const TColor(0xFFD9DCE1)),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(ctrl, style: const TextStyle(color: _barText, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // + New: a record in any module.
          PopupMenuButton<String>(
            tooltip: 'Create',
            offset: const Offset(0, 40),
            onSelected: (key) => nav.module(key, create: true),
            itemBuilder: (_) => [
              const PopupMenuItem(
                enabled: false,
                child: Text('Create new', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              for (final m in modules) PopupMenuItem(value: m.key, child: Text(m.title)),
            ],
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: _gradient,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: TColor(0x337B68EE), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, size: 17, color: Color(0xFFFFFFFF)),
                  SizedBox(width: 4),
                  Text(
                    'New',
                    style: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (activeItemId != null)
            ListenableBuilder(
              listenable: Favorites.instance,
              builder: (_, _) {
                final on = Favorites.instance.has(activeItemId!);
                return icon(
                  on ? Icons.star : Icons.star_border,
                  on ? 'Remove from Favorites' : 'Add this page to Favorites',
                  () => Favorites.instance.toggle(activeItemId!),
                  color: on ? const TColor(0xFFF5B941) : _barText,
                );
              },
            ),
          PopupMenuButton<String>(
            tooltip: 'Inbox',
            offset: const Offset(0, 40),
            icon: const Icon(Icons.notifications_none, size: 19, color: _barText),
            onSelected: (v) => (v == 'orders' ? nav.orders : nav.refunds)?.call(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                enabled: false,
                child: Text('Inbox', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              PopupMenuItem(
                value: 'orders',
                child: ListTile(dense: true, leading: Icon(Icons.receipt_long_outlined), title: Text('New orders')),
              ),
              PopupMenuItem(
                value: 'refunds',
                child: ListTile(dense: true, leading: Icon(Icons.undo), title: Text('Refund requests')),
              ),
            ],
          ),
          icon(
            Icons.help_outline,
            'Help',
            () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Shortcuts'),
                content: Text('$ctrl  Search pages, modules and features\n★  Pin the page you\'re on to Favorites\n☰  Show or hide the sidebar'),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            offset: const Offset(0, 40),
            onSelected: (v) => v == 'settings' ? nav.settings?.call() : onSignOut?.call(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Settings')),
              ),
              if (onSignOut != null)
                const PopupMenuItem(
                  value: 'out',
                  child: ListTile(dense: true, leading: Icon(Icons.logout), title: Text('Sign out')),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: TColor(0xFF7B5CFA),
                child: Text(
                  'A',
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _gradient = LinearGradient(colors: [TColor(0xFF7B68EE), TColor(0xFFB45CF0), TColor(0xFFFD71AF)]);

class _Tile {
  const _Tile(this.icon, this.title, this.text, this.onTap);
  final IconData icon;
  final String title, text;
  final VoidCallback? onTap;
}

/// A top-bar link with no menu.
class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: _barText, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
  );
}

/// A top-bar item that opens a ClickUp-style mega menu: icon tiles, each with a title and a line on what it is.
class _MegaMenu extends StatelessWidget {
  const _MegaMenu({required this.label, required this.tiles, this.columns = 2});
  final String label;
  final List<_Tile> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(0, 10),
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(TColor(0xFFFFFFFF)),
      elevation: const WidgetStatePropertyAll(12),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    menuChildren: [
      Builder(
        builder: (context) => SizedBox(
          width: columns * 270.0,
          child: Wrap(
            children: [
              for (final t in tiles)
                SizedBox(
                  width: 270,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: t.onTap == null
                        ? null
                        : () {
                            MenuController.maybeOf(context)?.close();
                            t.onTap!();
                          },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: const TColor(0xFFF1EEFF), borderRadius: BorderRadius.circular(10)),
                            child: Icon(t.icon, size: 19, color: const TColor(0xFF7B68EE)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _barText),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: _ink2, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
    builder: (context, menu, _) => TextButton(
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      style: TextButton.styleFrom(foregroundColor: _barText, minimumSize: const Size(0, 36), padding: const EdgeInsets.only(left: 12, right: 6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Icon(menu.isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    ),
  );
}

/// A section's short rail label: its first word ("Executive", "Vending"…).
String railLabel(NavSection s) => s.label.split(RegExp(r'[ ,&]+')).first;

/// The icon rail: one button per main section (nav_config.dart), icon above a short label. Choosing one shows its
/// pages in the wide panel beside it.
class ClickRail extends StatelessWidget {
  const ClickRail({super.key, required this.selected, required this.onSelect, this.onSettings});
  final String selected;
  final ValueChanged<String> onSelect;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    Widget item(String tip, IconData icon, String label, bool on, VoidCallback? onTap) => Tooltip(
      message: tip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 32,
                decoration: BoxDecoration(color: on ? const TColor(0xFFDDF0EA) : null, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 20, color: on ? _brand : const TColor(0xFF4F625E)),
              ),
              if (AppLayout.instance.railLabels) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, height: 1.15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? _brand : const TColor(0xFF4F625E)),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Container(
      width: AppLayout.instance.railLabels ? 84 : 60,
      decoration: const BoxDecoration(
        color: TColor(0xFFF7F9F8),
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              children: [
                item('Home', Icons.home_outlined, 'Home', selected == 'home', () => onSelect('home')),
                const Divider(height: 10, indent: 14, endIndent: 14),
                ListenableBuilder(
                  listenable: NavOrder.instance,
                  builder: (_, _) => Column(
                    children: [
                      for (final s in NavOrder.instance.visibleSections)
                        item(AppLayout.instance.label(s.id, s.label), s.icon, AppLayout.instance.label(s.id, s.label), selected == s.id, () => onSelect(s.id)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // The theme (System, Light, Dark), on every page.
          if (AppLayout.instance.themeOnRail) const Padding(padding: EdgeInsets.only(top: 6), child: ThemeModeButton()),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: item('Settings', Icons.settings_outlined, 'Settings', false, onSettings)),
        ],
      ),
    );
  }
}

/// The wide panel next to the rail: the chosen section's pages (or, on Home, the main pages and Favorites).
class ClickSidebar extends StatelessWidget {
  const ClickSidebar({super.key, required this.nav, required this.section, required this.activeItemId, required this.onHide});
  final AdminNav nav;

  /// A section id from nav_config.dart, or 'home'.
  final String section;
  final String? activeItemId;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final sec = navSections.where((s) => s.id == section).firstOrNull;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: TColor(0xFF7A8C88)),
      ),
    );
    Widget tile(IconData icon, String label, bool on, VoidCallback? onTap, {String? starId}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        selected: on,
        selectedTileColor: const TColor(0xFFDDF0EA),
        selectedColor: _brand,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon, size: 18),
        minLeadingWidth: 20,
        title: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(label, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 13.5)),
        ),
        trailing: starId == null || !AppLayout.instance.favorites
            ? null
            : ListenableBuilder(
                listenable: Favorites.instance,
                builder: (_, _) {
                  final fav = Favorites.instance.has(starId);
                  return IconButton(
                    tooltip: fav ? 'Remove from Favorites' : 'Add to Favorites',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Favorites.instance.toggle(starId),
                    icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? const TColor(0xFFF5B941) : const TColor(0xFFB5C2BF)),
                  );
                },
              ),
        onTap: onTap,
      ),
    );

    final List<Widget> body;
    if (sec == null) {
      body = [
        heading('Home'),
        ListenableBuilder(
          listenable: NavOrder.instance,
          builder: (_, _) {
            final go = {'founder-overview': nav.overview, 'home-orders': nav.orders, 'home-analytics': nav.analytics, 'home-refunds': nav.refunds, 'home-modules': nav.allModules};
            return Column(
              children: [
                for (final i in NavOrder.instance.items(homeSection))
                  () {
                    final added = HomeStore.target(i.id);
                    final itemId = added == null ? i.id : (added.$2 ?? added.$1.items.first).id;
                    final open = go[i.id] ?? () => nav.item?.call(itemId);
                    final on = (added != null || i.id == 'founder-overview') && activeItemId == itemId;
                    return tile(_iconOf(homeSection, i), i.label, on, open, starId: added?.$2 != null || i.id == 'founder-overview' ? itemId : null);
                  }(),
              ],
            );
          },
        ),
        if (AppLayout.instance.favorites) heading('Favorites'),
        if (AppLayout.instance.favorites)
          ListenableBuilder(
            listenable: Favorites.instance,
            builder: (_, _) {
              final favs = [for (final id in Favorites.instance.ids) ?navItemById(id)];
              if (favs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
                  child: Text('Star a page to keep it here.', style: TextStyle(fontSize: 12.5, color: TColor(0xFF8A9A96))),
                );
              }
              return Column(children: [for (final (s, i) in favs) tile(navItemIcon(i, s.icon), i.label, i.id == activeItemId, () => nav.item?.call(i.id), starId: i.id)]);
            },
          ),
      ];
    } else {
      body = [
        const SizedBox(height: 8),
        // The section's pages, in the order set in the Reorder pop-up.
        ListenableBuilder(
          listenable: NavOrder.instance,
          builder: (_, _) => Column(
            children: [
              for (final i in NavOrder.instance.items(sec))
                if (!AppLayout.instance.hiddenPages.contains(i.id))
                  tile(navItemIcon(i, sec.icon), AppLayout.instance.label(i.id, i.label), i.id == activeItemId, () => nav.item?.call(i.id), starId: i.id),
            ],
          ),
        ),
      ];
    }

    return Container(
      width: AppLayout.instance.panelPixels,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Material(
        color: TColor(0xFFFFFFFF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
              child: Row(
                children: [
                  if (sec != null) ...[Icon(sec.icon, size: 18, color: _brand), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(
                      sec == null ? 'Home' : AppLayout.instance.label(sec.id, sec.label),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    onSelected: (v) => switch (v) {
                      'customize' => showHomeCustomizer(context),
                      'reorder' => showReorderDialog(context, sec ?? homeSection),
                      _ => sec == null ? HomeStore.instance.reset() : NavOrder.instance.reset(sec),
                    },
                    itemBuilder: (_) => [
                      if (sec == null)
                        const PopupMenuItem(
                          value: 'customize',
                          child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Customize Home…')),
                        ),
                      const PopupMenuItem(
                        value: 'reorder',
                        child: ListTile(dense: true, leading: Icon(Icons.swap_vert), title: Text('Reorder')),
                      ),
                      PopupMenuItem(
                        value: 'reset',
                        child: ListTile(dense: true, leading: const Icon(Icons.restart_alt), title: Text(sec == null ? 'Reset Home' : 'Reset order')),
                      ),
                    ],
                  ),
                  if (AppLayout.instance.search)
                    IconButton(
                      tooltip: 'Search',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showCommandPalette(context, nav),
                      icon: const Icon(Icons.search, size: 18),
                    ),
                  IconButton(tooltip: 'Hide the sidebar', visualDensity: VisualDensity.compact, onPressed: onHide, icon: const Icon(Icons.keyboard_double_arrow_left, size: 18)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 12), children: body),
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon for a sub-page, from the words in its name; the section's icon when none fits.
IconData navItemIcon(NavItem item, IconData fallback) {
  final l = item.label.toLowerCase();
  for (final (words, icon) in _itemIcons) {
    if (words.any(l.contains)) return icon;
  }
  return fallback;
}

const _itemIcons = <(List<String>, IconData)>[
  (['overview', 'command centre'], Icons.space_dashboard_outlined),
  (['kpi', 'health &'], Icons.monitor_heart_outlined),
  (['exception', 'alert', 'incident', 'security'], Icons.warning_amber_outlined),
  (['decision', 'approval'], Icons.task_alt),
  (['target', 'forecast'], Icons.track_changes),
  (['sku', 'variant'], Icons.qr_code_2),
  (['bom', 'packaging', 'packing'], Icons.inventory_outlined),
  (['specification', 'revision', 'change control', 'firmware', 'configuration'], Icons.tune),
  (['pricing', 'tax', 'costing'], Icons.sell_outlined),
  (['supplier', 'partner', 'vendor', 'franchise'], Icons.handshake_outlined),
  (['warehouse', 'location', 'store'], Icons.location_on_outlined),
  (['purchase', 'quotation', 'procurement'], Icons.shopping_cart_outlined),
  (['production', 'work order', 'factory'], Icons.precision_manufacturing_outlined),
  (['receipt', 'consumption'], Icons.move_to_inbox_outlined),
  (['wastage', 'rework', 'retirement', 'redeployment'], Icons.recycling),
  (['quality', 'testing', 'lab', 'fat)'], Icons.science_outlined),
  (['batch', 'ledger', 'stock', 'reservation', 'inventory'], Icons.inventory_2_outlined),
  (['transfer', 'cycle count'], Icons.swap_horiz),
  (['reorder', 'refill', 'route'], Icons.alt_route),
  (['courier', 'delivery', 'deployment', 'installation'], Icons.local_shipping_outlined),
  (['return', 'reverse'], Icons.assignment_return_outlined),
  (['machine', 'device', 'slot'], Icons.local_convenience_store_outlined),
  (['connectivity', 'api', 'webhook', 'sync', 'integration', 'clickup'], Icons.hub_outlined),
  (['maintenance', 'service', 'warranty', 'amc'], Icons.build_outlined),
  (['settlement', 'payment', 'receivable', 'payable', 'reconciliation', 'revenue share'], Icons.account_balance_wallet_outlined),
  (['profitability', 'contribution', 'revenue', 'cash flow', 'valuation'], Icons.trending_up),
  (['expense', 'budget'], Icons.savings_outlined),
  (['crm', 'pipeline', 'tender', 'b2b', 'b2g', 'institutional'], Icons.business_center_outlined),
  (['order', 'transaction', 'marketplace', 'sales'], Icons.receipt_long_outlined),
  (['subscription', 'premium'], Icons.workspace_premium_outlined),
  (['compliance', 'claims', 'evidence', 'certificate', 'sop', 'document', 'policies'], Icons.verified_outlined),
  (['builder'], Icons.dashboard_customize_outlined),
  (['cms', 'website', 'app content'], Icons.web_outlined),
  (['banner', 'offer', 'coupon'], Icons.local_offer_outlined),
  (['blog', 'education'], Icons.menu_book_outlined),
  (['media'], Icons.perm_media_outlined),
  (['review', 'survey', 'feedback', 'complaint'], Icons.rate_review_outlined),
  (['release', 'history'], Icons.history),
  (['calendar', 'campaign'], Icons.campaign_outlined),
  (['social', 'creator'], Icons.groups_2_outlined),
  (['segment', 'acquisition', 'conversion', 'retention', 'repeat'], Icons.pie_chart_outline),
  (['support'], Icons.support_agent),
  (['team', 'directory'], Icons.badge_outlined),
  (['role', 'permission', 'access'], Icons.admin_panel_settings_outlined),
  (['report', 'catalogue'], Icons.assessment_outlined),
  (['data quality'], Icons.fact_check_outlined),
  (['notification'], Icons.notifications_outlined),
  (['audit', 'log'], Icons.manage_search),
  (['import', 'export'], Icons.import_export),
  (['backup', 'recovery'], Icons.backup_outlined),
  (['system'], Icons.settings_outlined),
];

/// The pop-up where a section's pages are put in order: drag a row by its handle, then Done.
Future<void> showReorderDialog(BuildContext context, NavSection sec) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Reorder · ${sec.label}'),
    contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    content: SizedBox(
      width: 420,
      height: 480,
      child: ListenableBuilder(
        listenable: NavOrder.instance,
        builder: (_, _) {
          final items = NavOrder.instance.items(sec);
          return ReorderableListView(
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => NavOrder.instance.moveItem(sec, from, to),
            children: [
              for (final (n, i) in items.indexed)
                ListTile(
                  key: ValueKey(i.id),
                  dense: true,
                  leading: Icon(_iconOf(sec, i), size: 18),
                  title: Text(i.label),
                  trailing: ReorderableDragStartListener(
                    index: n,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(Icons.drag_indicator, color: TColor(0xFF9AAEA9)),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => NavOrder.instance.reset(sec), child: const Text('Reset to default')),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ],
  ),
);

/// Settings › Navigation: the icon rail (drag to reorder, switch to show or hide) and each section's pages
/// (pick a section, drag to reorder). Changes show in the rail and the panel straight away.
class NavCustomizer extends StatefulWidget {
  const NavCustomizer({super.key});

  @override
  State<NavCustomizer> createState() => _NavCustomizerState();
}

class _NavCustomizerState extends State<NavCustomizer> {
  NavSection _section = homeSection;

  Widget _handle(int index) => ReorderableDragStartListener(
    index: index,
    child: const MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Tooltip(
        message: 'Drag to reorder',
        child: Icon(Icons.drag_indicator, color: TColor(0xFF9AAEA9)),
      ),
    ),
  );

  Widget _heading(String title, String hint, VoidCallback onReset) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(hint, style: const TextStyle(color: TColor(0xFF8A9A96), fontSize: 12.5)),
          ],
        ),
      ),
      TextButton.icon(onPressed: onReset, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Reset')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final order = NavOrder.instance;
    return ListenableBuilder(
      listenable: order,
      builder: (context, _) {
        final sections = order.sections, items = order.items(_section);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading('Icon rail', 'Drag sections to reorder them; switch one off to hide it from the rail.', order.resetRail),
            const SizedBox(height: 6),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: order.moveSection,
              children: [
                for (final (n, s) in sections.indexed)
                  ListTile(
                    key: ValueKey(s.id),
                    dense: true,
                    leading: _handle(n),
                    title: Tooltip(
                      message: s.label,
                      child: Row(
                        children: [
                          Icon(s.icon, size: 18, color: order.isHidden(s) ? const TColor(0xFFB5C2BF) : _brand),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppLayout.instance.label(s.id, s.label),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: order.isHidden(s) ? const TColor(0xFF8A9A96) : null),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => renameNavDialog(context, s.id, s.label)),
                        Switch(value: !order.isHidden(s), onChanged: (on) => order.setHidden(s, !on)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 28),
            _heading(
              'Pages',
              'Pick a section, then drag its pages into the order you want in the wide panel. Home can also take pages from any section, with your own names.',
              () => _section.id == homeSection.id ? HomeStore.instance.reset() : order.reset(_section),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _section.id,
              decoration: const InputDecoration(labelText: 'Section', isDense: true),
              items: [
                for (final s in [homeSection, ...sections])
                  DropdownMenuItem(
                    value: s.id,
                    child: Row(children: [Icon(s.icon, size: 18), const SizedBox(width: 8), Text(s.label)]),
                  ),
              ],
              onChanged: (id) => setState(() => _section = [homeSection, ...navSections].firstWhere((s) => s.id == id)),
            ),
            const SizedBox(height: 6),
            if (_section.id == homeSection.id)
              const HomeCustomizer()
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) => order.moveItem(_section, from, to),
                children: [
                  for (final (n, i) in items.indexed)
                    ListTile(
                      key: ValueKey(i.id),
                      dense: true,
                      leading: _handle(n),
                      title: Tooltip(
                        message: i.label,
                        child: Row(
                          children: [
                            Icon(_iconOf(_section, i), size: 18, color: _brand),
                            const SizedBox(width: 10),
                            Expanded(child: Text(AppLayout.instance.label(i.id, i.label), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => renameNavDialog(context, i.id, i.label)),
                          Tooltip(
                            message: 'Show in the wide panel',
                            child: Switch(value: !AppLayout.instance.hiddenPages.contains(i.id), onChanged: (on) => AppLayout.instance.setPageHidden(i.id, !on)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// The Home editor pop-up (the panel's gear menu › Customize Home…).
Future<void> showHomeCustomizer(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Customize Home'),
    contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    content: const SizedBox(width: 520, height: 520, child: SingleChildScrollView(child: HomeCustomizer())),
    actions: [
      TextButton(onPressed: HomeStore.instance.reset, child: const Text('Reset Home')),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ],
  ),
);

/// Home's entries: drag to reorder, rename in place, remove; Add page brings in any main page or sub-page.
class HomeCustomizer extends StatelessWidget {
  const HomeCustomizer({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([NavOrder.instance, HomeStore.instance]),
    builder: (context, _) {
      final store = HomeStore.instance, items = NavOrder.instance.items(homeSection);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => NavOrder.instance.moveItem(homeSection, from, to),
            children: [
              for (final (n, i) in items.indexed)
                Padding(
                  key: ValueKey(i.id),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: n,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Tooltip(
                            message: 'Drag to reorder',
                            child: Icon(Icons.drag_indicator, color: TColor(0xFF9AAEA9)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(_iconOf(homeSection, i), size: 18, color: _brand),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('name-${i.id}'),
                          initialValue: i.label,
                          decoration: InputDecoration(isDense: true, hintText: HomeStore.defaultName(i.id), helperText: _from(i.id)),
                          onChanged: (v) => store.rename(i.id, v),
                        ),
                      ),
                      IconButton(tooltip: 'Remove from Home', onPressed: () => store.remove(i.id), icon: const Icon(Icons.close, size: 18)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: () => _pick(context), icon: const Icon(Icons.add), label: const Text('Add page')),
          ),
        ],
      );
    },
  );

  /// Where an added entry comes from ("From 06 Vending Machine Operations").
  static String? _from(String id) => switch (HomeStore.target(id)) {
    (final s, null) => 'Main page of ${s.label}',
    (final s, _?) => 'From ${s.label}',
    _ => null,
  };

  /// A searchable list of every main page and sub-page (and built-in Home entries taken off) to add to Home.
  Future<void> _pick(BuildContext context) async {
    final store = HomeStore.instance;
    final options = <(String id, String label, String from, IconData icon)>[
      for (final i in homeSection.items)
        if (!store.has(i.id)) (i.id, i.label, 'Home', _homeIcons[i.id] ?? Icons.home_outlined),
      for (final sec in navSections) ...[
        ('add:section:${sec.id}', sec.label, 'Main page', sec.icon),
        for (final i in sec.items) ('add:${i.id}', i.label, sec.label, navItemIcon(i, sec.icon)),
      ],
    ].where((o) => !store.has(o.$1)).toList();
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) {
        var q = '';
        return StatefulBuilder(
          builder: (context, set) {
            final shown = [
              for (final o in options)
                if ('${o.$2} ${o.$3}'.toLowerCase().contains(q)) o,
            ];
            return AlertDialog(
              title: const Text('Add a page to Home'),
              contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              content: SizedBox(
                width: 480,
                height: 480,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search pages'),
                      onChanged: (v) => set(() => q = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final o in shown)
                            ListTile(dense: true, leading: Icon(o.$4, size: 18), title: Text(o.$2), subtitle: Text(o.$3), onTap: () => Navigator.pop(context, o.$1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
            );
          },
        );
      },
    );
    if (chosen != null) store.add(chosen);
  }
}

/// Renames a section or page (empty brings back its own name).
Future<void> renameNavDialog(BuildContext context, String id, String fallback) async {
  final c = TextEditingController(text: AppLayout.instance.label(id, fallback));
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Name', helperText: 'Leave empty for “$fallback”'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
      ],
    ),
  );
  if (name != null) AppLayout.instance.rename(id, name, fallback);
}

/// Settings › Layout & features: the frame's look and which features it shows.
class LayoutSettings extends StatelessWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppLayout.instance,
    builder: (context, _) {
      final l = AppLayout.instance;
      Widget sw(String title, String hint, bool value, void Function(bool) set) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(hint, style: const TextStyle(fontSize: 12.5, color: TColor(0xFF8A9A96))),
        value: value,
        onChanged: (v) => l.update((_) => set(v)),
      );
      Widget seg<T>(String title, T value, List<(T, String, IconData)> options, void Function(T) set) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [for (final (v, label, icon) in options) ButtonSegment(value: v, icon: Icon(icon, size: 16), label: Text(label))],
              selected: {value},
              onSelectionChanged: (s) => l.update((_) => set(s.first)),
            ),
          ],
        ),
      );
      Widget head(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: TColor(0xFF7A8C88)),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head('Navigation bar'),
          seg('Icon rail side', l.railRight, const [(false, 'Left', Icons.align_horizontal_left), (true, 'Right', Icons.align_horizontal_right)], (v) => l.railRight = v),
          seg('Wide panel width', l.panelWidth, const [
            ('narrow', 'Narrow', Icons.view_sidebar_outlined),
            ('normal', 'Normal', Icons.view_sidebar),
            ('wide', 'Wide', Icons.view_quilt_outlined),
          ], (v) => l.panelWidth = v),
          sw('Labels under rail icons', 'Off: icons only, with names on hover.', l.railLabels, (v) => l.railLabels = v),
          head('Alignment'),
          seg('Page content', l.centered, const [(false, 'Full width', Icons.fit_screen_outlined), (true, 'Centred', Icons.format_align_center)], (v) => l.centered = v),
          head('Features'),
          sw('Search', 'The search buttons and Ctrl / ⌘ + K.', l.search, (v) => l.search = v),
          sw('Theme switch on the rail', 'Light, dark or system, above Settings.', l.themeOnRail, (v) => l.themeOnRail = v),
          sw('Favorites', 'Stars on pages and the Favorites list on Home.', l.favorites, (v) => l.favorites = v),
          sw('Edit fields button', 'On every page that has one.', l.editFields, (v) => l.editFields = v),
          sw('Tooltips', 'Hints when hovering over buttons, icons and names.', l.tooltips, (v) => l.tooltips = v),
          sw('Page trail', 'The Admin › Section › Page line above each page.', l.breadcrumb, (v) => l.breadcrumb = v),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: l.reset, icon: const Icon(Icons.restart_alt, size: 18), label: const Text('Reset layout, features and names')),
          ),
        ],
      );
    },
  );
}
