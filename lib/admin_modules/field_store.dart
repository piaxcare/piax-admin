import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import 'option_store.dart';
import 'schema.dart';

import 'package:piax_orders_admin/palette.dart';
import 'package:piax_orders_admin/app_layout.dart';

// The team's own input fields on each sidebar page: added, renamed, made required, given choices, reordered or
// removed in the "Edit fields" panel on the right of the page. They show in the page's add and edit forms and on each
// record, after the built-in fields. Like the dropdown menus (option_store.dart), they're kept on this device
// (shared preferences); the records' values stay with the records.
//
// Pages are named by where they live: 'module:<module>' or 'nav:<page id>'.

enum CustomType {
  text('Short text', Icons.short_text),
  longText('Long text', Icons.notes),
  number('Number', Icons.pin_outlined),
  money('Amount (₹)', Icons.currency_rupee),
  date('Date', Icons.event_outlined),
  choice('Dropdown', Icons.arrow_drop_down_circle_outlined),
  yesNo('Yes / no', Icons.toggle_on_outlined),
  file('File upload', Icons.upload_file);

  const CustomType(this.label, this.icon);
  final String label;
  final IconData icon;

  /// Kinds whose value can carry a suffix after it ("500 ml", "12 days").
  bool get takesSuffix => this == text || this == number || this == money;
}

class CustomField {
  const CustomField({required this.id, required this.label, required this.type, this.required = false, this.options = const [], this.help, this.suffix});
  final String id, label;
  final CustomType type;
  final bool required;

  /// The choices of a dropdown.
  final List<String> options;
  final String? help;

  /// Optional text after the value, in the box and wherever the value shows: "ml", "kg", "pcs", "days".
  final String? suffix;

  CustomField copyWith({String? label, CustomType? type, bool? required, List<String>? options, String? help, String? suffix}) => CustomField(
    id: id,
    label: label ?? this.label,
    type: type ?? this.type,
    required: required ?? this.required,
    options: options ?? this.options,
    help: help ?? this.help,
    suffix: suffix ?? this.suffix,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'type': type.name,
    'required': required,
    'options': options,
    if (help != null) 'help': help,
    if (suffix != null) 'suffix': suffix,
  };

  static CustomField? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = CustomType.values.where((t) => t.name == j['type']).firstOrNull;
    if (type == null || '${j['label'] ?? ''}'.isEmpty) return null;
    return CustomField(
      id: '${j['id']}',
      label: '${j['label']}',
      type: type,
      required: j['required'] == true,
      options: [for (final o in (j['options'] as List?) ?? const []) '$o'],
      help: (j['help'] as String?)?.isEmpty ?? true ? null : j['help'] as String,
      suffix: (j['suffix'] as String?)?.trim().isEmpty ?? true ? null : (j['suffix'] as String).trim(),
    );
  }
}

/// The team's changes to a built-in field: its name, the hint under its box, whether it's required, and whether it's
/// deleted from the page ([hidden]: its saved values stay with the records, so Restore brings it back). Null means
/// "as built".
class BuiltinOverride {
  const BuiltinOverride({this.label, this.help, this.required, this.hidden = false});
  final String? label, help;
  final bool? required;
  final bool hidden;

  bool get isEmpty => label == null && help == null && required == null && !hidden;

  Map<String, dynamic> toJson() => {if (label != null) 'label': label, if (help != null) 'help': help, if (required != null) 'required': required, if (hidden) 'hidden': true};

  static BuiltinOverride fromJson(Object? j) =>
      j is Map ? BuiltinOverride(label: j['label'] as String?, help: j['help'] as String?, required: j['required'] as bool?, hidden: j['hidden'] == true) : const BuiltinOverride();
}

/// A built-in field as the Edit fields panel offers it: what can be changed depends on what the page needs from it.
class BuiltinField {
  const BuiltinField({
    required this.key,
    required this.label,
    required this.kind,
    this.help,
    this.required = true,
    this.canToggleRequired = false,
    this.choicesKey,
    this.defaultChoices = const [],
  });

  /// How the page knows the field (never changes), its built-in name and kind.
  final String key, label, kind;
  final String? help;
  final bool required, canToggleRequired;

  /// The dropdown menu of a choice field (option_store.dart), and its built-in values.
  final String? choicesKey;
  final List<String> defaultChoices;
}

