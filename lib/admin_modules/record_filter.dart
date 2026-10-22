import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import 'option_store.dart' show promptText;

// Filtering for every list of records in the admin console (module lists and the menu's content pages), in one place:
//   - a query: search across all fields, one filter per field (by the field's kind), and a sort;
//   - the engine that applies it to any rows, given how to read a field of a row;
//   - the filter bar: search, a Filters panel, sort, chips for what's active, saved views, and the result count.
// Each page keeps its query while the app is open (so coming back keeps the filters); saved views are kept on the
// device (shared preferences), per page.

// ================================================================ Fields and filters

enum FilterKind { text, choice, number, date, boolean }

/// A field that can be filtered and sorted on.
class FilterField {
  const FilterField(this.key, this.label, this.kind, {this.options = const [], this.money = false, this.unit = ''});
  final String key, label;
  final FilterKind kind;

  /// The choices of a choice field.
  final List<String> options;

  /// A number field holding rupees.
  final bool money;
  final String unit;
}

/// The sort key for "most recently modified".
const modifiedKey = '_modified';

enum TextOp { contains, equals, startsWith, notContains }

enum DatePreset { today, last7, last30, last90, thisMonth, lastMonth, next7, next30, overdue, custom }

const _textOps = {TextOp.contains: 'contains', TextOp.equals: 'is', TextOp.startsWith: 'starts with', TextOp.notContains: 'doesn’t contain'};
const _presets = {
  DatePreset.today: 'Today',
  DatePreset.last7: 'Last 7 days',
  DatePreset.last30: 'Last 30 days',
  DatePreset.last90: 'Last 90 days',
  DatePreset.thisMonth: 'This month',
  DatePreset.lastMonth: 'Last month',
  DatePreset.next7: 'Next 7 days',
  DatePreset.next30: 'Next 30 days',
  DatePreset.overdue: 'Before today',
  DatePreset.custom: 'Custom range',
};

sealed class FieldFilter {
  const FieldFilter();
  Map<String, Object?> toJson();

  static FieldFilter? fromJson(Map<String, Object?> j) => switch (j['t']) {
    'text' => TextFilter(TextOp.values.byName('${j['op']}'), '${j['v']}'),
    'choice' => ChoiceFilter({for (final v in (j['v'] as List? ?? const [])) '$v'}),
    'range' => RangeFilter(j['min'] as num?, j['max'] as num?),
    'date' => DateFilter(
      DatePreset.values.byName('${j['p']}'),
      from: DateTime.tryParse('${j['from'] ?? ''}'),
      to: DateTime.tryParse('${j['to'] ?? ''}'),
    ),
    'bool' => BoolFilter(j['v'] == true),
    _ => null,
  };
}

class TextFilter extends FieldFilter {
  const TextFilter(this.op, this.value);
  final TextOp op;
  final String value;
  @override
  Map<String, Object?> toJson() => {'t': 'text', 'op': op.name, 'v': value};
}

class ChoiceFilter extends FieldFilter {
  const ChoiceFilter(this.values);
  final Set<String> values;
  @override
  Map<String, Object?> toJson() => {'t': 'choice', 'v': values.toList()};
}

class RangeFilter extends FieldFilter {
  const RangeFilter(this.min, this.max);
  final num? min, max;
  @override
  Map<String, Object?> toJson() => {'t': 'range', 'min': min, 'max': max};
}

class DateFilter extends FieldFilter {
  const DateFilter(this.preset, {this.from, this.to});
  final DatePreset preset;
  final DateTime? from, to;
  @override
  Map<String, Object?> toJson() => {'t': 'date', 'p': preset.name, 'from': from?.toIso8601String(), 'to': to?.toIso8601String()};

