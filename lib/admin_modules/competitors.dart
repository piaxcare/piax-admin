import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart' show brand;
import 'admin_search.dart' show globalSearchActions;
import 'charts.dart';
import 'insights.dart' show Slice, chartPalette;
import 'nav_widgets.dart' show PageTreeSlot;
import 'package:piax_orders_admin/palette.dart';

// Competitor Comparison (Executive Command Centre): PIAX next to its direct competitors on price, product, reach,
// service and reputation, metric by metric. Each cell shows whether PIAX leads or trails, and "Where to improve" lists
// the biggest gaps with what to do about them. Competitors and every figure are the team's own research, edited on the
// page and kept on this device; the page starts with sample figures, labelled as such, until they're replaced.

/// What's compared. [higherBetter] decides who leads (a lower price or a faster delivery wins).
class CompMetric {
  const CompMetric(this.key, this.label, this.group, {this.unit = '', this.higherBetter = true, this.yesNo = false, this.money = false, required this.advice});
  final String key, label, group, unit;
  final bool higherBetter, yesNo, money;

  /// What to work on when PIAX trails here.
  final String advice;

  String show(num? v) {
    if (v == null) return '—';
    if (yesNo) return v > 0 ? 'Yes' : 'No';
    final n = NumberFormat.decimalPattern('en_IN').format(v);
    return money ? '₹$n' : unit.isEmpty ? n : '$n $unit';
  }
}

const compMetrics = <CompMetric>[
  CompMetric('price', 'Price per pad', 'Price & product', money: true, higherBetter: false,
      advice: 'Review pack pricing or add a value pack; show the per-pad price on product pages.'),
  CompMetric('pack', 'Pads per pack', 'Price & product', unit: 'pads', advice: 'Offer a larger pack for regular buyers.'),
  CompMetric('organic', 'Organic / biodegradable', 'Price & product', yesNo: true, advice: 'Plan a biodegradable or organic range.'),
  CompMetric('range', 'Products in range', 'Price & product', advice: 'Fill gaps in the range (overnight, liners, teen sizes).'),
  CompMetric('rating', 'Average rating', 'Reputation', unit: '★', advice: 'Follow up low ratings, fix the top complaints, and ask happy buyers for reviews.'),
  CompMetric('reviews', 'Reviews', 'Reputation', advice: 'Ask for a review after the second delivery.'),
  CompMetric('followers', 'Social followers', 'Reputation', unit: 'k', advice: 'Grow creator programs and Learn content on social channels.'),
  CompMetric('delivery', 'Delivery time', 'Service & reach', unit: 'days', higherBetter: false,
      advice: 'Add warehouses near the biggest cities or a faster courier for metros.'),
  CompMetric('cities', 'Cities served', 'Service & reach', advice: 'Open the next cities by demand from the website.'),
  CompMetric('machines', 'Vending machines', 'Service & reach', advice: 'Place more machines in colleges, offices and transit hubs.'),
  CompMetric('subscription', 'Subscription', 'Service & reach', yesNo: true, advice: 'Offer a monthly subscription with a small discount.'),
  CompMetric('returns', 'Return window', 'Service & reach', unit: 'days', advice: 'Lengthen the return window to build trust.'),
];

/// A brand on the page: PIAX ([ours]) or a competitor, with a value per metric key.
class Brand {
  Brand({required this.id, required this.name, required this.values, this.ours = false, this.note = ''});
  final String id;
  String name, note;
  final bool ours;
  final Map<String, num> values;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'note': note, 'ours': ours, 'values': values};

  static Brand fromJson(Map<String, dynamic> j) => Brand(
    id: '${j['id']}',
    name: '${j['name']}',
    note: '${j['note'] ?? ''}',
    ours: j['ours'] == true,
    values: {for (final e in ((j['values'] as Map?) ?? {}).entries) '${e.key}': e.value as num},
  );
}

/// The brands, kept on this device. Starts with sample figures ([sample] until the team changes anything).
class CompetitorStore extends ChangeNotifier {
  CompetitorStore._();
  static final instance = CompetitorStore._();
  static const _key = 'competitors';

  List<Brand> brands = _samples();
  bool sample = true;
  bool _loaded = false;