class FieldStore extends ChangeNotifier {
  FieldStore._();
  static final instance = FieldStore._();

  static const _prefsKey = 'custom_fields', _builtinKey = 'builtin_fields', _orderKey = 'field_order';
  final _pages = <String, List<CustomField>>{};
  final _builtin = <String, Map<String, BuiltinOverride>>{};

  /// The order the team put each page's fields in: keys from [builtinOrderKey] and [customOrderKey].
  final _order = <String, List<String>>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey), builtin = prefs.getString(_builtinKey), order = prefs.getString(_orderKey);
      if (order != null) {
        for (final e in (jsonDecode(order) as Map<String, dynamic>).entries) {
          _order[e.key] = [for (final k in e.value as List) '$k'];
        }
      }
      if (raw != null) {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) {
          _pages[e.key] = [for (final f in e.value as List) ?CustomField.fromJson(f)];
        }
      }
      if (builtin != null) {
        for (final e in (jsonDecode(builtin) as Map<String, dynamic>).entries) {
          _builtin[e.key] = {for (final o in (e.value as Map<String, dynamic>).entries) o.key: BuiltinOverride.fromJson(o.value)};
        }
      }
      notifyListeners();
    } catch (_) {
      // Unreadable: no custom fields.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          for (final e in _pages.entries) e.key: [for (final f in e.value) f.toJson()],
        }),
      );
      await prefs.setString(
        _builtinKey,
        jsonEncode({
          for (final e in _builtin.entries) e.key: {for (final o in e.value.entries) o.key: o.value.toJson()},
        }),
      );
      await prefs.setString(_orderKey, jsonEncode(_order));
    } catch (_) {
      // Not saved on this device; the change still holds until the app closes.
    }
  }

  List<CustomField> fields(String page) => List.unmodifiable(_pages[page] ?? const []);

  /// The order of [page]'s fields (empty: as built, the team's own after).
  List<String> order(String page) => List.unmodifiable(_order[page] ?? const []);

  Future<void> setOrder(String page, List<String> keys) async {
    await load();
    _order[page] = [...keys];
    await _save();
  }

  /// Back to the built-in order.
  Future<void> resetOrder(String page) async {
    await load();
    _order.remove(page);
    await _save();
  }

  /// The team's changes to built-in field [key] of [page] (empty when none).
  BuiltinOverride builtin(String page, String key) => _builtin[page]?[key] ?? const BuiltinOverride();

  Future<void> setBuiltin(String page, String key, BuiltinOverride o) async {
    await load();
    final map = _builtin.putIfAbsent(page, () => {});
    o.isEmpty ? map.remove(key) : map[key] = o;
    await _save();
  }

  Future<void> add(String page, CustomField field) async {
    await load();
    // Never twice: the same field, or one with the same name, is already there.
    if (fields(page).any((f) => f.id == field.id || f.label.toLowerCase() == field.label.toLowerCase())) return;
    _pages[page] = [...fields(page), field];
    await _save();
  }

  Future<void> update(String page, CustomField field) async {
    await load();
    _pages[page] = [for (final f in fields(page)) f.id == field.id ? field : f];
    await _save();
  }

  Future<void> remove(String page, String id) async {
    await load();
    _pages[page] = [
      for (final f in fields(page))
        if (f.id != id) f,
    ];
    await _save();
  }

  static String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1296).toRadixString(36)}';
}

/// How a field is named in a page's order: built-in ones by their key, the team's by their id.
String builtinOrderKey(String key) => 'b:$key';
String customOrderKey(String id) => 'c:$id';

/// [items] in the team's order for [page]: ordered ones first as set, any not in it (new fields) after, in their
/// usual order. Unchanged when the team hasn't reordered.
List<T> inFieldOrder<T>(String page, List<T> items, String Function(T) orderKey) {
  final order = FieldStore.instance.order(page);
  if (order.isEmpty) return items;
  final at = {for (final (i, k) in order.indexed) k: i};
  final indexed = [for (final (i, x) in items.indexed) (i, x)];
  indexed.sort((a, b) => (at[orderKey(a.$2)] ?? order.length + a.$1).compareTo(at[orderKey(b.$2)] ?? order.length + b.$1));
  return [for (final (_, x) in indexed) x];
}

// ---------------------------------------------------------------- admin modules

/// The section custom fields sit in, on forms and record pages.
const customSection = 'More fields';

