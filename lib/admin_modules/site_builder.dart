import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../format.dart';
import 'admin_search.dart' show globalSearchActions;
import 'nav_widgets.dart' show PageTreeSlot;
import 'site_layout.dart';

// The Site & app builder: the website's and the PIAX app's pages as a canvas you edit directly. Drag sections to
// reorder them; drag cards, tags and buttons within a section or into another; add sections from the component
// library and elements from a section's menu; hide, duplicate or delete anything; set alignment, colour and columns;
// undo and redo. Pages are listed on the left, the selected part's settings on the right.
//
// DEMO ONLY (site_layout.dart): edits a demo copy kept on this device; the live website and app don't read it yet.

class SiteBuilderScreen extends StatefulWidget {
  const SiteBuilderScreen({super.key});

  @override
  State<SiteBuilderScreen> createState() => _SiteBuilderScreenState();
}

class _SiteBuilderScreenState extends State<SiteBuilderScreen> {
  LayoutStore get store => LayoutStore.instance;
  Surface _surface = Surface.website;
  String? _pageId, _sectionId, _elementId;
  bool _mobile = false, _showHidden = true;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    // Connects to the local website when one is running (debug builds), so its Home page is edited live.
    store.load().then((_) {
      if (!kReleaseMode && store.link == SiteLink.off) store.connect();
    });
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  SitePage? get _page => store.page(_surface, _pageId) ?? store.pages(_surface).firstOrNull;

  void _select({String? section, String? element}) => setState(() => (_sectionId = section, _elementId = element));