  static List<Brand> _samples() => [
    Brand(id: 'piax', name: 'PIAX', ours: true, values: {
      'price': 9, 'pack': 20, 'organic': 1, 'range': 5, 'rating': 4.4, 'reviews': 1800, 'followers': 24,
      'delivery': 4, 'cities': 38, 'machines': 120, 'subscription': 1, 'returns': 7,
    }),
    Brand(id: 'c1', name: 'Competitor A', note: 'Mass-market leader (sample)', values: {
      'price': 7, 'pack': 30, 'organic': 0, 'range': 14, 'rating': 4.1, 'reviews': 52000, 'followers': 410,
      'delivery': 3, 'cities': 600, 'machines': 0, 'subscription': 0, 'returns': 7,
    }),
    Brand(id: 'c2', name: 'Competitor B', note: 'Premium organic D2C (sample)', values: {
      'price': 14, 'pack': 15, 'organic': 1, 'range': 9, 'rating': 4.6, 'reviews': 9400, 'followers': 180,
      'delivery': 5, 'cities': 120, 'machines': 0, 'subscription': 1, 'returns': 10,
    }),
    Brand(id: 'c3', name: 'Competitor C', note: 'Vending and institutional (sample)', values: {
      'price': 10, 'pack': 10, 'organic': 0, 'range': 4, 'rating': 3.9, 'reviews': 900, 'followers': 6,
      'delivery': 6, 'cities': 22, 'machines': 450, 'subscription': 0, 'returns': 0,
    }),
  ];

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      brands = [for (final b in j['brands'] as List) Brand.fromJson(b as Map<String, dynamic>)];
      sample = j['sample'] == true;
      notifyListeners();
    } catch (_) {
      // Unreadable: the sample figures.
    }
  }

  void _save() {
    sample = false;
    notifyListeners();
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key, jsonEncode({'sample': sample, 'brands': [for (final b in brands) b.toJson()]})))
        .catchError((_) => false);
  }

  void put(Brand b) {
    final i = brands.indexWhere((x) => x.id == b.id);
    i < 0 ? brands.add(b) : brands[i] = b;
    _save();
  }

  void remove(Brand b) {
    brands.removeWhere((x) => x.id == b.id);
    _save();
  }

  void reset() {
    brands = _samples();
    sample = true;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.remove(_key)).catchError((_) => false);
  }

  Brand get ours => brands.firstWhere((b) => b.ours);
  List<Brand> get rivals => [for (final b in brands) if (!b.ours) b];
}

/// Who's best on [m] among [brands] (null when nobody has a figure).
num? bestOf(CompMetric m, List<Brand> brands) {
  final vs = [for (final b in brands) ?b.values[m.key]];
  if (vs.isEmpty) return null;
  return m.higherBetter ? vs.reduce(math.max) : vs.reduce(math.min);
}

/// 0–100: how close [b] is to the best on [m] (100 = the best).
double scoreOf(CompMetric m, Brand b, List<Brand> brands) {
  final v = b.values[m.key];
  final vs = [for (final x in brands) ?x.values[m.key]];
  if (v == null || vs.isEmpty) return 0;
  final lo = vs.reduce(math.min), hi = vs.reduce(math.max);
  if (hi == lo) return 100;
  final f = (v - lo) / (hi - lo);
  return (m.higherBetter ? f : 1 - f) * 100;
}

/// A gap where PIAX trails the best competitor: the metric, PIAX's figure, the leader and theirs.
typedef Gap = ({CompMetric metric, num ours, Brand leader, num theirs, double behind});

List<Gap> gapsFor(List<Brand> brands) {
  final ours = brands.firstWhere((b) => b.ours);
  final gaps = <Gap>[];
  for (final m in compMetrics) {
    final mine = ours.values[m.key];
    if (mine == null) continue;
    Brand? leader;
    for (final b in brands) {
      final v = b.values[m.key];
      if (b.ours || v == null) continue;
      final better = m.higherBetter ? v > mine : v < mine;
      if (better && (leader == null || (m.higherBetter ? v > leader.values[m.key]! : v < leader.values[m.key]!))) leader = b;
    }
    if (leader == null) continue;
    gaps.add((metric: m, ours: mine, leader: leader, theirs: leader.values[m.key]!, behind: 100 - scoreOf(m, ours, brands)));
  }
  gaps.sort((a, b) => b.behind.compareTo(a.behind));
  return gaps;
}

class CompetitorComparisonScreen extends StatefulWidget {
  const CompetitorComparisonScreen({super.key});

  @override
  State<CompetitorComparisonScreen> createState() => _CompetitorComparisonScreenState();
}

class _CompetitorComparisonScreenState extends State<CompetitorComparisonScreen> {
  CompetitorStore get store => CompetitorStore.instance;