/// A module with the team's own fields added at the end (in their own section). Their values are kept on each record
/// under `cf_<id>`, so renaming a field keeps its values.
ModuleDef withCustomFields(ModuleDef module) {
  // Safe to call on a module that already has them (a screen passes its merged module to the next): start from the
  // built-in fields only, so nothing is added twice.
  final m = builtInModule(module);
  final page = 'module:${m.key}';
  final extra = FieldStore.instance.fields(page);
  final store = FieldStore.instance;
  if (extra.isEmpty && store.order(page).isEmpty && m.fields.every((f) => store.builtin(page, f.key).isEmpty)) return m;
  final merged = <FieldDef>[
    for (final f in m.fields)
      if (store.builtin(page, f.key) case final o when !o.isEmpty)
        FieldDef(
          f.key,
          o.label ?? f.label,
          f.type,
          options: f.options,
          required: o.required ?? f.required,
          readOnly: f.readOnly,
          help: o.help ?? f.help,
          section: f.section,
          hint: f.hint,
          maxLength: f.maxLength,
          pattern: f.pattern,
          patternMessage: f.patternMessage,
          fileTypes: f.fileTypes,
          multiple: f.multiple,
          hidden: o.hidden,
        )
      else
        f,
    for (final f in extra)
      FieldDef(
        'cf_${f.id}',
        f.label,
        switch (f.type) {
          CustomType.text => FieldType.text,
          CustomType.longText => FieldType.longText,
          CustomType.number => FieldType.decimal,
          CustomType.money => FieldType.money,
          CustomType.date => FieldType.dateTime,
          CustomType.choice => FieldType.choice,
          CustomType.yesNo => FieldType.boolean,
          CustomType.file => FieldType.file,
        },
        options: f.options,
        required: f.required,
        help: f.help,
        suffix: f.type.takesSuffix ? f.suffix : null,
        section: customSection,
        fileTypes: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'jpg', 'jpeg', 'png'],
      ),
  ];
  return ModuleDef(
    key: m.key,
    title: m.title,
    singular: m.singular,
    group: m.group,
    icon: m.icon,
    description: m.description,
    titleField: m.titleField,
    subtitleFields: m.subtitleFields,
    statusField: m.statusField,
    actions: m.actions,
    canCreate: m.canCreate,
    canEdit: m.canEdit,
    canDelete: m.canDelete,
    sensitive: m.sensitive,
    formIntro: m.formIntro,
    // In the team's order (Edit fields): the form's sections follow where their first field sits.
    fields: inFieldOrder(page, merged, (f) => f.key.startsWith('cf_') ? customOrderKey(f.key.substring(3)) : builtinOrderKey(f.key)),
  );
}

/// The module as built: its own field definitions, without the team's fields or changes.
ModuleDef builtInModule(ModuleDef m) => modules.firstWhere((x) => x.key == m.key, orElse: () => m);

// ---------------------------------------------------------------- the panel