  void _say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));

  // ---------------------------------------------------------------- actions

  Future<void> _addSection(SitePage page, int at) async {
    final kind = await showDialog<SectionKind>(context: context, builder: (_) => const _ComponentLibrary());
    if (kind == null) return;
    final section = starterSection(kind);
    store.edit((_) => page.sections.insert(at.clamp(0, page.sections.length), section));
    _select(section: section.id);
    _say('${kind.label} added.');
  }

  void _addElement(SiteSection section, ElementKind kind) {
    final e = SiteElement(
      kind: kind,
      title: 'New ${kind.label.toLowerCase()}',
      text: kind == ElementKind.tag || kind == ElementKind.button || kind == ElementKind.link ? '' : 'A line about it.',
      tone: section.kind == SectionKind.banner ? section.tone : Tone.white,
    );
    store.edit((_) => section.elements.add(e));
    _select(section: section.id, element: e.id);
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteSection(SitePage page, SiteSection s) async {
    final ok = await _confirm('Delete this ${s.kind.label.toLowerCase()}?', 'It and its ${s.elements.length} elements leave the page. Undo brings them back.');
    if (!ok) return;
    store.edit((_) => page.sections.remove(s));
    if (_sectionId == s.id) _select();
  }

  void _deleteElement(SiteSection s, SiteElement e) {
    store.edit((_) => s.elements.remove(e));
    if (_elementId == e.id) _select(section: s.id);
    _say('${e.kind.label} deleted. Undo brings it back.');
  }

  Future<void> _pageForm({SitePage? page}) async {
    final name = TextEditingController(text: page?.name ?? '');
    final path = TextEditingController(text: page?.path ?? (_surface == Surface.website ? '/new-page' : 'app://new'));
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(page == null ? 'Add a page' : 'Page settings'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(labelText: 'Page name *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Name the page.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: path,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: _surface == Surface.website ? 'Web address *' : 'App screen *',
                  helperText: _surface == Surface.website ? 'Starts with /, e.g. /offers' : 'e.g. app://offers',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Give it an address.';
                  if (_surface == Surface.website && !RegExp(r'^/[a-z0-9\-/]*$').hasMatch(t)) return 'Lowercase letters, numbers and dashes after /.';
                  if (store.pages(_surface).any((p) => p.path == t && p.id != page?.id)) return 'Another page already uses it.';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(context, true) : null, child: Text(page == null ? 'Add page' : 'Save')),
        ],
      ),
    );
    if (ok != true) return;
    if (page == null) {
      final p = SitePage(name: name.text.trim(), path: path.text.trim(), sections: [starterSection(SectionKind.hero)..title = name.text.trim()]);
      store.edit((_) => store.pages(_surface).add(p));
      setState(() => (_pageId = p.id, _sectionId = null, _elementId = null));
    } else {
      store.edit((_) => (page.name = name.text.trim(), page.path = path.text.trim()));
    }
  }

  Future<void> _connectDialog() async {
    final url = TextEditingController(text: store.siteUrl);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local website'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('The website running on this machine with npm run dev. Its home page follows the builder as you edit.', style: TextStyle(color: Color(0xFF5A6C68))),
          const SizedBox(height: 12),
          TextField(
            controller: url,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(labelText: 'Address', helperText: 'Usually http://localhost:3000 (Android emulator: http://10.0.2.2:3000)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Connect')),
        ],
      ),
    );
    if (go == true) await store.connect(url.text);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final wide = MediaQuery.sizeOf(context).width >= 1250;
    final inspector = _Inspector(
      key: ValueKey('${_surface.name}-$_sectionId-$_elementId-${store.revision}'),
      surface: _surface,
      sectionId: _sectionId,
      elementId: _elementId,
      onSelect: _select,
      onAddElement: _addElement,
      onDeleteElement: _deleteElement,
    );
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        title: const Text('Site & app builder', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(tooltip: 'Undo', onPressed: store.canUndo ? store.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Redo', onPressed: store.canRedo ? store.redo : null, icon: const Icon(Icons.redo)),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'connect') return _connectDialog();
              final live = store.link == SiteLink.live;
              if (v == 'reset' &&
                  await _confirm(
                    'Reset to the demo layout?',
                    live
                        ? 'Every change goes, and the local website’s home page goes back to its built-in layout.'
                        : 'Every change to the website and app layout goes. Undo can bring them back while the app is open.',
                  )) {
                await store.reset();
                _select();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'connect', child: Text('Local website address…')),
              PopupMenuItem(value: 'reset', child: Text('Reset to the demo layout')),
            ],
          ),
          ...globalSearchActions(context),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: wide ? null : Drawer(width: 380, child: SafeArea(child: inspector)),
      body: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: const PageTreeSlot(bottom: 6)),
            _toolbar(context, wide),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) SizedBox(width: 250, child: _pages()),
                  if (wide) const VerticalDivider(width: 1),
                  Expanded(child: page == null ? const Center(child: Text('No pages yet: add one.')) : _canvas(context, page, wide)),
                  if (wide) const VerticalDivider(width: 1),
                  if (wide)
                    SizedBox(
                      width: 360,
                      child: Material(color: const Color(0xFFF7FAF9), child: inspector),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool wide) {
    final pages = store.pages(_surface);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<Surface>(
            segments: [for (final s in Surface.values) ButtonSegment(value: s, icon: Icon(s.icon, size: 18), label: Text(s.label))],
            selected: {_surface},
            onSelectionChanged: (v) => setState(() => (_surface = v.first, _pageId = null, _sectionId = null, _elementId = null)),
          ),
          if (!wide)
            DropdownButton<String>(
              value: _page?.id,
              hint: const Text('Page'),
              items: [for (final p in pages) DropdownMenuItem(value: p.id, child: Text('${p.name}  ${p.path}'))],
              onChanged: (id) => setState(() => (_pageId = id, _sectionId = null, _elementId = null)),
            ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.desktop_windows_outlined, size: 18), label: Text('Desktop')),
              ButtonSegment(value: true, icon: Icon(Icons.smartphone, size: 18), label: Text('Mobile')),
            ],
            selected: {_mobile},
            onSelectionChanged: (v) => setState(() => _mobile = v.first),
          ),
          FilterChip(label: const Text('Show hidden'), selected: _showHidden, onSelected: (v) => setState(() => _showHidden = v)),
          if (!wide && (_sectionId != null))
            FilledButton.icon(onPressed: () => Scaffold.of(context).openEndDrawer(), icon: const Icon(Icons.tune, size: 18), label: const Text('Settings')),
          _LinkStatus(store: store, onConnect: _connectDialog),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- pages (left)

  Widget _pages() {
    final pages = store.pages(_surface);
    final current = _page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_surface.label.toUpperCase()} PAGES (${pages.length})',
                  style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .8),
                ),
              ),
              IconButton(tooltip: 'Add a page', onPressed: () => _pageForm(), icon: const Icon(Icons.add)),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            onReorderItem: (a, b) => store.edit((_) {
              final p = pages.removeAt(a);
              pages.insert(b.clamp(0, pages.length), p);
            }),
            children: [
              for (final (i, p) in pages.indexed)
                Material(
                  key: ValueKey(p.id),
                  color: p.id == current?.id ? const Color(0xFFDDF3EC) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.only(left: 4, right: 0),
                    onTap: () => setState(() => (_pageId = p.id, _sectionId = null, _elementId = null)),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.drag_indicator, size: 18, color: Color(0xFF9AAEA9)),
                      ),
                    ),
                    title: Row(children: [
                      Flexible(
                        child: Text(p.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: p.visible ? null : const Color(0xFF8A9A96))),
                      ),
                      if (_surface == Surface.website && p.path == '/' && store.link == SiteLink.live) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: const Color(0xFF0F8A5F), borderRadius: BorderRadius.circular(999)),
                          child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6)),
                        ),
                      ],
                    ]),
                    subtitle: Text('${p.path} · ${p.sections.length} sections${p.visible ? '' : ' · hidden'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Page ${p.name}',
                      onSelected: (v) async {
                        switch (v) {
                          case 'edit':
                            await _pageForm(page: p);
                          case 'hide':
                            store.edit((_) => p.visible = !p.visible);
                          case 'delete':
                            if (await _confirm('Delete the ${p.name} page?', 'Its ${p.sections.length} sections go with it. Undo brings it back.')) {
                              store.edit((_) => pages.remove(p));
                              setState(() => _pageId = null);
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Rename or change address')),
                        PopupMenuItem(value: 'hide', child: Text(p.visible ? 'Hide page' : 'Show page')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete page')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- canvas (middle)

  Widget _canvas(BuildContext context, SitePage page, bool wide) {
    final sections = page.sections;
    final shown = [
      for (final s in sections)
        if (_showHidden || s.visible) s,
    ];
    final width = _mobile ? 390.0 : 1080.0;
    return Container(
      color: const Color(0xFFE9EFED),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: ReorderableListView(
            key: ValueKey('canvas-${page.id}'),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 60),
            header: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(_surface.icon, size: 16, color: const Color(0xFF5A6C68)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${page.name} · ${page.path}${page.visible ? '' : ' · hidden page'}',
                      style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(onPressed: () => _addSection(page, 0), icon: const Icon(Icons.add, size: 18), label: const Text('Section at top')),
                ],
              ),
            ),
            footer: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () => _addSection(page, sections.length),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  side: const BorderSide(color: Color(0xFF9CCFC2), style: BorderStyle.solid),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add a section'),
              ),
            ),
            // Reorders the sections on show; hidden ones (when not shown) keep their places.
            onReorderItem: (a, b) => store.edit((_) {
              final moved = [...shown];
              final x = moved.removeAt(a);
              moved.insert(b.clamp(0, moved.length), x);
              var k = 0;
              for (var i = 0; i < sections.length; i++) {
                if (shown.contains(sections[i])) sections[i] = moved[k++];
              }
            }),
            children: [
              for (final (i, s) in shown.indexed)
                _SectionBlock(
                  key: ValueKey(s.id),
                  index: i,
                  section: s,
                  surface: _surface,
                  mobile: _mobile,
                  selected: _sectionId == s.id,
                  selectedElement: _elementId,
                  onSelect: () {
                    _select(section: s.id);
                    if (!wide) Scaffold.of(context).openEndDrawer();
                  },
                  onSelectElement: (e) {
                    _select(section: s.id, element: e.id);
                    if (!wide) Scaffold.of(context).openEndDrawer();
                  },
                  onHide: () => store.edit((_) => s.visible = !s.visible),
                  onDuplicate: () {
                    final copy = s.copy();
                    store.edit((_) => sections.insert(sections.indexOf(s) + 1, copy));
                    _select(section: copy.id);
                  },
                  onDelete: () => _deleteSection(page, s),
                  onAddBelow: () => _addSection(page, sections.indexOf(s) + 1),
                  onMoveUp: sections.indexOf(s) == 0
                      ? null
                      : () => store.edit((_) {
                          final at = sections.indexOf(s);
                          sections.removeAt(at);
                          sections.insert(at - 1, s);
                        }),
                  onMoveDown: sections.indexOf(s) == sections.length - 1
                      ? null
                      : () => store.edit((_) {
                          final at = sections.indexOf(s);
                          sections.removeAt(at);
                          sections.insert(at + 1, s);
                        }),
                  onAddElement: (k) => _addElement(s, k),
                  onDeleteElement: (e) => _deleteElement(s, e),
                  onDropElement: (id, before) => store.moveElement(_surface, id, s, before: before),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- a section on the canvas

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    super.key,
    required this.index,
    required this.section,
    required this.surface,
    required this.mobile,
    required this.selected,
    required this.selectedElement,
    required this.onSelect,
    required this.onSelectElement,
    required this.onHide,
    required this.onDuplicate,
    required this.onDelete,
    required this.onAddBelow,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onAddElement,
    required this.onDeleteElement,
    required this.onDropElement,
  });
  final int index;
  final SiteSection section;
  final Surface surface;
  final bool mobile, selected;
  final String? selectedElement;
  final VoidCallback onSelect, onHide, onDuplicate, onDelete, onAddBelow;
  final VoidCallback? onMoveUp, onMoveDown;
  final ValueChanged<SiteElement> onSelectElement, onDeleteElement;
  final ValueChanged<ElementKind> onAddElement;
  final void Function(String elementId, String? before) onDropElement;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final tone = s.tone;
    final big = s.kind == SectionKind.hero;
    Widget icon(IconData i, String tip, VoidCallback? on) =>
        IconButton(tooltip: tip, visualDensity: VisualDensity.compact, iconSize: 18, onPressed: on, icon: Icon(i));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: s.visible ? 1 : .45,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? brand : const Color(0xFFDCE6E3), width: selected ? 2 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The section's own bar: drag, name, actions.
              Container(
                color: selected ? const Color(0xFFDDF3EC) : const Color(0xFFF7FAF9),
                padding: const EdgeInsets.only(left: 4, right: 4),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Tooltip(
                        message: 'Drag to move this section',
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_indicator, size: 18, color: Color(0xFF7D918C)),
                        ),
                      ),
                    ),
                    Icon(s.kind.icon, size: 16, color: brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: InkWell(
                        onTap: onSelect,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '${s.kind.label}${s.visible ? '' : ' · hidden'}${s.title.isEmpty ? '' : ' · ${s.title}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF34443F)),
                          ),
                        ),
                      ),
                    ),
                    if (!mobile) ...[icon(Icons.arrow_upward, 'Move up', onMoveUp), icon(Icons.arrow_downward, 'Move down', onMoveDown)],
                    icon(s.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, s.visible ? 'Hide section' : 'Show section', onHide),
                    icon(Icons.tune, 'Section settings', onSelect),
                    PopupMenuButton<String>(
                      tooltip: 'Section menu',
                      iconSize: 18,
                      onSelected: (v) => switch (v) {
                        'dup' => onDuplicate(),
                        'below' => onAddBelow(),
                        'delete' => onDelete(),
                        _ => onAddElement(ElementKind.values.firstWhere((k) => k.name == v)),
                      },
                      itemBuilder: (_) => [
                        for (final k in s.kind.elements)
                          PopupMenuItem(
                            value: k.name,
                            child: Row(children: [Icon(k.icon, size: 18), const SizedBox(width: 10), Text('Add ${k.label.toLowerCase()}')]),
                          ),
                        if (s.kind.elements.isNotEmpty) const PopupMenuDivider(),
                        if (s.kind != SectionKind.builtin) const PopupMenuItem(value: 'dup', child: Text('Duplicate section')),
                        const PopupMenuItem(value: 'below', child: Text('Add a section below')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete section')),
                      ],
                    ),
                  ],
                ),
              ),
              // The section as it would look (a website section of the site's own: its name and where it sits).
              if (s.kind == SectionKind.builtin)
                InkWell(
                  onTap: onSelect,
                  child: Container(
                    height: 86,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFFEFF7F4), Color(0xFFF7FAF9)]),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.web_asset, color: brand),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19))),
                          const Text('The website’s own section: move or hide it here', style: TextStyle(fontSize: 12, color: Color(0xFF5A6C68))),
                        ]),
                      ),
                    ]),
                  ),
                )
              else
              InkWell(
                onTap: onSelect,
                child: Container(
                  color: tone.background,
                  padding: EdgeInsets.symmetric(horizontal: mobile ? 18 : 32, vertical: big ? 34 : 22),
                  child: Column(
                    crossAxisAlignment: s.align.cross,
                    children: [
                      if (s.title.isNotEmpty)
                        Text(
                          s.title,
                          textAlign: s.align.text,
                          style: TextStyle(fontSize: big ? (mobile ? 26 : 36) : (mobile ? 19 : 23), fontWeight: FontWeight.w600, color: tone.ink, height: 1.15),
                        ),
                      if (s.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          s.subtitle,
                          textAlign: s.align.text,
                          style: TextStyle(fontSize: big ? 15.5 : 13.5, color: tone.ink.withValues(alpha: .75), height: 1.4),
                        ),
                      ],
                      if (s.title.isNotEmpty || s.subtitle.isNotEmpty) const SizedBox(height: 16),
                      _Elements(
                        section: s,
                        mobile: mobile,
                        selected: selectedElement,
                        onSelect: onSelectElement,
                        onDelete: onDeleteElement,
                        onDrop: onDropElement,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The elements of a section, laid out by kind, each draggable (to reorder or move into another section) and
/// selectable; dropping on an element puts the dragged one before it, dropping on the end zone adds it last.
class _Elements extends StatelessWidget {
  const _Elements({required this.section, required this.mobile, required this.selected, required this.onSelect, required this.onDelete, required this.onDrop});
  final SiteSection section;
  final bool mobile;
  final String? selected;
  final ValueChanged<SiteElement> onSelect, onDelete;
  final void Function(String elementId, String? before) onDrop;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final inline =
        s.kind == SectionKind.hero ||
        s.kind == SectionKind.tagRow ||
        s.kind == SectionKind.cta ||
        s.kind == SectionKind.newsletter ||
        s.kind == SectionKind.appPromo ||
        s.kind == SectionKind.announcement;
    final cols = mobile ? (s.columns > 2 ? 1 : s.columns.clamp(1, 2)) : s.columns.clamp(1, 4);
    Widget wrap(SiteElement e, Widget child) => _DragTile(
      element: e,
      selected: selected == e.id,
      onSelect: () => onSelect(e),
      onDelete: () => onDelete(e),
      onDrop: (id) => onDrop(id, e.id),
      child: child,
    );
    final endZone = DragTarget<String>(
      onWillAcceptWithDetails: (d) => !s.elements.any((e) => e.id == d.data) || s.elements.last.id != d.data,
      onAcceptWithDetails: (d) => onDrop(d.data, null),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: candidates.isEmpty ? 10 : 36,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(color: candidates.isEmpty ? Colors.transparent : const Color(0x330B5B4E), borderRadius: BorderRadius.circular(10)),
        child: candidates.isEmpty
            ? null
            : const Center(
                child: Text('Drop here: last in this section', style: TextStyle(fontSize: 12, color: brand)),
              ),
      ),
    );
    if (s.elements.isEmpty) {
      return DragTarget<String>(
        onAcceptWithDetails: (d) => onDrop(d.data, null),
        builder: (context, candidates, _) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: candidates.isEmpty ? const Color(0x0F000000) : const Color(0x330B5B4E), borderRadius: BorderRadius.circular(12)),
          child: Text(
            'Empty: add an element from the section menu, or drop one here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: s.tone.ink.withValues(alpha: .7), fontSize: 12.5),
          ),
        ),
      );
    }
    final tiles = [for (final e in s.elements) wrap(e, _ElementView(element: e, section: s))];
    if (inline) {
      return Column(
        crossAxisAlignment: s.align.cross,
        children: [
          Wrap(alignment: s.align.wrap, spacing: 8, runSpacing: 8, children: tiles),
          endZone,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: s.align.wrap,
              spacing: gap,
              runSpacing: gap,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            ),
            endZone,
          ],
        );
      },
    );
  }
}

