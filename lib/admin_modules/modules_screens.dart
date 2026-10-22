import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../screens/login_screen.dart' show signOut;
import 'admin_drawer.dart';
import 'admin_shell.dart' show AdminSidebar;
import 'admin_search.dart';
import 'attachments.dart';
import 'charts.dart';
import 'discounts.dart';
import 'field_store.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart' show AreaTrend, SplitBar, breakdownText, greens;
import 'insights.dart';
import 'member_widgets.dart';
import 'overview_screen.dart';
import 'nav_config.dart' show AppPage;
import 'nav_widgets.dart' show PageTreeSlot, menuTitle;
import 'option_store.dart';
import 'record_filter.dart';
import 'repository.dart';
import 'schema.dart';

import 'package:piax_orders_admin/palette.dart';
import 'package:piax_orders_admin/app_layout.dart';

// The Admin modules mock-up: the backend admin panel's modules (schema.dart) on dummy data (repository.dart).
// One set of screens serves every module: Home (module groups) → List (search, status filter, add) → Details
// (fields, one-tap actions, edit, delete) → Form (add / edit).

String displayValue(FieldDef field, Object? value) {
  if (value == null || (value is String && value.isEmpty)) return '—';
  switch (field.type) {
    case FieldType.money:
      final n = value is num ? value : num.tryParse('$value');
      return n == null ? '$value' : rupees(n.round());
    case FieldType.boolean:
      return value == true || value == 'true' ? 'Yes' : 'No';
    case FieldType.list:
      return value is List ? (value.isEmpty ? '—' : value.join(', ')) : '$value';
    case FieldType.file:
      return attachmentsSummary(value);
    case FieldType.dateTime:
      final at = DateTime.tryParse('$value');
      return at == null ? '$value' : DateFormat('d MMM yyyy, h:mm a').format(at.toLocal());
    case FieldType.integer:
      final n = value is num ? value : num.tryParse('$value');
      return n == null ? '$value' : NumberFormat.decimalPattern('en_IN').format(n);
    default:
      return '$value';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusTone(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status,
        style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

Future<void> _handleError(BuildContext context, Object error) async {
  if (error is ApiException && error.signedOut) return signOut(context, message: 'Your session ended. Please sign in again.');
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error is ApiException ? error.message : 'Something went wrong. Please try again.')));
}

// ================================================================ Home

class ModulesHomeScreen extends StatefulWidget {
  const ModulesHomeScreen({
    super.key,
    required this.api,
    this.appNav,
    this.initialModule,
    this.initialStatus,
    this.startAdding = false,
    this.showAllModules = false,
    this.showSidebar = true,
    this.onTab,
  });
  final AdminApi api;

  /// Its own sidebar on big screens. Off inside the app frame (AdminShell), which has the sidebar for every page.
  final bool showSidebar;

  /// Told when the tab changes (0 overview, 1 all modules), so the frame's sidebar can show it.
  final ValueChanged<int>? onTab;

  /// The app's other pages (Orders, Analytics…), for the search. Their callbacks run after this screen closes.
  final AdminNav? appNav;

  /// Opens this module's list straight away (from the side menu or the search).
  final String? initialModule;
  final String? initialStatus;
  final bool startAdding;

  /// Starts on the "All modules" tab instead of the overview.
  final bool showAllModules;

  /// The route name the search uses to come back here.
  static const routeName = 'admin-modules';

  @override
  State<ModulesHomeScreen> createState() => ModulesHomeScreenState();
}

class ModulesHomeScreenState extends State<ModulesHomeScreen> {
  ModuleRepository? _repo;
  String? _error;
  late int _tab = widget.showAllModules ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  Future<void> _load({bool first = false}) async {
    try {
      final repo = await ModuleRepository.open(widget.api);
      if (!mounted) return;
      setState(() => (_repo = repo, _error = null));
      if (first && widget.initialModule != null) _open(widget.initialModule!, status: widget.initialStatus, create: widget.startAdding);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.signedOut) return signOut(context, message: 'Your session ended. Please sign in again.');
      setState(() => _error = e is ApiException ? e.message : 'Couldn’t load the admin modules.');
    }
  }

  /// Shows the overview (0) or all modules (1).
  void setTab(int tab) {
    setState(() => _tab = tab);
    widget.onTab?.call(tab);
  }

  /// Opens a module's list (filtered to [status], or straight into its "add" form).
  void open(String key, {String? status, bool create = false}) => _open(key, status: status, create: create);

  void _open(String key, {String? status, ListPreset? preset, bool create = false}) {
    final repo = _repo;
    if (repo == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: RouteSettings(name: 'module:$key'),
            builder: (_) => ModuleListScreen(repo: repo, module: moduleByKey(key), initialStatus: status, preset: preset, startAdding: create),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  /// Leaves the admin modules, then runs [go] (another page of the app).
  VoidCallback? _away(VoidCallback? go) => go == null
      ? null
      : () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          go();
        };

  AdminNav get _nav => AdminNav(
    orders: _away(widget.appNav?.orders),
    analytics: _away(widget.appNav?.analytics),
    refunds: _away(widget.appNav?.refunds),
    settings: _away(widget.appNav?.settings),
    overview: () {
      Navigator.of(context).popUntil((route) => route.settings.name == ModulesHomeScreen.routeName || route.isFirst);
      setTab(0);
    },
    allModules: () {
      Navigator.of(context).popUntil((route) => route.settings.name == ModulesHomeScreen.routeName || route.isFirst);
      setTab(1);
    },
    module: (key, {status, create = false}) => _open(key, status: status, create: create),
    item: widget.appNav?.item,
  );

  void _reload() {
    setState(() => _repo = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    // Big screens: a light sidebar and a header bar, like a modern admin. Phones: a top bar with the side drawer.
    final shell = MediaQuery.sizeOf(context).width >= 1100;
    final title = _tab == 0 ? menuTitle(context, 'Overview', page: AppPage.overview) : 'All modules';
    final content = repo == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
          )
        : _tab == 0
        ? AdminOverview(
            repo: repo,
            header: const PageTreeSlot(bottom: 4),
            onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset),
            onAdd: (key) => _open(key, create: true),
            onOpenOrders: _nav.orders,
            onNavItem: widget.appNav?.item,
          )
        : _allModules(repo);
    return Scaffold(
      backgroundColor: const TColor(0xFFF4F7F6),
      drawer: shell ? null : AdminDrawer(nav: _nav, server: widget.api.base, onSignOut: widget.api.isDemo ? null : () => signOut(context)),
      appBar: shell
          ? null
          : AppBar(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              actions: [
                AdminSearchBar(nav: _nav, compact: true),
                if (repo != null)
                  _Bell(
                    repo: repo,
                    onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset),
                  ),
                IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
              ],
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shell && widget.showSidebar)
              AdminSidebar(nav: _nav, activeItemId: _tab == 0 ? 'founder-overview' : null, onSignOut: widget.api.isDemo ? null : () => signOut(context)),
            Expanded(
              child: Column(
                children: [
                  if (shell)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19), letterSpacing: -.5),
                          ),
                          const SizedBox(width: 24),
                          const Spacer(),
                          // Inside the app frame the global search is in its top bar; on its own, here.
                          if (widget.showSidebar)
                            Flexible(
                              flex: 3,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 380),
                                child: AdminSearchBar(nav: _nav, hint: 'Search modules, features, pages'),
                              ),
                            ),
                          const SizedBox(width: 12),
                          // In the app frame: search (Ctrl / ⌘ + K), like every page's top bar.
                          if (!widget.showSidebar && AppLayout.instance.search)
                            IconButton(tooltip: 'Search (Ctrl / ⌘ + K)', icon: const Icon(Icons.search), onPressed: () => showCommandPalette(context, _nav)),
                          if (repo != null)
                            _Bell(
                              repo: repo,
                              onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset),
                            ),
                          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
                          const SizedBox(width: 10),
                          _Profile(server: widget.api.base),
                        ],
                      ),
                    ),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allModules(ModuleRepository repo) => LayoutBuilder(
    builder: (context, box) {
      final across = box.maxWidth >= 1200
          ? 4
          : box.maxWidth >= 860
          ? 3
          : box.maxWidth >= 560
          ? 2
          : 1;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const PageTreeSlot(bottom: 4),
          for (final group in moduleGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
              child: Text(
                group.toUpperCase(),
                style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.6),
              ),
            ),
            EqualRows(
              columns: across,
              gap: 12,
              children: [for (final module in modules.where((m) => m.group == group)) _ModuleTile(module: module, count: repo.count(module.key), onTap: () => _open(module.key))],
            ),
          ],
        ],
      );
    },
  );
}

