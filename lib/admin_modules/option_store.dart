import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import 'menu_options_screen.dart' show MenuEditorScreen;
import 'package:piax_orders_admin/palette.dart';

// The values of every dropdown menu in the admin console (a module's choice fields, a content page's choice columns),
// with the team's own changes: values added through "Other…" in a form, or edited in Settings → Dropdown menus.
// A menu nobody changed uses its built-in defaults. Changes are kept on this device (shared preferences).
//
// Menus are named by where they live: 'module:<module>.<field>' or 'nav:<page>.<column>'.

class OptionStore extends ChangeNotifier {
  OptionStore._();
  static final instance = OptionStore._();

  static const _prefsKey = 'menu_options';
  final _custom = <String, List<String>>{};
  bool _loaded = false;

  /// Reads the saved menus (once). Until then every menu shows its defaults.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        _custom[e.key] = [for (final v in e.value as List) '$v'];
      }
      notifyListeners();
    } catch (_) {
      // Unreadable: start from the defaults.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(_custom));
    } catch (_) {
      // Not saved on this device; the change still holds until the app closes.
    }
  }

  /// The menu's values: the team's version if it was changed, else [defaults].
  List<String> options(String key, List<String> defaults) => _custom[key] ?? defaults;

  bool isCustomized(String key) => _custom.containsKey(key);

  /// Adds [value] to the end of the menu (no duplicates, ignoring case) and returns the value as stored.
  Future<String> add(String key, List<String> defaults, String value) async {
    await load();
    final v = value.trim();
    final current = options(key, defaults);
    final existing = current.where((o) => o.toLowerCase() == v.toLowerCase()).firstOrNull;
    if (existing != null) return existing;
    _custom[key] = [...current, v];
    await _save();
    return v;
  }

  Future<void> set(String key, List<String> values) async {
    await load();
    _custom[key] = [for (final v in values) if (v.trim().isNotEmpty) v.trim()];
    await _save();
  }

  /// Back to the built-in values.
  Future<void> reset(String key) async {
    await load();
    _custom.remove(key);
    await _save();
  }
}

/// Asks for a line of text in a small popup; the trimmed text, or null when cancelled or left empty. The popup owns its
/// text box, so it's only released once the popup has fully closed.
Future<String?> promptText(BuildContext context, {required String title, required String label, required String action, String? helper, String? hint, String initial = ''}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(title: title, label: label, action: action, helper: helper, hint: hint, initial: initial),
  );
  final v = value?.trim() ?? '';
  return v.isEmpty ? null : v;
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({required this.title, required this.label, required this.action, this.helper, this.hint, this.initial = ''});
  final String title, label, action, initial;
  final String? helper, hint;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, helperText: widget.helper, helperMaxLines: 2),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: Text(widget.action)),
    ],
  );
}

/// Asks for a new menu value; null when cancelled or empty.
Future<String?> askNewOption(BuildContext context, String label) => promptText(
  context,
  title: 'New ${label.toLowerCase()}',
  label: label,
  action: 'Add and select',
  helper: 'It’s added to this menu for next time too (editable in Settings).',
);

/// A form dropdown for one menu, with "Other…" at the end: it asks for a new value, adds it to the menu and selects
/// it. A saved value that's no longer in the menu still shows (so nothing is lost).
class ChoiceDropdown extends StatefulWidget {
  const ChoiceDropdown({
    super.key,
    required this.optionKey,
    required this.defaults,
    required this.value,
    required this.label,
    required this.decoration,
    required this.onChanged,
    this.enabled = true,
    this.required = false,
    this.where = '',
  });
  final String optionKey, label;
  final List<String> defaults;
  final String? value;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final bool enabled, required;

  /// The page or module the menu belongs to, shown in its editor.
  final String where;

  @override
  State<ChoiceDropdown> createState() => _ChoiceDropdownState();
}

class _ChoiceDropdownState extends State<ChoiceDropdown> {
  static const _other = '\u0000other';
  static const _edit = '\u0000edit';

  /// Bumped when "Other…" is cancelled, so the field shows the previous value again.
  int _round = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: OptionStore.instance,
    builder: (context, _) {
      final w = widget;
      final options = OptionStore.instance.options(w.optionKey, w.defaults);
      final all = [...options, if (w.value != null && w.value!.isNotEmpty && !options.contains(w.value)) w.value!];
      return DropdownButtonFormField<String>(
        // A new key when the menu or the value changes, so the field shows them.
        key: ValueKey('${w.optionKey}|${all.join('|')}|${w.value}|$_round'),
        initialValue: all.contains(w.value) ? w.value : null,
        isExpanded: true,
        decoration: w.decoration,
        items: [
          for (final o in all) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(
            value: _other,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 18, color: brand),
              SizedBox(width: 8),
              Text('Other…', style: TextStyle(color: brand, fontWeight: FontWeight.w600)),
            ]),
          ),
          // Edit this menu's values (rename, reorder, remove) without leaving the form.
          const DropdownMenuItem(
            value: _edit,
            child: Row(children: [
              Icon(Icons.settings_outlined, size: 18, color: TColor(0xFF5A6C68)),
              SizedBox(width: 8),
              Text('Edit this menu…', style: TextStyle(color: TColor(0xFF34443F), fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: !w.enabled
            ? null
            : (v) async {
                if (v == null) return;
                if (v == _edit) {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MenuEditorScreen(optionKey: w.optionKey, where: w.where, label: w.label, defaults: w.defaults),
                  ));
                  if (mounted) setState(() => _round++); // back to the field's value, with the menu as edited
                  return;
                }
                if (v != _other) return w.onChanged(v);
                final typed = await askNewOption(context, w.label);
                if (typed == null) {
                  if (mounted) setState(() => _round++);
                  return;
                }
                w.onChanged(await OptionStore.instance.add(w.optionKey, w.defaults, typed));
              },
        validator: (v) => w.required && (v == null || v == _other || v == _edit) ? 'Choose a ${w.label.toLowerCase()}.' : null,
      );
    },
  );
}
