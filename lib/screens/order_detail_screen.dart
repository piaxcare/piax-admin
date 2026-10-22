import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../format.dart';
import '../models.dart';
import '../whatsapp.dart';
import '../widgets/brand.dart';
import 'login_screen.dart' show signOut;
import 'package:piax_orders_admin/palette.dart';
import 'package:piax_orders_admin/admin_modules/admin_search.dart' show globalSearchActions;

/// One order: its step and actions, the customer's contact and delivery address, the items, payment and timeline.
/// As its own page it pops `true` when the order was changed, so the list refreshes. [embedded] shows it inside the
/// desktop dashboard's side panel instead: a close button calls [onClose], and each change calls [onChanged]. With
/// [onToggleExpand], the panel's header has an expand button: [expanded] is true while the panel fills the screen, and
/// the order then uses the two-column layout of the full page.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.api,
    required this.orderId,
    this.initial,
    this.embedded = false,
    this.expanded = false,
    this.onChanged,
    this.onClose,
    this.onToggleExpand,
  });
  final bool embedded;
  final bool expanded;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpand;
  final AdminApi api;
  final String orderId;
  final Order? initial;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Order? _order;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  /// Everything the website knows about this customer (null until loaded, or if that failed).
  CustomerProfile? _profile;
  bool _openingInvoice = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    _reload();
    _loadProfile();
    _loadWhatsApp();
  }

  /// Whether the website sends WhatsApp Business templates (and the step updates automatically). Null: unknown, so the
  /// app uses its manual WhatsApp messages.
  ({bool api, bool automatic})? _whatsApp;

  Future<void> _loadWhatsApp() async {
    try {
      final status = await widget.api.whatsappStatus();
      if (mounted) setState(() => _whatsApp = status);
    } on ApiException catch (_) {
      // Older website without the templates route: manual messages.
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.api.customer(widget.orderId);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (_) {
      // Only adds detail to the customer card; it works without it.
    }
  }

  /// Opens the invoice PDF in the browser or PDF viewer, through a 5-minute link from the website.
  Future<void> _openInvoice() async {
    setState(() => _openingInvoice = true);
    try {
      final url = await widget.api.invoiceLink(widget.orderId);
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _toast('Couldn’t open the invoice. Is a browser or PDF viewer installed?');
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _openingInvoice = false);
    }
  }

  void _openPastOrder(PastOrder past) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OrderDetailScreen(api: widget.api, orderId: past.id),
    ),
  );

  Future<void> _reload() async {
    try {
      final order = await widget.api.order(widget.orderId);
      if (mounted) setState(() => (_order = order, _error = null));
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _move(OrderStatus status, {String? note, String? courier, String? number, bool refundAfter = false}) async {
    setState(() => _busy = true);
    try {
      var order = await widget.api.updateStatus(widget.orderId, status, note: note, courier: courier, trackingNumber: number);
      // "Cancel and refund": the refund goes out right after the cancel is saved. If it fails, the order stays
      // cancelled with its refund due, and the Refund button is there to try again.
      if (refundAfter && order.needsRefund) {
        try {
          order = await widget.api.refund(widget.orderId);
        } on ApiException catch (e) {
          if (e.signedOut) rethrow;
          if (mounted) _toast(e.message);
        }
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _changed = true;
        widget.onChanged?.call();
        _busy = false;
      });
      // Step 2, only once the website has saved the new step: the matching WhatsApp message, ready to send.
      final message = order.payment.status == 'refunded' ? CustomerMessage.refunded : CustomerMessage.forStatus(order.status);
      // With automatic WhatsApp updates on, the website has already told the customer about this step.
      if (message != null && message.template != null && _whatsApp?.automatic == true && message.sentAt(order) != null) {
        if (mounted) _toast('Marked as ${order.status.label.toLowerCase()}. The customer was notified on WhatsApp automatically.');
        return;
      }
      final sent = message != null && await _compose(message, justMarked: order.status);
      if (!mounted) return;
      if (!sent) _toast('Marked as ${order.status.label.toLowerCase()}. The customer wasn’t messaged.');
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('$what copied');
  }

  Future<void> _advance(OrderStatus next) async {
    if (next == OrderStatus.shipped) {
      final tracking = await showDialog<(String, String)>(context: context, builder: (_) => const _ShipDialog());
      if (tracking == null) return;
      return _move(next, courier: tracking.$1, number: tracking.$2);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as ${next.label.toLowerCase()}?'),
        content: Text('${_order!.id} moves to “${next.label}”. Steps can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Mark ${next.label.toLowerCase()}')),
        ],
      ),
    );
    if (ok == true) await _move(next);
  }

  Future<void> _cancel() async {
    final order = _order!;
    final paidOnline = order.payment.method == 'razorpay' && order.payment.status == 'paid';
    final choice = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => _CancelDialog(refundAmount: paidOnline ? order.totals.total : null),
    );
    if (choice == null || choice.$1.isEmpty) return;
    await _move(OrderStatus.cancelled, note: choice.$1, refundAfter: choice.$2);
  }

  bool _checkingRefund = false;

  /// Asks Razorpay where this order's refund stands (processed / pending / failed, bank reference) and shows it.
  Future<void> _checkRefund() async {
    setState(() => _checkingRefund = true);
    try {
      final updated = await widget.api.checkRefund(widget.orderId);
      if (!mounted) return;
      setState(() => _order = updated);
      widget.onChanged?.call();
      _toast(updated.payment.refund?.statusLabel ?? 'Razorpay says the refund failed. It’s due again.');
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _checkingRefund = false);
    }
  }

  /// Refunds a cancelled, paid order in full (after a confirmation), then offers the "Refund issued" message.
  Future<void> _refund() async {
    final order = _order!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Refund ${rupees(order.totals.total)}?'),
        content: Text(
          'The full ${rupees(order.totals.total)} goes back to the customer’s original payment method through Razorpay, '
          'and they get an email. This can’t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Refund ${rupees(order.totals.total)}')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.refund(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _changed = true;
        _busy = false;
      });
      widget.onChanged?.call();
      final sent = await _compose(CustomerMessage.refunded, justMarked: updated.status);
      if (mounted && !sent) {
        _toast(
          'Refunded ${rupees(updated.payment.refund?.amount ?? updated.totals.total)}. The customer is emailed if they gave an address.',
        );
      }
    } on ApiException catch (e) {
      if (e.signedOut && mounted) return signOut(context, message: 'Your session ended. Please sign in again.');
      if (mounted) _toast(e.message);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows [message] for the admin to check, then opens WhatsApp with it. [justMarked] is the step the order was just
  /// moved to, shown at the top of the popup. Returns false only when the admin skipped the message (any other
  /// problem has already been shown).
  Future<bool> _compose(CustomerMessage message, {OrderStatus? justMarked}) async {
    final order = _order!;
    var details = const <String, String>{};
    if (message.needsDetails) {
      final asked = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _DetailsDialog(message: message),
      );
      if (asked == null) return false;
      details = asked;
    }
    if (message.template != null && _whatsApp?.api == true) return _sendTemplate(message, details, justMarked: justMarked);
    if (whatsappNumber(order.customerPhone) == null) {
      _toast(
        justMarked == null
            ? 'This order has no valid phone number.'
            : 'Marked as ${justMarked.label.toLowerCase()}. No valid phone number to message.',
      );
      return true;
    }
    return _composeManual(message, details, justMarked: justMarked);
  }

  /// Has the website send [message]'s approved template (after a preview: template text can't be edited).
  Future<bool> _sendTemplate(CustomerMessage message, Map<String, String> details, {OrderStatus? justMarked}) async {
    final order = _order!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(justMarked == null ? 'Send “${message.label}”?' : 'Marked as ${justMarked.label.toLowerCase()}. Tell the customer?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sent by PIAX on WhatsApp Business to ${order.customerPhone}:', style: _muted),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const TColor(0xFFE7F6EE), borderRadius: BorderRadius.circular(12)),
                child: Text(message.textFor(order, details: details), style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(justMarked == null ? 'Cancel' : 'Skip')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send on WhatsApp'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.sendTemplate(order.id, message.template!, details: details);
      if (!mounted) return true;
      setState(() => _order = updated);
      widget.onChanged?.call();
      _toast('“${message.label}” sent to the customer on WhatsApp.');
    } on ApiException catch (e) {
      if (e.signedOut && mounted) {
        await signOut(context, message: 'Your session ended. Please sign in again.');
        return true;
      }
      // The API refused (template not approved yet, number not on WhatsApp…): fall back to the manual hand-off.
      if (mounted) _toast('WhatsApp Business couldn’t send it (${e.message}). Opening WhatsApp instead.');
      if (mounted) setState(() => _whatsApp = (api: false, automatic: _whatsApp?.automatic ?? false));
      if (!mounted) return true;
      setState(() => _busy = false);
      return _composeManual(message, details, justMarked: justMarked);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return true;
  }

  Future<bool> _composeManual(CustomerMessage message, Map<String, String> details, {OrderStatus? justMarked}) async {
    final order = _order!;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ComposeSheet(
        title: message.label,
        to: order.customerPhone,
        initial: message.textFor(order, details: details),
        justMarked: justMarked,
      ),
    );
    if (text == null) return false;
    final opened = await openWhatsApp(order.customerPhone, text);
    if (!opened) {
      if (mounted) _toast('Couldn’t open WhatsApp. Is it installed?');
      return true;
    }
    try {
      final updated = await widget.api.markMessageSent(order.id, message.api);
      if (mounted) setState(() => _order = updated);
      widget.onChanged?.call();
    } on ApiException catch (e) {
      if (mounted) _toast('WhatsApp opened, but the website didn’t record the message: ${e.message}');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final page = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded ? IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: widget.onClose) : null,
        title: Text(order?.id ?? widget.orderId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        actions: [
          ...globalSearchActions(context),
          IconButton(
            tooltip: 'Copy order number',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _copy(widget.orderId, 'Order number'),
          ),
          if (widget.embedded && widget.onToggleExpand != null)
            IconButton(
              tooltip: widget.expanded ? 'Back to side panel' : 'Expand to full screen',
              icon: Icon(widget.expanded ? Icons.close_fullscreen : Icons.open_in_full),
              onPressed: widget.onToggleExpand,
            ),
        ],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
      ),
      body: order == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(
              onRefresh: _reload,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // As its own page on a desktop or wide tablet, or the dashboard's panel expanded: the order and its
                  // actions on the left, the customer and delivery on the right. In the side panel and on phones: one column.
                  if ((!widget.embedded || widget.expanded) && constraints.maxWidth >= Breakpoints.desktop) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                      children: [
                        PageWidth(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _statusCard(order),
                                    const SizedBox(height: 16),
                                    if (order.status != OrderStatus.placed) ...[_messagesCard(order), const SizedBox(height: 16)],
                                    _itemsCard(order),
                                    const SizedBox(height: 16),
                                    _timelineCard(order),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [_customerCard(order), const SizedBox(height: 16), _addressCard(order)],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // This order first; the customer's earlier orders after it, across the page.
                        if (_historyCard() case final history?) ...[const SizedBox(height: 20), PageWidth(child: history)],
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      PageWidth(
                        maxWidth: 760,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _statusCard(order),
                            const SizedBox(height: 12),
                            if (order.status != OrderStatus.placed) ...[_messagesCard(order), const SizedBox(height: 12)],
                            _customerCard(order),
                            const SizedBox(height: 12),
                            _addressCard(order),
                            const SizedBox(height: 12),
                            _itemsCard(order),
                            const SizedBox(height: 12),
                            _timelineCard(order),
                            // This order first; the customer's earlier orders after it.
                            if (_historyCard() case final history?) ...[const SizedBox(height: 12), history],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
    if (widget.embedded) return page;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: page,
    );
  }

  Widget _statusCard(Order order) {
    final next = order.nextStep;
    return _Section(
      children: [
        Row(
          children: [
            StatusBadge(order.status),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Placed ${dateTime(order.createdAt)}', style: _muted, textAlign: TextAlign.end),
            ),
          ],
        ),
        if (order.tracking != null) ...[
          const SizedBox(height: 10),
          _Line(
            icon: Icons.local_shipping_outlined,
            text: '${order.tracking!.courier} · ${order.tracking!.number}',
            onTap: () => _copy(order.tracking!.number, 'Tracking number'),
          ),
        ],
        if (order.cancelReason != null) _Line(icon: Icons.info_outline, text: 'Cancelled: ${order.cancelReason}'),
        if (order.status == OrderStatus.cancelled && order.payment.method == 'razorpay') ...[
          const SizedBox(height: 12),
          _refundPanel(order),
        ],
        if (order.status == OrderStatus.placed)
          const _Line(icon: Icons.hourglass_empty, text: 'Waiting for the customer to pay online. It can only be cancelled until then.'),
        if (!order.status.isFinal) ...[
          const SizedBox(height: 14),
          if (next != null)
            FilledButton.icon(
              onPressed: _busy ? null : () => _advance(next),
              icon: Icon(_stepIcon(next)),
              label: Text('Mark as ${next.label.toLowerCase()}'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _cancel,
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Cancel order'),
          ),
        ],
      ],
    );
  }

  /// What happened to the money on a cancelled order paid online: due (with the Refund button), being sent, or done
  /// (with Razorpay's status, the bank reference and a check).
  Widget _refundPanel(Order order) {
    final p = order.payment;
    if (p.status == 'refunded') {
      final r = p.refund;
      final verified = r?.processed == true;
      return _Panel(
        color: verified ? const TColor(0xFFE3EDE2) : const TColor(0xFFE1EAF7),
        ink: verified ? const TColor(0xFF2F5A2C) : const TColor(0xFF2B3A5C),
        icon: verified ? Icons.verified_outlined : Icons.hourglass_top,
        title: 'Refunded ${rupees(r?.amount ?? order.totals.total)}${r == null ? '' : ' on ${dateTime(r.at)}'}',
        text: r == null
            ? 'Sent to the original payment method.'
            : [
                '${r.statusLabel}${r.checkedAt == null ? '' : ' (checked ${ago(r.checkedAt!)})'}.',
                'Refund ${r.id}${r.test ? ' (test, no money moved)' : ''}.',
                if (r.arn != null) 'Bank reference (ARN): ${r.arn}.',
                verified
                    ? 'It usually shows in the customer’s bank within 5–7 working days.'
                    : 'The customer is emailed if they gave an address.',
              ].join(' '),
        action: r == null
            ? null
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || _checkingRefund ? null : _checkRefund,
                    icon: _checkingRefund
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 18),
                    label: const Text('Check with Razorpay'),
                  ),
                  if (r.arn != null)
                    OutlinedButton.icon(
                      onPressed: () => _copy(r.arn!, 'Bank reference'),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('Copy ARN'),
                    ),
                ],
              ),
      );
    }
    if (p.status == 'refunding') {
      return const _Panel(
        color: TColor(0xFFFFF4D6),
        ink: TColor(0xFF6B4600),
        icon: Icons.hourglass_top,
        title: 'Refund being sent',
        text: 'Razorpay is processing it. Pull down to refresh.',
      );
    }
    if (!order.needsRefund) return const SizedBox.shrink();
    return _Panel(
      color: const TColor(0xFFFFF4D6),
      ink: const TColor(0xFF6B4600),
      icon: Icons.currency_rupee,
      title: 'Refund due: ${rupees(order.totals.total)}',
      text: p.failedRefund != null
          ? 'Razorpay reported the last refund (${p.failedRefund!.id}) as failed. Refund it again.'
          : 'Paid online and then cancelled. The money hasn’t gone back yet.',
      action: FilledButton.icon(
        onPressed: _busy ? null : _refund,
        icon: const Icon(Icons.undo),
        label: Text('Refund ${rupees(order.totals.total)} now'),
      ),
    );
  }

  /// One button per message. A step message that's been sent is done (✓ with the date); one for a step the order
  /// hasn't reached yet is off; the message for the current step stands out. Delay notices and missed-delivery
  /// messages can be sent again.
  Widget _messagesCard(Order order) {
    final suggested = order.payment.status == 'refunded' ? CustomerMessage.refunded : CustomerMessage.forStatus(order.status);
    final messages = order.status == OrderStatus.cancelled
        ? [CustomerMessage.cancelled, if (order.payment.method == 'razorpay') CustomerMessage.refunded]
        : CustomerMessage.values.where((m) => m != CustomerMessage.cancelled && m != CustomerMessage.refunded);
    final api = _whatsApp?.api == true;
    return _Section(
      title: 'Message customer on WhatsApp',
      children: [
        Text(
          api
              ? 'Sent by PIAX on WhatsApp Business${_whatsApp!.automatic ? ', and step updates go out automatically' : ''}. Delay notices and missed-delivery messages ask for details first.'
              : 'Opens WhatsApp with the message typed in. You check it and press send. Each update is sent once.',
          style: _muted,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final m in messages) _messageButton(order, m, highlight: m == suggested)]),
      ],
    );
  }

  Widget _messageButton(Order order, CustomerMessage m, {required bool highlight}) {
    final sentAt = m.sentAt(order);
    if (sentAt != null && !m.repeatable) {
      return Tooltip(
        message: 'Sent ${dateTime(sentAt)}',
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.check_circle, size: 18, color: brand),
          label: Text('${m.label} · sent ${shortDate(sentAt)}'),
        ),
      );
    }
    final onPressed = _busy || !m.reached(order) ? null : () => _compose(m);
    final icon = Icon(m.needsDetails ? Icons.report_gmailerrorred_outlined : Icons.chat_outlined, size: 18);
    final label = Text(sentAt != null ? '${m.label} · last sent ${shortDate(sentAt)}' : m.label);
    return highlight
        ? FilledButton.tonalIcon(onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label);
  }

  /// Who placed the order and how to reach them.
  Widget _customerCard(Order order) {
    final c = order.contact;
    final email = c.email.isNotEmpty ? c.email : (_profile?.account?.email ?? '');
    final name = order.customerName.isEmpty ? 'Name not given' : order.customerName;
    final phone = order.customerPhone;
    final receiverDiffers =
        order.address.name.isNotEmpty &&
        (order.address.name.toLowerCase() != name.toLowerCase() || _digits(order.address.phone) != _digits(phone));
    return _Section(
      title: 'Customer',
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const TColor(0xFFDDF3EC),
              child: Text(
                _initials(name),
                style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 17),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text('Ordered ${dateTime(order.createdAt)}', style: _muted),
                ],
              ),
            ),
          ],
        ),
        if (_profile != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: _profile!.account == null ? Icons.person_outline : Icons.verified_user_outlined,
                text: _profile!.account == null
                    ? 'Guest checkout'
                    : 'PIAX account${_profile!.account!.createdAt == null ? '' : ' since ${monthYear(_profile!.account!.createdAt!)}'}',
              ),
              _Pill(
                icon: _profile!.returning ? Icons.favorite_outline : Icons.fiber_new_outlined,
                text: _profile!.returning ? 'Returning customer · ${_profile!.completed} orders' : 'First order',
              ),
            ],
          ),
        ],
        const Divider(height: 28),
        _Field(
          icon: Icons.phone_outlined,
          label: 'Mobile number',
          value: phone.isEmpty ? 'Not given' : _prettyPhone(phone),
          actions: [
            if (phone.isNotEmpty) _SmallAction(icon: Icons.call_outlined, label: 'Call', onTap: () => callNumber(phone)),
            if (whatsappNumber(phone) != null)
              _SmallAction(icon: Icons.chat_outlined, label: 'WhatsApp', onTap: () => openWhatsApp(phone, '')),
            if (phone.isNotEmpty) _SmallAction(icon: Icons.copy_outlined, label: 'Copy', onTap: () => _copy(phone, 'Mobile number')),
          ],
        ),
        for (final other in _profile?.otherPhones ?? const <String>[])
          _Field(
            icon: Icons.phone_forwarded_outlined,
            label: 'Other number on their account or orders',
            value: _prettyPhone(other),
            actions: [_SmallAction(icon: Icons.call_outlined, label: 'Call', onTap: () => callNumber(other))],
          ),
        _Field(
          icon: Icons.mail_outline,
          label: 'Email',
          value: email.isEmpty ? 'Not given' : email,
          actions: [if (email.isNotEmpty) _SmallAction(icon: Icons.copy_outlined, label: 'Copy', onTap: () => _copy(email, 'Email'))],
        ),
        if (_profile?.account case final account?) ...[
          _Field(icon: Icons.login, label: 'Signs in with', value: account.signInLabel.isEmpty ? 'Not recorded' : account.signInLabel),
          if (account.lastLoginAt != null) _Field(icon: Icons.schedule, label: 'Last signed in', value: dateTime(account.lastLoginAt!)),
          _Field(
            icon: Icons.shopping_cart_outlined,
            label: 'On their account now',
            value: [
              '${account.savedAddresses} saved ${account.savedAddresses == 1 ? 'address' : 'addresses'}',
              '${account.cartItems} in cart',
              '${account.savedItems} saved for later',
            ].join(' · '),
          ),
        ],
        if (receiverDiffers)
          const _Note(
            icon: Icons.info_outline,
            text: 'Someone else receives this parcel. Their name and number are under Delivery address.',
          ),
      ],
    );
  }

  /// The customer's earlier orders, shown after everything about this order: totals, what they usually buy,
  /// addresses used before and their other orders, newest first (tap one to open it). Null until the profile has
  /// loaded, or when this is their only order.
  Widget? _historyCard() {
    final p = _profile;
    if (p == null || p.orderCount <= 1) return null;
    return _Section(title: 'Previous orders from this customer', children: _history(p));
  }

  List<Widget> _history(CustomerProfile p) => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Figure(value: '${p.orderCount}', label: p.orderCount == 1 ? 'order' : 'orders'),
        _Figure(value: '${p.delivered}', label: 'delivered'),
        if (p.cancelled > 0) _Figure(value: '${p.cancelled}', label: 'cancelled'),
        if (p.unpaid > 0) _Figure(value: '${p.unpaid}', label: 'not paid'),
        _Figure(value: rupees(p.spent), label: 'total spent'),
        if (p.completed > 0) _Figure(value: rupees(p.average), label: 'per order'),
      ],
    ),
    if (p.firstAt != null) ...[const SizedBox(height: 6), _Field(icon: Icons.history, label: 'First order', value: dateTime(p.firstAt!))],
    if (p.topProducts.isNotEmpty)
      _Field(icon: Icons.inventory_2_outlined, label: 'Usually buys', value: p.topProducts.map((t) => '${t.$1} × ${t.$2}').join('\n')),
    if (p.addresses.length > 1)
      _Field(
        icon: Icons.alt_route,
        label: 'Delivery addresses used (${p.addresses.length})',
        value: p.addresses.map((a) => '• $a').join('\n'),
      ),
    if (p.recent.isNotEmpty) ...[
      const SizedBox(height: 8),
      Text('Their other orders, newest first', style: _muted.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      for (final past in p.recent)
        InkWell(
          onTap: () => _openPastOrder(past),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(past.id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(
                        '${shortDate(past.createdAt)} · ${past.items} ${past.items == 1 ? 'pack' : 'packs'} · ${rupees(past.total)}',
                        style: _muted,
                      ),
                    ],
                  ),
                ),
                StatusBadge(past.status),
                const Icon(Icons.chevron_right, color: TColor(0xFF9AAEA9)),
              ],
            ),
          ),
        ),
    ],
  ];

  /// Where the parcel goes, field by field as the customer typed it at checkout, and what the courier collects.
  Widget _addressCard(Order order) {
    final a = order.address;
    final courierLabel = [a.name, if (a.phone.isNotEmpty) _prettyPhone(a.phone), ...a.lines].join('\n');
    final pinned = a.lat != null && a.lng != null;
    return _Section(
      title: 'Delivery address',
      trailing: a.type.isEmpty
          ? null
          : _Pill(icon: a.type.toLowerCase() == 'work' ? Icons.work_outline : Icons.home_outlined, text: a.type),
      children: [
        _Field(
          icon: Icons.person_outline,
          label: 'Receiver',
          value: [a.name, if (a.phone.isNotEmpty) _prettyPhone(a.phone)].where((p) => p.isNotEmpty).join(' · '),
          actions: [if (a.phone.isNotEmpty) _SmallAction(icon: Icons.call_outlined, label: 'Call', onTap: () => callNumber(a.phone))],
        ),
        _Field(icon: Icons.home_work_outlined, label: 'Flat, house no., building, street', value: a.line1.isEmpty ? 'Not given' : a.line1),
        if (a.line2.isNotEmpty) _Field(icon: Icons.signpost_outlined, label: 'Area, sector, village', value: a.line2),
        if (a.landmark.isNotEmpty) _Field(icon: Icons.place_outlined, label: 'Landmark (near)', value: a.landmark),
        _Field(icon: Icons.location_city_outlined, label: 'City and state', value: [a.city, a.state].where((p) => p.isNotEmpty).join(', ')),
        _Field(
          icon: Icons.markunread_mailbox_outlined,
          label: 'Pincode',
          value: a.pincode.isEmpty ? 'Not given' : a.pincode,
          big: true,
          actions: [
            if (a.pincode.isNotEmpty) _SmallAction(icon: Icons.copy_outlined, label: 'Copy', onTap: () => _copy(a.pincode, 'Pincode')),
          ],
        ),
        _Note(
          icon: pinned ? Icons.my_location : Icons.location_searching,
          text: pinned
              ? 'The customer pinned the exact spot on the map. “Open in Maps” goes straight there.'
              : 'No map pin. “Open in Maps” searches for the address.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => openMaps(a),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open in Maps'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy(courierLabel, 'Full address'),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copy full address'),
            ),
          ],
        ),
        const Divider(height: 28),
        if (order.deliverBy != null && !order.status.isFinal)
          _Field(icon: Icons.event_outlined, label: 'Deliver by', value: shortDate(order.deliverBy!)),
        _collectNote(order),
      ],
    );
  }

  /// Plain words for the delivery person: is there money to collect at the door?
  Widget _collectNote(Order order) {
    final p = order.payment;
    final (Color bg, Color fg, IconData icon, String title, String text) = switch ((p.method, p.status)) {
      ('cod', 'paid') => (
        const TColor(0xFFE3EDE2),
        const TColor(0xFF3E5E3C),
        Icons.check_circle_outline,
        'Cash collected',
        'Cash on delivery, already collected.',
      ),
      ('cod', _) => (
        const TColor(0xFFFFF4D6),
        const TColor(0xFF6B4600),
        Icons.payments_outlined,
        'Collect ${rupees(order.totals.total)} in cash',
        'Cash on delivery: the customer pays at the door.',
      ),
      (_, 'paid') => (
        const TColor(0xFFE3EDE2),
        const TColor(0xFF3E5E3C),
        Icons.verified_outlined,
        'Prepaid: nothing to collect',
        'Paid online. Don’t take any money at the door.',
      ),
      (_, 'refunded') => (
        const TColor(0xFFF3E3E3),
        const TColor(0xFF8B2E2E),
        Icons.undo,
        'Refunded',
        'Cancelled and refunded. Don’t deliver.',
      ),
      (_, 'refund_pending') => (
        const TColor(0xFFF3E3E3),
        const TColor(0xFF8B2E2E),
        Icons.undo,
        'Refund pending',
        'Paid online, refund due. Don’t deliver.',
      ),
      _ => (
        const TColor(0xFFF3E3E3),
        const TColor(0xFF8B2E2E),
        Icons.hourglass_empty,
        'Not paid yet',
        'Wait for the online payment before sending this.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                Text(text, style: TextStyle(color: fg, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(Order order) {
    final t = order.totals;
    return _Section(
      title: 'Items',
      children: [
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item.quantity}×', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      if (item.subtitle.isNotEmpty) Text(item.subtitle, style: _muted),
                      if (item.mix.isNotEmpty)
                        Text('Mix: ${item.mix.entries.map((e) => '${e.value}× ${e.key}').join(', ')}', style: _muted),
                    ],
                  ),
                ),
                Text(rupees(item.lineTotal)),
              ],
            ),
          ),
        const Divider(height: 20),
        _Amount('Subtotal', rupees(t.subtotal)),
        if (t.discount > 0) _Amount('Discount', '−${rupees(t.discount)}'),
        _Amount('Delivery', t.delivery == 0 ? 'Free' : rupees(t.delivery)),
        _Amount('Total', rupees(t.total), bold: true),
        const SizedBox(height: 8),
        _Amount(order.payment.methodLabel, order.payment.statusLabel),
        if (order.payment.paymentId != null)
          _Line(
            icon: Icons.receipt_long_outlined,
            text: order.payment.paymentId!,
            onTap: () => _copy(order.payment.paymentId!, 'Payment ID'),
          ),
        if (order.status != OrderStatus.cancelled) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: order.invoiceReady && !_openingInvoice ? _openInvoice : null,
            icon: _openingInvoice
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(order.invoiceReady ? 'Download invoice (PDF)' : 'Invoice ready once paid'),
          ),
        ],
      ],
    );
  }

  Widget _timelineCard(Order order) => _Section(
    title: 'Timeline',
    children: [
      for (final step in order.history.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 10, color: statusColors(step.status).$2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.status.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (step.note != null && step.note!.isNotEmpty) Text(step.note!, style: _muted),
                  ],
                ),
              ),
              Text(dateTime(step.at), style: _muted),
            ],
          ),
        ),
    ],
  );

  IconData _stepIcon(OrderStatus status) => switch (status) {
    OrderStatus.packed => Icons.inventory_2_outlined,
    OrderStatus.shipped => Icons.local_shipping_outlined,
    OrderStatus.outForDelivery => Icons.delivery_dining_outlined,
    OrderStatus.delivered => Icons.check_circle_outline,
    _ => Icons.arrow_forward,
  };
}