  /// The days it covers, start inclusive, end exclusive.
  (DateTime?, DateTime?) window(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (preset) {
      DatePreset.today => (today, tomorrow),
      DatePreset.last7 => (today.subtract(const Duration(days: 6)), tomorrow),
      DatePreset.last30 => (today.subtract(const Duration(days: 29)), tomorrow),
      DatePreset.last90 => (today.subtract(const Duration(days: 89)), tomorrow),
      DatePreset.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
      DatePreset.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
      DatePreset.next7 => (today, today.add(const Duration(days: 7))),
      DatePreset.next30 => (today, today.add(const Duration(days: 30))),
      DatePreset.overdue => (null, today),
      DatePreset.custom => (from == null ? null : DateTime(from!.year, from!.month, from!.day), to == null ? null : DateTime(to!.year, to!.month, to!.day + 1)),
    };
  }
}

class BoolFilter extends FieldFilter {
  const BoolFilter(this.value);
  final bool value;
  @override
  Map<String, Object?> toJson() => {'t': 'bool', 'v': value};
}

/// What a list shows: a search, filters by field key, and a sort (a field key, or [modifiedKey]).
class RecordQuery {
  const RecordQuery({this.search = '', this.filters = const {}, this.sortKey, this.ascending = true});
  final String search;
  final Map<String, FieldFilter> filters;
  final String? sortKey;
  final bool ascending;

  int get activeCount => filters.length + (search.trim().isEmpty ? 0 : 1);
  bool get isEmpty => activeCount == 0;

  RecordQuery copyWith({String? search, Map<String, FieldFilter>? filters, String? sortKey, bool clearSort = false, bool? ascending}) => RecordQuery(
    search: search ?? this.search,
    filters: filters ?? this.filters,
    sortKey: clearSort ? null : sortKey ?? this.sortKey,
    ascending: ascending ?? this.ascending,
  );

  RecordQuery withFilter(String key, FieldFilter? filter) {
    final next = {...filters};
    if (filter == null) {
      next.remove(key);
    } else {
      next[key] = filter;
    }
    return copyWith(filters: next);
  }

  Map<String, Object?> toJson() => {
    'search': search,
    'filters': {for (final e in filters.entries) e.key: e.value.toJson()},
    'sort': sortKey,
    'asc': ascending,
  };

  static RecordQuery fromJson(Map<String, Object?> j) => RecordQuery(
    search: '${j['search'] ?? ''}',
    filters: {
      for (final e in ((j['filters'] as Map?) ?? const {}).entries)
        '${e.key}': ?FieldFilter.fromJson(Map<String, Object?>.from(e.value as Map)),
    },
    sortKey: j['sort'] as String?,
    ascending: j['asc'] != false,
  );
}

/// Each page's query while the app is open, by page key.
final _remembered = <String, RecordQuery>{};
RecordQuery rememberedQuery(String page, [RecordQuery fallback = const RecordQuery()]) => _remembered[page] ?? fallback;
void rememberQuery(String page, RecordQuery q) => _remembered[page] = q;

/// Forgets every page's filters (a fresh start, as when the app opens).
void forgetQueries() => _remembered.clear();

// ================================================================ Engine

DateTime? _asDate(Object? v) => v is DateTime ? v : DateTime.tryParse('${v ?? ''}')?.toLocal();
num? _asNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
String _asText(Object? v) => v is List ? v.join(', ') : '${v ?? ''}';

bool _matches(FieldFilter f, Object? v, DateTime now) {
  switch (f) {
    case TextFilter(:final op, :final value):
      final text = _asText(v).toLowerCase(), q = value.trim().toLowerCase();
      if (q.isEmpty) return true;
      return switch (op) {
        TextOp.contains => text.contains(q),
        TextOp.equals => text == q,
        TextOp.startsWith => text.startsWith(q),
        TextOp.notContains => !text.contains(q),
      };
    case ChoiceFilter(:final values):
      return values.isEmpty || values.contains(_asText(v));
    case RangeFilter(:final min, :final max):
      final n = _asNum(v);
      if (n == null) return false;
      return (min == null || n >= min) && (max == null || n <= max);
    case DateFilter():
      final d = _asDate(v);
      if (d == null) return false;
      final (from, to) = f.window(now);
      return (from == null || !d.isBefore(from)) && (to == null || d.isBefore(to));
    case BoolFilter(:final value):
      return (v == true || v == 'true') == value;
  }
}

