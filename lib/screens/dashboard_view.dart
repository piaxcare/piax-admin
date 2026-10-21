import 'package:flutter/material.dart';

import '../admin_modules/admin_search.dart';
import '../admin_modules/schema.dart';
import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import '../widgets/brand.dart';
import 'order_detail_screen.dart';
import 'orders_screen.dart' show OrderFilter;

/// Screen widths where the dashboard takes over from the phone list, and where the order opens beside the table.
const dashboardMinWidth = 700.0;
const splitMinWidth = 1100.0;

/// Today's numbers, worked out from the most recent orders (the API's newest 300).
class DashboardStats {
  DashboardStats(List<Order> all, {DateTime? now}) {
    final today = _day(now ?? DateTime.now());
    for (final o in all) {
      switch (o.status) {
        case OrderStatus.confirmed:
          toPack++;
        case OrderStatus.packed:
          readyToShip++;
        case OrderStatus.shipped || OrderStatus.outForDelivery:
          inTransit++;
        case OrderStatus.placed:
          awaitingPayment++;
        case OrderStatus.delivered:
          break;
        case OrderStatus.cancelled:
          if (o.needsRefund) {
            refundsDue++;
            refundsDueAmount += o.totals.total;
          }
      }
      final delivered = o.history.where((h) => h.status == OrderStatus.delivered).map((h) => _day(h.at));
      if (delivered.contains(today)) deliveredToday++;

      // Orders that went through (paid or cash on delivery), by the day they were placed.
      if (o.status == OrderStatus.placed) continue;
      final age = today.difference(_day(o.createdAt)).inDays;
      if (age >= 0 && age < 7) {
        perDay[6 - age]++;
        if (o.status != OrderStatus.cancelled) revenue7d += o.totals.total;
      }
    }
    days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
  }

  int toPack = 0, readyToShip = 0, inTransit = 0, deliveredToday = 0, awaitingPayment = 0, revenue7d = 0;

  /// Cancelled orders paid online whose money hasn't gone back yet, and how much that is.
  int refundsDue = 0, refundsDueAmount = 0;

  /// Orders per day for the last 7 days, oldest first, matching [days].
  final List<int> perDay = List.filled(7, 0);
  late final List<DateTime> days;