/// The bell: how many things need action now, and the list of them in a menu.
class _Bell extends StatelessWidget {
  const _Bell({required this.repo, required this.onOpen});
  final ModuleRepository repo;
  final OpenModule onOpen;

  @override
  Widget build(BuildContext context) {
    final items = attentionItems(repo);
    final urgent = items.where((a) => a.urgency == Urgency.high).fold<int>(0, (n, a) => n + a.count);
    return PopupMenuButton<Attention>(
      tooltip: 'Needs attention',
      position: PopupMenuPosition.under,
      onSelected: (a) => onOpen(a.module, status: a.status, preset: a.preset),
      itemBuilder: (_) => [
        if (items.isEmpty) const PopupMenuItem(enabled: false, child: Text('All clear: nothing waiting for you.')),
        for (final a in items)
          PopupMenuItem(
            value: a,
            child: Row(
              children: [
                Container(
                  width: 30,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(color: a.urgency == Urgency.high ? const TColor(0xFFFBE7E5) : const TColor(0xFFEFF7F4), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${a.count}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: a.urgency == Urgency.high ? const TColor(0xFFB3261E) : brand),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(a.text, style: const TextStyle(fontSize: 13.5))),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Badge(
          isLabelVisible: urgent > 0,
          label: Text('$urgent'),
          backgroundColor: const TColor(0xFFB3261E),
          child: const Icon(Icons.notifications_none_rounded, color: TColor(0xFF34443F)),
        ),
      ),
    );
  }
}

/// Who's signed in: the PIAX mark, "Admin", and the server this app talks to.
class _Profile extends StatelessWidget {
  const _Profile({required this.server});
  final String server;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: greens[5], borderRadius: BorderRadius.circular(12)),
        child: Image.asset('assets/brand/icon.png', errorBuilder: (_, _, _) => const Icon(Icons.person_outline, color: brand)),
      ),
      const SizedBox(width: 10),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PIAX team',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: TColor(0xFF0C1C19)),
          ),
          Text('Admin · ${server.replaceFirst(RegExp(r'^https?://'), '')}', style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 11.5)),
        ],
      ),
    ],
  );
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.count, required this.onTap});
  final ModuleDef module;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: TColor(0xFFFFFFFF),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: module.sensitive ? const TColor(0xFFFDE7EA) : const TColor(0xFFD8EEE3), borderRadius: BorderRadius.circular(12)),
              child: Icon(module.icon, color: module.sensitive ? const TColor(0xFFA8243F) : brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    module.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: brand),
            ),
          ],
        ),
      ),
    ),
  );
}

// ================================================================ List

class ModuleListScreen extends StatefulWidget {
  const ModuleListScreen({super.key, required this.repo, required this.module, this.initialStatus, this.preset, this.startAdding = false});
  final ModuleRepository repo;
  final ModuleDef module;

  /// Opens already filtered to this status, or to [preset] (from the overview's "Needs attention").
  final String? initialStatus;
  final ListPreset? preset;

  /// Opens the "add" form straight away (from the search).
  final bool startAdding;

