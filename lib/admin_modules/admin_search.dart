import 'package:flutter/material.dart';

import '../format.dart';
import 'schema.dart';

// The search at the top of the admin app: finds pages (Orders, Analytics, Refunds, Settings, the admin overview),
// every admin module, and features inside them ("Verify doctor", "Add product", "Suspend partner", a field such as
// "Stock"), and jumps straight there.

/// Where the search can take the admin. Pages the current screen can't reach are left null and not offered.
class AdminNav {
  const AdminNav({this.orders, this.analytics, this.refunds, this.settings, required this.overview, required this.allModules, required this.module});
  final VoidCallback? orders, analytics, refunds, settings;
  final VoidCallback overview, allModules;

  /// Opens a module's list, optionally filtered to [status], or straight into its "add" form.
  final void Function(String module, {String? status, bool create}) module;
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
    final kindBonus = switch (kind) { SearchKind.page => 3, SearchKind.module => 2, SearchKind.feature => 0 };
    if (t.startsWith(q)) return 30 + kindBonus;
    if (t.contains(q)) return 20 + kindBonus;
    return 10 + kindBonus;
  }
}

List<SearchEntry> adminSearchEntries(AdminNav nav) => [
  if (nav.orders != null) SearchEntry(SearchKind.page, 'Orders', 'Order desk · pack, ship, track and cancel orders', Icons.dashboard_outlined, nav.orders!, keywords: 'order desk pack ship deliver track cancel invoice customer'),
  if (nav.analytics != null) SearchEntry(SearchKind.page, 'Analytics', 'Sales, orders and trends', Icons.insights_outlined, nav.analytics!, keywords: 'sales revenue charts reports trends'),
  if (nav.refunds != null) SearchEntry(SearchKind.page, 'Refunds', 'Cancelled orders waiting for a refund', Icons.currency_exchange, nav.refunds!, keywords: 'refund money return cancelled payment'),
  if (nav.settings != null) SearchEntry(SearchKind.page, 'Settings', 'Server, password and account', Icons.settings_outlined, nav.settings!, keywords: 'password server account preferences'),
  SearchEntry(SearchKind.page, 'Admin overview', 'Every module at a glance: numbers, charts and what needs attention', Icons.space_dashboard_outlined, nav.overview, keywords: 'dashboard insights charts kpi attention summary analytics'),
  SearchEntry(SearchKind.page, 'All admin modules', 'The list of every admin module, by group', Icons.apps_outlined, nav.allModules, keywords: 'modules list'),
  for (final m in modules) ...[
    SearchEntry(SearchKind.module, m.title, '${m.group} · ${m.description}', m.icon, () => nav.module(m.key),
        keywords: '${m.singular} ${m.fields.map((f) => f.label).join(' ')} ${m.statuses.join(' ')}'),
    if (m.canCreate) SearchEntry(SearchKind.feature, 'Add ${m.singular.toLowerCase()}', 'In ${m.title}', Icons.add_circle_outline, () => nav.module(m.key, create: true), keywords: 'new create ${m.title}'),
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
      SearchEntry(SearchKind.feature, '${m.title}: $s', 'Show only the ${m.title.toLowerCase()} that are $s', Icons.filter_alt_outlined, () => nav.module(m.key, status: s), keywords: 'status filter'),
  ],
];

/// The search field: a Material 3 search bar that opens a full list of results grouped as Pages, Modules and Features.
class AdminSearchBar extends StatelessWidget {
  const AdminSearchBar({super.key, required this.nav, this.hint = 'Search features, modules and pages', this.compact = false});
  final AdminNav nav;
  final String hint;

  /// Just a search icon (phone app bars); the search opens full screen when tapped.
  final bool compact;

  static const _kindLabel = {SearchKind.page: 'PAGES', SearchKind.module: 'MODULES', SearchKind.feature: 'FEATURES'};

  @override
  Widget build(BuildContext context) {
    final entries = adminSearchEntries(nav);
    return SearchAnchor(
      viewHintText: hint,
      viewBackgroundColor: Colors.white,
      isFullScreen: compact || MediaQuery.sizeOf(context).width < 600,
      builder: (context, controller) => compact
          ? IconButton(tooltip: 'Search features, modules and pages', icon: const Icon(Icons.manage_search), onPressed: controller.openView)
          : SearchBar(
        controller: controller,
        hintText: hint,
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFDCE6E3))),
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 16)),
        hintStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, color: Color(0xFF6B7B77))),
        leading: const Icon(Icons.search, color: brand),
        onTap: controller.openView,
        onChanged: (_) => controller.openView(),
      ),
      suggestionsBuilder: (context, controller) {
        final q = controller.text;
        final hits = [for (final e in entries) if (e.score(q) > 0) e]..sort((a, b) => b.score(q).compareTo(a.score(q)));
        final shown = q.trim().isEmpty ? hits.where((e) => e.kind != SearchKind.feature).toList() : hits.take(40).toList();
        if (shown.isEmpty) {
          return [const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nothing matches. Try a module name, like “doctors”, or an action, like “verify”.')))];
        }
        return [
          for (final kind in SearchKind.values)
            if (shown.any((e) => e.kind == kind)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(_kindLabel[kind]!, style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
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
