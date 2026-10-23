import 'chart_switch.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../format.dart';
import 'admin_search.dart' show AdminNavScope;
import 'charts.dart';
import 'dashboard_widgets.dart';
import 'insights.dart';
import 'nav_config.dart';
import 'nav_pages.dart' show navPageSpecs, rowsFor, demoTone, ColKind, specWithCustom;
import 'repository.dart';
import 'schema.dart';
import 'package:piax_orders_admin/palette.dart';

// The Analytics page's "every dataset" part: one small card per set of records in the admin app (the admin modules
// and every section page), each with the charts its fields allow: statuses as a split bar, the main breakdown as
// bars, records per week as columns, and the number fields as figures. Grouped like the menus, with a search.
// Module records come from the module data (bundled dummy data); section pages are demo
// data, and say so.

class _Dataset {
  _Dataset({
    required this.group,
    required this.title,
    required this.total,
    required this.noun,
    this.demo = false,
    this.statuses = const [],
    this.breakdownTitle,
    this.breakdown = const [],
    this.money = false,
    this.weekly,
    this.weeklyTitle,
    this.weeklyDetails,
    this.facts = const [],
    this.open,
  });
  final String group, title, noun;
  final int total;
  final bool demo, money;
  final List<Slice> statuses, breakdown;
  final String? breakdownTitle, weeklyTitle;
  final List<int>? weekly;
  final List<String>? weeklyDetails;
  final List<(String, String)> facts;
  final VoidCallback? open;
}

class AllDataCharts extends StatefulWidget {
  const AllDataCharts({super.key, required this.api});
  final AdminApi api;

  @override
  State<AllDataCharts> createState() => _AllDataChartsState();
}

class _AllDataChartsState extends State<AllDataCharts> {
  ModuleRepository? _repo;
  String? _error;
  String _group = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    ModuleRepository.open(widget.api).then((r) {
      if (mounted) setState(() => _repo = r);
    }, onError: (_) {
      if (mounted) setState(() => _error = 'Couldn’t load the module data.');
    });
  }

  List<_Dataset> _datasets(ModuleRepository repo) {
    final nav = AdminNavScope.maybeOf(context);
    final now = DateTime.now();
    final out = <_Dataset>[];
    for (final m in modules) {
      final i = analyse(m, repo.records(m.key), now: now);
      final b = i.breakdowns.firstOrNull;
      final d = i.dates.where((d) => d.weekly.any((v) => v > 0)).firstOrNull;
      final grouping = weeklyGrouping(m);
      final groups = d == null || grouping == null ? null : weeklyGroups(repo.records(m.key), d.field.key, grouping.$2, now: now);
      out.add(_Dataset(
        group: m.group,
        title: m.title,
        total: i.total,
        noun: m.title.toLowerCase(),
        statuses: i.statuses,
        breakdownTitle: b == null ? null : 'By ${b.field.label.toLowerCase()}',
        breakdown: b?.slices.take(5).toList() ?? const [],
        weekly: d?.weekly,
        weeklyTitle: d == null ? null : '${d.field.label}, per week',
        weeklyDetails: groups == null ? null : [for (final g in groups) breakdownText(g, title: grouping!.$1)],
        facts: [for (final n in i.numbers.take(3)) (n.headlineLabel, n.headline)],
        open: nav == null ? null : () => nav.module(m.key),
      ));
    }
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final start = monday.subtract(const Duration(days: 7 * 11));
    for (final section in navSections) {
      for (final item in section.items) {
        final base = navPageSpecs[item.id];
        if (base == null) continue;
        final spec = specWithCustom(item.id, base); // without the fields the team deleted
        final rows = rowsFor(item.id, spec);
        final status = spec.first(ColKind.status), money = spec.first(ColKind.money), date = spec.first(ColKind.date), pick = spec.first(ColKind.pick);
        final number = spec.columns.where((c) => (c.kind == ColKind.number || c.kind == ColKind.percent) && !c.custom && !c.hidden).firstOrNull;
        final statusCounts = <String, int>{}, byPick = <String, int>{};
        final weekly = List<int>.filled(12, 0);
        final groupCol = status ?? pick;
        final weekGroups = [for (var i = 0; i < 12; i++) <String, int>{}];
        var moneySum = 0, numSum = 0;
        for (final r in rows) {
          if (status != null) statusCounts['${r[status.label]}'] = (statusCounts['${r[status.label]}'] ?? 0) + 1;
          if (pick != null) byPick['${r[pick.label]}'] = (byPick['${r[pick.label]}'] ?? 0) + (money == null ? 1 : r[money.label] as int);
          if (money != null) moneySum += r[money.label] as int;
          if (number != null) numSum += r[number.label] as int;
          if (date != null) {
            final at = r[date.label] as DateTime;
            final w = DateTime(at.year, at.month, at.day).difference(start).inDays ~/ 7;
            if (w >= 0 && w < 12 && !at.isAfter(now)) {
              weekly[w]++;
              if (groupCol != null) weekGroups[w]['${r[groupCol.label]}'] = (weekGroups[w]['${r[groupCol.label]}'] ?? 0) + 1;
            }
          }
        }
        final avg = rows.isEmpty ? 0.0 : numSum / rows.length;
        out.add(_Dataset(
          group: '${section.numbered} ${section.label}',
          title: item.label,
          total: rows.length,
          noun: spec.plural,
          demo: true,
          statuses: [
            for (final e in statusCounts.entries)
              () {
                final base = demoTone(e.key).$2;
                return Slice(e.key, e.value, base);
              }(),
          ],
          breakdownTitle: pick == null ? null : '${money == null ? 'Count' : money.label} by ${pick.label.toLowerCase()}',
          breakdown: [for (final e in (byPick.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5)) Slice(e.key, e.value, chartPalette[0])],
          money: money != null,
          weekly: date == null || weekly.every((v) => v == 0) ? null : weekly,
          weeklyTitle: date == null ? null : '${spec.plural[0].toUpperCase()}${spec.plural.substring(1)} per week, by ${date.label.toLowerCase()}',
          weeklyDetails: groupCol == null ? null : [for (final g in weekGroups) breakdownText(g, title: 'By ${groupCol.label.toLowerCase()}')],
          facts: [
            if (money != null) ('${money.label} · total', rupees(moneySum)),
            if (number != null)
              ('${number.label} · average', number.kind == ColKind.percent ? '${avg.toStringAsFixed(1)}%' : '${NumberFormat.decimalPattern('en_IN').format(avg.round())}${number.unit.isEmpty ? '' : ' ${number.unit}'}'),
          ],
          open: nav?.item == null ? null : () => nav!.item!(item.id),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Every dataset', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ink)),
      const SizedBox(height: 3),
      Text(
        'Charts for every set of records in the admin app.',
        style: const TextStyle(color: muted, fontSize: 13),
      ),
      const SizedBox(height: 12),
    ]);
    if (_error != null) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Text(_error!, style: const TextStyle(color: muted))]);
    if (repo == null) return Column(children: [header, const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())]);

    final all = _datasets(repo);
    final groups = ['All', ...{for (final d in all) d.group}];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final d in all)
        if ((_group == 'All' || d.group == _group) && (q.isEmpty || '${d.title} ${d.group}'.toLowerCase().contains(q))) d,
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = math.max(1, (box.maxWidth / 360).floor()).clamp(1, 5);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: math.min(260.0, box.maxWidth),
            child: TextField(
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search, size: 20), hintText: 'Find a dataset', border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 16),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            width: math.min(340.0, box.maxWidth),
            child: DropdownButton<String>(
              value: _group,
              isExpanded: true,
              underline: const SizedBox(),
              items: [
                for (final g in groups)
                  DropdownMenuItem(value: g, child: Text(g == 'All' ? 'All groups (${all.length})' : '$g (${all.where((d) => d.group == g).length})', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (g) => setState(() => _group = g ?? 'All'),
            ),
          ),
          Text('${shown.length} shown', style: const TextStyle(color: muted, fontSize: 13)),
        ]),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('No dataset matches.', style: TextStyle(color: muted)))
        else
          EqualRows(columns: cols, gap: 14, children: [for (final d in shown) _DatasetCard(d: d)]),
      ]);
    });
  }
}