const _muted = TextStyle(color: TColor(0xFF5B6B67), fontSize: 13.5);

class _Section extends StatelessWidget {
  const _Section({required this.children, this.title, this.trailing});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .6, color: brand),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const TColor(0xFF5B6B67)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5))),
          if (onTap != null) const Icon(Icons.copy_outlined, size: 16, color: TColor(0xFF9AAEA9)),
        ],
      ),
    ),
  );
}

String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

/// "+91 98765 43210" for an Indian mobile number; anything else as given.
String _prettyPhone(String phone) {
  var d = _digits(phone);
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return d.length == 10 ? '+91 ${d.substring(0, 5)} ${d.substring(5)}' : phone;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// One labelled detail: a small grey label over the value, with optional labelled buttons under it.
class _Field extends StatelessWidget {
  const _Field({required this.icon, required this.label, required this.value, this.actions = const [], this.big = false});
  final IconData icon;
  final String label, value;
  final List<Widget> actions;
  final bool big;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: const TColor(0xFF5B6B67)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: TextStyle(
                  fontSize: big ? 20 : 15.5,
                  fontWeight: big ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: big ? 1.5 : 0,
                  height: 1.35,
                ),
              ),
              if (actions.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 6, runSpacing: 6, children: actions)],
            ],
          ),
        ),
      ],
    ),
  );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: const TColor(0xFFDDF3EC), borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: brand),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    ),
  );
}