  @override
  State<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends State<ModuleListScreen> {
  /// The list's search, filters and sort (kept while the app is open); a status from the overview starts it filtered.
  late RecordQuery _q = widget.initialStatus != null && m.statusField != null
      ? const RecordQuery().withFilter(m.statusField!, ChoiceFilter({widget.initialStatus!}))
      : rememberedQuery('module:${m.key}');
  late ListPreset? _preset = widget.preset;
  String? _selectedRecordId;

  /// The side panel (wide screens) shows a form instead of details: 'edit' the selected record, or 'add' one.
  String? _panelForm;
  bool _split = false;

  /// The side panel fills the page (its full-screen button); reset whenever the panel closes.
  bool _panelExpanded = false;

  ModuleDef get m => withCustomFields(widget.module); // with the team's own fields (Edit fields)

  void _menusChanged() => setState(() {});

  @override
  void dispose() {
    OptionStore.instance.removeListener(_menusChanged);
    FieldStore.instance.removeListener(_menusChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    OptionStore.instance.addListener(_menusChanged); // dropdown menus edited in Settings or by "Other…"
    FieldStore.instance.addListener(_menusChanged); // fields added or changed in Edit fields
    if (widget.startAdding && m.canCreate) WidgetsBinding.instance.addPostFrameCallback((_) => _add());
  }

  /// Every field but pictures, by its kind: text, choices, numbers, dates, yes / no.
  List<FilterField> get _fields => [
    for (final f in m.fields)
      if (f.type != FieldType.image && f.type != FieldType.file && !f.hidden)
        switch (f.type) {
          FieldType.choice => FilterField(f.key, f.label, FilterKind.choice, options: OptionStore.instance.options('module:${m.key}.${f.key}', f.options)),
          FieldType.boolean => FilterField(f.key, f.label, FilterKind.boolean),
          FieldType.integer || FieldType.decimal => FilterField(f.key, f.label, FilterKind.number),
          FieldType.money => FilterField(f.key, f.label, FilterKind.number, money: true),
          FieldType.dateTime => FilterField(f.key, f.label, FilterKind.date),
          _ => FilterField(f.key, f.label, FilterKind.text),
        },
  ];

  /// A field of a record; "last modified" is when it was last changed here, else its own updated / edited date.
  static Object? _read(Map<String, dynamic> r, String key) =>
      key == modifiedKey ? r['_modifiedAt'] ?? r['updatedAt'] ?? r['lastEdited'] ?? r['lastActive'] ?? r['uploadedAt'] : r[key];

  void _setQuery(RecordQuery q) {
    rememberQuery('module:${m.key}', q);
    setState(() => _q = q);
  }

  List<Map<String, dynamic>> _filter(RecordQuery q) {
    final base = widget.repo.records(m.key).where((r) => _preset == null || _preset!.test(r)).toList();
    return applyQuery(base, q, _fields, _read);
  }

  List<Map<String, dynamic>> get _shown => _filter(_q);

  Future<void> _open(Map<String, dynamic> record, {required bool split}) async {
    if (split) {
      setState(() => _selectedRecordId = '${record['id']}');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModuleDetailScreen(repo: widget.repo, module: m, recordId: '${record['id']}'),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editRecord(Map<String, dynamic> record) async {
    if (!m.canEdit || m.sensitive) return;
    if (_split) {
      return setState(() {
        _selectedRecordId = '${record['id']}';
        _panelForm = 'edit';
      });
    }
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ModuleFormScreen(repo: widget.repo, module: m, record: record),
      ),
    );
    if (saved != null && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  }

  /// The panel form finished: back to the record's details (a new one opens), or to what was there before.
  void _panelDone(Map<String, dynamic>? saved, {bool added = false}) {
    setState(() {
      _panelForm = null;
      if (saved == null) {
        _selectedRecordId = null; // closed: the whole panel goes, details too
        _panelExpanded = false;
      } else if (added) {
        _selectedRecordId = '${saved['id']}';
      }
    });
    if (saved != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? '${m.singular} added.' : 'Saved.')));
  }

  Future<void> _add() async {
    if (_split) return setState(() => _panelForm = 'add');
    final made = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ModuleFormScreen(repo: widget.repo, module: m),
      ),
    );
    if (made != null && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${m.singular} added.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final all = widget.repo.records(m.key);
    return Scaffold(
      backgroundColor: const TColor(0xFFF2F6F5),
      appBar: AppBar(
        title: Text(
          menuTitle(context, m.title, module: m.key),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          ...globalSearchActions(context),
          if (!m.readOnly && !m.sensitive) ...[
            const SizedBox(width: 8),
            EditFieldsButton(
              onPressed: () => showFieldEditor(
                context,
                page: 'module:${m.key}',
                title: m.title,
                builtIn: [
                  for (final f in widget.module.fields)
                    BuiltinField(
                      key: f.key,
                      label: f.label,
                      kind: _kindLabel(f.type),
                      help: f.help,
                      required: f.required,
                      canToggleRequired: !f.readOnly && f.type != FieldType.boolean,
                      choicesKey: f.type == FieldType.choice ? 'module:${m.key}.${f.key}' : null,
                      defaultChoices: f.options,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = _split = constraints.maxWidth >= 1100;
          final list = ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 104), // room under the last card for the Add button
            children: [
              const PageTreeSlot(bottom: 4),
              const SizedBox(height: 14),
              _ModuleHeader(module: m, total: all.length), // adding is the floating button
              const SizedBox(height: 14),
              _ModuleDashboard(
                insight: analyse(m, all),
                records: all,
                status: switch (_q.filters[m.statusField]) {
                  ChoiceFilter(:final values) when values.length == 1 => values.single,
                  _ => null,
                },
                onStatus: (s) => _setQuery(_q.withFilter(m.statusField ?? '', s == null ? null : ChoiceFilter({s}))),
              ),
              const SizedBox(height: 22),
              Text('All ${m.title.toLowerCase()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              FilterBar(
                pageKey: 'module:${m.key}',
                fields: _fields,
                query: _q,
                onChanged: _setQuery,
                total: all.length,
                shown: shown.length,
                count: (draft) => _filter(draft).length,
                noun: m.title.toLowerCase(),
                quickField: m.statusField,
                quickCounts: {
                  for (final st in OptionStore.instance.options('module:${m.key}.${m.statusField}', m.statuses)) st: all.where((r) => '${r[m.statusField]}' == st).length,
                },
                extraChips: [
                  if (_preset != null)
                    InputChip(
                      avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: Text(_preset!.label),
                      onDeleted: () => setState(() => _preset = null),
                      deleteButtonTooltipMessage: 'Remove this filter',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(all.isEmpty ? 'No ${m.title.toLowerCase()} yet.' : 'Nothing matches these filters.', style: const TextStyle(color: TColor(0xFF5A6C68))),
                  ),
                )
              else
                // One card per row on phones, two on tablets, three on desktops; cards in a row share one height.
                LayoutBuilder(
                  builder: (context, box) => EqualRows(
                    columns: box.maxWidth >= 1100
                        ? 3
                        : box.maxWidth >= 680
                        ? 2
                        : 1,
                    gap: 12,
                    children: [
                      for (final r in shown)
                        m.key == 'members'
                            ? MemberCard(
                                member: r,
                                onTap: () => _open(r, split: split),
                                onEdit: m.canEdit && !m.sensitive ? () => _editRecord(r) : null,
                              )
                            : _RecordCard(
                                module: m,
                                record: r,
                                onTap: () => _open(r, split: split),
                                onEdit: m.canEdit && !m.sensitive ? () => _editRecord(r) : null,
                              ),
                    ],
                  ),
                ),
            ],
          );
          final withAdd = m.canCreate ? floatingAdd('Add ${m.singular.toLowerCase()}', _add, list) : list;
          if (!split) return withAdd;
          final selected = _selectedRecordId;
          final form = _panelForm;
          final record = selected == null ? null : widget.repo.records(m.key).where((r) => '${r['id']}' == selected).firstOrNull;
          final Widget? panel = form == 'add'
              ? ModuleFormScreen(key: const ValueKey('panel-add'), repo: widget.repo, module: m, onDone: (saved) => _panelDone(saved, added: true))
              : form == 'edit' && record != null
              ? ModuleFormScreen(key: ValueKey('panel-edit-$selected'), repo: widget.repo, module: m, record: record, onDone: (saved) => _panelDone(saved))
              : selected != null
              ? ModuleDetailScreen(
                  key: ValueKey(selected),
                  repo: widget.repo,
                  module: m,
                  recordId: selected,
                  embedded: true,
                  onClose: () => setState(() {
                    _selectedRecordId = null;
                    _panelExpanded = false;
                  }),
                  onEdit: m.canEdit && !m.sensitive ? () => setState(() => _panelForm = 'edit') : null,
                )
              : null;
          // Full screen: the panel takes the whole page (the list comes back with the same button or on close).
          if (panel != null && _panelExpanded) {
            return PanelScope(expanded: true, onToggle: () => setState(() => _panelExpanded = false), child: panel);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: withAdd),
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: panel == null ? 0 : (form == null ? 460 : 520),
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(
                  color: TColor(0xFFF2F6F5),
                  border: Border(left: BorderSide(color: TColor(0xFFE1E8E6))),
                ),
                child: panel == null ? const SizedBox.shrink() : PanelScope(expanded: false, onToggle: () => setState(() => _panelExpanded = true), child: panel),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.module, required this.record, required this.onTap, this.onEdit});
  final ModuleDef module;
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final title = module.field(module.titleField);
    final subtitle = [
      for (final key in module.subtitleFields)
        if (module.field(key) case final f? when record[key] != null && '${record[key]}'.isNotEmpty)
          '${f.type == FieldType.text || f.type == FieldType.longText || f.type == FieldType.choice ? '' : '${f.label}: '}${displayValue(f, record[key])}',
      // A product's running offer, and what the customer pays with it.
      if (module.key == 'products' && discountSummary(record) != null)
        '${discountSummary(record)}${priceNow(record) != null && priceNow(record) != (record['price'] as num?)?.round() ? ' → ${rupees(priceNow(record)!)}' : ' (not running now)'}',
    ].join(' · ');
    final status = module.statusField == null ? null : record[module.statusField];
    return Material(
      color: TColor(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (recordImage(module.key, record) case final image?) ...[AssetThumb(image, size: 52), const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title == null ? '${record['id']}' : displayValue(title, record[module.titleField]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (status != null) ...[const SizedBox(width: 10), Flexible(child: _StatusChip('$status'))],
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit ${module.singular.toLowerCase()}',
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: TColor(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of a module page: its picture or icon, name, what it holds, and the add button.
class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.module, required this.total});
  final ModuleDef module;
  final int total;

  @override
  Widget build(BuildContext context) {
    final m = module;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TColor(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const TColor(0xFFE6EEEB)),
      ),
      child: Row(
        children: [
          if (moduleImage(m.key) case final image?)
            AssetThumb(image, size: 54, radius: 14)
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: m.sensitive ? const TColor(0xFFFDE7EA) : const TColor(0xFFD8EEE3), borderRadius: BorderRadius.circular(14)),
              child: Icon(m.icon, size: 26, color: m.sensitive ? const TColor(0xFFA8243F) : brand),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.title,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19)),
                ),
                const SizedBox(height: 3),
                Text(m.description, style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 13.5, height: 1.35)),
                const SizedBox(height: 6),
                Text(
                  '${m.group} · $total ${total == 1 ? 'record' : 'records'}${m.readOnly ? ' · read-only' : ''}',
                  style: const TextStyle(color: TColor(0xFF8A9A96), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A number card on module and record pages: label, big value, a line of context. Status cards filter the list.
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, this.caption, this.color = brand, this.icon, this.selected = false, this.onTap});
  final String label, value;
  final String? caption;
  final Color color;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: 0.08) : const TColor(0xFFFFFFFF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: selected ? color : const TColor(0xFFE6EEEB), width: selected ? 1.6 : 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null)
                  Icon(icon, size: 16, color: color)
                else
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TColor(0xFF34443F), fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19)),
              ),
            ),
            if (caption != null && caption!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A module's dashboard above its list: number cards (all, each status, the key numbers, recent activity) and
/// charts (status, how fields split, activity per week). Tapping a status card filters the list to it.
class _ModuleDashboard extends StatelessWidget {
  const _ModuleDashboard({required this.insight, required this.status, required this.onStatus, this.records = const []});

  /// The records [insight] was worked out from: for the weekly chart's hover breakdown.
  final List<Map<String, dynamic>> records;
  final ModuleInsight insight;
  final String? status;
  final ValueChanged<String?> onStatus;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    if (i.total == 0) return const SizedBox.shrink();
    final m = i.module;
    final trend = i.dates
        .where((d) => d.weekly.where((n) => n > 0).length >= 2 && const {'renewsAt', 'predictedNext', 'expiresAt', 'endsAt', 'startsAt'}.contains(d.field.key) == false)
        .firstOrNull;
    final recent = i.dates.where((d) => d.past30 > 0 || d.next30 > 0).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= 1400
            ? 7
            : w >= 1100
            ? 5
            : w >= 760
            ? 4
            : w >= 480
            ? 3
            : 2;
        final chartCols = w >= 1400
            ? 4
            : w >= 1000
            ? 3
            : w >= 640
            ? 2
            : 1;
        final tiles = <Widget>[
          _KpiTile(
            label: 'All ${m.title.toLowerCase()}',
            value: '${i.total}',
            caption: status == null ? 'showing all' : 'tap to show all',
            icon: m.icon,
            selected: status == null && i.statuses.isNotEmpty,
            onTap: () => onStatus(null),
          ),
          for (final s in i.statuses.where((s) => s.count > 0).take(4))
            _KpiTile(
              label: s.label,
              value: '${s.count}',
              caption: '${(s.count * 100 / i.total).round()}% of all',
              color: s.color,
              selected: status == s.label,
              onTap: () => onStatus(s.label),
            ),
          for (final n in i.numbers.take(3))
            _KpiTile(
              label: n.headlineLabel,
              value: n.headline,
              caption: n.range.isEmpty ? null : 'from ${n.range}',
              icon: Icons.insights_outlined,
              color: const TColor(0xFF0F766E),
            ),
          if (recent != null)
            _KpiTile(
              label: recent.field.label,
              value: '${recent.past30 > 0 ? recent.past30 : recent.next30}',
              caption: recent.past30 > 0 ? 'in the last 30 days${recent.next30 > 0 ? ' · ${recent.next30} coming up' : ''}' : 'in the next 30 days',
              icon: Icons.event_note_outlined,
              color: const TColor(0xFF2D5F80),
            ),
        ];
        Widget panel(String title, Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TColor(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const TColor(0xFFE6EEEB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        );
        final charts = <Widget>[
          if (i.statuses.isNotEmpty) panel('By status', SplitBar(slices: i.statuses)),
          for (final b in i.breakdowns.take((chartCols - (i.statuses.isEmpty ? 0 : 1) - (trend == null ? 0 : 1)).clamp(chartCols == 1 ? 2 : 1, 3)))
            panel('By ${b.field.label.toLowerCase()}', b.slices.length <= 4 ? SplitBar(slices: b.slices) : BarList(slices: b.slices.take(5).toList())),
          if (trend != null)
            panel(
              '${trend.field.label}, per week',
              // From the first week with any, so a short history isn't a row of empty columns (at least 4 weeks).
              SizedBox(
                height: 120,
                child: () {
                  final from = math.min(8, trend.weekly.indexWhere((n) => n > 0));
                  final grouping = weeklyGrouping(m);
                  final groups = grouping == null ? null : weeklyGroups(records, trend.field.key, grouping.$2);
                  return AreaTrend(
                    bars: [
                      for (final (k, v) in trend.weekly.indexed)
                        if (k >= from) (k == 11 ? 'This wk' : '${11 - k}w ago', v),
                    ],
                    details: groups == null ? null : [for (var k = from; k < 12; k++) breakdownText(groups[k], title: grouping!.$1)],
                  );
                }(),
              ),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rows as wide as the page: never more columns than tiles or charts.
            EqualRows(columns: math.min(cols, tiles.length), gap: 12, children: tiles),
            if (charts.isNotEmpty) ...[const SizedBox(height: 14), EqualRows(columns: math.min(chartCols, charts.length), gap: 14, children: charts)],
          ],
        );
      },
    );
  }
}

/// "Above average (₹179) · 2nd highest of 5": where a record's number sits among the module's records.
String? compareHint(FieldDef f, Object? value, List<Map<String, dynamic>> records) {
  final v = value is num ? value : num.tryParse('${value ?? ''}');
  if (v == null) return null;
  final all = [
    for (final r in records)
      if (r[f.key] case final num n) n,
  ];
  if (all.length < 2) return null;
  final avg = all.reduce((a, b) => a + b) / all.length;
  final rank = all.where((n) => n > v).length + 1;
  final where = (v - avg).abs() < avg * 0.05
      ? 'About average'
      : v > avg
      ? 'Above average'
      : 'Below average';
  final place = rank == 1
      ? 'highest'
      : rank == all.length
      ? 'lowest'
      : '#$rank highest';
  return '$where (${formatNumber(f, avg)}) · $place of ${all.length}';
}

// ================================================================ Details

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({super.key, required this.repo, required this.module, required this.recordId, this.embedded = false, this.onClose, this.onEdit});
  final ModuleRepository repo;
  final ModuleDef module;
  final String recordId;
  final bool embedded;
  final VoidCallback? onClose;

  /// In a side panel: opens the edit form in the panel instead of a full page.
  final VoidCallback? onEdit;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  bool _busy = false;

  ModuleDef get m => withCustomFields(widget.module); // with the team's own fields (Edit fields)

  /// The number fields this record has a value for (price, stock, fee, rating…).
  List<FieldDef> _numbers(Map<String, dynamic> record) => [
    for (final f in m.fields)
      if (const {FieldType.integer, FieldType.decimal, FieldType.money}.contains(f.type) && record[f.key] is num) f,
  ].take(8).toList();

  Map<String, dynamic>? get _record => widget.repo.records(m.key).where((r) => '${r['id']}' == widget.recordId).firstOrNull;

  Future<void> _run(ActionDef action) async {
    if (action.danger) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${action.label}?'),
          content: Text('This sets the ${m.singular.toLowerCase()} to “${action.to}”.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep as is')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action.label),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.update(m.key, widget.recordId, {(action.field ?? m.statusField)!: action.to});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${m.singular}: ${action.to}.')));
    } catch (e) {
      if (mounted) await _handleError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final record = _record;
    if (record == null) return;
    if (widget.onEdit != null) return widget.onEdit!();
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ModuleFormScreen(repo: widget.repo, module: m, record: record),
      ),
    );
    if (saved != null && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete this ${m.singular.toLowerCase()}?'),
        content: const Text('It’s removed from the dummy data. This can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.delete(m.key, widget.recordId);
      if (mounted) {
        if (widget.embedded) {
          widget.onClose?.call();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _handleError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    if (record == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(m.singular),
          automaticallyImplyLeading: !widget.embedded,
          actions: [
            ?panelExpandButton(context),
            if (widget.embedded) IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close)),
            const SizedBox(width: 8),
          ],
        ),
        body: const Center(child: Text('This record is no longer there.')),
      );
    }
    final title = m.field(m.titleField);
    final status = m.statusField == null ? null : record[m.statusField];
    final actions = m.actions.where((a) => a.appliesTo(record, m.statusField)).toList();
    return Scaffold(
      backgroundColor: const TColor(0xFFF2F6F5),
      appBar: AppBar(
        title: Text(m.singular, style: const TextStyle(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: !widget.embedded,
        actions: [
          if (m.canEdit && !m.sensitive) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: _busy ? null : _edit),
          if (m.canDelete && !m.sensitive) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
          // In the side panel: close at the right end, like every panel.
          ?panelExpandButton(context),
          if (widget.embedded) IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close)),
          const SizedBox(width: 8),
        ],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            key: const Key('detail-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const PageTreeSlot(bottom: 4),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recordImage(m.key, record) case final image?) ...[
                      AssetThumb(image, size: 120, radius: 18, fit: m.key == 'products' || m.key == 'healthBots' ? BoxFit.contain : BoxFit.cover),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title == null ? '${record['id']}' : displayValue(title, record[m.titleField]),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25),
                          ),
                        ),
                        if (status != null) ...[const SizedBox(width: 12), _StatusChip('$status')],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('ID ${record['id']}', style: const TextStyle(color: TColor(0xFF94A3B8), fontSize: 12.5)),
                    if (m.sensitive) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Health data: anonymised and read-only.',
                        style: TextStyle(color: TColor(0xFFA8243F), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Change this ${m.singular.toLowerCase()} with one tap. Each button says what it does; the red ones ask before they change anything.',
                        style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in actions)
                            Tooltip(
                              message: 'Sets the status to “${a.to}”',
                              child: a.danger
                                  ? OutlinedButton.icon(
                                      onPressed: _busy ? null : () => _run(a),
                                      icon: Icon(a.icon, size: 18),
                                      label: Text(a.label),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const TColor(0xFFB3261E),
                                        side: const BorderSide(color: TColor(0xFFF0B8B3)),
                                      ),
                                    )
                                  : FilledButton.tonalIcon(onPressed: _busy ? null : () => _run(a), icon: Icon(a.icon, size: 18), label: Text(a.label)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (m.key == 'members') ...[
                const SizedBox(height: 14),
                MemberProfile(member: record),
              ] else if (_numbers(record).isNotEmpty) ...[
                const SizedBox(height: 14),
                // The record's numbers as cards, each saying where it stands among the others.
                LayoutBuilder(
                  builder: (context, box) => EqualRows(
                    columns: box.maxWidth >= 900
                        ? 4
                        : box.maxWidth >= 560
                        ? 3
                        : 2,
                    gap: 12,
                    children: [
                      for (final f in _numbers(record))
                        _KpiTile(
                          label: f.label,
                          value: displayValue(f, record[f.key]),
                          caption: compareHint(f, record[f.key], widget.repo.records(m.key)),
                          icon: Icons.insights_outlined,
                          color: const TColor(0xFF0F766E),
                        ),
                    ],
                  ),
                ),
              ],
              for (final section in m.sections)
                if (m.fields.any((f) => f.section == section && !f.hidden)) ...[
                  const SizedBox(height: 14),
                  _SectionCard(
                    title: m.sections.length > 1 ? section : null,
                    child: _withDiscount(
                      m.key == 'products' && section == 'Discount',
                      record,
                      fieldGrid(
                        [
                          for (final f in m.fields)
                            if (f.section == section && !f.hidden) f,
                        ],
                        (f) => _FieldView(module: m, field: f, record: record, repo: widget.repo),
                        gap: 18,
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One field on the details page: its name, the value (a status chip, a photo, chips for a list, a link), where a
/// number stands among the others, and what the field is for.
class _FieldView extends StatelessWidget {
  const _FieldView({required this.module, required this.field, required this.record, required this.repo});
  final ModuleDef module;
  final FieldDef field;
  final Map<String, dynamic> record;
  final ModuleRepository repo;

  @override
  Widget build(BuildContext context) {
    final f = field, value = record[f.key];
    final empty = value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty);
    final Widget shown;
    if (empty) {
      shown = const Text(
        'Not filled in yet',
        style: TextStyle(color: TColor(0xFF94A3B8), fontSize: 14, fontStyle: FontStyle.italic),
      );
    } else if (f.key == module.statusField) {
      shown = Align(alignment: Alignment.centerLeft, child: _StatusChip('$value'));
    } else if (f.type == FieldType.image) {
      shown = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imagePreview('$value', repo.api.base, size: 110),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText('$value', style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5)),
          ),
        ],
      );
    } else if (f.type == FieldType.file) {
      shown = AttachmentList(files: attachmentsOf(value));
    } else if (f.type == FieldType.list && value is List) {
      shown = Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in value)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const TColor(0xFFEFF7F4), borderRadius: BorderRadius.circular(999)),
              child: Text(
                '$v',
                style: const TextStyle(fontSize: 13, color: TColor(0xFF26413B), fontWeight: FontWeight.w600),
              ),
            ),
        ],
      );
    } else if (f.type == FieldType.url) {
      shown = InkWell(
        onTap: () => launchUrl(Uri.parse('$value'), mode: LaunchMode.externalApplication),
        child: Text(
          '$value',
          style: const TextStyle(color: brand, fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
        ),
      );
    } else {
      shown = SelectableText(displayValue(f, value), style: TextStyle(fontSize: 14.5, fontWeight: f.type == FieldType.longText ? FontWeight.w500 : FontWeight.w600, height: 1.45));
    }
    final hint = const {FieldType.integer, FieldType.decimal, FieldType.money}.contains(f.type) ? compareHint(f, value, repo.records(module.key)) : null;
    final max = f.maxLength;
    final long = max != null && value is String && value.length > max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.label,
          style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        shown,
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(hint, style: const TextStyle(color: TColor(0xFF0F766E), fontSize: 12.5)),
          ),
        if (long)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${value.length} characters: over the $max that show in full.', style: const TextStyle(color: TColor(0xFF8A5A00), fontSize: 12.5)),
          ),
        if (f.help != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(f.help!, style: const TextStyle(color: TColor(0xFF8A9A96), fontSize: 12, height: 1.35)),
          ),
      ],
    );
  }
}