int _compare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final da = _asDate(a), db = _asDate(b);
  if (a is! num && b is! num && da != null && db != null) return da.compareTo(db);
  final na = _asNum(a), nb = _asNum(b);
  if (na != null && nb != null) return na.compareTo(nb);
  return _asText(a).toLowerCase().compareTo(_asText(b).toLowerCase());
}

/// The rows [q] keeps, in its order. [read] gets a field of a row by key ([modifiedKey] for the last change).
List<T> applyQuery<T>(List<T> rows, RecordQuery q, List<FilterField> fields, Object? Function(T row, String key) read, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final search = q.search.trim().toLowerCase();
  final list = rows.where((row) {
    for (final e in q.filters.entries) {
      if (!_matches(e.value, read(row, e.key), at)) return false;
    }
    if (search.isEmpty) return true;
    return fields.any((f) => _asText(read(row, f.key)).toLowerCase().contains(search));
  }).toList();
  final key = q.sortKey;
  if (key != null) {
    // Nulls last either way; ties keep their order.
    final indexed = list.indexed.toList()
      ..sort((x, y) {
        final a = read(x.$2, key), b = read(y.$2, key);
        if (a == null || b == null) return a == null && b == null ? x.$1 - y.$1 : (a == null ? 1 : -1);
        final r = q.ascending ? _compare(a, b) : _compare(b, a);
        return r != 0 ? r : x.$1 - y.$1;
      });
    return [for (final e in indexed) e.$2];
  }
  return list;
}

/// A filter in a few words, for its chip: "Status: Open, Draft", "Value: ₹10,000 – ₹50,000", "Raised: last 30 days".
String describeFilter(FilterField f, FieldFilter filter) {
  String n(num v) => f.money ? rupees(v.round()) : '${NumberFormat.decimalPattern('en_IN').format(v)}${f.unit.isEmpty ? '' : ' ${f.unit}'}';
  final d = DateFormat('d MMM yyyy');
  final what = switch (filter) {
    TextFilter(:final op, :final value) => '${_textOps[op]} “$value”',
    ChoiceFilter(:final values) => values.length <= 2 ? values.join(', ') : '${values.take(2).join(', ')} +${values.length - 2}',
    RangeFilter(:final min, :final max) => min != null && max != null ? '${n(min)} – ${n(max)}' : min != null ? 'at least ${n(min)}' : 'at most ${n(max!)}',
    DateFilter(:final preset, :final from, :final to) => preset == DatePreset.custom
        ? '${from == null ? '…' : d.format(from)} – ${to == null ? '…' : d.format(to)}'
        : _presets[preset]!.toLowerCase(),
    BoolFilter(:final value) => value ? 'yes' : 'no',
  };
  return '${f.label}: $what';
}

// ================================================================ The filter bar