  /// The competitor in the head-to-head; null is all of them.
  String? _versus;
  String _group = 'All';

  @override
  void initState() {
    super.initState();
    store.load();
  }

  static const _good = TColor(0xFF0B7A55), _bad = TColor(0xFFB3261E), _muted = TColor(0xFF5A6C68), _ink = TColor(0xFF0C1C19);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final brands = store.brands;
      final versus = brands.where((b) => b.id == _versus && !b.ours).firstOrNull;
      final shown = versus == null ? brands : [store.ours, versus];
      return Scaffold(
        backgroundColor: const TColor(0xFFF2F6F5),
        appBar: AppBar(
          title: const Text('Competitor comparison', style: TextStyle(fontWeight: FontWeight.w600)),
          actions: [
            ...globalSearchActions(context),
            if (MediaQuery.sizeOf(context).width >= 600)
              TextButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Add competitor'))
            else
              IconButton.filled(tooltip: 'Add competitor', onPressed: () => _edit(null), icon: const Icon(Icons.add)),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => store.reset(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Start again with sample figures'))],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final pad = w >= 900 ? 28.0 : 16.0;
          final inner = math.min(w - pad * 2, 1600.0);
          final wide = inner >= 1100, medium = inner >= 700;
          const gap = 18.0;
          final metrics = [for (final m in compMetrics) if (_group == 'All' || m.group == _group) m];
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: inner + pad * 2,
              child: ListView(
                key: const Key('competitor-scroll'),
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                children: [
                  const PageTreeSlot(bottom: 10),
                  Text(
                    'PIAX next to its direct competitors on price, product, reputation, service and reach. Green: PIAX leads; red: PIAX trails.',
                    style: const TextStyle(color: _muted, fontSize: 13.5),
                  ),
                  if (store.sample) ...[const SizedBox(height: 12), _sampleNotice()],
                  const SizedBox(height: 16),
                  _brands(brands),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('Compare with', style: TextStyle(fontWeight: FontWeight.w600, color: _ink)),
                    ChoiceChip(label: const Text('All competitors'), selected: versus == null, onSelected: (_) => setState(() => _versus = null)),
                    for (final b in store.rivals) ChoiceChip(label: Text(b.name), selected: versus?.id == b.id, onSelected: (_) => setState(() => _versus = b.id)),
                  ]),
                  const SizedBox(height: gap),
                  _summary(shown, medium),
                  const SizedBox(height: gap),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: _radar(shown)),
                        const SizedBox(width: gap),
                        Expanded(child: _improve(shown)),
                      ]),
                    )
                  else ...[_radar(shown), const SizedBox(height: gap), _improve(shown)],
                  const SizedBox(height: gap),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in ['All', ...{for (final m in compMetrics) m.group}])
                      ChoiceChip(label: Text(g), selected: _group == g, onSelected: (_) => setState(() => _group = g)),
                  ]),
                  const SizedBox(height: 12),
                  _table(shown, metrics),
                  const SizedBox(height: gap),
                  EqualRows(
                    columns: inner >= 1400 ? 3 : medium ? 2 : 1,
                    gap: gap,
                    children: [
                      for (final m in metrics.where((m) => !m.yesNo))
                        ChartCard(
                          title: m.label,
                          note: m.higherBetter ? 'Higher is better.' : 'Lower is better.',
                          child: BarList(
                            slices: [
                              for (final (i, b) in shown.indexed)
                                if (b.values[m.key] != null) Slice(b.name, (b.values[m.key]! * (m.unit == '★' ? 10 : 1)).round(), b.ours ? brand : chartPalette[(i + 1) % chartPalette.length]),
                            ],
                            format: (v) => m.show(m.unit == '★' ? v / 10 : v),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      );
    },
  );

  Widget _card({required String title, String? note, required Widget child}) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(color: const TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const TColor(0xFFE6ECEA))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: _ink)),
      if (note != null) ...[const SizedBox(height: 3), Text(note, style: const TextStyle(color: _muted, fontSize: 12.5))],
      const SizedBox(height: 14),
      child,
    ]),
  );

  Widget _sampleNotice() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const TColor(0xFFFFF4D6), borderRadius: BorderRadius.circular(14)),
    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 20, color: TColor(0xFF8A5A00)),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'These are sample figures. Tap a brand below to enter your own research (competitor names, prices, ratings, reach); '
          'your figures are kept on this device.',
          style: TextStyle(color: TColor(0xFF6B4700), fontSize: 13),
        ),
      ),
    ]),
  );

  Widget _brands(List<Brand> brands) => Wrap(spacing: 10, runSpacing: 10, children: [
    for (final b in brands)
      ActionChip(
        avatar: CircleAvatar(
          backgroundColor: b.ours ? brand : const TColor(0xFFE1E8E6),
          child: Text(b.name.isEmpty ? '?' : b.name[0].toUpperCase(), style: TextStyle(fontSize: 12, color: b.ours ? Colors.white : _ink)),
        ),
        label: Text(b.ours ? '${b.name} (us)' : b.name),
        tooltip: b.note.isEmpty ? 'Edit ${b.name}' : b.note,
        onPressed: () => _edit(b),
      ),
  ]);

  /// Overall score, leads and gaps for PIAX against [shown].
  Widget _summary(List<Brand> shown, bool medium) {
    final ours = store.ours;
    double overall(Brand b) => compMetrics.map((m) => scoreOf(m, b, shown)).fold<double>(0, (a, s) => a + s) / compMetrics.length;
    final ranked = [...shown]..sort((a, b) => overall(b).compareTo(overall(a)));
    final rank = ranked.indexOf(ours) + 1;
    var leads = 0, trails = 0;
    for (final m in compMetrics) {
      final v = ours.values[m.key], best = bestOf(m, shown);
      if (v == null || best == null) continue;
      v == best ? leads++ : trails++;
    }
    Widget tile(String label, String value, Color c, IconData icon) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const TColor(0xFFFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const TColor(0xFFE6ECEA))),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: c)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _ink)),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: _muted)),
          ]),
        ),
      ]),
    );
    return EqualRows(columns: medium ? 4 : 2, gap: 12, children: [
      tile('PIAX score out of 100', overall(ours).round().toString(), brand, Icons.speed),
      tile('Rank among ${shown.length} brands', '#$rank', const TColor(0xFF5B3F73), Icons.emoji_events_outlined),
      tile('Metrics where PIAX leads', '$leads', _good, Icons.trending_up),
      tile('Metrics where PIAX trails', '$trails', _bad, Icons.trending_down),
    ]);
  }

  Widget _radar(List<Brand> shown) {
    final colors = [brand, ...chartPalette.skip(1)];
    return _card(
      title: 'Scorecard',
      note: 'Each metric scored 0–100 against the brands shown (100 = best).',
      child: Column(children: [
        SizedBox(
          height: 300,
          child: RadarChart(RadarChartData(
            radarShape: RadarShape.polygon,
            tickCount: 4,
            ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
            gridBorderData: const BorderSide(color: TColor(0xFFE1E8E6)),
            radarBorderData: const BorderSide(color: TColor(0xFFD3DDDA)),
            titleTextStyle: const TextStyle(fontSize: 10.5, color: _muted),
            getTitle: (i, _) => RadarChartTitle(text: compMetrics[i].label.split(' ').first),
            dataSets: [
              for (final (i, b) in shown.indexed)
                RadarDataSet(
                  fillColor: colors[i % colors.length].withValues(alpha: b.ours ? .25 : .06),
                  borderColor: colors[i % colors.length],
                  borderWidth: b.ours ? 2.5 : 1.5,
                  entryRadius: 2,
                  dataEntries: [for (final m in compMetrics) RadarEntry(value: scoreOf(m, b, shown))],
                ),
            ],
          )),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final (i, b) in shown.indexed)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(b.name, style: TextStyle(fontSize: 12.5, fontWeight: b.ours ? FontWeight.w700 : FontWeight.w500)),
            ]),
        ]),
      ]),
    );
  }

  Widget _improve(List<Brand> shown) {
    final gaps = gapsFor(shown);
    return _card(
      title: 'Where to improve',
      note: 'Where PIAX trails, biggest gap first, with the brand doing best.',
      child: gaps.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('PIAX leads on every metric shown.', style: TextStyle(color: _good)))
          : Column(children: [
              for (final g in gaps.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _bad.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
                      child: Text('−${g.behind.round()}', style: const TextStyle(color: _bad, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.metric.label, style: const TextStyle(fontWeight: FontWeight.w600, color: _ink)),
                        Text('PIAX ${g.metric.show(g.ours)} · ${g.leader.name} ${g.metric.show(g.theirs)}', style: const TextStyle(fontSize: 12.5, color: _muted)),
                        const SizedBox(height: 2),
                        Text(g.metric.advice, style: const TextStyle(fontSize: 12.5, color: _ink)),
                      ]),
                    ),
                  ]),
                ),
            ]),
    );
  }

  Widget _table(List<Brand> shown, List<CompMetric> metrics) {
    final ours = store.ours;
    return _card(
      title: 'Side by side',
      note: 'Tap a brand’s name to edit its figures.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 52,
          columnSpacing: 22,
          columns: [
            const DataColumn(label: Text('Metric', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final b in shown)
              DataColumn(
                label: InkWell(
                  onTap: () => _edit(b),
                  child: Text(b.name, style: TextStyle(fontWeight: FontWeight.w700, color: b.ours ? brand : _ink, decoration: TextDecoration.underline)),
                ),
              ),
          ],
          rows: [
            for (final m in metrics)
              DataRow(cells: [
                DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(m.group, style: const TextStyle(fontSize: 11, color: _muted)),
                ])),
                for (final b in shown) DataCell(_cell(m, b, ours, shown)),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _cell(CompMetric m, Brand b, Brand ours, List<Brand> shown) {
    final v = b.values[m.key];
    final best = bestOf(m, shown);
    final isBest = v != null && v == best;
    // PIAX's cells: green where it leads, red where it trails. A competitor's: red where it beats PIAX.
    Color? tone;
    final mine = ours.values[m.key];
    if (v != null && mine != null) {
      if (b.ours) {
        tone = isBest ? _good : _bad;
      } else if (m.higherBetter ? v > mine : v < mine) {
        tone = _bad;
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(m.show(v), style: TextStyle(fontWeight: b.ours || isBest ? FontWeight.w700 : FontWeight.w500, color: tone ?? _ink)),
      if (isBest) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.emoji_events, size: 14, color: TColor(0xFFE0A33A))),
    ]);
  }

  Future<void> _edit(Brand? brand0) async {
    final saved = await showDialog<Brand?>(context: context, builder: (_) => _BrandDialog(brand: brand0));
    if (saved != null) store.put(saved);
  }
}