/// Opens the "Edit fields" panel on the right of the page for [page]: the page's built-in fields (rename, hint,
/// choices, required where the page allows it, delete and restore) and the team's own, which can be added, edited,
/// reordered and removed. [onRenamed] moves a renamed custom field's values on pages that key values by name.
Future<void> showFieldEditor(
  BuildContext context, {
  required String page,
  required String title,
  required List<BuiltinField> builtIn,
  void Function(String from, String to)? onRenamed,
}) async {
  await FieldStore.instance.load();
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const TColor(0x400C1C19),
    transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: const TColor(0xFFF7FAF9),
        elevation: 12,
        child: SizedBox(
          width: math.min(460.0, MediaQuery.sizeOf(context).width),
          height: double.infinity,
          child: SafeArea(
            child: _FieldEditor(page: page, title: title, builtIn: builtIn, onRenamed: onRenamed),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// The "Edit fields" button for a page's top bar: the app's primary button (brand green, white text); an icon on
/// narrow screens.
class EditFieldsButton extends StatelessWidget {
  const EditFieldsButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  static final _style = FilledButton.styleFrom(
    backgroundColor: brand,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) => !AppLayout.instance.editFields
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(right: 4),
          child: MediaQuery.sizeOf(context).width >= 700
              ? FilledButton.icon(onPressed: onPressed, style: _style, icon: const Icon(Icons.tune, size: 18), label: const Text('Edit fields'))
              : IconButton.filled(
                  tooltip: 'Edit fields',
                  onPressed: onPressed,
                  style: IconButton.styleFrom(backgroundColor: brand, foregroundColor: Colors.white),
                  icon: const Icon(Icons.tune),
                ),
        );
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({required this.page, required this.title, required this.builtIn, this.onRenamed});
  final String page, title;
  final List<BuiltinField> builtIn;
  final void Function(String from, String to)? onRenamed;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  /// The field open in the form: an existing one, a new one (id null), or none (the list).
  CustomField? _editing;
  bool _adding = false;

  /// The built-in field open in its form.
  BuiltinField? _builtinEditing;

  FieldStore get store => FieldStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  String _nameOf(BuiltinField b) => store.builtin(widget.page, b.key).label ?? b.label;

  Set<String> get _taken => {for (final b in widget.builtIn) _nameOf(b).toLowerCase(), for (final f in store.fields(widget.page)) f.label.toLowerCase()};

  /// Deletes a built-in field from the page (form, table, filters, record page and the charts that use it). Required
  /// fields too: once deleted, nothing asks for them.
  Future<void> _deleteBuiltin(BuiltinField b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${_nameOf(b)}”?'),
        content: Text(
          'It goes from this page’s form, table, filters and record pages, and from any chart built on it${b.required ? ', and new records no longer need it' : ''}. '
          'Values already saved stay with the records: Restore brings the field back with them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final o = store.builtin(widget.page, b.key);
    await store.setBuiltin(widget.page, b.key, BuiltinOverride(label: o.label, help: o.help, required: o.required, hidden: true));
  }

  Future<void> _delete(CustomField f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove “${f.label}”?'),
        content: const Text('It goes from the forms and record pages. Values already filled in are kept with the records, and come back if you add the field again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await store.remove(widget.page, f.id);
  }

  @override
  Widget build(BuildContext context) {
    final form = _adding || _editing != null || _builtinEditing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
          child: Row(
            children: [
              if (form)
                IconButton(
                  tooltip: 'Back to the fields',
                  onPressed: () => setState(() => (_adding = false, _editing = null, _builtinEditing = null)),
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      form
                          ? (_adding
                                ? 'Add a field'
                                : _builtinEditing != null
                                ? 'Edit built-in field'
                                : 'Edit field')
                          : 'Fields',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _builtinEditing != null
              ? _BuiltinForm(
                  key: ValueKey('builtin-${_builtinEditing!.key}'),
                  page: widget.page,
                  field: _builtinEditing!,
                  taken: {..._taken}..remove(_nameOf(_builtinEditing!).toLowerCase()),
                  onDone: (message) {
                    setState(() => _builtinEditing = null);
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
                  },
                )
              : form
              ? _FieldForm(
                  key: ValueKey(_editing?.id ?? 'new'),
                  field: _editing,
                  taken: {..._taken}..remove(_editing?.label.toLowerCase()),
                  onSave: (f) async {
                    final before = _editing;
                    if (before == null) {
                      await store.add(widget.page, f);
                    } else {
                      await store.update(widget.page, f);
                      if (before.label != f.label) widget.onRenamed?.call(before.label, f.label);
                    }
                    if (!mounted) return;
                    setState(() => (_adding = false, _editing = null));
                    ScaffoldMessenger.maybeOf(this.context)?.showSnackBar(SnackBar(content: Text(before == null ? 'Field “${f.label}” added.' : 'Field saved.')));
                  },
                )
              : _list(),
        ),
      ],
    );
  }

  /// The page's fields in their current order: built-in ones (not deleted) and the team's, as one list.
  List<_Entry> get _entries => inFieldOrder(widget.page, [
    for (final b in widget.builtIn)
      if (!store.builtin(widget.page, b.key).hidden) _Entry(builtinOrderKey(b.key), builtin: b),
    for (final f in store.fields(widget.page)) _Entry(customOrderKey(f.id), custom: f),
  ], (e) => e.key);

  /// Moves the field at [from] to [to] (indexes after removal) and saves the whole order.
  Future<void> _move(int from, int to) async {
    final list = [..._entries];
    if (from < 0 || from >= list.length) return;
    final e = list.removeAt(from);
    list.insert(to.clamp(0, list.length), e);
    // Deleted built-in fields keep their place at the end, ready to come back.
    await store.setOrder(widget.page, [
      for (final x in list) x.key,
      for (final b in widget.builtIn)
        if (store.builtin(widget.page, b.key).hidden) builtinOrderKey(b.key),
    ]);
  }

  Widget _row(_Entry e, int i, int count) {
    final b = e.builtin, f = e.custom;
    final name = b != null ? _nameOf(b) : f!.label;
    final o = b == null ? null : store.builtin(widget.page, b.key);
    return Container(
      key: ValueKey(e.key),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: TColor(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const TColor(0xFFE6EEEB)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 6, right: 4),
        leading: ReorderableDragStartListener(
          index: i,
          child: Tooltip(
            message: 'Drag to move $name',
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.drag_indicator, color: TColor(0xFF9AAEA9)),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: b != null ? const TColor(0xFFEEF2F1) : const TColor(0xFFDDF3EC), borderRadius: BorderRadius.circular(999)),
              child: Text(
                b != null ? 'Built-in' : 'Yours',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: b != null ? const TColor(0xFF475569) : brand),
              ),
            ),
          ],
        ),
        subtitle: Text(
          b != null
              ? [b.kind, if (o!.required ?? b.required) 'required', if (o.label != null) 'was “${b.label}”' else if (!o.isEmpty) 'changed'].join(' · ')
              : [f!.type.label, if (f.required) 'required', if (f.type == CustomType.choice) '${f.options.length} choices'].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit $name',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 19),
              onPressed: () => setState(() => b != null ? _builtinEditing = b : _editing = f),
            ),
            IconButton(
              tooltip: b != null ? 'Delete $name' : 'Remove $name',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 19),
              onPressed: () => b != null ? _deleteBuiltin(b) : _delete(f!),
            ),
            PopupMenuButton<int>(
              tooltip: 'Move $name',
              icon: const Icon(Icons.swap_vert, size: 19),
              onSelected: (to) => _move(i, to),
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, enabled: i > 0, child: const Text('Move to top')),
                PopupMenuItem(value: i - 1, enabled: i > 0, child: const Text('Move up')),
                PopupMenuItem(value: i + 1, enabled: i < count - 1, child: const Text('Move down')),
                PopupMenuItem(value: count - 1, enabled: i < count - 1, child: const Text('Move to bottom')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    final entries = _entries;
    final deleted = [
      for (final b in widget.builtIn)
        if (store.builtin(widget.page, b.key).hidden) b,
    ];
    final reordered = store.order(widget.page).isNotEmpty;
    const head = TextStyle(color: TColor(0xFF5A6C68), fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .8);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        FilledButton.icon(onPressed: () => setState(() => _adding = true), icon: const Icon(Icons.add), label: const Text('Add a field')),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Text('FIELDS (${entries.length})', style: head)),
            if (reordered)
              TextButton.icon(
                onPressed: () => store.resetOrder(widget.page),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Original order'),
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Drag ⋮⋮ (or use ⇅) to set the order: the table’s columns, the form and each record follow it.',
            style: TextStyle(color: TColor(0xFF5A6C68), fontSize: 12, height: 1.4),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _move,
          children: [for (final (i, e) in entries.indexed) _row(e, i, entries.length)],
        ),
        if (deleted.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('DELETED FIELDS (${deleted.length})', style: head),
          const SizedBox(height: 6),
          for (final b in deleted)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const TColor(0xFFF1F4F3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const TColor(0xFFE6EEEB)),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.delete_outline, size: 18, color: TColor(0xFF9AAEA9)),
                title: Text(
                  _nameOf(b),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: TColor(0xFF8A9A96), decoration: TextDecoration.lineThrough),
                ),
                subtitle: Text('${b.kind} · values kept'),
                trailing: TextButton.icon(
                  onPressed: () {
                    final o = store.builtin(widget.page, b.key);
                    store.setBuiltin(widget.page, b.key, BuiltinOverride(label: o.label, help: o.help, required: o.required));
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: Text('Restore', semanticsLabel: 'Restore ${_nameOf(b)}'),
                ),
              ),
            ),
        ],
        const SizedBox(height: 10),
        const Text(
          'Built-in fields keep their kind (the page’s numbers and charts rely on it). Any of them can be renamed or deleted, required ones too; deleting keeps the values already saved, so Restore brings them back.',
          style: TextStyle(color: TColor(0xFF8A9A96), fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

/// One line of the fields list: a built-in field or one of the team's.
class _Entry {
  const _Entry(this.key, {this.builtin, this.custom});
  final String key;
  final BuiltinField? builtin;
  final CustomField? custom;
}

/// Adds or edits one field: its name, kind, whether it's required, its choices (dropdowns) and a hint.
class _FieldForm extends StatefulWidget {
  const _FieldForm({super.key, required this.field, required this.taken, required this.onSave});
  final CustomField? field;
  final Set<String> taken;
  final Future<void> Function(CustomField) onSave;

  @override
  State<_FieldForm> createState() => _FieldFormState();
}

class _FieldFormState extends State<_FieldForm> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.field?.label ?? '');
  late final _help = TextEditingController(text: widget.field?.help ?? '');
  late final _options = TextEditingController(text: widget.field?.options.join('\n') ?? '');
  late final _suffix = TextEditingController(text: widget.field?.suffix ?? '');
  late CustomType _type = widget.field?.type ?? CustomType.text;
  late bool _required = widget.field?.required ?? false;

  /// Saving: the button is off, so a double click can't add the field twice.
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _help.dispose();
    _options.dispose();
    _suffix.dispose();
    super.dispose();
  }

  List<String> get _choices => [
    for (final l in _options.text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ].fold<List<String>>([], (a, o) => a.any((x) => x.toLowerCase() == o.toLowerCase()) ? a : [...a, o]);

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final f = CustomField(
      id: widget.field?.id ?? FieldStore.newId(),
      label: _label.text.trim(),
      type: _type,
      required: _required,
      options: _type == CustomType.choice ? _choices : const [],
      help: _help.text.trim().isEmpty ? null : _help.text.trim(),
      suffix: _type.takesSuffix && _suffix.text.trim().isNotEmpty ? _suffix.text.trim() : null,
    );
    try {
      await widget.onSave(f);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextFormField(
            controller: _label,
            autofocus: widget.field == null,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Field name *',
              hintText: 'e.g. Reviewer, Batch number, Signed copy',
              border: border,
              filled: true,
              fillColor: TColor(0xFFFFFFFF),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Name the field.';
              if (t.length > 40) return 'Keep it to 40 characters.';
              if (widget.taken.contains(t.toLowerCase())) return 'This page already has a field with that name.';
              return null;
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<CustomType>(
            initialValue: _type,
            decoration: InputDecoration(labelText: 'Kind of input', border: border, filled: true, fillColor: TColor(0xFFFFFFFF)),
            items: [
              for (final t in CustomType.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 18, color: brand),
                      const SizedBox(width: 10),
                      Text(t.label),
                    ],
                  ),
                ),
            ],
            onChanged: (t) => setState(() => _type = t ?? _type),
          ),
          if (widget.field != null && widget.field!.type != _type)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('Values already filled in may not fit the new kind; check them after saving.', style: TextStyle(color: TColor(0xFF8A5A00), fontSize: 12)),
            ),
          if (_type == CustomType.choice) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _options,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Choices *',
                helperText: 'One per line, in the order they should appear.',
                border: border,
                filled: true,
                fillColor: TColor(0xFFFFFFFF),
                alignLabelWithHint: true,
              ),
              validator: (_) => _choices.length < 2 ? 'Give at least two choices.' : null,
            ),
          ],
          if (_type.takesSuffix) ...[
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: _suffix,
              builder: (_, _) => TextFormField(
                controller: _suffix,
                maxLength: 12,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Suffix (optional)',
                  hintText: 'e.g. ml, kg, pcs, days',
                  helperText: _suffix.text.trim().isEmpty ? 'Shown after the value, in the box and on records.' : 'Shows as: 500 ${_suffix.text.trim()}',
                  border: border,
                  filled: true,
                  fillColor: TColor(0xFFFFFFFF),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _help,
            style: const TextStyle(fontSize: 16),
            maxLength: 140,
            decoration: InputDecoration(labelText: 'Hint under the box', hintText: 'What to enter, and why', border: border, filled: true, fillColor: TColor(0xFFFFFFFF)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _required,
            onChanged: (v) => setState(() => _required = v),
            title: const Text('Required', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Forms can’t be saved without it.'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: Icon(widget.field == null ? Icons.add : Icons.check),
            label: Text(widget.field == null ? 'Add field' : 'Save field'),
          ),
        ],
      ),
    );
  }
}