/// A small labelled number in the order history.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: const TColor(0xFFF2F6F5), borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        Text(label, style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 12)),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const TColor(0xFF5B6B67)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: TColor(0xFF5B6B67), fontSize: 13.5, height: 1.35)),
        ),
      ],
    ),
  );
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.value, {this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 16 : 14.5, fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Courier and tracking number for "Shipped" (both optional; they go on the customer's order page and message).
class _ShipDialog extends StatefulWidget {
  const _ShipDialog();

  @override
  State<_ShipDialog> createState() => _ShipDialogState();
}

class _ShipDialogState extends State<_ShipDialog> {
  final _courier = TextEditingController();
  final _number = TextEditingController();

  @override
  void dispose() {
    _courier.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Mark as shipped'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _courier,
          style: const TextStyle(fontSize: 16),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Courier', hintText: 'e.g. Delhivery'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _number,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(labelText: 'Tracking number (optional)'),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
      FilledButton(onPressed: () => Navigator.pop(context, (_courier.text.trim(), _number.text.trim())), child: const Text('Mark shipped')),
    ],
  );
}

/// The reason the customer sees on her order page when it's cancelled.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({this.refundAmount});

  /// The amount to refund, for an order paid online (null otherwise: nothing to refund).
  final int? refundAmount;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

/// The reason the customer sees, and (for an order paid online) whether to refund it straight away. Pops (reason, refund).
class _CancelDialogState extends State<_CancelDialog> {
  /// Filled in to start with, and used if the box is left empty (the website and WhatsApp use the same default).
  static const _defaultReason = 'Temporary technical issue';
  static const _reasons = [
    _defaultReason,
    'Out of stock',
    'Requested by customer',
    'We don’t deliver to this pincode yet',
    'Payment not received',
  ];
  final _reason = TextEditingController(text: _defaultReason);
  bool _refund = true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.refundAmount;
    return AlertDialog(
      title: const Text('Cancel this order?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The customer sees this reason on their order page.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final r in _reasons) ActionChip(label: Text(r), onPressed: () => setState(() => _reason.text = r))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              style: const TextStyle(fontSize: 16),
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (amount != null)
              CheckboxListTile(
                value: _refund,
                onChanged: (v) => setState(() => _refund = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Also refund ${rupees(amount)} now'),
                subtitle: const Text('Back to their original payment method through Razorpay; they get an email. Untick to refund later.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep order')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () {
            final typed = _reason.text.trim();
            Navigator.pop(context, (typed.isEmpty ? _defaultReason : typed, amount != null && _refund));
          },
          child: Text(amount != null && _refund ? 'Cancel and refund' : 'Cancel order'),
        ),
      ],
    );
  }
}

/// A tinted note with an icon, a bold line, a short explanation and an optional action under it.
class _Panel extends StatelessWidget {
  const _Panel({required this.color, required this.ink, required this.icon, required this.title, required this.text, this.action});
  final Color color, ink;
  final IconData icon;
  final String title, text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ink, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  Text(text, style: TextStyle(color: ink, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        if (action != null) ...[const SizedBox(height: 10), action!],
      ],
    ),
  );
}

