import '../admin_modules/admin_drawer.dart';
import '../admin_modules/admin_search.dart';
import '../admin_modules/modules_screens.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../session.dart';
import 'login_screen.dart' show signOut;
import 'order_detail_screen.dart';
import 'analytics_screen.dart';
import 'dashboard_view.dart';
import 'refunds_screen.dart';
import 'settings_screen.dart';

enum OrderFilter {
  open('Open', 'open'),
  toPack('To pack', 'confirmed'),
  packed('Packed', 'packed'),
  shipped('Shipped', 'shipped'),
  outForDelivery('Out for delivery', 'out_for_delivery'),
  unpaid('Awaiting payment', 'placed'),
  delivered('Delivered', 'delivered'),
  cancelled('Cancelled', 'cancelled'),
  all('All', 'all');

  const OrderFilter(this.label, this.api);
  final String label, api;
}

/// The order list. While it's on screen it checks for new orders every 30 seconds and flags paid orders the admin
/// hasn't opened yet as NEW. Unpaid checkouts aren't announced: they show up once the payment goes through.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.api, this.nav, this.embedded = false});
  final AdminApi api;

  /// The app frame's navigation (every page and module). Without it, the orders screen opens them itself.
  final AdminNav? nav;

  /// Inside the app frame: the frame's sidebar is used, not the dashboard's own.
  final bool embedded;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 30);

  late AdminApi _api = widget.api;
  final _search = TextEditingController();
  bool _defaultPassword = false;
  OrderFilter _filter = OrderFilter.open;
  List<Order> _orders = [];

  /// The newest orders of every status (the API returns up to 300): the dashboard's numbers and chart come from these.
  List<Order> _all = [];

  /// The order open in the desktop dashboard's side panel.
  String? _selectedId;
  bool _loading = true;
  String? _error;
  Set<String> _seen = {};
  Set<String> _fresh = {};
  int _toPack = 0;
  Timer? _poll;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // Checks only while the app is in front: on return it checks at once, then every 30 s.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForNew();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
    }
  }

  Future<void> _start() async {
    final saved = await Session.seenOrderIds();
    _seen = saved ?? {};
    // First run on this phone: nothing is "new" yet, so the whole backlog isn't flagged.
    await _checkForNew(firstRun: saved == null);
    await _load();
    _startPolling();
    _checkAccount();
  }

  Future<void> _checkAccount() async {
    try {
      final account = await _api.account();
      if (mounted) setState(() => _defaultPassword = account.defaultPassword);
    } on ApiException catch (_) {
      // Only drives the reminder banner; the order list reports connection problems itself.
    }
  }

  void _openRefunds() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RefundsScreen(api: _api))).then((_) => _refresh());

  void _openAnalytics() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnalyticsScreen(api: _api)));
  void _openModules({String? module, String? status, bool create = false, bool all = false}) => Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: ModulesHomeScreen.routeName),
      builder: (_) => ModulesHomeScreen(api: _api, appNav: _nav, initialModule: module, initialStatus: status, startAdding: create, showAllModules: all),
    ),
  );

  /// Every page and admin module, for the side menu, the phone drawer and the search.
  AdminNav get _nav => widget.nav ?? AdminNav(
    orders: () {},
    analytics: _openAnalytics,
    refunds: _openRefunds,
    settings: _openSettings,
    overview: _openModules,
    allModules: () => _openModules(all: true),
    module: (key, {status, create = false}) => _openModules(module: key, status: status, create: create),
  );

  Future<void> _openSettings() async {
    final api = await Navigator.of(context).push<AdminApi>(MaterialPageRoute(builder: (_) => SettingsScreen(api: _api)));
    if (api == null || !mounted) return;
    setState(() => _api = api);
    _checkAccount();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) async {
      await _checkForNew();
      if (_filter != OrderFilter.open || _search.text.isNotEmpty) await _load(quiet: true);
    });
  }

  /// Fetches the newest orders to spot new paid ones, feed the dashboard, and refresh the list when it's showing open
  /// orders.
  Future<void> _checkForNew({bool firstRun = false}) async {
    try {
      final all = await _api.orders(status: 'all');
      final open = all.where((o) => !o.status.isFinal).toList();
      final paid = open.where((o) => o.payment.isPaid && o.status != OrderStatus.placed);
      if (firstRun) {
        _seen = paid.map((o) => o.id).toSet();
        await Session.saveSeenOrderIds(_seen);
      }
      final fresh = paid.where((o) => !_seen.contains(o.id)).map((o) => o.id).toSet();
      final arrived = fresh.difference(_fresh);
      if (!mounted) return;
      setState(() {
        _all = all;
        _fresh = fresh;
        _toPack = open.where((o) => o.status == OrderStatus.confirmed).length;
        if (_filter == OrderFilter.open && _search.text.isEmpty) {
          _orders = open;
          _error = null;
          _loading = false;
        }
      });
      if (arrived.isNotEmpty && !firstRun) _announce(arrived.length);
    } on ApiException catch (e) {
      if (e.signedOut && mounted) await signOut(context, message: 'Your session ended. Please sign in again.');
    }
  }

  void _announce(int count) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(count == 1 ? '🛍️ New order received' : '🛍️ $count new orders received'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Show',
            onPressed: () {
              _search.clear();
              _setFilter(OrderFilter.toPack);
            },
          ),
        ),
      );
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final orders = await _api.orders(status: _filter.api, query: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _error = null;
      });
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _checkForNew();
    await _load(quiet: true);
  }

  void _setFilter(OrderFilter filter) {
    setState(() => _filter = filter);
    _load();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Opens an order: in the dashboard's side panel when [split], else as its own page.
  Future<void> _open(Order order, {bool split = false}) async {
    if (_fresh.contains(order.id) || !_seen.contains(order.id)) {
      _seen.add(order.id);
      setState(() => _fresh.remove(order.id));
      await Session.saveSeenOrderIds(_seen);
    }
    if (!mounted) return;
    if (split) return setState(() => _selectedId = order.id);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(api: _api, orderId: order.id, initial: order),
      ),
    );
    if (changed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= dashboardMinWidth ? _dashboard() : _phone());
  }

  Widget _dashboard() => OrdersDashboard(
    api: _api,
    all: _all,
    orders: _orders,
    loading: _loading,
    error: _error,
    filter: _filter,
    search: _search,
    fresh: _fresh,
    defaultPassword: _defaultPassword,
    selectedId: _selectedId,
    onFilter: _setFilter,
    onSearch: _onSearch,
    onRefresh: _refresh,
    onOpen: (order, {required split}) => _open(order, split: split),
    onCloseOrder: () => setState(() => _selectedId = null),
    onOrderChanged: _refresh,
    onSettings: _openSettings,
    onSignOut: () => signOut(context),
    onAnalytics: _openAnalytics,
    onRefunds: _openRefunds,
    onModules: _openModules,
    nav: _nav,
    showSidebar: !widget.embedded,
  );

  Widget _phone() {
    return Scaffold(
      drawer: AdminDrawer(nav: _nav, server: _api.base, onSignOut: () => signOut(context)),
      appBar: AppBar(
        title: const Text('PIAX Orders', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          AdminSearchBar(nav: _nav, compact: true),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') _openSettings();
              if (value == 'analytics') _openAnalytics();
              if (value == 'refunds') _openRefunds();
              if (value == 'modules') _openModules();
              if (value == 'signout') signOut(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(_api.base, style: const TextStyle(fontSize: 13))),
              const PopupMenuItem(
                value: 'analytics',
                child: ListTile(leading: Icon(Icons.insights_outlined), title: Text('Analytics'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'refunds',
                child: ListTile(leading: Icon(Icons.currency_exchange), title: Text('Refunds'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'modules',
                child: ListTile(leading: Icon(Icons.apps_outlined), title: Text('Admin modules'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Order no., name, phone or pincode',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in OrderFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f == OrderFilter.toPack && _toPack > 0 ? '${f.label} · $_toPack' : f.label),
                      selected: _filter == f,
                      onSelected: (_) => _setFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          if (_defaultPassword)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: const Color(0xFFFFF4D6),
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
                  title: const Text(
                    'Change the default password',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6B4600)),
                  ),
                  subtitle: const Text(
                    'Anyone who knows admin / admin can see customer details.',
                    style: TextStyle(color: Color(0xFF6B4600)),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A5A00)),
                  onTap: _openSettings,
                ),
              ),
            ),
          if (_fresh.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: const Color(0xFFDDF3EC),
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.notifications_active_outlined, color: brand),
                  title: Text(
                    _fresh.length == 1 ? '1 new order to look at' : '${_fresh.length} new orders to look at',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: brand),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: brand),
                  onTap: () {
                    _search.clear();
                    _setFilter(OrderFilter.toPack);
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _orders.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _orders.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        text: _error!,
        action: FilledButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            _Message(
              icon: Icons.inbox_outlined,
              text: _search.text.isNotEmpty ? 'No orders match “${_search.text}”.' : 'No ${_filter.label.toLowerCase()} orders.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _OrderCard(order: _orders[i], isNew: _fresh.contains(_orders[i].id), onTap: () => _open(_orders[i])),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.isNew, required this.onTap});
  final Order order;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = const TextStyle(color: Color(0xFF5B6B67), fontSize: 13.5);
    final place = [order.address.city, order.address.pincode].where((p) => p.isNotEmpty).join(' · ');
    return Card(
      shape: isNew
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: brand, width: 1.5),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isNew) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(6)),
                      child: const Text(
                        'NEW',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(order.id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  StatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.customerName.isEmpty ? 'No name' : order.customerName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              if (place.isNotEmpty) Text(place, style: muted),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${order.itemCount} ${order.itemCount == 1 ? 'pack' : 'packs'} · ${rupees(order.totals.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!order.payment.isPaid) ...[
                    const SizedBox(width: 8),
                    Text(
                      order.payment.statusLabel,
                      style: const TextStyle(color: Color(0xFF8A5A00), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const Spacer(),
                  Text(ago(order.createdAt), style: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: const Color(0xFF9AAEA9)),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 15),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}