/// Search, filters, sort and saved views above a list, with chips for what's active and the result count.
/// [count] tells the Filters panel how many rows a draft query would show.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.pageKey,
    required this.fields,
    required this.query,
    required this.onChanged,
    required this.total,
    required this.shown,
    required this.count,
    this.noun = 'records',
    this.quickField,
    this.quickCounts = const {},
    this.extraChips = const [],
  });

  /// The page these filters belong to (saved views are kept per page).
  final String pageKey;
  final List<FilterField> fields;
  final RecordQuery query;
  final ValueChanged<RecordQuery> onChanged;
  final int total, shown;
  final int Function(RecordQuery draft) count;
  final String noun;

  /// A choice field shown as one-tap chips under the search (usually the status), with counts.
  final String? quickField;
  final Map<String, int> quickCounts;

  /// Other active filters the page owns (shown with the rest).
  final List<Widget> extraChips;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final _search = TextEditingController(text: widget.query.search);
  List<(String, RecordQuery)> _views = const [];

  String get _prefsKey => 'views:${widget.pageKey}';

  @override
  void initState() {
    super.initState();
    _loadViews();
  }

  @override
  void didUpdateWidget(FilterBar old) {
    super.didUpdateWidget(old);
    if (widget.query.search != _search.text) _search.text = widget.query.search;
    if (old.pageKey != widget.pageKey) _loadViews();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadViews() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      final list = raw == null ? const [] : jsonDecode(raw) as List;
      if (!mounted) return;
      setState(() => _views = [for (final v in list) ('${v['name']}', RecordQuery.fromJson(Map<String, Object?>.from(v['query'] as Map)))]);
    } catch (_) {
      // Unreadable saved views: start with none.
    }
  }

  Future<void> _storeViews(List<(String, RecordQuery)> views) async {
    setState(() => _views = views);
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode([for (final (name, q) in views) {'name': name, 'query': q.toJson()}]));
    } catch (_) {
      // Not saved on this device; the views still work until the app closes.
    }
  }

  Future<void> _saveView() async {
    final label = await promptText(context, title: 'Save this view', label: 'Name', hint: 'Overdue, high value', action: 'Save');
    if (label == null || !mounted) return;
    await _storeViews([..._views.where((v) => v.$1 != label), (label, widget.query)]);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('View “$label” saved.')));
  }

  FilterField? _field(String key) => widget.fields.where((f) => f.key == key).firstOrNull;

  Future<void> _openPanel() async {
    final result = await showModalBottomSheet<RecordQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (context) => _FilterPanel(fields: widget.fields, query: widget.query, count: widget.count, noun: widget.noun),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final sortable = [for (final f in widget.fields) if (f.kind != FilterKind.boolean) f];
    final sortLabel = q.sortKey == null
        ? 'Sort'
        : q.sortKey == modifiedKey
        ? 'Last modified ${q.ascending ? '↑' : '↓'}'
        : '${_field(q.sortKey!)?.label ?? q.sortKey} ${q.ascending ? '↑' : '↓'}';
    final quick = widget.quickField == null ? null : _field(widget.quickField!);
    final quickSel = q.filters[widget.quickField] is ChoiceFilter ? (q.filters[widget.quickField] as ChoiceFilter).values : const <String>{};

    final search = TextField(
      controller: _search,
      onChanged: (v) => widget.onChanged(q.copyWith(search: v)),
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Search ${widget.noun}',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _search.clear();
                  widget.onChanged(q.copyWith(search: ''));
                },
              ),
      ),
    );
    final filtersButton = Badge(
      isLabelVisible: q.filters.isNotEmpty,
      label: Text('${q.filters.length}'),
      backgroundColor: brand,
      child: OutlinedButton.icon(onPressed: _openPanel, icon: const Icon(Icons.tune), label: const Text('Filters')),
    );
    final sortButton = PopupMenuButton<String>(
      tooltip: 'Sort',
      onSelected: (key) {
        if (key == '') return widget.onChanged(q.copyWith(clearSort: true));
        if (key == '~dir') return widget.onChanged(q.copyWith(ascending: !q.ascending));
        widget.onChanged(q.copyWith(sortKey: key, ascending: key == modifiedKey ? false : q.sortKey == key ? q.ascending : _field(key)?.kind == FilterKind.text || _field(key)?.kind == FilterKind.choice));
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('Default order')),
        PopupMenuItem(value: modifiedKey, child: _check('Last modified (newest first)', q.sortKey == modifiedKey)),
        const PopupMenuDivider(),
        for (final f in sortable) PopupMenuItem(value: f.key, child: _check(f.label, q.sortKey == f.key)),
        if (q.sortKey != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(value: '~dir', child: Text(q.ascending ? 'Switch to descending ↓' : 'Switch to ascending ↑')),
        ],
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5D1)), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sort, size: 18, color: brand),
          const SizedBox(width: 6),
          Flexible(child: Text(sortLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: brand, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
    final viewsButton = PopupMenuButton<Object>(
      tooltip: 'Saved views',
      onSelected: (v) async {
        if (v == 'save') return _saveView();
        if (v case ('apply', final (String, RecordQuery) view)) return widget.onChanged(view.$2);
        if (v case ('delete', final String name)) {
          await _storeViews([..._views.where((x) => x.$1 != name)]);
        }
      },
      itemBuilder: (_) => [
        if (_views.isEmpty) const PopupMenuItem(enabled: false, child: Text('No saved views yet')),
        for (final v in _views)
          PopupMenuItem(
            value: ('apply', v),
            child: Row(children: [
              const Icon(Icons.bookmark_outline, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(v.$1)),
            ]),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: !q.isEmpty || q.sortKey != null, value: 'save', child: const Text('Save current view…')),
        for (final v in _views) PopupMenuItem(value: ('delete', v.$1), child: Text('Delete “${v.$1}”', style: const TextStyle(color: Color(0xFFB3261E)))),
      ],
      child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.bookmarks_outlined, color: brand)),
    );

    final chips = <Widget>[
      ...widget.extraChips,
      for (final e in q.filters.entries)
        if (_field(e.key) case final f?)
          InputChip(
            label: Text(describeFilter(f, e.value)),
            onPressed: _openPanel,
            onDeleted: () => widget.onChanged(q.withFilter(e.key, null)),
            deleteButtonTooltipMessage: 'Remove this filter',
          ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 720;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(children: [Expanded(child: search), const SizedBox(width: 10), filtersButton, const SizedBox(width: 8), sortButton, viewsButton])
            else ...[
              search,
              const SizedBox(height: 8),
              Row(children: [filtersButton, const SizedBox(width: 8), Flexible(child: sortButton), const Spacer(), viewsButton]),
            ],
            if (quick != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: Text('All ${widget.total}'), selected: quickSel.isEmpty, onSelected: (_) => widget.onChanged(q.withFilter(quick.key, null))),
                for (final o in quick.options)
                  FilterChip(
                    label: Text('$o ${widget.quickCounts[o] ?? 0}'),
                    selected: quickSel.contains(o),
                    onSelected: (on) {
                      final next = {...quickSel};
                      on ? next.add(o) : next.remove(o);
                      widget.onChanged(q.withFilter(quick.key, next.isEmpty ? null : ChoiceFilter(next)));
                    },
                  ),
              ]),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ...chips,
                TextButton(
                  onPressed: () {
                    _search.clear();
                    widget.onChanged(RecordQuery(sortKey: q.sortKey, ascending: q.ascending));
                  },
                  child: const Text('Clear all'),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            Text(
              widget.shown == widget.total ? 'Showing all ${widget.total} ${widget.noun}' : 'Showing ${widget.shown} of ${widget.total} ${widget.noun}',
              style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        );
      },
    );
  }

  Widget _check(String label, bool on) => Row(children: [
    Expanded(child: Text(label)),
    if (on) const Icon(Icons.check, size: 18, color: brand),
  ]);
}