class _DragTile extends StatelessWidget {
  const _DragTile({required this.element, required this.selected, required this.onSelect, required this.onDelete, required this.onDrop, required this.child});
  final SiteElement element;
  final bool selected;
  final VoidCallback onSelect, onDelete;
  final ValueChanged<String> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final e = element;
    final body = Opacity(
      opacity: e.visible ? 1 : .4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? brand : Colors.transparent, width: 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onSelect, child: child),
        ),
      ),
    );
    final feedback = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: brand),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(e.kind.icon, size: 18, color: brand),
            const SizedBox(width: 8),
            Text(e.title.isEmpty ? e.kind.label : e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != e.id,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Draggable<String>(
            data: e.id,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: .25, child: body),
            child: Tooltip(message: 'Drag to move · tap to edit', waitDuration: const Duration(milliseconds: 600), child: body),
          ),
          if (candidates.isNotEmpty)
            Positioned(
              left: -5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          if (selected)
            Positioned(
              right: -6,
              top: -6,
              child: Material(
                color: const Color(0xFFB3261E),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One element, drawn the way the site would show it.
class _ElementView extends StatelessWidget {
  const _ElementView({required this.element, required this.section});
  final SiteElement element;
  final SiteSection section;

  @override
  Widget build(BuildContext context) {
    final e = element;
    final ink = e.tone == Tone.white ? section.tone.ink : e.tone.ink;
    Widget tags() => Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: e.align.wrap,
      children: [
        for (final t in e.tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCE6E3)),
            ),
            child: Text(
              t,
              style: const TextStyle(fontSize: 11, color: Color(0xFF26413B), fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
    switch (e.kind) {
      case ElementKind.button:
        final primary = section.elements.where((x) => x.kind == ElementKind.button).firstOrNull?.id == e.id;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: primary ? brand : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: brand),
          ),
          child: Text(
            e.title.isEmpty ? 'Button' : e.title,
            style: TextStyle(color: primary ? Colors.white : brand, fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        );
      case ElementKind.tag:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: e.tone == Tone.white ? Colors.white : e.tone.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFCFE0DA)),
          ),
          child: Text(
            e.title.isEmpty ? 'Tag' : e.title,
            style: TextStyle(color: e.tone == Tone.white ? const Color(0xFF26413B) : e.tone.ink, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        );
      case ElementKind.link:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  e.title.isEmpty ? 'Link' : e.title,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    decoration: TextDecoration.underline,
                    decorationColor: ink.withValues(alpha: .4),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 15, color: ink),
            ],
          ),
        );
      case ElementKind.faq:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE1E8E6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  const Icon(Icons.expand_more, size: 20),
                ],
              ),
              if (e.text.isNotEmpty) ...[const SizedBox(height: 6), Text(e.text, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13, height: 1.4))],
            ],
          ),
        );
      case ElementKind.stat:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: e.tone == Tone.white ? Colors.white : e.tone.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE1E8E6)),
          ),
          child: Column(
            crossAxisAlignment: e.align.cross,
            children: [
              Text(
                e.title,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: e.tone == Tone.white ? const Color(0xFF0C1C19) : e.tone.ink),
              ),
              Text(
                e.text,
                textAlign: e.align.text,
                style: TextStyle(color: (e.tone == Tone.white ? const Color(0xFF5A6C68) : e.tone.ink), fontSize: 12.5),
              ),
            ],
          ),
        );
      case ElementKind.ad:
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: e.tone.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: .06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: e.align.cross,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: e.tone.ink.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'AD',
                        style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w600, color: e.tone.ink),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.title,
                      textAlign: e.align.text,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: e.tone.ink),
                    ),
                    if (e.text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.text,
                        textAlign: e.align.text,
                        style: TextStyle(color: e.tone.ink.withValues(alpha: .8), fontSize: 13.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (e.link.isNotEmpty) ...[const SizedBox(width: 12), Icon(Icons.arrow_forward, color: e.tone.ink)],
            ],
          ),
        );
      case ElementKind.quote:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE1E8E6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.format_quote, color: brand),
              Text(e.text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
              const SizedBox(height: 8),
              Text(
                e.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: Color(0xFF5A6C68)),
              ),
            ],
          ),
        );
      case ElementKind.image:
        return AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFDCE6E3), borderRadius: BorderRadius.circular(14)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_outlined, size: 30, color: Color(0xFF7D918C)),
                  Text(e.title.isEmpty ? 'Image' : e.title, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6C68))),
                ],
              ),
            ),
          ),
        );
      case ElementKind.card || ElementKind.product:
        if (section.kind == SectionKind.text) {
          return Text(
            e.text,
            textAlign: e.align.text,
            style: TextStyle(color: section.tone.ink, fontSize: 14.5, height: 1.55),
          );
        }
        final bg = e.tone == Tone.white ? Colors.white : e.tone.background;
        final fg = e.tone == Tone.white ? const Color(0xFF0C1C19) : e.tone.ink;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E8E6)),
          ),
          child: Column(
            crossAxisAlignment: e.align.cross,
            children: [
              if (e.kind == ElementKind.product)
                Container(
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: e.tone == Tone.white ? 1 : .55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Icon(Icons.inventory_2_outlined, size: 32, color: fg.withValues(alpha: .6))),
                ),
              Text(
                e.title,
                textAlign: e.align.text,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: fg),
              ),
              if (e.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  e.text,
                  textAlign: e.align.text,
                  style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: .75), height: 1.4),
                ),
              ],
              if (e.tags.isNotEmpty) ...[const SizedBox(height: 10), tags()],
            ],
          ),
        );
    }
  }
}