class _DatasetCard extends StatelessWidget {
  const _DatasetCard({required this.d});
  final _Dataset d;

  static const _sub = TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: .3);

  @override
  Widget build(BuildContext context) {
    final compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final weekly = d.weekly;
    return ChartSwitchHost(id: 'dataset: ${d.title}', builder: (context, button) => Material(
      color: TColor(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: d.open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: ink)),
                  Text(d.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11.5)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(NumberFormat.decimalPattern('en_IN').format(d.total), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: brand)),
              ]),
              ?button,
            ]),
            if (d.facts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final (label, value) in d.facts)
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '$label  ', style: const TextStyle(color: muted)),
                    TextSpan(text: value, style: const TextStyle(color: ink, fontWeight: FontWeight.w600)),
                  ]), style: const TextStyle(fontSize: 12)),
              ]),
            ],
            if (d.statuses.any((s) => s.count > 0)) ...[
              const SizedBox(height: 10),
              const Text('BY STATUS', style: _sub),
              const SizedBox(height: 6),
              SplitBar(slices: d.statuses),
            ],
            if (d.breakdown.isNotEmpty && d.breakdownTitle != null) ...[
              const SizedBox(height: 10),
              Text(d.breakdownTitle!.toUpperCase(), style: _sub),
              const SizedBox(height: 4),
              BarList(dense: true, slices: d.breakdown, format: d.money ? rupees : null),
            ],
            if (weekly != null) ...[
              const SizedBox(height: 10),
              Text((d.weeklyTitle ?? 'Per week').toUpperCase(), style: _sub),
              const SizedBox(height: 6),
              SizedBox(
                height: 64,
                child: AreaTrend(
                  bars: [for (final (k, v) in weekly.indexed) (k == 11 ? 'This wk' : '${11 - k}w ago', v)],
                  format: d.money ? (v) => compact.format(v) : null,
                  details: d.weeklyDetails,
                ),
              ),
            ],
            if (d.statuses.isEmpty && d.breakdown.isEmpty && weekly == null && d.facts.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('${d.total} ${d.noun}; nothing to chart.', style: const TextStyle(color: muted, fontSize: 12))),
          ]),
        ),
      ),
    ));
  }
}
