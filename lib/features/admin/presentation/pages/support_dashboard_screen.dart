import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/core/widgets/logout_prompt_dialog.dart';
import 'package:marketflow/core/support/support_reply_template.dart';

import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_support_requests_tab.dart';
import 'package:marketflow/features/admin/presentation/bloc/admin_dashboard_provider.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:flutter/services.dart';

class SupportDashboardScreen extends StatefulWidget {
  const SupportDashboardScreen({super.key});

  @override
  State<SupportDashboardScreen> createState() => _SupportDashboardScreenState();
}

class _SupportDashboardScreenState extends State<SupportDashboardScreen> {
  List<SupportReplyTemplate> _replyTemplatesForRequest(
    AdminSupportRequest request, {
    required String targetStatus,
  }) {
    return supportReplyTemplatesForContext(
      isDeliveryAddressRecoveryRequest:
          request.isDeliveryAddressRecoveryRequest,
      targetStatus: targetStatus,
    );
  }

  String _defaultReplyMessageForRequest(
    AdminSupportRequest request, {
    required String targetStatus,
  }) {
    return supportReplyDefaultMessageForContext(
      isDeliveryAddressRecoveryRequest:
          request.isDeliveryAddressRecoveryRequest,
      targetStatus: targetStatus,
    );
  }