// ================================================================ Form (add / edit)

/// Lays out [fields] one per row on narrow screens and two per row on wide ones; long text, lists, photos and
/// switches always take the full width.
Widget fieldGrid(List<FieldDef> fields, Widget Function(FieldDef) build, {double gap = 14}) => LayoutBuilder(
  builder: (context, box) {
    final two = box.maxWidth >= 640;
    final rows = <Widget>[];
    FieldDef? waiting;
    void flush() {
      if (waiting != null) {
        rows.add(
          two
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: build(waiting!)),
                    SizedBox(width: gap),
                    const Expanded(child: SizedBox()),
                  ],
                )
              : build(waiting!),
        );
      }
      waiting = null;
    }

    for (final f in fields) {
      if (!two || f.wide) {
        flush();
        rows.add(build(f));
      } else if (waiting == null) {
        waiting = f;
      } else {
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: build(waiting!)),
              SizedBox(width: gap),
              Expanded(child: build(f)),
            ],
          ),
        );
        waiting = null;
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: r,
          ),
      ],
    );
  },
);

/// A white card with a section title ("Basics", "Pricing & tax"…).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: TColor(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const TColor(0xFFE6EEEB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColor(0xFF0C1C19)),
          ),
          const SizedBox(height: 14),
        ],
        child,
      ],
    ),
  );
}

