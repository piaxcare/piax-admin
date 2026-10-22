import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'charts.dart';
import 'dashboard_images.dart';
import 'dashboard_widgets.dart';
import 'insights.dart';
import 'repository.dart';
import 'founder_dashboard.dart';
import 'nav_pages.dart' show navPageSpecs, rowsFor;
import 'schema.dart';

// The unified admin dashboard, in the deployed admin's style (piax-admin.vercel.app): big KPI cards, area line
// charts, donut rings, a health gauge, the member funnel and share bars, full width on desktop. The Founder Overview's sales part first (revenue, orders), then alerts and decisions, stock
// and operations, customers (members by city, member journey), recent transactions, quick actions and every module.

/// Opens a module list: optionally filtered to a status or a custom filter.
typedef OpenModule = void Function(String module, {String? status, ListPreset? preset});

class AdminOverview extends StatelessWidget {
  const AdminOverview({super.key, required this.repo, required this.onOpen, this.onAdd, this.header, this.onOpenOrders, this.onNavItem});
  final ModuleRepository repo;
  final OpenModule onOpen;

  /// Opens a module's "add" form (the quick actions).
  final void Function(String module)? onAdd;

  /// Shown above everything (the source notice).
  final Widget? header;

  /// Opens the order desk, from the revenue and orders section.
  final VoidCallback? onOpenOrders;

  /// Opens a sidebar page by its menu id (pending approvals → Decisions & Approvals).
  final void Function(String itemId)? onNavItem;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final attention = attentionItems(repo, now: now);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final pad = w >= 900 ? 28.0 : 16.0;
        final inner = math.max(0.0, w - pad * 2);
        const gap = 18.0;
        final medium = inner >= 720;
        final chartCols = inner >= 1800 ? 5 : inner >= 1400 ? 4 : inner >= 1050 ? 3 : medium ? 2 : 1;