/// What a Delay notice (reason, new expected date) or Missed delivery (the delivery partner's note) needs.
class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.message});
  final CustomerMessage message;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  static const _delayReasons = ['Heavy rain in your area', 'Courier delay', 'High order volume', 'We’re facing a technical issue'];
  static const _missedNotes = ['No one was at home', 'Phone not reachable', 'Address couldn’t be found'];
  final _text = TextEditingController();
  DateTime? _date;

  bool get _delay => widget.message == CustomerMessage.delayed;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _date ?? now.add(const Duration(days: 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _text.text.trim().isNotEmpty && (!_delay || _date != null);
    return AlertDialog(
      title: Text(_delay ? 'Delay notice' : 'Missed delivery'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_delay ? 'Why is it late? The customer sees this.' : 'What did the delivery partner say? The customer sees this.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _delay ? _delayReasons : _missedNotes)
                  ActionChip(label: Text(r), onPressed: () => setState(() => _text.text = r)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLength: 120,
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: _delay ? 'Reason' : 'Delivery partner’s note'),
            ),
            if (_delay)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_date == null ? 'Pick the new expected date' : 'New expected date: ${shortDate(_date!)}'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: ready
              ? () => Navigator.pop(
                  context,
                  _delay ? {'reason': _text.text.trim(), 'newDate': shortDate(_date!)} : {'note': _text.text.trim()},
                )
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

/// Shows the message so the admin can adjust it, then hands it to WhatsApp.
class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.title, required this.to, required this.initial, this.justMarked});
  final String title, to, initial;

  /// The step the order was just moved to, when this opens right after a status change.
  final OrderStatus? justMarked;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.justMarked != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const TColor(0xFFDDF3EC), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: brand, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Marked as ${widget.justMarked!.label.toLowerCase()} on the website. Now let the customer know.',
                    style: const TextStyle(color: brand, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text('“${widget.title}” to ${widget.to}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
          child: TextField(controller: _text, maxLines: null, style: const TextStyle(fontSize: 16, height: 1.4)),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Open in WhatsApp'),
        ),
        if (widget.justMarked != null) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip, don’t message')),
      ],
    ),
  );
}