/// A picture from a link (https://…), a path on the website (/images/…, loaded from the server the app talks to) or
/// one of the app's own pictures (assets/…). A placeholder when it can't be loaded.
Widget imagePreview(String value, String server, {double size = 96}) {
  final v = value.trim();
  Widget fallback(BuildContext _, Object _, StackTrace? _) => Container(
    color: const TColor(0xFFEFF5F3),
    alignment: Alignment.center,
    child: const Icon(Icons.image_outlined, color: TColor(0xFF8DA19C)),
  );
  final Widget image = v.startsWith('assets/')
      ? Image.asset(v, fit: BoxFit.contain, errorBuilder: fallback)
      : Image.network(v.startsWith('/') ? '${server.replaceFirst(RegExp(r'/+$'), '')}$v' : v, fit: BoxFit.contain, errorBuilder: fallback);
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Container(width: size, height: size, color: const TColor(0xFFF4F8F6), child: image),
  );
}

class ModuleFormScreen extends StatefulWidget {
  const ModuleFormScreen({super.key, required this.repo, required this.module, this.record, this.onDone});
  final ModuleRepository repo;
  final ModuleDef module;

  /// In a side panel: called with the saved record (null when closed without saving), instead of leaving a page.
  final void Function(Map<String, dynamic>? saved)? onDone;