/// Edits a built-in field: its name, hint, choices (dropdowns) and, where the page allows, whether it's required.
/// "Back to original" undoes every change.
class _BuiltinForm extends StatefulWidget {
  const _BuiltinForm({super.key, required this.page, required this.field, required this.taken, required this.onDone});
  final String page;
  final BuiltinField field;
  final Set<String> taken;
  final ValueChanged<String> onDone;

  @override
  State<_BuiltinForm> createState() => _BuiltinFormState();
}

class _BuiltinFormState extends State<_BuiltinForm> {
  final _form = GlobalKey<FormState>();
  late final BuiltinOverride _o = FieldStore.instance.builtin(widget.page, widget.field.key);
  late final _label = TextEditingController(text: _o.label ?? widget.field.label);
  late final _help = TextEditingController(text: _o.help ?? widget.field.help ?? '');
  late final _choices = TextEditingController(
    text: widget.field.choicesKey == null ? '' : OptionStore.instance.options(widget.field.choicesKey!, widget.field.defaultChoices).join('\n'),
  );
  late bool _required = _o.required ?? widget.field.required;

  BuiltinField get b => widget.field;

  @override
  void dispose() {
    _label.dispose();
    _help.dispose();
    _choices.dispose();
    super.dispose();
  }

  List<String> get _list => [
    for (final l in _choices.text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ].fold<List<String>>([], (a, o) => a.any((x) => x.toLowerCase() == o.toLowerCase()) ? a : [...a, o]);

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final label = _label.text.trim(), help = _help.text.trim();
    await FieldStore.instance.setBuiltin(
      widget.page,
      b.key,
      BuiltinOverride(
        label: label == b.label ? null : label,
        help: help == (b.help ?? '') ? null : help,
        required: !b.canToggleRequired || _required == b.required ? null : _required,
        hidden: _o.hidden,
      ),
    );
    if (b.choicesKey != null) {
      final same = _list.length == b.defaultChoices.length && [for (var i = 0; i < _list.length; i++) _list[i] == b.defaultChoices[i]].every((x) => x);
      same ? await OptionStore.instance.reset(b.choicesKey!) : await OptionStore.instance.set(b.choicesKey!, _list);
    }
    widget.onDone('“$label” saved.');
  }