  Future<String?> _promptCustomerReply({
    required String title,
    String initialValue = '',
    required List<SupportReplyTemplate> templates,
  }) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => SupportReplyComposerDialog(
        title: title,
        initialValue: initialValue,
        templates: templates,
      ),
    );
    return note;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    final provider = context.read<AdminDashboardProvider>();
    final result = await provider.initialize();
    if (!mounted || result.isSuccess) return;
    final failure = result.requireFailure;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failure.message)));
  }

  Future<void> _refreshSupport() async {
    final result = await context.read<AdminDashboardProvider>().refreshAll();
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
  }

  String _formatMoney(BuildContext context, double usd) {
    return context.read<AppSettingsProvider>().formatUsd(usd);
  }

  Future<void> _openLinkedOrder(AdminSupportRequest request) async {
    final orderId = request.linkedOrderId;
    if (orderId == null) return;

    final provider = context.read<AdminDashboardProvider>();

    AdminOrder? findOrder() {
      for (final order in provider.orders) {
        if (order.id == orderId) return order;
      }
      return null;
    }

    var order = findOrder();
    if (order == null) {
      final result = await provider.loadOrders();
      if (!mounted) return;
      if (result.isFailure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
        return;
      }
      order = findOrder();
    }

    if (!mounted) return;
    if (order == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Order #$orderId was not found')));
      return;
    }

    Future<AdminOrder?> applyUpdatedAddress(
      AdminSupportRequest supportRequest,
      AdminOrder currentOrder,
    ) async {
      final updatedAddress = supportRequest.updatedDeliveryAddress;
      if (updatedAddress.isEmpty) return currentOrder;

      final result = await provider.updateOrderAddress(
        orderId: currentOrder.id,
        address: updatedAddress,
        addressDetails: currentOrder.addressDetails,
      );
      if (!mounted) return null;
      if (result.isFailure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
        return null;
      }

      if (!supportRequest.isResolved) {
        final statusResult = await provider.updateSupportRequestStatus(
          requestId: supportRequest.id,
          status: 'address_applied',
          note: supportRequest.hasSupportNote
              ? supportRequest.supportNote
              : _defaultReplyMessageForRequest(
                  supportRequest,
                  targetStatus: 'address_applied',
                ),
        );
        if (!mounted) return null;
        if (statusResult.isFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(statusResult.requireFailure.message)),
          );
        }
      }

      final refreshedOrder = findOrder();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated delivery address for order #${currentOrder.id}',
          ),
        ),
      );
      return refreshedOrder ?? currentOrder;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LinkedOrderSheet(
        order: order!,
        request: request,
        formatDateTimeLocal: _formatDateTimeLocal,
        formatMoney: (usd) => _formatMoney(context, usd),
        onApplyUpdatedAddress: applyUpdatedAddress,
      ),
    );
  }

  Future<void> _updateSupportRequestStatus(
    AdminSupportRequest request,
    String status,
  ) async {
    String? note;
    if (status == 'resolved' && !request.hasSupportNote) {
      final templates = _replyTemplatesForRequest(
        request,
        targetStatus: status,
      );
      note = await _promptCustomerReply(
        title: 'Add a customer reply',
        initialValue: _defaultReplyMessageForRequest(
          request,
          targetStatus: status,
        ),
        templates: templates,
      );
      if (!mounted) return;
      if (note == null) return;
    }
    final result = await context
        .read<AdminDashboardProvider>()
        .updateSupportRequestStatus(
          requestId: request.id,
          status: status,
          note: note,
        );
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
  }

  Future<void> _composeReply(AdminSupportRequest request) async {
    final templates = _replyTemplatesForRequest(
      request,
      targetStatus: request.status,
    );
    final note = await _promptCustomerReply(
      title: request.hasSupportNote
          ? 'Edit customer reply'
          : 'Add customer reply',
      initialValue: request.hasSupportNote
          ? request.supportNote
          : _defaultReplyMessageForRequest(
              request,
              targetStatus: request.status,
            ),
      templates: templates,
    );
    if (!mounted) return;
    if (note == null) return;
    if (note.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reply cannot be empty')));
      return;
    }

    final result = await context
        .read<AdminDashboardProvider>()
        .updateSupportRequestStatus(
          requestId: request.id,
          status: request.status,
          note: note,
        );
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutPrompt(context);
    if (!confirmed || !mounted) return;
    try {
      await context.read<AuthenticationProvider>().logout();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $error')));
    }
  }

  String _formatDateTimeLocal(dynamic raw) {
    final source = (raw ?? '').toString();
    final dt = DateTime.tryParse(source)?.toLocal();
    if (dt == null) return source.isEmpty ? '-' : source;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final support = context.watch<AdminDashboardProvider>();

    if (support.checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!support.hasSupportAgentAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support Access Required')),
        body: const Center(
          child: Text('Only support-agent accounts can access this screen'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Support Desk'),
        actions: [
          IconButton(
            onPressed: support.submitting ? null : _refreshSupport,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: AdminSupportRequestsTab(
        loadingSupportRequests: support.loadingSupportRequests,
        supportRequests: support.supportRequests,
        formatDateTimeLocal: _formatDateTimeLocal,
        submitting: support.submitting,
        onOpenLinkedOrder: _openLinkedOrder,
        onUpdateStatus: _updateSupportRequestStatus,
        onComposeReply: _composeReply,
      ),
    );
  }
}

class SupportReplyComposerDialog extends StatefulWidget {
  const SupportReplyComposerDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.templates = const <SupportReplyTemplate>[
      supportReplyTemplateReviewing,
      supportReplyTemplateResolved,
    ],
  });

  final String title;
  final String initialValue;
  final List<SupportReplyTemplate> templates;

  @override
  State<SupportReplyComposerDialog> createState() =>
      _SupportReplyComposerDialogState();
}

class _SupportReplyComposerDialogState
    extends State<SupportReplyComposerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _applyTemplate(SupportReplyTemplate template) {
    _controller.value = TextEditingValue(
      text: template.message,
      selection: TextSelection.collapsed(offset: template.message.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick replies',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a template to fill the reply, then adjust it if needed.',
              style: TextStyle(fontSize: 12, color: Color(0xFF56636D)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.templates
                  .map(
                    (template) => ActionChip(
                      label: Text(template.label),
                      onPressed: () => _applyTemplate(template),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'Add a short customer-visible update',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _LinkedOrderSheet extends StatefulWidget {
  const _LinkedOrderSheet({
    required this.order,
    required this.request,
    required this.formatDateTimeLocal,
    required this.formatMoney,
    required this.onApplyUpdatedAddress,
  });

  final AdminOrder order;
  final AdminSupportRequest request;
  final String Function(dynamic) formatDateTimeLocal;
  final String Function(double usd) formatMoney;
  final Future<AdminOrder?> Function(
    AdminSupportRequest request,
    AdminOrder order,
  )
  onApplyUpdatedAddress;

  @override
  State<_LinkedOrderSheet> createState() => _LinkedOrderSheetState();
}

class _LinkedOrderSheetState extends State<_LinkedOrderSheet> {
  late AdminOrder _order;
  bool _applyingAddress = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  String _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'order_received':
      case 'pending':
      case 'paid':
        return 'Order Received';
      case 'order_packed':
        return 'Order Packed';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'out_for_delivery':
      case 'shipped':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        final normalized = status.trim().toLowerCase().replaceAll('_', ' ');
        if (normalized.isEmpty) return '-';
        return normalized[0].toUpperCase() + normalized.substring(1);
    }
  }

  String _deliveryTypeLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'real_meeting' || value == 'pickup') return 'Store Pickup';
    return 'Drop-off';
  }

  String _paymentMethodLabel(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'aba_payway_qr') return 'ABA PayWay QR';
    return 'Cash on delivery';
  }

  Future<void> _applyUpdatedAddress() async {
    if (_applyingAddress) return;
    setState(() => _applyingAddress = true);
    final nextOrder = await widget.onApplyUpdatedAddress(
      widget.request,
      _order,
    );
    if (!mounted) return;
    if (nextOrder != null) {
      setState(() => _order = nextOrder);
    }
    setState(() => _applyingAddress = false);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final updatedAddress = request.updatedDeliveryAddress;
    final hasUpdatedAddress = updatedAddress.isNotEmpty;
    final canApplyUpdatedAddress =
        hasUpdatedAddress &&
        updatedAddress.trim().toLowerCase() !=
            _order.address.trim().toLowerCase();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Order #${_order.id}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OrderMetaChip(label: _statusLabel(_order.status)),
                  _OrderMetaChip(
                    label: _deliveryTypeLabel(_order.deliveryType),
                  ),
                  _OrderMetaChip(
                    label: _paymentMethodLabel(_order.paymentMethod),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Customer: ${_order.email.isEmpty ? '-' : _order.email}'),
              const SizedBox(height: 4),
              Text(
                'Date: ${widget.formatDateTimeLocal(_order.createdAt?.toIso8601String())}',
              ),
              const SizedBox(height: 4),
              Text('Total: ${widget.formatMoney(_order.total)}'),
              const SizedBox(height: 4),
              Text('Items: ${_order.items.length}'),
              const SizedBox(height: 4),
              Text('Address: ${_order.address.isEmpty ? '-' : _order.address}'),
              if (_order.addressDetails.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Details: ${_order.addressDetails.trim()}'),
              ],
              if (_order.paymentReference.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Payment Ref: ${_order.paymentReference.trim()}'),
              ],
              if (hasUpdatedAddress) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFFAF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF9BD3AE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customer provided this updated address',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        updatedAddress,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F5F3A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (canApplyUpdatedAddress)
                  FilledButton.icon(
                    onPressed: _applyingAddress ? null : _applyUpdatedAddress,
                    icon: _applyingAddress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_location_alt_outlined),
                    label: Text(
                      _applyingAddress
                          ? 'Applying address...'
                          : 'Apply updated address',
                    ),
                  )
                else
                  const Text(
                    'This order already matches the customer-provided address.',
                    style: TextStyle(
                      color: Color(0xFF1F5F3A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Support message',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SelectableText(
                request.message.trim().isEmpty ? '-' : request.message.trim(),
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_order.email.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _order.email),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied customer email for order #${_order.id}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.content_copy_outlined),
                      label: const Text('Copy customer email'),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderMetaChip extends StatelessWidget {
  const _OrderMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF23313A),
        ),
      ),
    );
  }
}
