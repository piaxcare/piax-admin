import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import 'charts.dart';
import 'dashboard_widgets.dart' show greens, ink, muted, line;
import 'insights.dart';

// Members, made easy to read: a card with a letter avatar, who they are, badges (subscriber, repeat buyer, blocked)
// and their order numbers; and, on the member's page, a profile with numbers and charts: how their orders ended,
// what they spent, and orders over the last six months.

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
bool isSubscriber(Map<String, dynamic> m) => '${m['plan'] ?? 'None'}' != 'None' && '${m['plan'] ?? ''}'.isNotEmpty;
bool isRepeatBuyer(Map<String, dynamic> m) => _n(m['orders']) >= 3;

/// A round avatar with the first letter of the name, in a colour of its own for each name.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.name, {super.key, this.size = 46});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color = chartPalette[name.codeUnits.fold<int>(0, (a, c) => a + c) % chartPalette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withValues(alpha: 0.75), color]),
      ),
      child: Text(
        letter,
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.icon, this.fg, this.bg);
  final String text;
  final IconData icon;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

List<Widget> memberBadges(Map<String, dynamic> m) => [
  if (isSubscriber(m)) const _Badge('Subscriber', Icons.card_membership_outlined, Color(0xFF0B5B4E), Color(0xFFDDF3EC)),
  if (isRepeatBuyer(m)) const _Badge('Repeat buyer', Icons.repeat, Color(0xFF5B4A86), Color(0xFFEDE7F6)),
  if (_n(m['orders']) == 0) const _Badge('No orders yet', Icons.hourglass_empty, Color(0xFF475569), Color(0xFFEEF2F1)),
  if (m['status'] == 'Blocked') const _Badge('Blocked', Icons.block, Color(0xFF8B2E2E), Color(0xFFF3E3E3)),
];

/// The member's card in the list: avatar, name, email and city, badges, and their order numbers at a glance.
class MemberCard extends StatelessWidget {
  const MemberCard({super.key, required this.member, required this.onTap, this.onEdit});
  final Map<String, dynamic> member;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final m = member;
    Widget stat(String label, Object? value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            '${_n(value).round()}',
            style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LetterAvatar('${m['name'] ?? ''}'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['name'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${m['email'] ?? m['phone'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12.5),
                        ),
                        Text(
                          [m['city'], m['phone']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(tooltip: 'Edit member', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: onEdit, visualDensity: VisualDensity.compact)
                  else
                    const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: memberBadges(m)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFF7FAF9), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    stat('Orders', m['orders'], ink),
                    stat('Delivered', m['delivered'], greens[0]),
                    stat('Cancelled', m['cancelled'], const Color(0xFFB3261E)),
                    stat('Refunded', m['refunded'], const Color(0xFF8A5A00)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Spent ${rupees(_n(m['totalSpent']).round())}${m['lastOrderAt'] == null ? '' : ' · last order ${DateFormat('d MMM').format(DateTime.parse('${m['lastOrderAt']}').toLocal())}'}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The member's page: a profile with numbers and charts, above the full details.
class MemberProfile extends StatelessWidget {
  const MemberProfile({super.key, required this.member});
  final Map<String, dynamic> member;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final orders = _n(m['orders']).round(), delivered = _n(m['delivered']).round(), cancelled = _n(m['cancelled']).round();
    final refunded = _n(m['refunded']).round(), moving = _n(m['inProgress']).round();
    final spent = _n(m['totalSpent']);
    final average = delivered == 0 ? 0 : spent / delivered;
    final monthly = [for (final v in (m['monthlyOrders'] as List?) ?? const []) _n(v).round()];
    final now = DateTime.now();
    String month(int i) => DateFormat('MMM').format(DateTime(now.year, now.month - (5 - i)));

    Widget tile(String label, String value, IconData icon, {Color color = const Color(0xFF0B5B4E)}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF7FAF9), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget outcome(bool beside) => DonutChart(
      horizontal: beside,
      slices: [
        Slice('Delivered', delivered, chartPalette[0]),
        Slice('On the way', moving, chartPalette[3]),
        // Checked together (all pairs): teal, blue, yellow, status red.
        Slice('Cancelled, refunded', refunded, chartPalette[4]),
        Slice('Cancelled, not refunded', cancelled - refunded, const Color(0xFFD03B3B)),
      ],
      centerLabel: 'orders',
      size: 140,
    );
    final top = math.max(1, monthly.fold<int>(0, math.max));
    final history = monthly.isEmpty || monthly.every((v) => v == 0)
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('No orders in the last six months', style: TextStyle(color: muted)),
            ),
          )
        : SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: top * 1.25,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: top <= 4 ? 1 : (top / 4).ceilToDouble(),
                  getDrawingHorizontalLine: (_) => const FlLine(color: line, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: top <= 4 ? 1 : (top / 4).ceilToDouble(),
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text('${v.toInt()}', style: const TextStyle(color: muted, fontSize: 11)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(month(v.toInt()), style: const TextStyle(color: muted, fontSize: 11)),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1E293B),
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem('${month(group.x)}: ${rod.toY.toInt()} orders', const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                barGroups: [
                  for (final (i, v) in monthly.indexed)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: v.toDouble(),
                          width: 20,
                          color: chartPalette[0],
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final tiles = [
          tile('Orders placed', '$orders', Icons.receipt_long_outlined, color: ink),
          tile('Delivered', '$delivered', Icons.local_shipping_outlined),
          tile('Cancelled', '$cancelled', Icons.cancel_outlined, color: const Color(0xFFB3261E)),
          tile('Refunded', '$refunded', Icons.currency_exchange, color: const Color(0xFF8A5A00)),
          tile('Total spent', rupees(spent.round()), Icons.payments_outlined),
          tile('Average order', rupees(average.round()), Icons.shopping_bag_outlined, color: const Color(0xFF5B4A86)),
        ];
        final cols = box.maxWidth >= 900 ? 3 : 2;
        final card = BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LetterAvatar('${m['name'] ?? ''}', size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${m['name'] ?? '—'}',
                              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: ink),
                            ),
                            const SizedBox(height: 3),
                            Text([m['email'], m['phone']].where((v) => v != null && '$v'.isNotEmpty).join(' · '), style: const TextStyle(color: muted, fontSize: 13)),
                            if (m['address'] != null) Text('${m['address']}${m['pincode'] == null ? '' : ' – ${m['pincode']}'}', style: const TextStyle(color: muted, fontSize: 13)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 6, children: memberBadges(m)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  EqualRows(columns: cols, gap: 10, children: tiles),
                  const SizedBox(height: 12),
                  Text(
                    [
                      if (m['joinedAt'] != null) 'Member since ${DateFormat('MMM yyyy').format(DateTime.parse('${m['joinedAt']}').toLocal())}',
                      if (m['favouriteProduct'] != null) 'buys ${m['favouriteProduct']} most',
                      if (m['paymentMethod'] != null) 'usually pays by ${m['paymentMethod']}',
                      if (isSubscriber(m)) 'on the ${m['plan']} plan',
                    ].join(' · '),
                    style: const TextStyle(color: Color(0xFF34443F), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            EqualRows(
              columns: wide ? 2 : 1,
              gap: 14,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('How their orders ended', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                      const SizedBox(height: 14),
                      if (orders == 0) const Text('No orders yet.', style: TextStyle(color: muted)) else outcome(DonutChart.fitsBeside((wide ? (box.maxWidth - 14) / 2 : box.maxWidth) - 36, size: 140)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Orders, last 6 months', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                      const SizedBox(height: 14),
                      history,
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