  Future<void> _reset() async {
    await FieldStore.instance.setBuiltin(widget.page, b.key, const BuiltinOverride());
    if (b.choicesKey != null) await OptionStore.instance.reset(b.choicesKey!);
    widget.onDone('“${b.label}” is back to how it was built.');
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12));
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          TextFormField(
            controller: _label,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(labelText: 'Field name *', helperText: 'Built in as “${b.label}”.', border: border, filled: true, fillColor: TColor(0xFFFFFFFF)),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Name the field.';
              if (t.length > 40) return 'Keep it to 40 characters.';
              if (widget.taken.contains(t.toLowerCase())) return 'This page already has a field with that name.';
              return null;
            },
          ),
          const SizedBox(height: 14),
          InputDecorator(
            decoration: InputDecoration(labelText: 'Kind of input', border: border, filled: true, fillColor: const TColor(0xFFF1F4F3), helperText: 'Fixed for built-in fields.'),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 16, color: TColor(0xFF8A9A96)),
                const SizedBox(width: 8),
                Text(b.kind),
              ],
            ),
          ),
          if (b.choicesKey != null) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _choices,
              minLines: 3,
              maxLines: 10,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Choices *',
                helperText: 'One per line, in order. Records keep the value they have.',
                border: border,
                filled: true,
                fillColor: TColor(0xFFFFFFFF),
                alignLabelWithHint: true,
              ),
              validator: (_) => _list.isEmpty ? 'Give at least one choice.' : null,
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _help,
            maxLength: 140,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(labelText: 'Hint under the box', border: border, filled: true, fillColor: TColor(0xFFFFFFFF)),
          ),
          if (b.canToggleRequired)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              title: const Text('Required', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Forms can’t be saved without it.'),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(b.required ? 'Always required: the page needs it.' : 'Optional.', style: const TextStyle(color: TColor(0xFF5A6C68), fontSize: 12.5)),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Save field')),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt), label: const Text('Back to original')),
        ],
      ),
    );
  }
}
