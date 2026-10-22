import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'dashboard_images.dart';
import 'repository.dart';
import 'schema.dart';
import 'package:piax_orders_admin/palette.dart';

// Turns the Admin modules' records into things an admin can read at a glance: how many of each status, totals and
// averages of every number, how a field splits (by city, category, plan…), what happened recently or is coming up,
// a one-line summary per module, and the short list of things that need someone's attention. Pure calculations:
// the screens (overview_screen.dart, modules_screens.dart) only draw them.

/// Categorical chart colours (which item is which), in this fixed order, never cycled past the end: brand teal first.
/// Checked with the data-viz validator on white: every hue inside the lightness band and above the chroma floor, and
/// neighbours apart for colour-blind readers (worst ΔE 18) and everyone else (worst ΔE 23). Yellow is under 3:1 on
/// white, so charts using it always carry labels or a legend. Red is left out on purpose: it means "stopped" (status).
/// More than six parts fold into "Other".
const chartPalette = [
  TColor(0xFF0F8A6F), // teal (brand)
  TColor(0xFF5B4BD1), // violet
  TColor(0xFFE8692F), // orange
  TColor(0xFF2A78D6), // blue
  TColor(0xFFE39A00), // yellow
  TColor(0xFFD9558A), // pink
];

/// "Other" (the parts past the sixth) and empty tracks: a quiet grey.
const otherColor = TColor(0xFFB8C4C1);

/// One part of a whole: a status, a city, a category…
/// The slices with a different colour for each part: a colour already used (or a shade family) gets the next unused
/// palette colour, so no two parts of one chart look alike. "Other" keeps its grey.
List<Slice> distinctSlices(List<Slice> slices) {
  final used = <int>{};
  var next = 0;
  Color fresh() {
    for (var i = 0; i < chartPalette.length; i++) {
      final c = chartPalette[(next + i) % chartPalette.length];
      if (!used.contains(c.toARGB32())) {
        next += i + 1;
        return c;
      }
    }
    return chartPalette[next++ % chartPalette.length];
  }

  return [
    for (final s in slices)
      if (s.label == 'Other')
        s
      else
        () {
          final c = used.contains(s.color.toARGB32()) ? fresh() : s.color;
          used.add(c.toARGB32());
          return identical(c, s.color) ? s : Slice(s.label, s.count, c, image: s.image);
        }(),
  ];
}

class Slice {
  const Slice(this.label, this.count, this.color, {this.image});
  final String label;
  final int count;
  final Color color;

  /// A picture shown beside the bar (a product packshot, an article thumbnail…).
  final String? image;
}

/// A number field across a module's records. Counts that add up (stock, views, chats…) show a total; the rest
/// (price, rating, fee…) an average.
class NumberStat {
  const NumberStat(this.field, {required this.isSum, required this.total, required this.average, required this.min, required this.max, required this.n});
  final FieldDef field;
  final bool isSum;
  final num total, average, min, max;
  final int n;

  String get headline => isSum ? formatNumber(field, total) : formatNumber(field, average);
  String get headlineLabel => isSum ? '${field.label} · total' : '${field.label} · average';
  String get range => n < 2 ? '' : '${formatNumber(field, min)} – ${formatNumber(field, max)}';
}

/// A date field: how many fall in the last / next 30 days, and a 12-week history for the trend chart.
class DateStat {
  const DateStat(this.field, {required this.past30, required this.next30, required this.weekly});
  final FieldDef field;
  final int past30, next30;

  /// Records per week for the last 12 weeks, oldest first.
  final List<int> weekly;
}

class Breakdown {
  const Breakdown(this.field, this.slices);
  final FieldDef field;
  final List<Slice> slices;
}

class ModuleInsight {
  const ModuleInsight({required this.module, required this.total, required this.statuses, required this.numbers, required this.breakdowns, required this.dates, required this.summary});
  final ModuleDef module;
  final int total;
  final List<Slice> statuses;
  final List<NumberStat> numbers;
  final List<Breakdown> breakdowns;
  final List<DateStat> dates;

  /// One plain sentence, e.g. "5 products · 4 active, 1 hidden · Stock 2,320 in total".
  final String summary;
}

/// Number fields that add up across records; every other number is averaged.
const _summed = {'stock', 'views', 'chats', 'deliveries', 'members', 'orders', 'messages', 'amount', 'sizeKb'};

