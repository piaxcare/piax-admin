import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import 'schema.dart';

import 'package:piax_orders_admin/palette.dart';
import 'package:piax_orders_admin/app_layout.dart';

// The search at the top of the admin app: finds pages (Orders, Analytics, Refunds, Settings, the admin overview),
// every admin module, and features inside them ("Verify doctor", "Add product", "Suspend partner", a field such as
// "Stock"), and jumps straight there.

/// Where the search can take the admin. Pages the current screen can't reach are left null and not offered.
class AdminNav {
  const AdminNav({this.orders, this.analytics, this.refunds, this.settings, required this.overview, required this.allModules, required this.module, this.item});
  final VoidCallback? orders, analytics, refunds, settings;
  final VoidCallback overview, allModules;

  /// Opens a module's list, optionally filtered to [status], or straight into its "add" form.
  final void Function(String module, {String? status, bool create}) module;

  /// Opens a sidebar menu item by its id (nav_config.dart) and highlights it. Set by the app frame; without it, items
  /// open their page or module directly.
  final void Function(String itemId)? item;
}

enum SearchKind { page, module, feature }

class SearchEntry {
  const SearchEntry(this.kind, this.title, this.subtitle, this.icon, this.go, {this.keywords = ''});
  final SearchKind kind;
  final String title, subtitle, keywords;
  final IconData icon;
  final VoidCallback go;

  /// 0 = no match; higher is better. Every word of the query must appear somewhere.
  int score(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 1;
    final t = title.toLowerCase();
    final all = '$t ${subtitle.toLowerCase()} ${keywords.toLowerCase()}';
    if (!q.split(RegExp(r'\s+')).every(all.contains)) return 0;
    final kindBonus = switch (kind) {
      SearchKind.page => 3,
      SearchKind.module => 2,
      SearchKind.feature => 0,
    };
    if (t.startsWith(q)) return 30 + kindBonus;
    if (t.contains(q)) return 20 + kindBonus;
    return 10 + kindBonus;
  }
}

List<SearchEntry> adminSearchEntries(AdminNav nav) => [
  if (nav.orders != null)
    SearchEntry(
      SearchKind.page,
      'Orders',
      'Order desk · pack, ship, track and cancel orders',
      Icons.dashboard_outlined,
      nav.orders!,
      keywords: 'order desk pack ship deliver track cancel invoice customer',
    ),
  if (nav.analytics != null)
    SearchEntry(SearchKind.page, 'Analytics', 'Sales, orders and trends', Icons.insights_outlined, nav.analytics!, keywords: 'sales revenue charts reports trends'),
  if (nav.refunds != null)
    SearchEntry(SearchKind.page, 'Refunds', 'Cancelled orders waiting for a refund', Icons.currency_exchange, nav.refunds!, keywords: 'refund money return cancelled payment'),
  if (nav.settings != null)
    SearchEntry(SearchKind.page, 'Settings', 'Server, password and account', Icons.settings_outlined, nav.settings!, keywords: 'password server account preferences'),
  SearchEntry(
    SearchKind.page,
    'Admin overview',
    'Every module at a glance: numbers, charts and what needs attention',
    Icons.space_dashboard_outlined,
    nav.overview,
    keywords: 'dashboard insights charts kpi attention summary analytics',
  ),
  SearchEntry(SearchKind.page, 'All admin modules', 'The list of every admin module, by group', Icons.apps_outlined, nav.allModules, keywords: 'modules list'),
  for (final m in modules) ...[
    SearchEntry(
      SearchKind.module,
      m.title,
      '${m.group} · ${m.description}',
      m.icon,
      () => nav.module(m.key),
      keywords: '${m.singular} ${m.fields.map((f) => f.label).join(' ')} ${m.statuses.join(' ')}',
    ),
    if (m.canCreate)
      SearchEntry(
        SearchKind.feature,
        'Add ${m.singular.toLowerCase()}',
        'In ${m.title}',
        Icons.add_circle_outline,
        () => nav.module(m.key, create: true),
        keywords: 'new create ${m.title}',
      ),
    for (final a in m.actions)
      SearchEntry(
        SearchKind.feature,
        '${a.label} · ${m.singular.toLowerCase()}',
        a.from.length == 1 ? 'In ${m.title} · shows the ones that are ${a.from.single}' : 'In ${m.title}',
        a.icon,
        () => nav.module(m.key, status: a.from.length == 1 ? a.from.single : null),
        keywords: '${m.title} ${a.to} ${a.from.join(' ')}',
      ),
    for (final s in m.statuses)
      SearchEntry(
        SearchKind.feature,
        '${m.title}: $s',
        'Show only the ${m.title.toLowerCase()} that are $s',
        Icons.filter_alt_outlined,
        () => nav.module(m.key, status: s),
        keywords: 'status filter',
      ),
  ],
];