  static DateTime _day(DateTime at) {
    final local = at.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

enum SortBy { placed, total }

/// The desktop and tablet view: a sidebar, today's numbers, a 7-day chart and the orders table. From [splitMinWidth]
/// the selected order opens in a panel beside the table; below it, it opens as its own page (through [onOpen]).
class OrdersDashboard extends StatefulWidget {
  const OrdersDashboard({
    super.key,
    required this.api,
    required this.all,
    required this.orders,
    required this.loading,
    required this.error,
    required this.filter,
    required this.search,
    required this.fresh,
    required this.defaultPassword,
    required this.selectedId,
    required this.onFilter,
    required this.onSearch,
    required this.onRefresh,
    required this.onOpen,
    required this.onCloseOrder,
    required this.onOrderChanged,
    required this.onSettings,
    required this.onSignOut,
    required this.onAnalytics,
    required this.onRefunds,
    required this.onModules,
    this.nav,
    this.showSidebar = true,
  });

  final AdminApi api;

  /// Its own dark sidebar. Off inside the app frame, which has one sidebar for every page.
  final bool showSidebar;
  final List<Order> all;
  final List<Order> orders;
  final bool loading;
  final String? error;
  final OrderFilter filter;
  final TextEditingController search;
  final Set<String> fresh;
  final bool defaultPassword;
  final String? selectedId;
  final ValueChanged<OrderFilter> onFilter;
  final ValueChanged<String> onSearch;
  final Future<void> Function() onRefresh;
  final void Function(Order order, {required bool split}) onOpen;
  final VoidCallback onCloseOrder;
  final VoidCallback onOrderChanged;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;
  final VoidCallback onAnalytics;
  final VoidCallback onRefunds;
  final VoidCallback onModules;

  /// Every page and admin module: lists the modules in the sidebar and powers the search at the top. Optional so
  /// the dashboard can be shown on its own (tests).
  final AdminNav? nav;

  @override
  State<OrdersDashboard> createState() => _OrdersDashboardState();
}

class _OrdersDashboardState extends State<OrdersDashboard> {
  SortBy _sortBy = SortBy.placed;
  bool _ascending = false;
  DateTime _updatedAt = DateTime.now();

  /// The left sidebar can be closed for more room; the choice is remembered on this device.
  bool _ownSidebarOpen = true;
  bool get _sidebarOpen => widget.showSidebar && _ownSidebarOpen;

  /// The last order shown in the side panel, kept while the panel slides shut so it doesn't empty as it closes.
  String? _lastSelected;

  /// The order panel expanded to the full width beside the sidebar (the orders list is hidden meanwhile).
  bool _expanded = false;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  void _closeOrder() {
    setState(() => _expanded = false);
    widget.onCloseOrder();
  }

  @override
  void initState() {
    super.initState();
    Session.sidebarOpen().then((open) {
      if (mounted) setState(() => _ownSidebarOpen = open);
    });
  }

  void _toggleSidebar() {
    setState(() => _ownSidebarOpen = !_ownSidebarOpen);
    Session.saveSidebarOpen(_ownSidebarOpen);
  }

  @override
  void didUpdateWidget(covariant OrdersDashboard old) {
    super.didUpdateWidget(old);
    if (!identical(old.all, widget.all)) _updatedAt = DateTime.now();
  }

  List<Order> get _sorted {
    final list = [...widget.orders];
    int compare(Order a, Order b) =>
        _sortBy == SortBy.placed ? a.createdAt.compareTo(b.createdAt) : a.totals.total.compareTo(b.totals.total);
    list.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return list;
  }

  void _sort(SortBy by) => setState(() {
    if (_sortBy == by) {
      _ascending = !_ascending;
    } else {
      _sortBy = by;
      _ascending = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= splitMinWidth;
        final wideSidebar = constraints.maxWidth >= 1280;
        final selected = split ? widget.selectedId : null;
        if (selected != null) _lastSelected = selected;
        final shown = selected ?? _lastSelected;
        final sidebarWidth = wideSidebar ? 228.0 : 76.0;
        const panelWidth = 460.0;
        // Expanded: the panel takes all the width beside the sidebar.
        final expanded = _expanded && selected != null;
        final fullWidth = constraints.maxWidth - (_sidebarOpen ? sidebarWidth : 0);
        final contentWidth = expanded ? fullWidth : panelWidth;
        const slide = Duration(milliseconds: 260);
        return Scaffold(
          backgroundColor: const Color(0xFFF2F6F5),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The sidebar slides shut (its content keeps its width and is clipped as it goes).
                AnimatedContainer(
                  duration: slide,
                  curve: Curves.easeOutCubic,
                  width: _sidebarOpen ? sidebarWidth : 0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: sidebarWidth,
                    maxWidth: sidebarWidth,
                    child: _Sidebar(
                      wide: wideSidebar,
                      server: widget.api.base,
                      onSettings: widget.onSettings,
                      onSignOut: widget.onSignOut,
                      onAnalytics: widget.onAnalytics,
                      onRefunds: widget.onRefunds,
                      onModules: widget.onModules,
                      nav: widget.nav,
                      onClose: _toggleSidebar,
                    ),
                  ),
                ),
                // While the panel is expanded the list is squeezed to nothing: it keeps a usable width and is clipped,
                // and is hidden from screen readers and the keyboard.
                Expanded(
                  child: ExcludeSemantics(
                    excluding: expanded,
                    child: ExcludeFocus(
                      excluding: expanded,
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (context, area) => area.maxWidth >= 560
                              ? _main(split)
                              : OverflowBox(alignment: Alignment.centerLeft, minWidth: 560, maxWidth: 560, child: _main(split)),
                        ),
                      ),
                    ),
                  ),
                ),
                // The order's details only while one is open: the dashboard has the full width otherwise.
                if (split)
                  AnimatedContainer(
                    duration: slide,
                    curve: Curves.easeOutCubic,
                    width: selected == null ? 0 : contentWidth,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(
                      color: mist,
                      border: Border(left: BorderSide(color: Color(0xFFE1E8E6))),
                    ),
                    onEnd: () {
                      if (widget.selectedId == null && _lastSelected != null) setState(() => _lastSelected = null);
                    },
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: contentWidth,
                      maxWidth: contentWidth,
                      child: shown == null
                          ? const SizedBox.shrink()
                          : OrderDetailScreen(
                              key: ValueKey(shown),
                              api: widget.api,
                              orderId: shown,
                              initial:
                                  widget.all.where((o) => o.id == shown).firstOrNull ??
                                  widget.orders.where((o) => o.id == shown).firstOrNull,
                              embedded: true,
                              expanded: expanded,
                              onToggleExpand: _toggleExpanded,
                              onChanged: widget.onOrderChanged,
                              onClose: _closeOrder,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _main(bool split) {
    final stats = DashboardStats(widget.all);
    final rows = _sorted;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pad = width >= 900 ? 28.0 : 20.0;
          final columns = _TableColumns.forWidth(width - pad * 2);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
                sliver: SliverList.list(
                  children: [
                    if (widget.nav != null) ...[
                      Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: AdminSearchBar(nav: widget.nav!))),
                      const SizedBox(height: 18),
                    ],
                    _header(),
                    const SizedBox(height: 18),
                    if (widget.defaultPassword) ...[
                      _Banner(
                        color: const Color(0xFFFFF4D6),
                        ink: const Color(0xFF6B4600),
                        icon: Icons.warning_amber_rounded,
                        text: 'You’re using the default password. Anyone who knows admin / admin can see customer details.',
                        action: 'Change it',
                        onTap: widget.onSettings,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.fresh.isNotEmpty) ...[
                      _Banner(
                        color: const Color(0xFFDDF3EC),
                        ink: brand,
                        icon: Icons.notifications_active_outlined,
                        text: widget.fresh.length == 1
                            ? '1 new order is waiting to be packed.'
                            : '${widget.fresh.length} new orders are waiting to be packed.',
                        action: 'Show',
                        onTap: () => widget.onFilter(OrderFilter.toPack),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (stats.refundsDue > 0) ...[
                      _Banner(
                        color: const Color(0xFFFFF4D6),
                        ink: const Color(0xFF6B4600),
                        icon: Icons.currency_exchange,
                        text: stats.refundsDue == 1
                            ? '1 cancelled order is waiting for its refund (${rupees(stats.refundsDueAmount)}).'
                            : '${stats.refundsDue} cancelled orders are waiting for refunds (${rupees(stats.refundsDueAmount)}).',
                        action: 'Review',
                        onTap: widget.onRefunds,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _overview(stats, width),
                    const SizedBox(height: 24),
                    _tableToolbar(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE1E8E6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TableHeader(columns: columns, sortBy: _sortBy, ascending: _ascending, onSort: _sort),
                        if (widget.loading && rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (widget.error != null && rows.isEmpty)
                          _TableMessage(icon: Icons.cloud_off, text: widget.error!)
                        else if (rows.isEmpty)
                          _TableMessage(
                            icon: Icons.inbox_outlined,
                            text: widget.search.text.isNotEmpty
                                ? 'No orders match “${widget.search.text}”.'
                                : 'No ${widget.filter.label.toLowerCase()} orders.',
                          )
                        else
                          for (final (i, order) in rows.indexed)
                            _TableRow(
                              order: order,
                              columns: columns,
                              isNew: widget.fresh.contains(order.id),
                              selected: split && order.id == widget.selectedId,
                              divider: i < rows.length - 1,
                              onTap: () => widget.onOpen(order, split: split),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    final now = DateTime.now();
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showSidebar && !_sidebarOpen) ...[
              IconButton.filledTonal(tooltip: 'Open the sidebar', onPressed: _toggleSidebar, icon: const Icon(Icons.menu)),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Orders',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19), letterSpacing: -.5),
                ),
                Text(
                  '${weekdayDate(now)} · updated ${timeOnly(_updatedAt)}',
                  style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 14),
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: widget.search,
                onChanged: widget.onSearch,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search order no., name, phone, pincode',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Color(0xFFDCE5E2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: Color(0xFFDCE5E2)),
                  ),
                  suffixIcon: widget.search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            widget.search.clear();
                            widget.onSearch('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Refresh', onPressed: widget.onRefresh, icon: const Icon(Icons.refresh)),
          ],
        ),
      ],
    );
  }

  /// The number tiles and the 7-day chart: side by side on wide screens, stacked on tablets.
  Widget _overview(DashboardStats s, double width) {
    final tiles = [
      _Stat(
        icon: Icons.inventory_2_outlined,
        tone: const Color(0xFF0B5B4E),
        value: '${s.toPack}',
        label: 'To pack',
        hint: 'Paid, waiting to be packed',
        onTap: () => widget.onFilter(OrderFilter.toPack),
      ),
      _Stat(
        icon: Icons.local_shipping_outlined,
        tone: const Color(0xFF5B3F73),
        value: '${s.readyToShip}',
        label: 'Ready to ship',
        hint: 'Packed, hand to courier',
        onTap: () => widget.onFilter(OrderFilter.packed),
      ),
      _Stat(
        icon: Icons.route_outlined,
        tone: const Color(0xFF2B3A5C),
        value: '${s.inTransit}',
        label: 'On the way',
        hint: 'Shipped or out for delivery',
        onTap: () => widget.onFilter(OrderFilter.shipped),
      ),
      _Stat(
        icon: Icons.check_circle_outline,
        tone: const Color(0xFF3E5E3C),
        value: '${s.deliveredToday}',
        label: 'Delivered today',
        hint: 'Reached the customer',
        onTap: () => widget.onFilter(OrderFilter.delivered),
      ),
      _Stat(
        icon: Icons.hourglass_empty,
        tone: const Color(0xFF8A5A00),
        value: '${s.awaitingPayment}',
        label: 'Awaiting payment',
        hint: 'Checkout not paid yet',
        onTap: () => widget.onFilter(OrderFilter.unpaid),
      ),
      _Stat(
        icon: Icons.currency_rupee,
        tone: const Color(0xFF8E4A30),
        value: rupees(s.revenue7d),
        label: 'Sales, 7 days',
        hint: 'Orders not cancelled',
      ),
    ];
    // Tiles in a grid with the chart beside it, as tall as the grid; on narrow widths the chart goes underneath.
    const gap = 12.0;
    final side = width >= 680;
    final across = width >= 1180 || !side ? 3 : 2;
    final rows = (tiles.length / across).ceil();
    final gridHeight = rows * _Stat.height + (rows - 1) * gap;
    final grid = LayoutBuilder(
      builder: (context, c) {
        final tileWidth = (c.maxWidth - gap * (across - 1)) / across;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: tileWidth, height: _Stat.height, child: t)],
        );
      },
    );
    if (side) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: across == 3 ? 3 : 5, child: grid),
          const SizedBox(width: 16),
          Expanded(
            flex: across == 3 ? 2 : 4,
            child: SizedBox(
              height: gridHeight,
              child: _WeekChart(stats: s),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        grid,
        const SizedBox(height: 16),
        SizedBox(height: 220, child: _WeekChart(stats: s)),
      ],
    );
  }

  Widget _tableToolbar() {
    return Row(
      children: [
        const Text(
          'All orders',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0C1C19)),
        ),
        const SizedBox(width: 12),
        Text('${widget.orders.length} shown', style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 13.5)),
        const SizedBox(width: 16),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in OrderFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.label), selected: widget.filter == f, onSelected: (_) => widget.onFilter(f)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- sidebar

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.wide,
    required this.server,
    required this.onSettings,
    required this.onSignOut,
    required this.onAnalytics,
    required this.onRefunds,
    required this.onModules,
    required this.onClose,
    this.nav,
  });
  final bool wide;
  final String server;
  final VoidCallback onSettings, onSignOut, onAnalytics, onRefunds, onModules, onClose;
  final AdminNav? nav;