  /// The record being edited; null to add a new one.
  final Map<String, dynamic>? record;

  @override
  State<ModuleFormScreen> createState() => _ModuleFormScreenState();
}

class _ModuleFormScreenState extends State<ModuleFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text;
  late final Map<String, dynamic> _values;
  bool _busy = false;

  ModuleDef get m => withCustomFields(widget.module); // with the team's own fields (Edit fields)
  bool get _editing => widget.record != null;
  Iterable<FieldDef> get _editable => m.fields.where((f) => !f.readOnly && !f.hidden);

  static const _picked = {FieldType.boolean, FieldType.choice, FieldType.dateTime, FieldType.list, FieldType.file};

  @override
  void initState() {
    super.initState();
    final record = widget.record ?? {};
    _values = {
      for (final f in _editable)
        f.key: switch (f.type) {
          FieldType.list => [for (final v in (record[f.key] as List?) ?? const []) '$v'],
          FieldType.file => attachmentsOf(record[f.key]),
          _ =>
            record[f.key] ??
                switch (f.type) {
                  FieldType.boolean => false,
                  FieldType.choice => f.options.firstOrNull,
                  FieldType.dateTime => DateTime.now().toUtc().toIso8601String(),
                  _ => null,
                },
        },
    };
    _text = {for (final f in _editable.where((f) => !_picked.contains(f.type))) f.key: TextEditingController(text: record[f.key] == null ? '' : '${record[f.key]}')};
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? _parsed(FieldDef f) {
    final raw = _text[f.key]?.text.trim() ?? '';
    return switch (f.type) {
      FieldType.integer || FieldType.money => raw.isEmpty ? null : int.tryParse(raw.replaceAll(RegExp(r'[^\d-]'), '')),
      FieldType.decimal => raw.isEmpty ? null : double.tryParse(raw),
      _ => raw,
    };
  }

  /// The form as it stands, as a record (for saving, and for the discount preview as it's typed).
  Map<String, dynamic> get _draft => {for (final f in _editable) f.key: _text.containsKey(f.key) ? _parsed(f) : _values[f.key]};

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Some boxes need a look. They’re marked in red.')));
      return;
    }
    final record = _draft;
    // A product's discount must make sense with its price (discounts.dart).
    final problem = m.key == 'products' ? discountProblem({...?widget.record, ...record}) : null;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = _editing ? await widget.repo.update(m.key, '${widget.record!['id']}', record) : await widget.repo.create(m.key, record);
      if (!mounted) return;
      if (widget.onDone != null) {
        widget.onDone!(saved);
      } else {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _handleError(context, e);
      }
    }
  }

  Future<void> _pickDate(FieldDef f) async {
    final current = DateTime.tryParse('${_values[f.key]}')?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    final at = DateTime(date.year, date.month, date.day, time?.hour ?? current.hour, time?.minute ?? current.minute);
    setState(() => _values[f.key] = at.toUtc().toIso8601String());
  }

  InputDecoration _decoration(FieldDef f) => InputDecoration(
    labelText: f.required ? '${f.label} *' : f.label,
    hintText: f.hint,
    helperText: f.help,
    helperMaxLines: 5,
    helperStyle: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5, height: 1.35),
    errorMaxLines: 3,
    filled: true,
    fillColor: TColor(0xFFFFFFFF),
    alignLabelWithHint: f.type == FieldType.longText,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  String? _check(FieldDef f, String value) {
    if (f.required && value.isEmpty) return 'Enter the ${f.label.toLowerCase()}.';
    if (value.isEmpty) return null;
    final numeric = f.type == FieldType.integer || f.type == FieldType.money || f.type == FieldType.decimal;
    if (numeric && _parsed(f) == null) return 'Enter a number.';
    if (f.type == FieldType.email && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(value)) return 'Enter a valid email.';
    if (f.type == FieldType.url && !RegExp(r'^https?://\S+$').hasMatch(value)) return 'Enter a full link starting with https://';
    if (f.type == FieldType.image && !RegExp(r'^(https?://\S+|/\S+|assets/\S+)$').hasMatch(value)) return 'Enter a link (https://…) or a website path starting with /';
    if (f.pattern != null && !RegExp(f.pattern!).hasMatch(value)) return f.patternMessage ?? 'Check the format.';
    return null;
  }

  Widget _field(FieldDef f) {
    final decoration = _decoration(f);
    switch (f.type) {
      case FieldType.boolean:
        return Material(
          color: const TColor(0xFFF7FAF9),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: SwitchListTile(
              value: _values[f.key] == true,
              onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v),
              title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: f.help == null ? null : Text(f.help!, style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        );
      case FieldType.choice:
        // The menu with the team's own values, and "Other…" to add one.
        return ChoiceDropdown(
          optionKey: 'module:${m.key}.${f.key}',
          where: m.title,
          defaults: f.options,
          value: _values[f.key] as String?,
          label: f.label,
          decoration: decoration,
          enabled: !_busy,
          required: f.required,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.dateTime:
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _pickDate(f),
          child: InputDecorator(
            decoration: decoration.copyWith(suffixIcon: const Icon(Icons.event)),
            child: Text(displayValue(f, _values[f.key])),
          ),
        );
      case FieldType.file:
        return AttachmentField(
          label: f.label,
          initial: attachmentsOf(_values[f.key]),
          types: f.fileTypes.isEmpty ? docTypes : f.fileTypes,
          multiple: f.multiple,
          mandatory: f.required,
          help: f.help,
          onChanged: (files) => _values[f.key] = files,
        );
      case FieldType.list:
        return _ListField(field: f, decoration: decoration, initial: _values[f.key] as List<String>, enabled: !_busy, onChanged: (items) => _values[f.key] = items);
      default:
        final numeric = f.type == FieldType.integer || f.type == FieldType.money || f.type == FieldType.decimal;
        final input = TextFormField(
          controller: _text[f.key],
          enabled: !_busy,
          minLines: f.type == FieldType.longText ? 3 : 1,
          maxLines: f.type == FieldType.longText ? 8 : 1,
          maxLength: f.maxLength,
          // Pictures preview as their link is typed; a product's prices redraw its discount preview.
          onChanged: f.type == FieldType.image || (m.key == 'products' && const {'price', 'mrp', 'discountValue', 'discountMinBoxes'}.contains(f.key))
              ? (_) => setState(() {})
              : null,
          style: const TextStyle(fontSize: 16),
          keyboardType: switch (f.type) {
            FieldType.email => TextInputType.emailAddress,
            FieldType.phone => TextInputType.phone,
            FieldType.url || FieldType.image => TextInputType.url,
            FieldType.decimal => const TextInputType.numberWithOptions(decimal: true),
            FieldType.longText => TextInputType.multiline,
            _ when numeric => TextInputType.number,
            _ => TextInputType.text,
          },
          decoration: decoration.copyWith(prefixText: f.type == FieldType.money ? '₹ ' : null),
          validator: (v) => _check(f, (v ?? '').trim()),
        );
        if (f.type != FieldType.image) return input;
        final link = _text[f.key]!.text.trim();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input),
            const SizedBox(width: 14),
            link.isEmpty
                ? Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: const TColor(0xFFF4F8F6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const TColor(0xFFDCE6E3)),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined, color: TColor(0xFF8DA19C)),
                  )
                : imagePreview(link, widget.repo.api.base),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _editing ? 'Edit ${m.singular.toLowerCase()}' : 'Add ${m.singular.toLowerCase()}';
    final sections = [
      for (final s in m.sections)
        if (_editable.any((f) => f.section == s)) s,
    ];
    return Scaffold(
      backgroundColor: const TColor(0xFFF2F6F5),
      appBar: AppBar(
        automaticallyImplyLeading: widget.onDone == null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: widget.onDone == null ? 12 : 4),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(_editing ? 'Save' : 'Add'),
            ),
          ),
          // In the side panel: close (without saving) at the right end; it closes the whole panel.
          ?panelExpandButton(context),
          if (widget.onDone != null) ...[IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => widget.onDone!(null)), const SizedBox(width: 8)],
        ],
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            // Every field stays built (not a lazy list), so "Add" checks the boxes scrolled out of view too.
            child: SingleChildScrollView(
              key: const Key('form-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (m.formIntro != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const TColor(0xFFEFF7F4), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: brand, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(m.formIntro!, style: const TextStyle(color: TColor(0xFF26413B), fontSize: 13.5, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 10),
                      child: Text('Boxes marked * are needed. Each box says what it’s for underneath.', style: TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5)),
                    ),
                  ],
                  for (final s in sections) ...[
                    _SectionCard(
                      title: sections.length > 1 || s != 'Details' ? s : null,
                      child: _withDiscount(
                        m.key == 'products' && s == 'Discount',
                        _draft,
                        fieldGrid([
                          for (final f in _editable)
                            if (f.section == s) f,
                        ], _field),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 52,
                      width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 260,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFFFFFFFF)))
                            : Text(_editing ? 'Save changes' : 'Add ${m.singular.toLowerCase()}'),
                      ),
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