String formatNumber(FieldDef field, num value) {
  switch (field.type) {
    case FieldType.money:
      return rupees(value.round());
    case FieldType.decimal:
      return value.toStringAsFixed(1);
    default:
      final whole = value == value.roundToDouble();
      return whole ? NumberFormat.decimalPattern('en_IN').format(value.round()) : value.toStringAsFixed(1);
  }
}

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

/// Status colours follow the status chips (green good, amber waiting, red stopped); two statuses sharing a tone get
/// lighter shades so the chart keeps them apart.
List<Slice> statusSlices(ModuleDef m, List<Map<String, dynamic>> records) {
  return [
    for (final s in m.statuses)
      () {
        final base = statusTone(s).$2;
        return Slice(s, records.where((r) => '${r[m.statusField]}' == s).length, base);
      }(),
  ];
}

List<Slice> countBy(Iterable<Object?> values, {int top = 6, Map<String, Color>? colors}) {
  top = top.clamp(1, chartPalette.length);
  final counts = <String, int>{};
  for (final v in values) {
    final key = v == null || '$v'.isEmpty ? 'Not set' : '$v';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final shown = sorted.take(top).toList();
  final rest = sorted.skip(top).fold<int>(0, (sum, e) => sum + e.value);
  return [
    for (final (i, e) in shown.indexed) Slice(e.key, e.value, colors?[e.key] ?? chartPalette[i]),
    if (rest > 0) Slice('Other', rest, otherColor),
  ];
}

ModuleInsight analyse(ModuleDef m, List<Map<String, dynamic>> records, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final statuses = m.statusField == null ? <Slice>[] : statusSlices(m, records);

  final numbers = <NumberStat>[];
  for (final f in m.fields.where((f) => f.type == FieldType.integer || f.type == FieldType.decimal || f.type == FieldType.money)) {
    final values = [for (final r in records) ?_num(r[f.key])];
    if (values.isEmpty) continue;
    final total = values.fold<num>(0, (a, b) => a + b);
    numbers.add(NumberStat(f,
        isSum: _summed.contains(f.key),
        total: total,
        average: total / values.length,
        min: values.reduce((a, b) => a < b ? a : b),
        max: values.reduce((a, b) => a > b ? a : b),
        n: values.length));
  }

  final breakdowns = <Breakdown>[];
  for (final f in m.fields) {
    if (f.key == m.statusField || f.key == m.titleField) continue;
    final values = records.map((r) => r[f.key]).toList();
    final distinct = values.map((v) => '$v').toSet().length;
    final useful = f.type == FieldType.choice ||
        f.type == FieldType.boolean ||
        (f.type == FieldType.text && records.length >= 3 && distinct <= 8 && distinct < records.length);
    if (!useful || distinct < 2) continue;
    breakdowns.add(Breakdown(f, countBy(f.type == FieldType.boolean ? values.map((v) => v == true || v == 'true' ? 'Yes' : 'No') : values)));
  }

  final dates = <DateStat>[];
  final weekStart = DateTime(at.year, at.month, at.day).subtract(Duration(days: at.weekday - 1));
  for (final f in m.fields.where((f) => f.type == FieldType.dateTime)) {
    final when = [for (final r in records) ?DateTime.tryParse('${r[f.key] ?? ''}')?.toLocal()];
    if (when.isEmpty) continue;
    final weekly = List<int>.filled(12, 0);
    for (final d in when) {
      final weeksAgo = weekStart.difference(DateTime(d.year, d.month, d.day)).inDays;
      final index = 11 - (weeksAgo <= 0 ? 0 : (weeksAgo + 6) ~/ 7);
      if (index >= 0 && index < 12 && !d.isAfter(at)) weekly[index]++;
    }
    dates.add(DateStat(f,
        past30: when.where((d) => !d.isAfter(at) && at.difference(d).inDays < 30).length,
        next30: when.where((d) => d.isAfter(at) && d.difference(at).inDays < 30).length,
        weekly: weekly));
  }

  final parts = <String>['${records.length} ${(records.length == 1 ? m.singular : m.title).toLowerCase()}'];
  final present = statuses.where((s) => s.count > 0).toList();
  if (present.isNotEmpty) parts.add(present.map((s) => '${s.count} ${s.label.toLowerCase()}').join(', '));
  final lead = numbers.where((n) => !n.field.readOnly || n.isSum).firstOrNull ?? numbers.firstOrNull;
  if (lead != null) parts.add('${lead.field.label} ${lead.headline} ${lead.isSum ? 'in total' : 'on average'}');
  if (m.sensitive) parts.add('anonymised');

  return ModuleInsight(module: m, total: records.length, statuses: statuses, numbers: numbers, breakdowns: breakdowns, dates: dates, summary: parts.join(' · '));
}

// ================================================================ Overview: headline numbers and attention list

class Kpi {
  const Kpi({required this.label, required this.value, required this.caption, required this.icon, required this.module, this.color = const TColor(0xFF0B5B4E), this.image});
  final String label, value, caption;
  final IconData icon;

  /// A picture shown on the card instead of the icon.
  final String? image;
  final String module;
  final Color color;
}

/// How urgent an attention item is: act now, worth a look, or just so you know.
enum Urgency { high, medium, info }

/// A list filter the overview hands to a module list ("low on stock", "renewing this week").
class ListPreset {
  const ListPreset(this.label, this.test);
  final String label;
  final bool Function(Map<String, dynamic> record) test;
}

class Attention {
  const Attention({required this.module, required this.count, required this.text, required this.urgency, this.status, this.preset});
  final String module;
  final int count;
  final String text;
  final Urgency urgency;

  /// Opens the module list filtered to this status…
  final String? status;

  /// …or to this custom filter.
  final ListPreset? preset;
}

ModuleDef moduleByKey(String key) => modules.firstWhere((m) => m.key == key);

String _n(num v) => NumberFormat.decimalPattern('en_IN').format(v.round());
DateTime? _date(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
String _plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

List<Kpi> headlineNumbers(ModuleRepository repo, {DateTime? now}) {
  final at = now ?? DateTime.now();
  List<Map<String, dynamic>> r(String k) => repo.records(k);
  int where(String k, bool Function(Map<String, dynamic>) test) => r(k).where(test).length;
  num sum(Iterable<Map<String, dynamic>> rows, String field) => rows.fold<num>(0, (a, x) => a + (_num(x[field]) ?? 0));

  final members = r('members');
  final activeSubs = r('subscriptions').where((x) => x['status'] == 'Active');
  final stars = [for (final x in r('ratings')) ?_num(x['stars'])];
  final upcoming = where('appointments', (x) => x['status'] == 'Booked' && (_date(x['at'])?.isAfter(at) ?? false));
  final partners = r('partners');
  final products = r('products').where((x) => x['status'] == 'Active');
  final published = r('articles').where((x) => x['status'] == 'Published');
  final pages = r('pages');
  final creds = r('credentials');

  return [
    Kpi(label: 'Members', value: _n(where('members', (x) => x['status'] == 'Active')), caption: 'active of ${members.length} · ${where('members', (x) => x['status'] == 'Blocked')} blocked', icon: Icons.people_outline, module: 'members'),
    Kpi(label: 'Subscription income', value: rupees(sum(activeSubs, 'amount').round()), caption: 'per billing cycle from ${_plural(activeSubs.length, 'active subscription')}', icon: Icons.card_membership_outlined, module: 'subscriptions', color: chartPalette[1]),
    Kpi(label: 'App rating', value: stars.isEmpty ? '—' : '${(stars.reduce((a, b) => a + b) / stars.length).toStringAsFixed(1)} ★', caption: 'average of ${_plural(stars.length, 'rating')}', icon: Icons.star_half_outlined, module: 'ratings', color: chartPalette[4]),
    Kpi(label: 'Upcoming appointments', value: '$upcoming', caption: 'booked from today on', icon: Icons.event_available_outlined, module: 'appointments', color: chartPalette[3]),
    Kpi(label: 'Partners online', value: '${partners.where((x) => x['status'] == 'Online').length}', caption: 'of ${_plural(partners.length, 'delivery partner')}', icon: Icons.delivery_dining_outlined, module: 'partners', color: chartPalette[2]),
    Kpi(label: 'Products in shop', value: '${products.length}', caption: '${_n(sum(products, 'stock'))} boxes in stock', icon: Icons.inventory_2_outlined, module: 'products', color: chartPalette[4], image: moduleImage('products')),
    Kpi(label: 'Website pages live', value: '${pages.where((x) => x['status'] == 'Live').length} of ${pages.length}', caption: '${_n(sum(pages, 'views30d'))} views in the last 30 days', icon: Icons.web_outlined, module: 'pages', color: chartPalette[5]),
    Kpi(label: 'Integrations working', value: '${creds.where((x) => x['status'] == 'Connected').length} of ${creds.length}', caption: '${creds.where((x) => x['status'] == 'Expiring soon' || x['status'] == 'Error').length} need attention', icon: Icons.key_outlined, module: 'credentials', color: chartPalette[3]),
    Kpi(label: 'Learn article views', value: _n(sum(published, 'views')), caption: 'across ${_plural(published.length, 'published article')}', icon: Icons.article_outlined, module: 'articles', color: chartPalette[5], image: moduleImage('articles')),
    Kpi(label: 'AI bot chats', value: _n(sum(r('healthBots'), 'chats')), caption: 'with ${_plural(r('healthBots').length, 'health bot')}', icon: Icons.smart_toy_outlined, module: 'healthBots', color: chartPalette[1], image: robotImage),
  ];
}

/// The things someone should look at, most urgent first. Only items with something in them are listed.
List<Attention> attentionItems(ModuleRepository repo, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final week = at.add(const Duration(days: 7));
  int status(String k, String s) => repo.records(k).where((x) => x['status'] == s).length;
  int count(String k, ListPreset p) => repo.records(k).where(p.test).length;

  // Each product's own alert level (set in its form), 200 boxes when it has none.
  final lowStock = ListPreset('In the shop, below its low-stock level', (x) => x['status'] == 'Active' && (_num(x['stock']) ?? 0) < (_num(x['lowStockAt']) ?? 200));
  final lowRatings = ListPreset('Visible, 1–2 stars', (x) => x['status'] == 'Visible' && (_num(x['stars']) ?? 5) <= 2);
  final overdue = ListPreset('Booked, but the time has passed', (x) => x['status'] == 'Booked' && (_date(x['at'])?.isBefore(at) ?? false));
  final renewing = ListPreset('Active, renewing in the next 7 days', (x) => x['status'] == 'Active' && ((_date(x['renewsAt']))?.isBefore(week) ?? false) && ((_date(x['renewsAt']))?.isAfter(at) ?? false));
  final ending = ListPreset('Live, ending in the next 7 days', (x) => x['status'] == 'Live' && ((_date(x['endsAt']))?.isBefore(week) ?? false));

  final items = <Attention>[
    Attention(module: 'credentials', count: status('credentials', 'Error'), text: 'integrations with an error (payments, sign-in or app stores may stop working)', urgency: Urgency.high, status: 'Error'),
    Attention(module: 'credentials', count: status('credentials', 'Expiring soon'), text: 'keys expiring soon: renew them before they stop working', urgency: Urgency.high, status: 'Expiring soon'),
    Attention(module: 'pages', count: status('pages', 'Maintenance'), text: 'website pages showing “under maintenance”', urgency: Urgency.medium, status: 'Maintenance'),
    Attention(module: 'conversations', count: status('conversations', 'Reported'), text: 'reported chats to review', urgency: Urgency.high, status: 'Reported'),
    Attention(module: 'products', count: count('products', lowStock), text: 'products below their low-stock level', urgency: Urgency.high, preset: lowStock),
    Attention(module: 'appointments', count: count('appointments', overdue), text: 'past appointments still marked Booked', urgency: Urgency.high, preset: overdue),
    Attention(module: 'doctors', count: status('doctors', 'Pending verification'), text: 'doctors waiting for verification', urgency: Urgency.medium, status: 'Pending verification'),
    Attention(module: 'partners', count: status('partners', 'Pending KYC'), text: 'delivery partners waiting for KYC approval', urgency: Urgency.medium, status: 'Pending KYC'),
    Attention(module: 'ratings', count: count('ratings', lowRatings), text: 'low app ratings (1–2 stars) to read', urgency: Urgency.medium, preset: lowRatings),
    Attention(module: 'staff', count: status('staff', 'Invited'), text: 'staff invites not accepted yet', urgency: Urgency.medium, status: 'Invited'),
    Attention(module: 'subscriptions', count: count('subscriptions', renewing), text: 'subscriptions renewing in the next 7 days', urgency: Urgency.info, preset: renewing),
    Attention(module: 'banners', count: count('banners', ending), text: 'live banners ending this week', urgency: Urgency.info, preset: ending),
    Attention(module: 'appUpdates', count: status('appUpdates', 'Rollout'), text: 'app updates still in rollout', urgency: Urgency.info, status: 'Rollout'),
    for (final k in ['articles', 'myths', 'careTips'])
      Attention(module: k, count: status(k, 'Draft'), text: '${moduleByKey(k).title.toLowerCase()} in draft', urgency: Urgency.info, status: 'Draft'),
  ];
  return items.where((a) => a.count > 0).toList();
}

/// Weekly activity for the overview trend chart: new members, appointments and app ratings over the last 12 weeks.
List<(String, Color, List<int>)> activityTrend(ModuleRepository repo, {DateTime? now}) {
  List<int> weeks(String module, String field) =>
      analyse(moduleByKey(module), repo.records(module), now: now).dates.where((d) => d.field.key == field).firstOrNull?.weekly ?? List.filled(12, 0);
  return [
    ('New members', chartPalette[0], weeks('members', 'joinedAt')),
    ('Appointments', chartPalette[1], weeks('appointments', 'at')),
    ('App ratings', chartPalette[2], weeks('ratings', 'at')),
    ('Admin changes', chartPalette[3], weeks('audit', 'at')),
  ];
}

// ================================================================ Dashboard cards (the EzMart-style layout)

/// A change against the previous period: "+12%" (green) or "−5%" (red), and what it's compared with.
class Delta {
  const Delta(this.text, this.up, {this.caption = 'vs previous 30 days'});
  final String text;
  final bool up;
  final String caption;
}

/// Records whose [field] date falls in the last [days] days, and in the [days] before that.
(int, int) periodCounts(List<Map<String, dynamic>> records, String field, {int days = 30, DateTime? now}) {
  final at = now ?? DateTime.now();
  var current = 0, previous = 0;
  for (final r in records) {
    final d = _date(r[field]);
    if (d == null || d.isAfter(at)) continue;
    final age = at.difference(d).inDays;
    if (age < days) {
      current++;
    } else if (age < days * 2) {
      previous++;
    }
  }
  return (current, previous);
}

Delta countDelta((int, int) counts, {String noun = 'new'}) {
  final (current, previous) = counts;
  if (previous == 0) return Delta(current == 0 ? 'no change' : '+$current $noun', current > 0);
  final pct = (current - previous) * 100 / previous;
  return Delta('${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%', pct >= 0);
}

class HeadlineCard {
  const HeadlineCard({required this.label, required this.value, required this.icon, required this.module, required this.delta});
  final String label, value, module;
  final IconData icon;
  final Delta delta;
}

/// The three big numbers at the top of the dashboard.
List<HeadlineCard> headlineCards(ModuleRepository repo, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final subs = repo.records('subscriptions');
  final members = repo.records('members');
  final ratings = repo.records('ratings');
  final income = subs.where((x) => x['status'] == 'Active').fold<num>(0, (a, x) => a + (_num(x['amount']) ?? 0));

  final stars = [for (final x in ratings) ?_num(x['stars'])];
  final recent = [for (final x in ratings) if ((_date(x['at']) ?? DateTime(0)).isAfter(at.subtract(const Duration(days: 30)))) ?_num(x['stars'])];
  final older = [for (final x in ratings) if (!(_date(x['at']) ?? DateTime(0)).isAfter(at.subtract(const Duration(days: 30)))) ?_num(x['stars'])];
  double avg(List<num> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  final change = recent.isEmpty || older.isEmpty ? 0.0 : avg(recent) - avg(older);

  return [
    HeadlineCard(label: 'Subscription income', value: rupees(income.round()), icon: Icons.currency_rupee, module: 'subscriptions', delta: countDelta(periodCounts(subs, 'startedAt', now: at), noun: 'started')),
    HeadlineCard(label: 'Active members', value: _n(members.where((x) => x['status'] == 'Active').length), icon: Icons.people_outline, module: 'members', delta: countDelta(periodCounts(members, 'joinedAt', now: at), noun: 'joined')),
    HeadlineCard(
      label: 'App rating',
      value: stars.isEmpty ? '—' : '${avg(stars).toStringAsFixed(1)} ★',
      icon: Icons.star_outline_rounded,
      module: 'ratings',
      delta: Delta('${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)} ★', change >= 0, caption: 'last 30 days vs before'),
    ),
  ];
}

/// How much of everything with a status is in a good state (live, active, connected…) against waiting or stopped.
({int good, int waiting, int stopped}) healthCounts(ModuleRepository repo) {
  var good = 0, waiting = 0, stopped = 0;
  for (final m in modules.where((m) => m.statusField != null)) {
    for (final r in repo.records(m.key)) {
      final tone = statusTone('${r[m.statusField]}').$2;
      if (tone == const TColor(0xFF0B5B4E)) {
        good++;
      } else if (tone == const TColor(0xFF8A5A00)) {
        waiting++;
      } else {
        stopped++;
      }
    }
  }
  return (good: good, waiting: waiting, stopped: stopped);
}

/// Date fields that are about the future or a schedule, not something that happened.
const _scheduleFields = {'renewsAt', 'predictedNext', 'expiresAt', 'endsAt', 'startsAt'};

/// Weekly counts for the activity chart, oldest first: everything that happened across the modules, and what
/// members did (joined, subscribed, booked, rated).
({List<int> all, List<int> members}) weeklyActivity(ModuleRepository repo, {DateTime? now}) {
  final all = List<int>.filled(12, 0), members = List<int>.filled(12, 0);
  const memberEvents = {'members': 'joinedAt', 'subscriptions': 'startedAt', 'appointments': 'at', 'ratings': 'at'};
  for (final m in modules) {
    for (final d in analyse(m, repo.records(m.key), now: now).dates) {
      if (_scheduleFields.contains(d.field.key)) continue;
      for (var i = 0; i < 12; i++) {
        all[i] += d.weekly[i];
        if (memberEvents[m.key] == d.field.key) members[i] += d.weekly[i];
      }
    }
  }
  return (all: all, members: members);
}

class FunnelStep {
  const FunnelStep(this.label, this.value, this.note, {this.bad = false});
  final String label, note;
  final int value;
  final bool bad;
}

/// From account to repeat buyer: how members move through PIAX.
List<FunnelStep> memberFunnel(ModuleRepository repo) {
  final members = repo.records('members');
  final total = members.length;
  final subscribed = members.where((x) => '${x['plan'] ?? 'None'}' != 'None').length;
  final active = repo.records('subscriptions').where((x) => x['status'] == 'Active').length;
  final repeat = members.where((x) => (_num(x['orders']) ?? 0) >= 3).length;
  final blocked = members.where((x) => x['status'] == 'Blocked').length;
  String of(int v) => total == 0 ? '0%' : '${(v * 100 / total).round()}%';
  return [
    FunnelStep('Accounts', total, 'all members'),
    FunnelStep('Chose a plan', subscribed, '${of(subscribed)} of accounts'),
    FunnelStep('Subscription active', active, '${of(active)} of accounts'),
    FunnelStep('Repeat buyers (3+ orders)', repeat, '${of(repeat)} of accounts'),
    FunnelStep('Blocked', blocked, '${of(blocked)} of accounts', bad: true),
  ];
}

/// Records per week for the last 12 weeks (as [DateStat.weekly]), each week split by [group] (a status, a type…):
/// what a weekly chart shows on hover.
List<Map<String, int>> weeklyGroups(List<Map<String, dynamic>> records, String dateKey, String Function(Map<String, dynamic>) group, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final weekStart = DateTime(at.year, at.month, at.day).subtract(Duration(days: at.weekday - 1));
  final out = [for (var i = 0; i < 12; i++) <String, int>{}];
  for (final r in records) {
    final d = DateTime.tryParse('${r[dateKey] ?? ''}')?.toLocal();
    if (d == null || d.isAfter(at)) continue;
    final weeksAgo = weekStart.difference(DateTime(d.year, d.month, d.day)).inDays;
    final index = 11 - (weeksAgo <= 0 ? 0 : (weeksAgo + 6) ~/ 7);
    if (index < 0 || index >= 12) continue;
    final k = group(r);
    out[index][k] = (out[index][k] ?? 0) + 1;
  }
  return out;
}

/// The category a record's weekly chart is split by: its status, else its first choice field. Null when it has neither.
(String, String Function(Map<String, dynamic>))? weeklyGrouping(ModuleDef m) {
  final key = m.statusField ?? m.fields.where((f) => f.type == FieldType.choice).firstOrNull?.key;
  if (key == null) return null;
  final label = m.fields.where((f) => f.key == key).firstOrNull?.label ?? 'Status';
  return ('By ${label.toLowerCase()}', (r) => '${r[key] ?? 'Unknown'}');
}