        final cards = headlineCards(repo, now: now);
        const tones = [brand, Color(0xFF5B3F73), Color(0xFF8A5A00)];
        final heads = [
          for (final (i, c) in cards.indexed)
            MiniStat(highlight: i == 0, icon: c.icon, tone: tones[i % tones.length], value: c.value, label: c.label, delta: c.delta, onTap: () => onOpen(c.module)),
        ];
        // The deployed admin's charts: activity line, health gauge, stock ring, member funnel, Learn share bar.
        final activity = weeklyActivity(repo, now: now);
        final activityCard = ActivityCard(all: activity.all, members: activity.members, now: now);
        final journey = DashCard(
          title: 'Member journey',
          subtitle: 'From signing up to buying again.',
          trailing: SeeAll(onTap: () => onOpen('members')),
          child: medium ? FunnelChart(steps: memberFunnel(repo)) : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 600, height: 240, child: FunnelChart(steps: memberFunnel(repo)))),
        );
        Widget fixed(double h, Widget child) => SizedBox(height: h, child: child);
        Widget row(double h, List<(int, Widget)> parts) => SizedBox(
          height: h,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (flex, child)) in parts.indexed) ...[if (i > 0) const SizedBox(width: gap), Expanded(flex: flex, child: child)],
          ]),
        );
        final wide = inner >= 1180;

        // Between the orders section and the recent transactions (not affected by the sales filters):
        // alerts and decisions, inventory and operations, customers and marketing.
        final approvals = _PendingApprovals(onOpen: onNavItem);
        final alerts = DashSection(
          title: 'Critical alerts & pending decisions',
          note: 'Across the business, most urgent first. Not filtered by the sales filters.',
          child: EqualRows(columns: medium ? 2 : 1, gap: gap, children: [_AttentionCard(items: attention, onOpen: onOpen), approvals]),
        );
        final operations = DashSection(
          title: 'Inventory & operational health',
          note: 'Stock, statuses and what’s running across the modules.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (medium) row(480, [(1, _health()), (1, _stock())]) else ...[fixed(390, _health()), const SizedBox(height: gap), fixed(490, _stock())],
            const SizedBox(height: gap),
            _OperationsCard(repo: repo, onOpen: onOpen, now: now),
          ]),
        );
        final customers = DashSection(
          title: 'Customer & marketing performance',
          note: 'Members, subscriptions, ratings and content. Member segments: ${memberSegments(repo)}.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MiniStatGrid(tiles: heads, across: 3),
            const SizedBox(height: gap),
            if (wide) row(380, [(1, _cities(now)), (2, journey), (1, _learnShare())])
            else if (medium) ...[row(380, [(1, _cities(now)), (1, _learnShare())]), const SizedBox(height: gap), fixed(330, journey)]
            else ...[fixed(390, _cities(now)), const SizedBox(height: gap), fixed(330, journey), const SizedBox(height: gap), fixed(370, _learnShare())],
            const SizedBox(height: gap),
            fixed(medium ? 380 : 340, activityCard),
          ]),
        );

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: inner + pad * 2,
            child: ListView(
              key: const Key('overview-scroll'),
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
              children: [
                if (header != null) ...[header!, const SizedBox(height: gap)],
                // Founder Overview, in priority order: revenue, orders, then (middle) alerts, operations, customers,
                // then recent transactions. One set of sales filters over the revenue and order parts.
                FounderDashboard(repo: repo, onOpenOrders: onOpenOrders, middle: [alerts, operations, customers]),
                const SizedBox(height: 30),
                if (onAdd != null) ...[
                  const SizedBox(height: 22),
                  const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF34443F))),
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
                const _SectionTitle('Every module', 'What each module holds, in one line. Tap one to see its records and charts.'),
                for (final group in moduleGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                    child: Text(group.toUpperCase(), style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.6)),
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
                  Text(title, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600)),
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
      for (final (i, p) in products.take(5).indexed) Slice('${p['name']}', ((p['stock'] as num?) ?? 0).round(), chartPalette[i], image: recordImage('products', p)),
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
                  Text(NumberFormat.decimalPattern('en_IN').format(active), style: const TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w600)),
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
    final slices = [for (final (i, e) in sorted.take(chartPalette.length).indexed) Slice(e.key, e.value, chartPalette[i])];
    return DashCard(
      title: 'Learn views by topic',
      trailing: SeeAll(onTap: () => onOpen('articles')),
      child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: ShareBar(slices: slices)),
    );
  }

}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.note);
  final String title, note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
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
                    Text(k.value, style: const TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 16)),
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
                            child: Text('${a.count}', style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
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
                  Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                  Text('${insight.total}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: brand)),
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


/// Who the members are, by segment ("12 B2C, 3 B2B, 1 Unknown"); missing ones count as Unknown.
String memberSegments(ModuleRepository repo) {
  final counts = <String, int>{};
  for (final m in repo.records('members')) {
    final s = normalizeSegment('${m['segment'] ?? ''}');
    counts[s] = (counts[s] ?? 0) + 1;
  }
  return [for (final s in segments) if ((counts[s] ?? 0) > 0) '${counts[s]} $s'].join(', ');
}

/// Decisions waiting for a yes or no (Executive › Decisions & Approvals), biggest first.
class _PendingApprovals extends StatelessWidget {
  const _PendingApprovals({this.onOpen});
  final void Function(String itemId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final spec = navPageSpecs['decisions-approvals'];
    final rows = spec == null ? const <Map<String, Object>>[] : [for (final r in rowsFor('decisions-approvals', spec)) if (r['Status'] == 'Pending approval') r]
      ..sort((a, b) => ((b['Amount'] as num?) ?? 0).compareTo((a['Amount'] as num?) ?? 0));
    final total = rows.fold<num>(0, (a, r) => a + ((r['Amount'] as num?) ?? 0));
    return ChartCard(
      title: 'Pending decisions',
      note: rows.isEmpty ? null : '${rows.length} waiting · ${rupees(total.round())} in total',
      trailing: onOpen == null ? null : TextButton(onPressed: () => onOpen!('decisions-approvals'), child: const Text('Open')),
      child: rows.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Nothing waiting for a decision.'))
          : Column(children: [
              for (final (i, r) in rows.take(5).indexed)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onOpen == null ? null : () => onOpen!('decisions-approvals'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEDF2F0)))),
                    child: Row(children: [
                      const Icon(Icons.gavel_outlined, size: 18, color: Color(0xFF8A5A00)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['Type']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          Text('${r['ID']} · asked by ${r['Requested by']}', style: const TextStyle(color: Color(0xFF5A6C68), fontSize: 12)),
                        ]),
                      ),
                      Text(rupees(((r['Amount'] as num?) ?? 0).round()), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