/// The search field: a Material 3 search bar that opens a full list of results grouped as Pages, Modules and Features.
class AdminSearchBar extends StatelessWidget {
  const AdminSearchBar({super.key, required this.nav, this.hint = 'Search features, modules and pages', this.compact = false, this.controller});

  /// Lets the app frame open it from the keyboard (Ctrl / ⌘ + K).
  final SearchController? controller;
  final AdminNav nav;
  final String hint;

  /// Just a search icon (phone app bars); the search opens full screen when tapped.
  final bool compact;

  static const _kindLabel = {SearchKind.page: 'PAGES', SearchKind.module: 'MODULES', SearchKind.feature: 'FEATURES'};

  @override
  Widget build(BuildContext context) {
    final entries = adminSearchEntries(nav);
    return SearchAnchor(
      searchController: controller,
      viewHintText: hint,
      viewBackgroundColor: TColor(0xFFFFFFFF),
      isFullScreen: compact || MediaQuery.sizeOf(context).width < 600,
      builder: (context, controller) => compact
          ? IconButton(tooltip: 'Search features, modules and pages', icon: const Icon(Icons.manage_search), onPressed: controller.openView)
          : SearchBar(
              controller: controller,
              hintText: hint,
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(TColor(0xFFFFFFFF)),
              side: const WidgetStatePropertyAll(BorderSide(color: TColor(0xFFDCE6E3))),
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 16)),
              hintStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, color: TColor(0xFF6B7B77))),
              leading: const Icon(Icons.search, color: brand),
              onTap: controller.openView,
              onChanged: (_) => controller.openView(),
            ),
      suggestionsBuilder: (context, controller) {
        final q = controller.text;
        final hits = [
          for (final e in entries)
            if (e.score(q) > 0) e,
        ]..sort((a, b) => b.score(q).compareTo(a.score(q)));
        final shown = q.trim().isEmpty ? hits.where((e) => e.kind != SearchKind.feature).toList() : hits.take(40).toList();
        if (shown.isEmpty) {
          return [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nothing matches. Try a module name, like “doctors”, or an action, like “verify”.')),
            ),
          ];
        }
        return [
          for (final kind in SearchKind.values)
            if (shown.any((e) => e.kind == kind)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  _kindLabel[kind]!,
                  style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.4),
                ),
              ),
              for (final e in shown.where((e) => e.kind == kind))
                ListTile(
                  leading: Icon(e.icon, color: brand),
                  title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    controller.closeView('');
                    controller.clear();
                    WidgetsBinding.instance.addPostFrameCallback((_) => e.go());
                  },
                ),
            ],
        ];
      },
    );
  }
}

/// The app's navigation for everything inside the app frame, so any page can offer the global search.
class AdminNavScope extends InheritedWidget {
  const AdminNavScope({super.key, required this.nav, required super.child});
  final AdminNav nav;

  static AdminNav? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AdminNavScope>()?.nav;

  @override
  bool updateShouldNotify(AdminNavScope old) => !identical(old.nav, nav);
}

