import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/brand.dart';
import 'login_screen.dart' show signOut;
import 'order_detail_screen.dart';

/// Every cancelled order that was paid online, by where its refund stands, so refunds can be verified:
///   Due          cancelled and paid, not refunded yet (or a refund that failed): refund it here
///   In progress  sent to Razorpay, not processed yet
///   Completed    processed by Razorpay, with the bank reference (ARN) once there is one
/// Opening the page checks every unfinished refund with Razorpay; "Check all" does it again.
class RefundsScreen extends StatefulWidget {
  const RefundsScreen({super.key, required this.api});
  final AdminApi api;

  @override
  State<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends State<RefundsScreen> {
  List<Order>? _orders;
  String? _error;
  bool _checking = false;
  DateTime? _checkedAt;
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _load(check: true);
  }

  Future<void> _load({bool check = false}) async {
    try {
      final orders = await widget.api.orders(status: 'refunds');
      if (!mounted) return;
      setState(() => (_orders = orders, _error = null));
      if (check) await _checkAll();
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Asks Razorpay about every refund that isn't processed yet, one at a time, updating each row as it comes back.
  Future<void> _checkAll() async {
    final pending = (_orders ?? []).where((o) => o.payment.refund != null && !o.payment.refund!.processed).toList();
    if (pending.isEmpty) {
      setState(() => _checkedAt = DateTime.now());
      return;
    }
    setState(() => _checking = true);
    String? problem;
    for (final order in pending) {
      try {
        _replace(await widget.api.checkRefund(order.id));
      } on ApiException catch (e) {
        if (e.signedOut) {
          if (mounted) await signOut(context, message: 'Your session ended. Please sign in again.');
          return;
        }
        problem ??= e.message;
      }
    }
    if (!mounted) return;
    setState(() => (_checking = false, _checkedAt = DateTime.now()));
    if (problem != null) _toast(problem);
  }

  void _replace(Order order) {
    if (!mounted) return;
    setState(() => _orders = [for (final o in _orders ?? <Order>[]) o.id == order.id ? order : o]);
  }

  Future<void> _check(Order order) async {
    setState(() => _working.add(order.id));
    try {
      final updated = await widget.api.checkRefund(order.id);
      _replace(updated);
      _toast(
        updated.payment.refund?.statusLabel ?? (updated.needsRefund ? 'Razorpay says the refund failed. It’s due again.' : 'Checked.'),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _working.remove(order.id));
    }
  }

  Future<void> _refund(Order order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Refund ${rupees(order.totals.total)}?'),
        content: Text(
          'The full ${rupees(order.totals.total)} for ${order.id} goes back to the customer’s original payment method through '
          'Razorpay (5–7 working days), and they get an email. This can’t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Refund ${rupees(order.totals.total)}')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working.add(order.id));
    try {
      _replace(await widget.api.refund(order.id));
      _toast('Refunded ${rupees(order.totals.total)} for ${order.id}.');
    } on ApiException catch (e) {
      _toast(e.message);
      await _load();
    } finally {
      if (mounted) setState(() => _working.remove(order.id));
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _open(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(api: widget.api, orderId: order.id, initial: order),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F6F5),
        title: const Text('Refunds', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          TextButton.icon(
            onPressed: _checking || orders == null ? null : _checkAll,
            icon: _checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined),
            label: Text(_checking ? 'Checking…' : 'Check all with Razorpay'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: orders == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(onRefresh: () => _load(check: true), child: _list(orders)),
    );
  }

  Widget _list(List<Order> orders) {
    final due = orders.where((o) => o.needsRefund).toList();
    final inProgress = orders
        .where((o) => o.payment.status == 'refunding' || (o.payment.refund != null && !o.payment.refund!.processed))
        .toList();
    final done = orders.where((o) => o.payment.refund?.processed == true).toList();
    int sum(List<Order> list) => list.fold(0, (n, o) => n + (o.payment.refund?.amount ?? o.totals.total));

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth >= Breakpoints.tablet ? 28.0 : 16.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 40),
          children: [
            PageWidth(
              maxWidth: 1100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tile(
                        label: 'Refunds due',
                        value: '${due.length}',
                        detail: rupees(sum(due)),
                        color: const Color(0xFF8A5A00),
                        icon: Icons.pending_actions_outlined,
                      ),
                      _Tile(
                        label: 'In progress',
                        value: '${inProgress.length}',
                        detail: rupees(sum(inProgress)),
                        color: const Color(0xFF2B3A5C),
                        icon: Icons.hourglass_top,
                      ),
                      _Tile(
                        label: 'Completed',
                        value: '${done.length}',
                        detail: rupees(sum(done)),
                        color: const Color(0xFF2F5A2C),
                        icon: Icons.check_circle_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _checking
                        ? 'Checking refunds with Razorpay…'
                        : _checkedAt == null
                        ? ''
                        : 'Checked with Razorpay at ${timeOnly(_checkedAt!)}. Normal refunds usually show in the customer’s bank within 5–7 working days.',
                    style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  _Group(
                    title: 'Due',
                    hint: 'Cancelled after paying online. The money hasn’t gone back yet.',
                    empty: 'No refunds due.',
                    children: [for (final o in due) _row(o)],
                  ),
                  const SizedBox(height: 16),
                  _Group(
                    title: 'In progress',
                    hint: 'Sent to Razorpay, not processed yet.',
                    empty: 'Nothing in progress.',
                    children: [for (final o in inProgress) _row(o)],
                  ),
                  const SizedBox(height: 16),
                  _Group(
                    title: 'Completed',
                    hint: 'Processed by Razorpay. The bank reference (ARN) is what the customer’s bank can trace it with.',
                    empty: 'No completed refunds yet.',
                    children: [for (final o in done) _row(o)],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(Order order) {
    final r = order.payment.refund;
    final busy = _working.contains(order.id);
    final (chipBg, chipInk, chipText) = order.needsRefund
        ? (const Color(0xFFFFF4D6), const Color(0xFF6B4600), order.payment.failedRefund != null ? 'Last refund failed' : 'Refund due')
        : r == null
        ? (const Color(0xFFE1EAF7), const Color(0xFF2B3A5C), 'Being sent')
        : r.processed
        ? (const Color(0xFFE3EDE2), const Color(0xFF2F5A2C), 'Processed')
        : (const Color(0xFFE1EAF7), const Color(0xFF2B3A5C), r.status == 'pending' ? 'Pending at Razorpay' : 'Sent');

    return InkWell(
      onTap: () => _open(order),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(order.id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          chipText,
                          style: TextStyle(color: chipInk, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (r?.test == true) const Text('test, no money moved', style: TextStyle(color: Color(0xFF5B6B67), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.customerName.isEmpty ? 'No name' : order.customerName} · ${rupees(r?.amount ?? order.totals.total)}'
                    '${order.cancelReason == null ? '' : ' · ${order.cancelReason}'}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  if (r != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Refunded ${dateTime(r.at)} · ${r.id}${r.checkedAt == null ? '' : ' · checked ${ago(r.checkedAt!)}'}',
                      style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12.5),
                    ),
                    if (r.arn != null)
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: r.arn!));
                          _toast('Bank reference copied');
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Bank reference (ARN): ${r.arn}  ⧉',
                            style: const TextStyle(color: brand, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                  if (order.payment.failedRefund != null && order.needsRefund)
                    Text(
                      'Razorpay reported refund ${order.payment.failedRefund!.id} as failed. Refund it again.',
                      style: const TextStyle(color: Color(0xFF8B2E2E), fontSize: 12.5),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (order.needsRefund)
              FilledButton(onPressed: () => _refund(order), child: const Text('Refund now'))
            else if (r != null && !r.processed)
              OutlinedButton(onPressed: () => _check(order), child: const Text('Check'))
            else
              const Icon(Icons.chevron_right, color: Color(0xFF9AAEA9)),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.detail, required this.color, required this.icon});
  final String label, value, detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE1E8E6)),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)),
              ),
              Text('$label · $detail', style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12.5)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.hint, required this.empty, required this.children});
  final String title, hint, empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1E8E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$title (${children.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0C1C19)),
        ),
        Text(hint, style: const TextStyle(color: Color(0xFF5B6B67), fontSize: 12.5)),
        const SizedBox(height: 6),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(empty, style: const TextStyle(color: Color(0xFF9AAEA9))),
          )
        else
          for (final (i, child) in children.indexed) ...[if (i > 0) const Divider(height: 1), child],
      ],
    ),
  );
}
