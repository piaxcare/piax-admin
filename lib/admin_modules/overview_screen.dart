import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'charts.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart';
import 'insights.dart';
import 'repository.dart';
import 'revenue_section.dart';
import 'schema.dart';

// The unified admin dashboard, laid out like a modern commerce admin in the app's own colours and font:
//   1. Three big numbers (subscription income, members, app rating) with their change, and a ring of stock by
//      product beside them.
//   2. Activity over the weeks (with a period picker) and a health gauge: how much of everything is running well.
//   3. Members by city, the member journey (accounts → plan → active → repeat buyers) and Learn views by category.
//   4. Needs attention, everything else at a glance, quick actions, more charts, and every module in one line.

/// Opens a module list: optionally filtered to a status or a custom filter.
typedef OpenModule = void Function(String module, {String? status, ListPreset? preset});

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key, required this.repo, required this.onOpen, this.onAdd, this.header, this.onOpenOrders});
  final ModuleRepository repo;
  final OpenModule onOpen;

  /// Opens a module's "add" form (the quick actions).
  final void Function(String module)? onAdd;

  /// Shown above everything (the source notice).
  final Widget? header;

  /// Opens the order desk, from the revenue and orders section.
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final attention = attentionItems(repo, now: now);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final pad = w >= 900 ? 28.0 : 16.0;
        final inner = (w - pad * 2).clamp(0.0, 1500.0);
        const gap = 18.0;
        final wide = inner >= 1180, medium = inner >= 720;
        final chartCols = inner >= 1150 ? 3 : medium ? 2 : 1;
        double tile(int cols) => (inner - gap * (cols - 1)) / cols;

        final cards = headlineCards(repo, now: now);
        final heads = [for (final (i, c) in cards.indexed) HeadlineStatCard(card: c, highlight: i == 0, onTap: () => onOpen(c.module))];
        final activity = weeklyActivity(repo, now: now);
        final activityCard = ActivityCard(all: activity.all, members: activity.members, now: now);
        final health = _health();
        final stock = _stock();
        final cities = _cities(now);
        final funnel = DashCard(
          title: 'Member journey',
          subtitle: 'From signing up to buying again.',
          trailing: SeeAll(onTap: () => onOpen('members')),
          child: medium ? FunnelChart(steps: memberFunnel(repo)) : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 600, height: 240, child: FunnelChart(steps: memberFunnel(repo)))),
        );
        final learn = _learnShare();
        Widget fixed(double h, Widget child) => SizedBox(height: h, child: child);
        Widget row(double h, List<(int, Widget)> parts) => SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (flex, child)) in parts.indexed) ...[if (i > 0) const SizedBox(width: gap), Expanded(flex: flex, child: child)],
            ],
          ),
        );

        final List<Widget> top;
        if (wide) {
          top = [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(children: [
                    row(140, [for (final h in heads) (1, h)]),
                    const SizedBox(height: gap),
                    row(400, [(2, activityCard), (1, health)]),
                  ]),
                ),
                const SizedBox(width: gap),
                Expanded(child: fixed(140 + gap + 400, stock)),
              ],
            ),
            const SizedBox(height: gap),
            row(380, [(1, cities), (2, funnel), (1, learn)]),
          ];
        } else if (medium) {
          top = [
            row(140, [for (final h in heads) (1, h)]),
            const SizedBox(height: gap),
            fixed(360, activityCard),
            const SizedBox(height: gap),
            row(480, [(1, health), (1, stock)]),
            const SizedBox(height: gap),
            row(380, [(1, cities), (1, learn)]),
            const SizedBox(height: gap),
            fixed(330, funnel),
          ];
        } else {
          top = [
            for (final h in heads) ...[fixed(140, h), const SizedBox(height: 12)],
            fixed(340, activityCard),
            const SizedBox(height: gap),
            fixed(390, health),
            const SizedBox(height: gap),
            fixed(490, stock),
            const SizedBox(height: gap),
            fixed(390, cities),
            const SizedBox(height: gap),
            fixed(330, funnel),
            const SizedBox(height: gap),
            fixed(370, learn),
          ];
        }

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: inner + pad * 2,
            child: ListView(
              key: const Key('overview-scroll'),
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
              children: [
                if (header != null) ...[header!, const SizedBox(height: gap)],
                ...top,
                const SizedBox(height: 30),
                RevenueSection(repo: repo, onOpenOrders: onOpenOrders),
                const SizedBox(height: 30),
                EqualRows(
                  columns: medium ? 2 : 1,
                  gap: gap,
                  children: [_AttentionCard(items: attention, onOpen: onOpen), _OperationsCard(repo: repo, onOpen: onOpen, now: now)],
                ),
                if (onAdd != null) ...[
                  const SizedBox(height: 22),
                  const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF34443F))),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (key, label, icon) in const [
                        ('products', 'Add a product', Icons.add_box_outlined),
                        ('articles', 'Write a Learn article', Icons.edit_note),
                        ('banners', 'New banner', Icons.campaign_outlined),
                        ('pages', 'Add a website page', Icons.web_outlined),
                        ('doctors', 'Add a doctor', Icons.medical_services_outlined),
                        ('staff', 'Invite staff', Icons.person_add_alt),
                        ('credentials', 'Add an integration', Icons.key_outlined),
                        ('appUpdates', 'Plan an app update', Icons.system_update_outlined),
                      ])
                        ActionChip(avatar: Icon(icon, size: 18, color: brand), label: Text(label), onPressed: () => onAdd!(key)),
                    ],
                  ),
                ],
                const SizedBox(height: 30),
                const _SectionTitle('More breakdowns', 'Statuses, places, plans and favourites across the modules.'),
                const SizedBox(height: 12),
                EqualRows(columns: chartCols, gap: gap, children: _charts(beside: DonutChart.fitsBeside(tile(chartCols) - 36), fill: chartCols > 1)),
                const SizedBox(height: 30),
                const _SectionTitle('Every module', 'What each module holds, in one line. Tap one to see its records and charts.'),
                for (final group in moduleGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                    child: Text(group.toUpperCase(), style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
                  ),
                  EqualRows(
                    columns: chartCols,
                    gap: gap,
                    children: [
                      for (final m in modules.where((m) => m.group == group))
                        _ModuleSummaryCard(insight: analyse(m, repo.records(m.key), now: now), onTap: () => onOpen(m.key)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Health gauge: the share of everything with a status that's running well (live, active, connected…).
  Widget _health() {
    final h = healthCounts(repo);
    final total = h.good + h.waiting + h.stopped;
    final pct = total == 0 ? 0.0 : h.good * 100 / total;
    final (title, line) = switch (pct) {
      >= 80 => ('In great shape', 'Almost everything is live and working.'),
      >= 60 => ('Mostly running well', 'A few things are waiting or stopped. See “Needs attention”.'),
      _ => ('Needs some care', 'Many things are waiting or stopped. Start with “Needs attention”.'),
    };
    return DashCard(
      title: 'Health',
      subtitle: 'Across every module with a status.',
      child: Column(
        children: [
          // Scales down to the room the card has, so it fits a short laptop row as well as a tall phone card.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 260,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Gauge(percent: pct, caption: 'running well'),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(line, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 12.5)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SplitStat(left: ('Running well', '${h.good}'), right: ('Waiting or stopped', '${h.waiting + h.stopped}')),
        ],
      ),
    );
  }

  Widget _stock() {
    final products = [...repo.records('products')]..sort((a, b) => ((b['stock'] as num?) ?? 0).compareTo((a['stock'] as num?) ?? 0));
    final slices = [
      for (final (i, p) in products.take(5).indexed) Slice('${p['name']}', ((p['stock'] as num?) ?? 0).round(), greens[i], image: recordImage('products', p)),
    ];
    final total = slices.fold<int>(0, (a, s) => a + s.count);
    final number = NumberFormat.decimalPattern('en_IN');
    return DashCard(
      title: 'Stock by product',
      trailing: SeeAll(onTap: () => onOpen('products')),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: RingWithList(slices: slices, centerLabel: 'Boxes in stock', centerValue: number.format(total), format: (v) => number.format(v), ring: 180),
      ),
    );
  }

  Widget _cities(DateTime now) {
    final members = repo.records('members');
    final active = members.where((x) => x['status'] == 'Active').length;
    return DashCard(
      title: 'Members by city',
      trailing: SeeAll(onTap: () => onOpen('members')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(NumberFormat.decimalPattern('en_IN').format(active), style: const TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w800)),
                  const Text('active members', style: TextStyle(color: muted, fontSize: 12)),
                ]),
              ),
              DeltaBadge(countDelta(periodCounts(members, 'joinedAt', now: now), noun: 'joined'), boxed: true),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: ProgressRows(slices: countBy(members.map((x) => x['city']), top: 4)))),
        ],
      ),
    );
  }

  Widget _learnShare() {
    final views = <String, int>{};
    for (final a in repo.records('articles')) {
      views['${a['category']}'] = (views['${a['category']}'] ?? 0) + ((a['views'] as num?) ?? 0).round();
    }
    final sorted = views.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final slices = [for (final (i, e) in sorted.indexed) Slice(e.key, e.value, greens[(i * 2).clamp(0, greens.length - 2)])];
    return DashCard(
      title: 'Learn views by topic',
      trailing: SeeAll(onTap: () => onOpen('articles')),
      child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: ShareBar(slices: slices)),
    );
  }

  List<Widget> _charts({required bool beside, required bool fill}) {
    List<Map<String, dynamic>> r(String k) => repo.records(k);
    Widget open(String k) => TextButton(onPressed: () => onOpen(k), child: const Text('Open'));
    Slice valueSlice(String k, Map<String, dynamic> x, String label, String value, int i) =>
        Slice('${x[label]}', (x[value] is num ? x[value] as num : num.tryParse('${x[value]}') ?? 0).round(), chartPalette[i % chartPalette.length], image: recordImage(k, x));
    List<Slice> ranked(String k, String label, String value, {bool Function(Map<String, dynamic>)? where}) {
      final rows = r(k).where(where ?? (_) => true).toList()
        ..sort((a, b) => ((b[value] as num?) ?? 0).compareTo((a[value] as num?) ?? 0));
      return [for (final (i, x) in rows.take(5).indexed) valueSlice(k, x, label, value, i)];
    }

    final number = NumberFormat.decimalPattern('en_IN');
    final starColors = [const Color(0xFF8B2E2E), const Color(0xFFC4785B), const Color(0xFFD29B2B), const Color(0xFF6E9A6C), const Color(0xFF0B5B4E)];
    return [
      ChartCard(
        fill: fill,
        title: 'App ratings by stars',
        note: 'How members rate the app. Low ratings are worth a read.',
        trailing: open('ratings'),
        child: ColumnChart(slices: [
          for (var s = 1; s <= 5; s++) Slice('$s ★', r('ratings').where((x) => x['stars'] == s).length, starColors[s - 1]),
        ]),
      ),
      ChartCard(
        fill: fill,title: 'Members by status', note: 'Active members against blocked ones.', trailing: open('members'), child: DonutChart(horizontal: beside, slices: statusSlices(moduleByKey('members'), r('members')), centerLabel: 'members')),
      ChartCard(
        fill: fill,title: 'Subscriptions by plan', note: 'Which plans people choose.', trailing: open('subscriptions'), child: DonutChart(horizontal: beside, slices: countBy(r('subscriptions').map((x) => x['plan'])), centerLabel: 'subscriptions')),
      ChartCard(
        fill: fill,title: 'Appointments by status', note: 'Booked, completed, cancelled and no-shows.', trailing: open('appointments'), child: DonutChart(horizontal: beside, slices: statusSlices(moduleByKey('appointments'), r('appointments')), centerLabel: 'appointments')),
      ChartCard(
        fill: fill,title: 'Most-read Learn articles', note: 'Views of each article.', trailing: open('articles'), child: BarList(slices: ranked('articles', 'title', 'views'), format: number.format)),
      ChartCard(
        fill: fill,title: 'AI health bot chats', note: 'Chats with each health bot.', trailing: open('healthBots'), child: BarList(slices: ranked('healthBots', 'name', 'chats'), format: number.format)),
      ChartCard(
        fill: fill,title: 'Delivery partners by status', note: 'Online, offline, suspended and waiting for KYC.', trailing: open('partners'), child: DonutChart(horizontal: beside, slices: statusSlices(moduleByKey('partners'), r('partners')), centerLabel: 'partners')),
      ChartCard(
        fill: fill,title: 'Top delivery partners', note: 'Deliveries made by each partner.', trailing: open('partners'), child: BarList(slices: ranked('partners', 'name', 'deliveries'), format: number.format)),
      ChartCard(
        fill: fill,title: 'Doctors by specialty', note: 'Who members can consult.', trailing: open('doctors'), child: DonutChart(horizontal: beside, slices: countBy(r('doctors').map((x) => x['specialty'])), centerLabel: 'doctors')),
      ChartCard(
        fill: fill,title: 'Why members block someone', note: 'Reasons given in chat blocks.', trailing: open('blocks'), child: BarList(slices: countBy(r('blocks').map((x) => x['reason'])))),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.note);
  final String title, note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      Text(note, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 13)),
    ],
  );
}

