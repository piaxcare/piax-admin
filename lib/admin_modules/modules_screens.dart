import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../screens/login_screen.dart' show signOut;
import 'admin_drawer.dart';
import 'admin_shell.dart' show AdminSidebar;
import 'admin_search.dart';
import 'charts.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart' show greens;
import 'insights.dart';
import 'member_widgets.dart';
import 'overview_screen.dart';
import 'repository.dart';
import 'schema.dart';

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
      child: Text(status, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// "Dummy data" notice under every Admin modules title, so nobody takes these records for real ones.
class _SourceBanner extends StatelessWidget {
  const _SourceBanner(this.repo);
  final ModuleRepository repo;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF3D9A6))),
    child: Row(
      children: [
        Icon(repo.source == ModuleSource.localServer ? Icons.dns_outlined : Icons.science_outlined, size: 18, color: const Color(0xFF7F5300)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            repo.source == ModuleSource.localServer
                ? 'Mock-up on the local website’s dummy data. Changes are saved on that website while you test.'
                : 'Mock-up on dummy data bundled in the app. Nothing here is real, and changes reset when the app closes.',
            style: const TextStyle(color: Color(0xFF7F5300), fontSize: 13),
          ),
        ),
      ],
    ),
  );
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
        .push(MaterialPageRoute(settings: RouteSettings(name: 'module:$key'), builder: (_) => ModuleListScreen(repo: repo, module: moduleByKey(key), initialStatus: status, preset: preset, startAdding: create)))
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
    final title = _tab == 0 ? 'Overview' : 'All modules';
    final content = repo == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))]),
          )
        : _tab == 0
        ? AdminOverview(
            repo: repo,
            header: _SourceBanner(repo),
            onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset),
            onAdd: (key) => _open(key, create: true),
            onOpenOrders: _nav.orders,
          )
        : _allModules(repo);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      drawer: shell ? null : AdminDrawer(nav: _nav, server: widget.api.base, onSignOut: () => signOut(context)),
      appBar: shell
          ? null
          : AppBar(
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: [
                AdminSearchBar(nav: _nav, compact: true),
                if (repo != null) _Bell(repo: repo, onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset)),
                IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
              ],
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shell && widget.showSidebar) AdminSidebar(nav: _nav, active: _tab == 0 ? 'overview' : 'modules', onSignOut: () => signOut(context)),
            Expanded(
              child: Column(
                children: [
                  if (shell)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                      child: Row(
                        children: [
                          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19), letterSpacing: -.5)),
                          const SizedBox(width: 24),
                          const Spacer(),
                          Flexible(flex: 3, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: AdminSearchBar(nav: _nav, hint: 'Search modules, features, pages'))),
                          const SizedBox(width: 12),
                          if (repo != null) _Bell(repo: repo, onOpen: (key, {status, preset}) => _open(key, status: status, preset: preset)),
                          IconButton(tooltip: 'Reload', icon: const Icon(Icons.refresh), onPressed: _reload),
                          const SizedBox(width: 10),
                          _Profile(server: widget.api.base),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: SizedBox(width: double.infinity, child: _tabs()),
                    ),
                  if (shell)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
                      child: Align(alignment: Alignment.centerLeft, child: _tabs()),
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

  Widget _tabs() => SegmentedButton<int>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: 0, icon: Icon(Icons.space_dashboard_outlined, size: 18), label: Text('Overview')),
      ButtonSegment(value: 1, icon: Icon(Icons.apps_outlined, size: 18), label: Text('All modules')),
    ],
    selected: {_tab},
    onSelectionChanged: (s) => setTab(s.first),
  );

  Widget _allModules(ModuleRepository repo) => LayoutBuilder(
    builder: (context, box) {
      final across = box.maxWidth >= 1200 ? 4 : box.maxWidth >= 860 ? 3 : box.maxWidth >= 560 ? 2 : 1;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SourceBanner(repo),
          for (final group in moduleGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
              child: Text(group.toUpperCase(), style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
            ),
            EqualRows(
              columns: across,
              gap: 12,
              children: [
                for (final module in modules.where((m) => m.group == group))
                  _ModuleTile(module: module, count: repo.count(module.key), onTap: () => _open(module.key)),
              ],
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
            child: Row(children: [
              Container(
                width: 30,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(color: a.urgency == Urgency.high ? const Color(0xFFFBE7E5) : const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(8)),
                child: Text('${a.count}', style: TextStyle(fontWeight: FontWeight.w800, color: a.urgency == Urgency.high ? const Color(0xFFB3261E) : brand)),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(a.text, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Badge(
          isLabelVisible: urgent > 0,
          label: Text('$urgent'),
          backgroundColor: const Color(0xFFB3261E),
          child: const Icon(Icons.notifications_none_rounded, color: Color(0xFF34443F)),
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
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: greens[5], borderRadius: BorderRadius.circular(12)),
      child: Image.asset('assets/brand/icon.png', errorBuilder: (_, _, _) => const Icon(Icons.person_outline, color: brand)),
    ),
    const SizedBox(width: 10),
    Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('PIAX team', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0C1C19))),
      Text('Admin · ${server.replaceFirst(RegExp(r'^https?://'), '')}', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 11.5)),
    ]),
  ]);
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.count, required this.onTap});
  final ModuleDef module;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
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
              decoration: BoxDecoration(color: module.sensitive ? const Color(0xFFFDE7EA) : const Color(0xFFD8EEE3), borderRadius: BorderRadius.circular(12)),
              child: Icon(module.icon, color: module.sensitive ? const Color(0xFFA8243F) : brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(module.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(module.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: brand)),
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
  final _search = TextEditingController();
  late String? _status = widget.initialStatus;
  late ListPreset? _preset = widget.preset;

  /// Sorted by this field (null: as stored), biggest / newest first unless [_ascending].
  String? _sortBy;
  bool _ascending = false;

  ModuleDef get m => widget.module;

  @override
  void initState() {
    super.initState();
    if (widget.startAdding && m.canCreate) WidgetsBinding.instance.addPostFrameCallback((_) => _add());
  }

  /// Fields worth sorting by: numbers, dates and the title.
  List<FieldDef> get _sortable => [
    for (final f in m.fields)
      if (f.key == m.titleField || const {FieldType.integer, FieldType.decimal, FieldType.money, FieldType.dateTime}.contains(f.type)) f,
  ];

  int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final f = m.field(_sortBy!)!;
    final x = a[f.key], y = b[f.key];
    final int result;
    if (f.type == FieldType.dateTime) {
      result = (DateTime.tryParse('${x ?? ''}') ?? DateTime(0)).compareTo(DateTime.tryParse('${y ?? ''}') ?? DateTime(0));
    } else if (x is num && y is num) {
      result = x.compareTo(y);
    } else {
      result = '${x ?? ''}'.toLowerCase().compareTo('${y ?? ''}'.toLowerCase());
    }
    return _ascending ? result : -result;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _shown {
    final q = _search.text.trim().toLowerCase();
    final list = widget.repo.records(m.key).where((r) {
      if (_status != null && '${r[m.statusField]}' != _status) return false;
      if (_preset != null && !_preset!.test(r)) return false;
      if (q.isEmpty) return true;
      return r.values.any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
    if (_sortBy != null) list.sort(_compare);
    return list;
  }

  Future<void> _open(Map<String, dynamic> record) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModuleDetailScreen(repo: widget.repo, module: m, recordId: '${record['id']}')));
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final made = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ModuleFormScreen(repo: widget.repo, module: m)));
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
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: m.canCreate
          ? FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text('Add ${m.singular.toLowerCase()}'))
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _SourceBanner(widget.repo),
          const SizedBox(height: 14),
          _ModuleHeader(module: m, total: all.length, onAdd: m.canCreate ? _add : null),
          const SizedBox(height: 14),
          _ModuleDashboard(insight: analyse(m, all), status: _status, onStatus: (s) => setState(() => _status = s)),
          const SizedBox(height: 22),
          Text('All ${m.title.toLowerCase()}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Search ${m.title.toLowerCase()}',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
            ),
          ),
          if (m.statuses.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(label: Text('All ${all.length}'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                for (final s in m.statuses)
                  ChoiceChip(
                    label: Text('$s ${all.where((r) => '${r[m.statusField]}' == s).length}'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = _status == s ? null : s),
                  ),
              ],
            ),
          ],
          if (_preset != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                label: Text(_preset!.label),
                onDeleted: () => setState(() => _preset = null),
                deleteButtonTooltipMessage: 'Remove this filter',
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  shown.length == all.length ? 'Showing all ${all.length}' : 'Showing ${shown.length} of ${all.length}',
                  style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Sort',
                onSelected: (key) => setState(() {
                  if (key == '') {
                    _sortBy = null;
                  } else if (_sortBy == key) {
                    _ascending = !_ascending;
                  } else {
                    _sortBy = key;
                    _ascending = m.field(key)?.type == FieldType.text || m.field(key)?.type == FieldType.longText;
                  }
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '', child: Text('Default order')),
                  for (final f in _sortable)
                    PopupMenuItem(
                      value: f.key,
                      child: Row(children: [
                        Expanded(child: Text(f.label)),
                        if (_sortBy == f.key) Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: brand),
                      ]),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort, size: 18, color: brand),
                    const SizedBox(width: 6),
                    Text(
                      _sortBy == null ? 'Sort' : '${m.field(_sortBy!)!.label} ${_ascending ? '↑' : '↓'}',
                      style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text(all.isEmpty ? 'No ${m.title.toLowerCase()} yet.' : 'Nothing matches your search.', style: const TextStyle(color: Color(0xFF5A6C68)))),
            )
          else
            // One card per row on phones, two on tablets, three on desktops; cards in a row share one height.
            LayoutBuilder(
              builder: (context, box) => EqualRows(
                columns: box.maxWidth >= 1100 ? 3 : box.maxWidth >= 680 ? 2 : 1,
                gap: 12,
                children: [
                  for (final r in shown)
                    m.key == 'members' ? MemberCard(member: r, onTap: () => _open(r)) : _RecordCard(module: m, record: r, onTap: () => _open(r)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.module, required this.record, required this.onTap});
  final ModuleDef module;
  final Map<String, dynamic> record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = module.field(module.titleField);
    final subtitle = [
      for (final key in module.subtitleFields)
        if (module.field(key) case final f? when record[key] != null && '${record[key]}'.isNotEmpty) '${f.type == FieldType.text || f.type == FieldType.longText || f.type == FieldType.choice ? '' : '${f.label}: '}${displayValue(f, record[key])}',
    ].join(' · ');
    final status = module.statusField == null ? null : record[module.statusField];
    return Material(
        color: Colors.white,
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
                      Text(title == null ? '${record['id']}' : displayValue(title, record[module.titleField]),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                if (status != null) ...[const SizedBox(width: 10), _StatusChip('$status')],
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
    );
  }
}

/// The top of a module page: its picture or icon, name, what it holds, and the add button.
class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.module, required this.total, this.onAdd});
  final ModuleDef module;
  final int total;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final m = module;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6EEEB))),
      child: Row(
        children: [
          if (moduleImage(m.key) case final image?)
            AssetThumb(image, size: 54, radius: 14)
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: m.sensitive ? const Color(0xFFFDE7EA) : const Color(0xFFD8EEE3), borderRadius: BorderRadius.circular(14)),
              child: Icon(m.icon, size: 26, color: m.sensitive ? const Color(0xFFA8243F) : brand),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19))),
              const SizedBox(height: 3),
              Text(m.description, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13.5, height: 1.35)),
              const SizedBox(height: 6),
              Text('${m.group} · $total ${total == 1 ? 'record' : 'records'}${m.readOnly ? ' · read-only' : ''}', style: const TextStyle(color: Color(0xFF8A9A96), fontSize: 12)),
            ]),
          ),
          if (onAdd != null && wide) ...[
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text('Add ${m.singular.toLowerCase()}')),
          ],
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
    color: selected ? color.withValues(alpha: 0.08) : Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: selected ? color : const Color(0xFFE6EEEB), width: selected ? 1.6 : 1)),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null)
                Icon(icon, size: 16, color: color)
              else
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF34443F), fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19)))),
            if (caption != null && caption!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 11.5)),
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
  const _ModuleDashboard({required this.insight, required this.status, required this.onStatus});
  final ModuleInsight insight;
  final String? status;
  final ValueChanged<String?> onStatus;

  @override
  Widget build(BuildContext context) {
    final i = insight;
    if (i.total == 0) return const SizedBox.shrink();
    final m = i.module;
    final trend = i.dates.where((d) => d.weekly.any((n) => n > 0) && const {'renewsAt', 'predictedNext', 'expiresAt', 'endsAt', 'startsAt'}.contains(d.field.key) == false).firstOrNull;
    final recent = i.dates.where((d) => d.past30 > 0 || d.next30 > 0).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cols = w >= 1100 ? 5 : w >= 760 ? 4 : w >= 480 ? 3 : 2;
        final chartCols = w >= 1100 ? 3 : w >= 640 ? 2 : 1;
        final chartWidth = (w - 14 * (chartCols - 1)) / chartCols;
        final beside = DonutChart.fitsBeside(chartWidth - 36, size: 132);
        final tiles = <Widget>[
          _KpiTile(label: 'All ${m.title.toLowerCase()}', value: '${i.total}', caption: status == null ? 'showing all' : 'tap to show all', icon: m.icon, selected: status == null && i.statuses.isNotEmpty, onTap: () => onStatus(null)),
          for (final s in i.statuses.where((s) => s.count > 0).take(4))
            _KpiTile(label: s.label, value: '${s.count}', caption: '${(s.count * 100 / i.total).round()}% of all', color: s.color, selected: status == s.label, onTap: () => onStatus(s.label)),
          for (final n in i.numbers.take(3)) _KpiTile(label: n.headlineLabel, value: n.headline, caption: n.range.isEmpty ? null : 'from ${n.range}', icon: Icons.insights_outlined, color: const Color(0xFF0F766E)),
          if (recent != null)
            _KpiTile(
              label: recent.field.label,
              value: '${recent.past30 > 0 ? recent.past30 : recent.next30}',
              caption: recent.past30 > 0 ? 'in the last 30 days${recent.next30 > 0 ? ' · ${recent.next30} coming up' : ''}' : 'in the next 30 days',
              icon: Icons.event_note_outlined,
              color: const Color(0xFF2D5F80),
            ),
        ];
        Widget panel(String title, Widget child) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE6EEEB))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 12),
            if (chartCols > 1) Expanded(child: Center(child: child)) else child,
          ]),
        );
        final charts = <Widget>[
          if (i.statuses.isNotEmpty) panel('By status', DonutChart(slices: i.statuses, centerLabel: m.title.toLowerCase(), size: 132, horizontal: beside)),
          for (final b in i.breakdowns.take(trend == null ? 3 : 2))
            panel(
              'By ${b.field.label.toLowerCase()}',
              b.slices.length <= 4 ? DonutChart(slices: b.slices, centerLabel: m.title.toLowerCase(), size: 132, horizontal: beside) : BarList(slices: b.slices.take(5).toList()),
            ),
          if (trend != null) panel('${trend.field.label}, per week', TrendChart(series: [(trend.field.label, brand, trend.weekly)], height: 150)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EqualRows(columns: cols, gap: 12, children: tiles),
            if (charts.isNotEmpty) ...[const SizedBox(height: 14), EqualRows(columns: chartCols, gap: 14, children: charts)],
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
  final all = [for (final r in records) if (r[f.key] case final num n) n];
  if (all.length < 2) return null;
  final avg = all.reduce((a, b) => a + b) / all.length;
  final rank = all.where((n) => n > v).length + 1;
  final where = (v - avg).abs() < avg * 0.05 ? 'About average' : v > avg ? 'Above average' : 'Below average';
  final place = rank == 1 ? 'highest' : rank == all.length ? 'lowest' : '#$rank highest';
  return '$where (${formatNumber(f, avg)}) · $place of ${all.length}';
}

// ================================================================ Details

class ModuleDetailScreen extends StatefulWidget {
  const ModuleDetailScreen({super.key, required this.repo, required this.module, required this.recordId});
  final ModuleRepository repo;
  final ModuleDef module;
  final String recordId;

  @override
  State<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends State<ModuleDetailScreen> {
  bool _busy = false;

  ModuleDef get m => widget.module;
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
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ModuleFormScreen(repo: widget.repo, module: m, record: record)));
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
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.delete(m.key, widget.recordId);
      if (mounted) Navigator.of(context).pop();
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
      return Scaffold(appBar: AppBar(title: Text(m.singular)), body: const Center(child: Text('This record is no longer there.')));
    }
    final title = m.field(m.titleField);
    final status = m.statusField == null ? null : record[m.statusField];
    final actions = m.actions.where((a) => a.appliesTo(record, m.statusField)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        title: Text(m.singular, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (m.canEdit && !m.sensitive) IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: _busy ? null : _edit),
          if (m.canDelete && !m.sensitive) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
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
              _SourceBanner(widget.repo),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
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
                          child: Text(title == null ? '${record['id']}' : displayValue(title, record[m.titleField]),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
                        ),
                        if (status != null) ...[const SizedBox(width: 12), _StatusChip('$status')],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('ID ${record['id']}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                    if (m.sensitive) ...[
                      const SizedBox(height: 10),
                      const Text('Health data: anonymised and read-only.', style: TextStyle(color: Color(0xFFA8243F), fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Change this ${m.singular.toLowerCase()} with one tap. Each button says what it does; the red ones ask before they change anything.',
                        style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5),
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
                                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB3261E), side: const BorderSide(color: Color(0xFFF0B8B3))),
                                  )
                                : FilledButton.tonalIcon(onPressed: _busy ? null : () => _run(a), icon: Icon(a.icon, size: 18), label: Text(a.label)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (m.key == 'members') ...[const SizedBox(height: 14), MemberProfile(member: record)] else if (_numbers(record).isNotEmpty) ...[
                const SizedBox(height: 14),
                // The record's numbers as cards, each saying where it stands among the others.
                LayoutBuilder(
                  builder: (context, box) => EqualRows(
                    columns: box.maxWidth >= 900 ? 4 : box.maxWidth >= 560 ? 3 : 2,
                    gap: 12,
                    children: [
                      for (final f in _numbers(record))
                        _KpiTile(label: f.label, value: displayValue(f, record[f.key]), caption: compareHint(f, record[f.key], widget.repo.records(m.key)), icon: Icons.insights_outlined, color: const Color(0xFF0F766E)),
                    ],
                  ),
                ),
              ],
              for (final section in m.sections) ...[
                const SizedBox(height: 14),
                _SectionCard(
                  title: m.sections.length > 1 ? section : null,
                  child: fieldGrid([for (final f in m.fields) if (f.section == section) f], (f) => _FieldView(module: m, field: f, record: record, repo: widget.repo), gap: 18),
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
      shown = const Text('Not filled in yet', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontStyle: FontStyle.italic));
    } else if (f.key == module.statusField) {
      shown = Align(alignment: Alignment.centerLeft, child: _StatusChip('$value'));
    } else if (f.type == FieldType.image) {
      shown = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        imagePreview('$value', repo.api.base, size: 110),
        const SizedBox(width: 12),
        Expanded(child: SelectableText('$value', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5))),
      ]);
    } else if (f.type == FieldType.list && value is List) {
      shown = Wrap(spacing: 6, runSpacing: 6, children: [
        for (final v in value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(999)),
            child: Text('$v', style: const TextStyle(fontSize: 13, color: Color(0xFF26413B), fontWeight: FontWeight.w600)),
          ),
      ]);
    } else if (f.type == FieldType.url) {
      shown = InkWell(
        onTap: () => launchUrl(Uri.parse('$value'), mode: LaunchMode.externalApplication),
        child: Text('$value', style: const TextStyle(color: brand, fontSize: 14, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
      );
    } else {
      shown = SelectableText(displayValue(f, value), style: TextStyle(fontSize: 14.5, fontWeight: f.type == FieldType.longText ? FontWeight.w500 : FontWeight.w700, height: 1.45));
    }
    final hint = const {FieldType.integer, FieldType.decimal, FieldType.money}.contains(f.type) ? compareHint(f, value, repo.records(module.key)) : null;
    final max = f.maxLength;
    final long = max != null && value is String && value.length > max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        shown,
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint, style: const TextStyle(color: Color(0xFF0F766E), fontSize: 12.5))),
        if (long) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${value.length} characters: over the $max that show in full.', style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 12.5))),
        if (f.help != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.help!, style: const TextStyle(color: Color(0xFF8A9A96), fontSize: 12, height: 1.35))),
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
      if (waiting != null) rows.add(two ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: build(waiting!)), SizedBox(width: gap), const Expanded(child: SizedBox())]) : build(waiting!));
      waiting = null;
    }

    for (final f in fields) {
      if (!two || f.wide) {
        flush();
        rows.add(build(f));
      } else if (waiting == null) {
        waiting = f;
      } else {
        rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: build(waiting!)), SizedBox(width: gap), Expanded(child: build(f))]));
        waiting = null;
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, r) in rows.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : gap), child: r)]);
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
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE6EEEB))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19))),
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
    color: const Color(0xFFEFF5F3),
    alignment: Alignment.center,
    child: const Icon(Icons.image_outlined, color: Color(0xFF8DA19C)),
  );
  final Widget image = v.startsWith('assets/')
      ? Image.asset(v, fit: BoxFit.contain, errorBuilder: fallback)
      : Image.network(v.startsWith('/') ? '${server.replaceFirst(RegExp(r'/+$'), '')}$v' : v, fit: BoxFit.contain, errorBuilder: fallback);
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Container(width: size, height: size, color: const Color(0xFFF4F8F6), child: image),
  );
}