/// A list of short items (features, tags, languages, photo links): chips you can remove, and a box to add more.
/// Pasting several lines adds one item per line.
class _ListField extends StatefulWidget {
  const _ListField({required this.field, required this.decoration, required this.initial, required this.enabled, required this.onChanged});
  final FieldDef field;
  final InputDecoration decoration;
  final List<String> initial;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ListField> createState() => _ListFieldState();
}

class _ListFieldState extends State<_ListField> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<List<String>>(
    initialValue: widget.initial,
    validator: (items) => widget.field.required && (items ?? const []).isEmpty ? 'Add at least one.' : null,
    builder: (state) {
      final items = state.value ?? const <String>[];
      void add() {
        final added = _input.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty && !items.contains(s)).toList();
        if (added.isEmpty) return;
        final next = [...items, ...added];
        state.didChange(next);
        widget.onChanged(next);
        _input.clear();
      }

      return InputDecorator(
        decoration: widget.decoration.copyWith(errorText: state.errorText, contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (items.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in items)
                    InputChip(
                      label: Text(item, overflow: TextOverflow.ellipsis),
                      onDeleted: widget.enabled
                          ? () {
                              final next = [...items]..remove(item);
                              state.didChange(next);
                              widget.onChanged(next);
                            }
                          : null,
                      deleteButtonTooltipMessage: 'Remove',
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: widget.enabled,
                    style: const TextStyle(fontSize: 16),
                    minLines: 1,
                    maxLines: 3,
                    onSubmitted: (_) => add(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Type one, then press Add',
                      filled: true,
                      fillColor: const TColor(0xFFF7FAF9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: widget.enabled ? add : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// A built-in field's kind, as the Edit fields panel lists it.
String _kindLabel(FieldType t) => switch (t) {
  FieldType.text || FieldType.email || FieldType.phone || FieldType.url => 'Short text',
  FieldType.longText => 'Long text',
  FieldType.integer || FieldType.decimal => 'Number',
  FieldType.money => 'Amount (₹)',
  FieldType.boolean => 'Yes / no',
  FieldType.dateTime => 'Date',
  FieldType.choice => 'Dropdown',
  FieldType.image => 'Image link',
  FieldType.list => 'List',
  FieldType.file => 'File upload',
};

/// A form or record section with the product's discount preview under its fields (Products › Discount).
Widget _withDiscount(bool show, Map<String, dynamic> product, Widget fields) => !show
    ? fields
    : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fields,
          const SizedBox(height: 14),
          DiscountPreview(product: product),
        ],
      );