// ---------------------------------------------------------------- the component library

class _ComponentLibrary extends StatelessWidget {
  const _ComponentLibrary();

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Add a section', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                ),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text('Pick a component. It arrives with starter content to edit.', style: TextStyle(color: Color(0xFF5A6C68))),
          ),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 240,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                for (final k in SectionKind.values.where((k) => k != SectionKind.builtin))
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE1E8E6)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(context, k),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(k.icon, color: brand),
                            const SizedBox(height: 8),
                            Text(k.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Expanded(
                              child: Text(
                                k.description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12),
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
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- the inspector (right)

class _Inspector extends StatefulWidget {
  const _Inspector({
    super.key,
    required this.surface,
    required this.sectionId,
    required this.elementId,
    required this.onSelect,
    required this.onAddElement,
    required this.onDeleteElement,
  });
  final Surface surface;
  final String? sectionId, elementId;
  final void Function({String? section, String? element}) onSelect;
  final void Function(SiteSection, ElementKind) onAddElement;
  final void Function(SiteSection, SiteElement) onDeleteElement;

  @override
  State<_Inspector> createState() => _InspectorState();
}

class _InspectorState extends State<_Inspector> {
  LayoutStore get store => LayoutStore.instance;
  final _tag = TextEditingController();

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  Widget _head(String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .8),
    ),
  );

  Widget _text(String label, String initial, ValueChanged<String> onChanged, {int lines = 1, String? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: initial,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 3,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (v) => store.edit((_) => onChanged(v), key: key ?? label),
    ),
  );

  Widget _align(Align3 value, ValueChanged<Align3> set) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SegmentedButton<Align3>(
      showSelectedIcon: false,
      segments: [for (final a in Align3.values) ButtonSegment(value: a, icon: Icon(a.icon, size: 18), tooltip: 'Align ${a.label.toLowerCase()}')],
      selected: {value},
      onSelectionChanged: (v) => store.edit((_) => set(v.first)),
    ),
  );

  Widget _tone(Tone value, ValueChanged<Tone> set) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in Tone.values)
          Tooltip(
            message: t.label,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => store.edit((_) => set(t)),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: t == value ? brand : const Color(0xFFCBD5D1), width: t == value ? 3 : 1),
                ),
                child: t == value ? Icon(Icons.check, size: 16, color: t.ink) : null,
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final el = store.element(widget.surface, widget.elementId);
    final sec = store.section(widget.surface, widget.sectionId)?.$2 ?? el?.$1;
    if (sec == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app_outlined, size: 36, color: Color(0xFF9AAEA9)),
            SizedBox(height: 10),
            Text(
              'Select a section or an element on the page to change it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5A6C68)),
            ),
            SizedBox(height: 8),
            Text(
              'Drag sections by ⋮⋮ to reorder them; drag cards, tags and buttons to move them, even into another section.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A9A96), fontSize: 12.5),
            ),
          ],
        ),
      );
    }
    final e = el?.$2;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        Row(
          children: [
            if (e != null)
              IconButton(
                tooltip: 'Back to the section',
                onPressed: () => widget.onSelect(section: sec.id),
                icon: const Icon(Icons.arrow_back),
              ),
            Icon(e?.kind.icon ?? sec.kind.icon, color: brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e == null ? sec.kind.label : e.kind.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Switch(value: e?.visible ?? sec.visible, onChanged: (v) => store.edit((_) => e != null ? e.visible = v : sec.visible = v)),
          ],
        ),
        Text(
          (e?.visible ?? sec.visible) ? 'Shown' : 'Hidden: kept here, not shown on the page.',
          style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5),
        ),
        if (sec.kind == SectionKind.builtin)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text(
              'One of the website’s own designed sections. Drag it to move it on the page, or switch it off to hide it. Its words and pictures are edited in the website’s code or CMS.',
              style: TextStyle(color: Color(0xFF34443F), height: 1.45),
            ),
          )
        else if (e == null) ..._sectionForm(sec) else ..._elementForm(sec, e),
      ],
    );
  }

  List<Widget> _sectionForm(SiteSection s) => [
    _head('CONTENT'),
    _text('Heading', s.title, (v) => s.title = v, key: '${s.id}.title'),
    _text('Line under the heading', s.subtitle, (v) => s.subtitle = v, lines: 2, key: '${s.id}.subtitle'),
    _head('LAYOUT'),
    _align(s.align, (a) => s.align = a),
    if (s.kind.columns > 1 || s.columns > 1)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Columns', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final n in [1, 2, 3, 4]) ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {s.columns.clamp(1, 4)},
              onSelectionChanged: (v) => store.edit((_) => s.columns = v.first),
            ),
          ],
        ),
      ),
    _head('BACKGROUND'),
    _tone(s.tone, (t) => s.tone = t),
    _head('ELEMENTS (${s.elements.length})'),
    ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (a, b) => store.edit((_) {
        final x = s.elements.removeAt(a);
        s.elements.insert(b.clamp(0, s.elements.length), x);
      }),
      children: [
        for (final (i, x) in s.elements.indexed)
          Padding(
            key: ValueKey(x.id),
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE6EEEB)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 4, right: 0),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.drag_indicator, size: 18, color: Color(0xFF9AAEA9)),
                  ),
                ),
                title: Text(
                  x.title.isEmpty ? x.kind.label : x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: x.visible ? null : const Color(0xFF8A9A96)),
                ),
                subtitle: Text('${x.kind.label}${x.visible ? '' : ' · hidden'}'),
                onTap: () => widget.onSelect(section: s.id, element: x.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: x.visible ? 'Hide ${x.title}' : 'Show ${x.title}',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(x.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      onPressed: () => store.edit((_) => x.visible = !x.visible),
                    ),
                    IconButton(
                      tooltip: 'Duplicate ${x.title}',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () => store.edit((_) => s.elements.insert(i + 1, x.copy())),
                    ),
                    IconButton(
                      tooltip: 'Delete ${x.title}',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => widget.onDeleteElement(s, x),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
    const SizedBox(height: 6),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in s.kind.elements)
          OutlinedButton.icon(onPressed: () => widget.onAddElement(s, k), icon: Icon(k.icon, size: 18), label: Text('Add ${k.label.toLowerCase()}')),
      ],
    ),
  ];

  List<Widget> _elementForm(SiteSection s, SiteElement e) => [
    _head('CONTENT'),
    _text(
      switch (e.kind) {
        ElementKind.faq => 'Question',
        ElementKind.stat => 'Number',
        ElementKind.quote => 'Who said it',
        _ => 'Title',
      },
      e.title,
      (v) => e.title = v,
      key: '${e.id}.title',
    ),
    if (e.kind != ElementKind.tag && e.kind != ElementKind.button && e.kind != ElementKind.link)
      _text(
        switch (e.kind) {
          ElementKind.faq => 'Answer',
          ElementKind.stat => 'What it counts',
          ElementKind.quote => 'Quote',
          _ => 'Text',
        },
        e.text,
        (v) => e.text = v,
        lines: 3,
        key: '${e.id}.text',
      ),
    if (e.kind != ElementKind.tag && e.kind != ElementKind.stat && e.kind != ElementKind.quote && e.kind != ElementKind.faq)
      _text('Link', e.link, (v) => e.link = v, key: '${e.id}.link'),
    if (e.kind == ElementKind.card || e.kind == ElementKind.product) ...[
      _head('TAGS'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final t in e.tags) InputChip(label: Text(t), onDeleted: () => store.edit((_) => e.tags.remove(t)))],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _tag,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: 'Add a tag',
          helperText: 'Product tags: validated claims only (e.g. Winged design, Breathable backsheet).',
          helperMaxLines: 2,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: IconButton(tooltip: 'Add tag', icon: const Icon(Icons.add), onPressed: () => _addTag(e)),
        ),
        onSubmitted: (_) => _addTag(e),
      ),
    ],
    _head('LAYOUT'),
    _align(e.align, (a) => e.align = a),
    _head('COLOUR'),
    _tone(e.tone, (t) => e.tone = t),
    const SizedBox(height: 8),
    OutlinedButton.icon(
      onPressed: () => widget.onDeleteElement(s, e),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFB3261E),
        side: const BorderSide(color: Color(0xFFF0B8B3)),
      ),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text('Delete ${e.kind.label.toLowerCase()}'),
    ),
  ];

  void _addTag(SiteElement e) {
    final t = _tag.text.trim();
    if (t.isEmpty || e.tags.contains(t)) return;
    store.edit((_) => e.tags.add(t));
    _tag.clear();
  }
}