/// The Filters panel: one section per field, by its kind, working on a draft; "Show N" applies it.
class _FilterPanel extends StatefulWidget {
  const _FilterPanel({required this.fields, required this.query, required this.count, required this.noun});
  final List<FilterField> fields;
  final RecordQuery query;
  final int Function(RecordQuery) count;
  final String noun;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late RecordQuery _draft = widget.query;
  final _text = <String, TextEditingController>{};
  final _min = <String, TextEditingController>{}, _max = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final current = widget.query.filters[f.key];
      if (f.kind == FilterKind.text) _text[f.key] = TextEditingController(text: current is TextFilter ? current.value : '');
      if (f.kind == FilterKind.number) {
        _min[f.key] = TextEditingController(text: current is RangeFilter && current.min != null ? '${current.min}' : '');
        _max[f.key] = TextEditingController(text: current is RangeFilter && current.max != null ? '${current.max}' : '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in [..._text.values, ..._min.values, ..._max.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, FieldFilter? f) => setState(() => _draft = _draft.withFilter(key, f));

  Widget _section(FilterField f) {
    final current = _draft.filters[f.key];
    final Widget body;
    switch (f.kind) {
      case FilterKind.choice:
        final sel = current is ChoiceFilter ? current.values : const <String>{};
        body = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in f.options)
            FilterChip(
              label: Text(o),
              selected: sel.contains(o),
              onSelected: (on) {
                final next = {...sel};
                on ? next.add(o) : next.remove(o);
                _set(f.key, next.isEmpty ? null : ChoiceFilter(next));
              },
            ),
        ]);
      case FilterKind.text:
        final op = current is TextFilter ? current.op : TextOp.contains;
        void update(TextOp o) {
          final v = _text[f.key]!.text;
          _set(f.key, v.trim().isEmpty ? null : TextFilter(o, v));
        }
        body = Row(children: [
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<TextOp>(
              initialValue: op,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [for (final e in _textOps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (o) => update(o ?? TextOp.contains),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _text[f.key],
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(isDense: true, hintText: 'Type to filter ${f.label.toLowerCase()}'),
              onChanged: (_) => update(op),
            ),
          ),
        ]);
      case FilterKind.number:
        void update() {
          final lo = num.tryParse(_min[f.key]!.text.trim()), hi = num.tryParse(_max[f.key]!.text.trim());
          _set(f.key, lo == null && hi == null ? null : RangeFilter(lo, hi));
        }
        InputDecoration deco(String hint) => InputDecoration(isDense: true, hintText: hint, prefixText: f.money ? '₹ ' : null, suffixText: f.unit.isEmpty ? null : f.unit);
        body = Row(children: [
          Expanded(child: TextField(controller: _min[f.key], keyboardType: TextInputType.number, style: const TextStyle(fontSize: 16), decoration: deco('Min'), onChanged: (_) => update())),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('to')),
          Expanded(child: TextField(controller: _max[f.key], keyboardType: TextInputType.number, style: const TextStyle(fontSize: 16), decoration: deco('Max'), onChanged: (_) => update())),
        ]);
      case FilterKind.date:
        final sel = current is DateFilter ? current : null;
        body = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in DatePreset.values)
            ChoiceChip(
              label: Text(p == DatePreset.custom && sel?.preset == DatePreset.custom ? describeFilter(f, sel!).split(': ').last : _presets[p]!),
              selected: sel?.preset == p,
              onSelected: (on) async {
                if (!on) return _set(f.key, null);
                if (p != DatePreset.custom) return _set(f.key, DateFilter(p));
                final now = DateTime.now();
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  initialDateRange: sel?.from != null && sel?.to != null ? DateTimeRange(start: sel!.from!, end: sel.to!) : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
                );
                if (range != null) _set(f.key, DateFilter(DatePreset.custom, from: range.start, to: range.end));
              },
            ),
        ]);
      case FilterKind.boolean:
        final v = current is BoolFilter ? (current.value ? 'yes' : 'no') : 'any';
        body = SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'any', label: Text('Any')), ButtonSegment(value: 'yes', label: Text('Yes')), ButtonSegment(value: 'no', label: Text('No'))],
          selected: {v},
          onSelectionChanged: (s) => _set(f.key, s.first == 'any' ? null : BoolFilter(s.first == 'yes')),
        );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5))),
          if (current != null)
            TextButton(
              onPressed: () {
                _text[f.key]?.clear();
                _min[f.key]?.clear();
                _max[f.key]?.clear();
                _set(f.key, null);
              },
              child: const Text('Reset'),
            ),
        ]),
        const SizedBox(height: 8),
        body,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count(_draft);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('Filters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () {
                  for (final c in [..._text.values, ..._min.values, ..._max.values]) {
                    c.clear();
                  }
                  setState(() => _draft = _draft.copyWith(filters: const {}));
                },
                child: const Text('Clear filters'),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              children: [for (final f in widget.fields) _section(f)],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: Text(n == 0 ? 'No ${widget.noun} match' : 'Show $n ${widget.noun}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