class ModuleFormScreen extends StatefulWidget {
  const ModuleFormScreen({super.key, required this.repo, required this.module, this.record});
  final ModuleRepository repo;
  final ModuleDef module;

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

  ModuleDef get m => widget.module;
  bool get _editing => widget.record != null;
  Iterable<FieldDef> get _editable => m.fields.where((f) => !f.readOnly);

  static const _picked = {FieldType.boolean, FieldType.choice, FieldType.dateTime, FieldType.list};

  @override
  void initState() {
    super.initState();
    final record = widget.record ?? {};
    _values = {
      for (final f in _editable)
        f.key: switch (f.type) {
          FieldType.list => [for (final v in (record[f.key] as List?) ?? const []) '$v'],
          _ => record[f.key] ?? switch (f.type) {
            FieldType.boolean => false,
            FieldType.choice => f.options.firstOrNull,
            FieldType.dateTime => DateTime.now().toUtc().toIso8601String(),
            _ => null,
          },
        },
    };
    _text = {
      for (final f in _editable.where((f) => !_picked.contains(f.type)))
        f.key: TextEditingController(text: record[f.key] == null ? '' : '${record[f.key]}'),
    };
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

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Some boxes need a look. They’re marked in red.')));
      return;
    }
    final record = <String, dynamic>{
      for (final f in _editable) f.key: _text.containsKey(f.key) ? _parsed(f) : _values[f.key],
    };
    setState(() => _busy = true);
    try {
      final saved = _editing ? await widget.repo.update(m.key, '${widget.record!['id']}', record) : await widget.repo.create(m.key, record);
      if (mounted) Navigator.of(context).pop(saved);
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
    helperStyle: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5, height: 1.35),
    errorMaxLines: 3,
    filled: true,
    fillColor: Colors.white,
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
          color: const Color(0xFFF7FAF9),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: SwitchListTile(
            value: _values[f.key] == true,
            onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v),
            title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: f.help == null ? null : Text(f.help!, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
            contentPadding: EdgeInsets.zero,
          ),
          ),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String>(
          initialValue: f.options.contains(_values[f.key]) ? _values[f.key] as String : null,
          isExpanded: true,
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: _busy ? null : (v) => setState(() => _values[f.key] = v),
          decoration: decoration,
          validator: (v) => f.required && v == null ? 'Choose a ${f.label.toLowerCase()}.' : null,
        );
      case FieldType.dateTime:
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _pickDate(f),
          child: InputDecorator(decoration: decoration.copyWith(suffixIcon: const Icon(Icons.event)), child: Text(displayValue(f, _values[f.key]))),
        );
      case FieldType.list:
        return _ListField(
          field: f,
          decoration: decoration,
          initial: _values[f.key] as List<String>,
          enabled: !_busy,
          onChanged: (items) => _values[f.key] = items,
        );
      default:
        final numeric = f.type == FieldType.integer || f.type == FieldType.money || f.type == FieldType.decimal;
        final input = TextFormField(
          controller: _text[f.key],
          enabled: !_busy,
          minLines: f.type == FieldType.longText ? 3 : 1,
          maxLines: f.type == FieldType.longText ? 8 : 1,
          maxLength: f.maxLength,
          onChanged: f.type == FieldType.image ? (_) => setState(() {}) : null,
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
                    decoration: BoxDecoration(color: const Color(0xFFF4F8F6), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDCE6E3))),
                    child: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF8DA19C)),
                  )
                : imagePreview(link, widget.repo.api.base),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _editing ? 'Edit ${m.singular.toLowerCase()}' : 'Add ${m.singular.toLowerCase()}';
    final sections = [for (final s in m.sections) if (_editable.any((f) => f.section == s)) s];
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _busy ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: Text(_editing ? 'Save' : 'Add')),
          ),
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
                    decoration: BoxDecoration(color: const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(16)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.info_outline, color: brand, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(m.formIntro!, style: const TextStyle(color: Color(0xFF26413B), fontSize: 13.5, height: 1.4))),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('Boxes marked * are needed. Each box says what it’s for underneath.', style: TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5)),
                  ),
                ],
                for (final s in sections) ...[
                  _SectionCard(
                    title: sections.length > 1 || s != 'Details' ? s : null,
                    child: fieldGrid([for (final f in _editable) if (f.section == s) f], _field),
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
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
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
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: widget.enabled,
                  style: const TextStyle(fontSize: 16),
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => add(),
                  decoration: InputDecoration(isDense: true, hintText: 'Type one, then press Add', filled: true, fillColor: const Color(0xFFF7FAF9), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(onPressed: widget.enabled ? add : null, icon: const Icon(Icons.add, size: 18), label: const Text('Add'), style: FilledButton.styleFrom(minimumSize: const Size(0, 44))),
            ]),
          ],
        ),
      );
    },
  );
}