/// Where the builder's changes go: live to the local website, or kept here (with Connect and why).
class _LinkStatus extends StatelessWidget {
  const _LinkStatus({required this.store, required this.onConnect});
  final LayoutStore store;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(store.siteUrl)?.authority ?? store.siteUrl;
    Widget chip(Color bg, Color fg, IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
    return switch (store.link) {
      SiteLink.live => Tooltip(
        message: 'The website’s Home page on $host follows every change within a couple of seconds. Other pages and the app are demo copies.',
        child: chip(const Color(0xFFDDF3EC), const Color(0xFF0B5B4E), Icons.wifi_tethering, 'Live on $host · Home page'),
      ),
      SiteLink.connecting => chip(const Color(0xFFEEF2F1), const Color(0xFF475569), Icons.sync, 'Connecting to $host…'),
      _ => Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: store.linkProblem ?? 'Run the website with npm run dev, then connect to edit its home page live.',
          child: chip(const Color(0xFFFFF4D6), const Color(0xFF7F5300), Icons.cloud_off_outlined, store.link == SiteLink.failed ? 'Not connected: demo layout' : 'Demo layout: not live yet'),
        ),
        const SizedBox(width: 6),
        TextButton.icon(onPressed: onConnect, icon: const Icon(Icons.link, size: 18), label: const Text('Connect')),
      ]),
    };
  }
}