/// For a page's top bar, right of Edit fields: the global search as an icon (the Ctrl / ⌘ + K pop-up on big screens).
List<Widget> globalSearchActions(BuildContext context) {
  final nav = AdminNavScope.maybeOf(context);
  return [
    if (nav != null && AppLayout.instance.search)
      MediaQuery.sizeOf(context).width >= 1100
          ? IconButton(tooltip: 'Search (Ctrl / ⌘ + K)', onPressed: () => showCommandPalette(context, nav), icon: const Icon(Icons.search))
          : AdminSearchBar(nav: nav, compact: true),
  ];
}

// ================================================================ Command palette (Ctrl / ⌘ + K)

/// Opens the search as a pop-up in the middle of the screen: type to filter pages, modules and features, ↑ ↓ to move,
/// Enter to open, Esc to close. The same results as the search bar.
Future<void> showCommandPalette(BuildContext context, AdminNav nav) async {
  final chosen = await showDialog<SearchEntry>(
    context: context,
    barrierColor: const TColor(0x590C1C19),
    builder: (_) => _CommandPalette(entries: adminSearchEntries(nav)),
  );
  // After the pop-up has closed, so the page it opens isn't covered.
  if (chosen != null) WidgetsBinding.instance.addPostFrameCallback((_) => chosen.go());
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.entries});
  final List<SearchEntry> entries;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Best matches first; with nothing typed, the pages and modules.
  List<SearchEntry> get _hits {
    final q = _query.text;
    final hits = [
      for (final e in widget.entries)
        if (e.score(q) > 0) e,
    ]..sort((a, b) => b.score(q).compareTo(a.score(q)));
    final list = q.trim().isEmpty ? hits.where((e) => e.kind != SearchKind.feature).toList() : hits.take(40).toList();
    // Grouped as shown: pages, modules, features.
    return [for (final kind in SearchKind.values) ...list.where((e) => e.kind == kind)];
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _index = (_index + by) % count < 0 ? count - 1 : (_index + by) % count);
    // Keep the highlighted row in view (rows are about 56 px, plus group labels).
    final target = (_index * 56.0) - 120;
    if (_scroll.hasClients) _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    if (_index >= hits.length) _index = hits.isEmpty ? 0 : hits.length - 1;
    const labels = {SearchKind.page: 'PAGES', SearchKind.module: 'MODULES', SearchKind.feature: 'FEATURES'};
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.7),
          child: Material(
            color: TColor(0xFFFFFFFF),
            elevation: 12,
            shadowColor: const TColor(0x330C1C19),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, hits.length),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, hits.length),
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (hits.isNotEmpty) Navigator.of(context).pop(hits[_index]);
                },
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: brand),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _query,
                            autofocus: true,
                            style: const TextStyle(fontSize: 17),
                            decoration: const InputDecoration(
                              hintText: 'Search pages, modules and features',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() => _index = 0),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: const TColor(0xFFDCE6E3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Esc', style: TextStyle(color: TColor(0xFF8A9A96), fontSize: 11.5)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: hits.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                              'Nothing matches. Try a module name, like “doctors”, or an action, like “verify”.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: TColor(0xFF5A6C68)),
                            ),
                          )
                        : ListView(
                            controller: _scroll,
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            children: [
                              for (final (i, e) in hits.indexed) ...[
                                if (i == 0 || hits[i - 1].kind != e.kind)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                                    child: Text(
                                      labels[e.kind]!,
                                      style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1.4),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: ListTile(
                                    selected: i == _index,
                                    selectedTileColor: const TColor(0xFFEFF7F4),
                                    selectedColor: const TColor(0xFF0C1C19),
                                    leading: Icon(e.icon, color: brand),
                                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: i == _index ? const Icon(Icons.keyboard_return, size: 16, color: TColor(0xFF8A9A96)) : null,
                                    onTap: () => Navigator.of(context).pop(e),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [Text('↑ ↓ to move · Enter to open · Esc to close', style: TextStyle(color: TColor(0xFF8A9A96), fontSize: 12))],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