  @override
  Widget build(BuildContext context) {
    Widget heading(String text) => wide
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 8, 6),
            child: Text(text.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8DB8AE), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
          )
        : const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 14), child: Divider(height: 1, color: Color(0x33FFFFFF)));

    Widget item(IconData icon, String label, {bool active = false, VoidCallback? onTap, bool compact = false}) {
      final color = active ? Colors.white : const Color(0xFFB9D6CF);
      final child = Container(
        height: compact ? 38 : 46,
        padding: EdgeInsets.symmetric(horizontal: wide ? 14 : 0),
        decoration: BoxDecoration(color: active ? Colors.white.withValues(alpha: .12) : null, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: compact ? 19 : 22),
            if (wide) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
              ),
            ],
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: wide ? '' : label,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: child),
          ),
        ),
      );
    }

    return Container(
      width: wide ? 228 : 76,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B5B4E), Color(0xFF083F37)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandLogo(height: 40),
                        SizedBox(height: 6),
                        Text(
                          'ORDER DESK',
                          style: TextStyle(color: Color(0xFFB9D6CF), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close the sidebar',
                  onPressed: onClose,
                  icon: const Icon(Icons.keyboard_double_arrow_left, color: Color(0xFFB9D6CF)),
                ),
              ],
            )
          else
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Image.asset('assets/brand/icon.png', fit: BoxFit.contain, semanticLabel: 'PIAX'),
            ),
          if (!wide) ...[
            const SizedBox(height: 12),
            Center(
              child: IconButton(
                tooltip: 'Close the sidebar',
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_double_arrow_left, color: Color(0xFFB9D6CF)),
              ),
            ),
          ],
          const SizedBox(height: 28),
          // Pages, then every admin module by group; scrolls when the window is short.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                item(Icons.dashboard_outlined, 'Orders', active: true),
                item(Icons.insights_outlined, 'Analytics', onTap: onAnalytics),
                item(Icons.currency_exchange, 'Refunds', onTap: onRefunds),
                if (nav == null)
                  item(Icons.apps_outlined, 'Admin modules', onTap: onModules)
                else ...[
                  heading('Admin'),
                  item(Icons.space_dashboard_outlined, 'Admin overview', onTap: nav!.overview),
                  item(Icons.apps_outlined, 'All modules', onTap: nav!.allModules),
                  for (final group in moduleGroups) ...[
                    heading(group),
                    for (final m in modules.where((m) => m.group == group)) item(m.icon, m.title, onTap: () => nav!.module(m.key), compact: true),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Text(
                server.replaceFirst(RegExp(r'^https?://'), ''),
                style: const TextStyle(color: Color(0xFF8DB8AE), fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          item(Icons.settings_outlined, 'Settings', onTap: onSettings),
          item(Icons.logout, 'Sign out', onTap: onSignOut),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- overview

/// A number tile: icon on the left, the number and what it means beside it. Tapping it filters the table.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.tone, required this.value, required this.label, required this.hint, this.onTap});
  final IconData icon;
  final Color tone;
  final String value, label, hint;
  final VoidCallback? onTap;

  static const height = 92.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      // Narrow tiles keep the number and label; the explanation moves to a tooltip.
      final roomy = c.maxWidth >= 230;
      return Tooltip(message: roomy ? '' : hint, child: _tile(roomy));
    },
  );

  Widget _tile(bool roomy) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE1E8E6)),
        ),
        child: Row(
          children: [
            Container(
              width: roomy ? 42 : 36,
              height: roomy ? 42 : 36,
              decoration: BoxDecoration(color: tone.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: tone, size: roomy ? 22 : 20),
            ),
            SizedBox(width: roomy ? 12 : 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0C1C19), height: 1.1),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFF0C1C19)),
                  ),
                  if (roomy)
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12),
                    ),
                ],
              ),
            ),
            if (onTap != null && roomy) const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9AAEA9)),
          ],
        ),
      ),
    ),
  );
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats});
  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final peak = stats.perDay.fold(0, (a, b) => a > b ? a : b);
    final total = stats.perDay.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E8E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Orders, last 7 days',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: Color(0xFF0C1C19)),
                ),
              ),
              Text('$total total', style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${weekdayDate(stats.days[i])}: ${stats.perDay[i]} ${stats.perDay[i] == 1 ? 'order' : 'orders'}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${stats.perDay[i]}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF5B6B67)),
                            ),
                            const SizedBox(height: 4),
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: peak == 0 ? .04 : (stats.perDay[i] / peak).clamp(.04, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: i == 6 ? [brand2, brand] : [const Color(0xFFB7DDD3), const Color(0xFF9CCFC2)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                i == 6 ? 'Today' : weekdayShort(stats.days[i]),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: i == 6 ? brand : const Color(0xFF5B6B67),
                                  fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.ink,
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });
  final Color color, ink;
  final IconData icon;
  final String text, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, color: ink),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: ink, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: TextStyle(color: ink, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- table

/// Which columns fit: narrower tables drop the place and item columns first.
class _TableColumns {
  const _TableColumns({required this.place, required this.items, required this.payment});
  final bool place, items, payment;

  factory _TableColumns.forWidth(double width) => _TableColumns(place: width >= 860, items: width >= 760, payment: width >= 620);
}

const _rowPadding = EdgeInsets.symmetric(horizontal: 18);
const _headStyle = TextStyle(color: Color(0xFF5B6B67), fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: .4);

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns, required this.sortBy, required this.ascending, required this.onSort});
  final _TableColumns columns;
  final SortBy sortBy;
  final bool ascending;
  final ValueChanged<SortBy> onSort;

  @override
  Widget build(BuildContext context) {
    Widget sortable(String label, SortBy by, {TextAlign align = TextAlign.start}) => InkWell(
      onTap: () => onSort(by),
      borderRadius: BorderRadius.circular(6),
      // Shrinks to fit a narrow column rather than overflowing it.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align == TextAlign.end ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _headStyle.copyWith(color: sortBy == by ? brand : null)),
            Icon(
              sortBy == by ? (ascending ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 14,
              color: sortBy == by ? brand : const Color(0xFF9AAEA9),
            ),
          ],
        ),
      ),
    );
    return Container(
      height: 46,
      padding: _rowPadding,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAF9),
        border: Border(bottom: BorderSide(color: Color(0xFFE1E8E6))),
      ),
      child: Row(
        children: [
          const Expanded(flex: 23, child: Text('ORDER', style: _headStyle)),
          const Expanded(flex: 22, child: Text('CUSTOMER', style: _headStyle)),
          if (columns.place) const Expanded(flex: 16, child: Text('DELIVER TO', style: _headStyle)),
          if (columns.items) const Expanded(flex: 8, child: Text('PACKS', style: _headStyle)),
          Expanded(
            flex: 11,
            child: Align(
              alignment: Alignment.centerRight,
              child: sortable('TOTAL', SortBy.total, align: TextAlign.end),
            ),
          ),
          const SizedBox(width: 20),
          if (columns.payment) const Expanded(flex: 13, child: Text('PAYMENT', style: _headStyle)),
          const Expanded(flex: 15, child: Text('STATUS', style: _headStyle)),
          Expanded(
            flex: 12,
            child: Align(alignment: Alignment.centerLeft, child: sortable('PLACED', SortBy.placed)),
          ),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.order,
    required this.columns,
    required this.isNew,
    required this.selected,
    required this.divider,
    required this.onTap,
  });
  final Order order;
  final _TableColumns columns;
  final bool isNew, selected, divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF0C1C19);
    const muted = Color(0xFF5B6B67);
    final payment = order.payment;
    final (payText, payColor) = switch ((payment.method, payment.status)) {
      ('cod', 'paid') => ('Cash · collected', const Color(0xFF3E5E3C)),
      ('cod', _) => ('Cash on delivery', const Color(0xFF8A5A00)),
      (_, 'paid') => ('Paid online', const Color(0xFF3E5E3C)),
      (_, 'refund_pending') => ('Refund pending', const Color(0xFF8B2E2E)),
      (_, 'refunding') => ('Refund being sent', const Color(0xFF8A5A00)),
      (_, 'refunded') => ('Refunded', const Color(0xFF5B6B67)),
      (_, 'failed') => ('Payment failed', const Color(0xFF8B2E2E)),
      _ => ('Not paid yet', const Color(0xFF8A5A00)),
    };
    final place = [order.address.city, order.address.pincode].where((p) => p.isNotEmpty).join(' · ');
    return Material(
      color: selected ? const Color(0xFFE6F4EF) : Colors.white,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFFF2F8F6),
        child: Container(
          height: 64,
          padding: _rowPadding,
          decoration: BoxDecoration(
            border: divider ? const Border(bottom: BorderSide(color: Color(0xFFEDF2F0))) : null,
            // The open order's green edge.
            gradient: selected
                ? const LinearGradient(colors: [brand, brand, Colors.transparent, Colors.transparent], stops: [0, .004, .004, 1])
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 23,
                child: Row(
                  children: [
                    if (isNew) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(6)),
                        child: const Text(
                          'NEW',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        order.id,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 22,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName.isEmpty ? 'No name' : order.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: ink, fontSize: 14),
                    ),
                    Text(
                      order.customerPhone,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (columns.place)
                Expanded(
                  flex: 16,
                  child: Text(
                    place,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontSize: 13.5),
                  ),
                ),
              if (columns.items)
                Expanded(
                  flex: 8,
                  child: Text('${order.itemCount}', style: const TextStyle(color: ink, fontSize: 13.5)),
                ),
              Expanded(
                flex: 11,
                child: Text(
                  rupees(order.totals.total),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: ink, fontSize: 14),
                ),
              ),
              const SizedBox(width: 20),
              if (columns.payment)
                Expanded(
                  flex: 13,
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: payColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          payText,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: payColor, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                flex: 15,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(fit: BoxFit.scaleDown, child: StatusBadge(order.status)),
                ),
              ),
              Expanded(
                flex: 12,
                child: Tooltip(
                  message: dateTime(order.createdAt),
                  child: Text(
                    agoShort(order.createdAt),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableMessage extends StatelessWidget {
  const _TableMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Column(
      children: [
        Icon(icon, size: 36, color: const Color(0xFF9AAEA9)),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 15),
        ),
      ],
    ),
  );
}