/// Adds or edits a brand: its name, a note, and its figure for each metric. Competitors can be removed.
class _BrandDialog extends StatefulWidget {
  const _BrandDialog({this.brand});
  final Brand? brand;

  @override
  State<_BrandDialog> createState() => _BrandDialogState();
}

class _BrandDialogState extends State<_BrandDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.brand?.name ?? '');
  late final _note = TextEditingController(text: widget.brand?.note ?? '');
  late final _values = {
    for (final m in compMetrics) m.key: TextEditingController(text: widget.brand?.values[m.key]?.toString() ?? ''),
  };
  late final _flags = {for (final m in compMetrics) if (m.yesNo) m.key: (widget.brand?.values[m.key] ?? 0) > 0};

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      Brand(
        id: widget.brand?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim(),
        note: _note.text.trim(),
        ours: widget.brand?.ours ?? false,
        values: {
          for (final m in compMetrics)
            if (m.yesNo) m.key: _flags[m.key]! ? 1 : 0 else m.key: ?num.tryParse(_values[m.key]!.text.trim()),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brand;
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(b == null ? 'Add a competitor' : 'Edit ${b.name}'),
      insetPadding: EdgeInsets.symmetric(horizontal: size.width < 600 ? 12 : 40, vertical: 24),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: ListView(shrinkWrap: true, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Brand name *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Name the brand.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note', hintText: 'Positioning, source of the figures…')),
            for (final g in {for (final m in compMetrics) m.group}) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
                child: Text(g.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .8, fontWeight: FontWeight.w700, color: TColor(0xFF7A8C88))),
              ),
              for (final m in compMetrics.where((m) => m.group == g))
                m.yesNo
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.label),
                        value: _flags[m.key]!,
                        onChanged: (v) => setState(() => _flags[m.key] = v),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextFormField(
                          controller: _values[m.key],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: m.label,
                            prefixText: m.money ? '₹ ' : null,
                            suffixText: m.unit.isEmpty ? null : m.unit,
                            helperText: m.higherBetter ? null : 'Lower is better',
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty || num.tryParse(v!.trim()) != null ? null : 'Enter a number.',
                        ),
                      ),
            ],
          ]),
        ),
      ),
      actions: [
        if (b != null && !b.ours)
          TextButton(
            style: TextButton.styleFrom(backgroundColor: const TColor(0xFFB3261E)),
            onPressed: () {
              CompetitorStore.instance.remove(b);
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