/// Everything else worth a number, as a tidy list: appointments, partners, products, pages, integrations…
class _OperationsCard extends StatelessWidget {
  const _OperationsCard({required this.repo, required this.onOpen, required this.now});
  final ModuleRepository repo;
  final OpenModule onOpen;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rows = headlineNumbers(repo, now: now).where((k) => !const {'members', 'subscriptions', 'ratings'}.contains(k.module)).toList();
    return ChartCard(
      title: 'Everything else at a glance',
      note: 'Tap a line to open its module.',
      child: Column(
        children: [
          for (final (i, k) in rows.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(k.module),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: line))),
                child: Row(
                  children: [
                    if (k.image != null)
                      AssetThumb(k.image!, size: 34, radius: 10)
                    else
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: const Color(0xFFEFF7F4), borderRadius: BorderRadius.circular(10)),
                        child: Icon(k.icon, size: 18, color: brand),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        Text(k.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Text(k.value, style: const TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttentionCard extends StatefulWidget {
  const _AttentionCard({required this.items, required this.onOpen});
  final List<Attention> items;
  final OpenModule onOpen;

  @override
  State<_AttentionCard> createState() => _AttentionCardState();
}

class _AttentionCardState extends State<_AttentionCard> {
  /// The 5 most urgent show at first, so the card stays the size of the chart beside it.
  static const _first = 5;
  bool _all = false;

  List<Attention> get items => widget.items;
  OpenModule get onOpen => widget.onOpen;

  static (Color, Color, String) _tone(Urgency u) => switch (u) {
    Urgency.high => (const Color(0xFFFBE7E5), const Color(0xFFB3261E), 'Act now'),
    Urgency.medium => (const Color(0xFFFFF4D6), const Color(0xFF8A5A00), 'Look soon'),
    Urgency.info => (const Color(0xFFE3EEF6), const Color(0xFF2D5F80), 'FYI'),
  };

  @override
  Widget build(BuildContext context) => ChartCard(
    title: 'Needs attention',
    note: items.isEmpty ? null : 'Most urgent first. Tap a line to open the module, already filtered.',
    child: items.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Row(children: [Icon(Icons.task_alt, color: brand), SizedBox(width: 10), Text('All clear: nothing waiting for you.')]),
          )
        : Column(
            children: [
              for (final a in _all ? items : items.take(_first))
                () {
                  final (bg, fg, tag) = _tone(a.urgency);
                  final m = moduleByKey(a.module);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(a.module, status: a.status, preset: a.preset),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                            child: Text('${a.count}', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text('${m.title} · $tag', style: TextStyle(color: fg, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  );
                }(),
              if (items.length > _first)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _all = !_all),
                    icon: Icon(_all ? Icons.expand_less : Icons.expand_more),
                    label: Text(_all ? 'Show fewer' : 'Show all ${items.length}'),
                  ),
                ),
            ],
          ),
  );
}

class _ModuleSummaryCard extends StatelessWidget {
  const _ModuleSummaryCard({required this.insight, required this.onTap});
  final ModuleInsight insight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = insight.module;
    final dates = insight.dates.where((d) => d.past30 > 0 || d.next30 > 0).take(1);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (moduleImage(m.key) case final image?)
                    AssetThumb(image, size: 38, radius: 11)
                  else
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: m.sensitive ? const Color(0xFFFDE7EA) : const Color(0xFFD8EEE3), borderRadius: BorderRadius.circular(11)),
                      child: Icon(m.icon, size: 20, color: m.sensitive ? const Color(0xFFA8243F) : brand),
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Text('${insight.total}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: brand)),
                ],
              ),
              const SizedBox(height: 8),
              Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF34443F), fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 12),
              if (insight.statuses.isNotEmpty) ...[
                StackedBar(slices: insight.statuses),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    for (final s in insight.statuses.where((s) => s.count > 0))
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text('${s.label} ${s.count}', style: const TextStyle(fontSize: 12)),
                      ]),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Text(insight.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12.5, height: 1.35)),
              for (final d in dates) ...[
                const SizedBox(height: 4),
                Text(
                  [if (d.past30 > 0) '${d.past30} in the last 30 days', if (d.next30 > 0) '${d.next30} due in the next 30 days'].join(' · ').replaceFirst(RegExp('^'), '${d.field.label}: '),
                  style: const TextStyle(color: Color(0xFF0F766E), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
