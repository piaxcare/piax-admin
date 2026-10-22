import 'package:flutter/material.dart';

import '../format.dart';
import 'nav_config.dart';
import 'nav_pages.dart';
import 'nav_widgets.dart' show PageTreeSlot;
import 'option_store.dart';
import 'schema.dart';

// Settings → Dropdown menus: every dropdown in the admin console, searchable, and an editor for each one's values
// (add, rename, reorder, delete, back to the defaults). The same menus the forms and filters use (option_store.dart).

class _Menu {
  const _Menu(this.key, this.where, this.label, this.defaults, {this.status = false});
  final String key, where, label;
  final List<String> defaults;

  /// A status menu: its values also drive colours and one-tap actions.
  final bool status;
}

List<_Menu> _allMenus() => [
  for (final m in modules)
    for (final f in m.fields)
      if (f.type == FieldType.choice && !f.readOnly && !m.readOnly) _Menu('module:${m.key}.${f.key}', m.title, f.label, f.options, status: f.key == m.statusField),
  for (final e in navPageSpecs.entries)
    if (navItemById(e.key) case (final section, final item))
      for (final c in e.value.columns)
        if (c.kind == ColKind.pick || c.kind == ColKind.status || c.kind == ColKind.person)
          _Menu('nav:${e.key}.${c.label}', '${section.numbered} · ${item.label}', c.label, c.kind == ColKind.person ? demoPeople : c.pool, status: c.kind == ColKind.status),
];

class MenuOptionsScreen extends StatefulWidget {
  const MenuOptionsScreen({super.key});

  @override
  State<MenuOptionsScreen> createState() => _MenuOptionsScreenState();
}

class _MenuOptionsScreenState extends State<MenuOptionsScreen> {
  final _search = TextEditingController();
  final _menus = _allMenus();

  @override
  void initState() {
    super.initState();
    OptionStore.instance.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [for (final m in _menus) if (q.isEmpty || '${m.where} ${m.label}'.toLowerCase().contains(q)) m];
    final store = OptionStore.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(title: const Text('Dropdown menus', style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const PageTreeSlot(),
                const Text(
                  'The values in every dropdown of the add and edit forms (and their filters). Values added with “Other…” in a form show up here too. Changes are saved on this device.',
                  style: TextStyle(color: Color(0xFF5A6C68), fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(hintText: 'Search menus: a page or a field, like “status” or “supplier”', prefixIcon: Icon(Icons.search)),
                ),
                const SizedBox(height: 8),
                Text('${shown.length} menus · ${_menus.where((m) => store.isCustomized(m.key)).length} changed', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE6EEEB))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final (i, m) in shown.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text('${m.where} › ${m.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(store.options(m.key, m.defaults).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (store.isCustomized(m.key))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0xFFDDF3EC), borderRadius: BorderRadius.circular(999)),
                              child: const Text('Changed', style: TextStyle(color: brand, fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right),
                        ]),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MenuEditor(menu: m))),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One menu's editor, opened from a form's dropdown (its gear item). [where] says which page or module it belongs to.
class MenuEditorScreen extends StatelessWidget {
  const MenuEditorScreen({super.key, required this.optionKey, required this.where, required this.label, required this.defaults, this.status = false});
  final String optionKey, where, label;
  final List<String> defaults;
  final bool status;

  @override
  Widget build(BuildContext context) => _MenuEditor(menu: _Menu(optionKey, where, label, defaults, status: status));
}

/// One menu's values: add, rename, reorder (drag), delete, or back to the defaults. Saved as you go.
class _MenuEditor extends StatefulWidget {
  const _MenuEditor({required this.menu});
  final _Menu menu;

  @override
  State<_MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends State<_MenuEditor> {
  final _add = TextEditingController();
  _Menu get m => widget.menu;
  OptionStore get store => OptionStore.instance;

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  List<String> get _values => store.options(m.key, m.defaults);

  Future<void> _addValue() async {
    final v = _add.text.trim();
    if (v.isEmpty) return;
    await store.add(m.key, m.defaults, v);
    _add.clear();
  }

  Future<void> _rename(int i) async {
    final v = await promptText(context, title: 'Rename value', label: 'Value', action: 'Rename', initial: _values[i]);
    if (v == null) return;
    await store.set(m.key, [for (final (j, o) in _values.indexed) j == i ? v : o]);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Back to the defaults?'),
        content: Text('“${m.label}” goes back to: ${m.defaults.join(', ')}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep my values')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) await store.reset(m.key);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final values = _values;
      return Scaffold(
        backgroundColor: const Color(0xFFF2F6F5),
        appBar: AppBar(
          title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          actions: [
            if (store.isCustomized(m.key)) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('Reset to defaults')),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(m.where, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13.5)),
                if (m.status) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      'A status menu: its values also set the status colours and one-tap actions. Records keep the status they have, so renaming a value leaves older records on the old name (they still show).',
                      style: TextStyle(color: Color(0xFF7F5300), fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE6EEEB))),
                  clipBehavior: Clip.antiAlias,
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: (from, to) {
                      final next = [...values];
                      final v = next.removeAt(from);
                      next.insert(to, v);
                      store.set(m.key, next);
                    },
                    children: [
                      for (final (i, v) in values.indexed)
                        ListTile(
                          key: ValueKey('$i|$v'),
                          leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator, color: Color(0xFF8A9A96))),
                          title: Text(v),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _rename(i)),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: values.length <= 1 ? null : () => store.set(m.key, [...values]..removeAt(i)),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _add,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(hintText: 'New value'),
                      onSubmitted: (_) => _addValue(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(onPressed: _addValue, icon: const Icon(Icons.add), label: const Text('Add')),
                ]),
                const SizedBox(height: 8),
                const Text('Drag the handle to reorder. A menu keeps at least one value.', style: TextStyle(color: Color(0xFF8A9A96), fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
