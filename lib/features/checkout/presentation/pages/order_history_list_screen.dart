import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/core/location/address_text.dart';
import 'package:marketflow/core/support/support_notification_store.dart';
import 'package:marketflow/core/support/support_notification_summary.dart';
import 'package:marketflow/core/support/support_request_link.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_address_selection_screen.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/support/presentation/pages/customer_support_screen.dart';

class OrderHistoryListScreen extends StatefulWidget {
  const OrderHistoryListScreen({super.key, this.initialOrderId});

  final int? initialOrderId;

  @override
  State<OrderHistoryListScreen> createState() => _OrderHistoryListScreenState();
}

class _OrderHistoryListScreenState extends State<OrderHistoryListScreen> {
  late Stream<List<Map<String, dynamic>>> _ordersStream;
  final Set<String> _exportingOrderIds = {};
  final SupportNotificationStore _supportNotificationStore =
      const SupportNotificationStore();
  final Map<String, GlobalKey> _orderCardKeys = <String, GlobalKey>{};
  Timer? _refreshTicker;
  bool _markingSupportNotificationsSeen = false;
  bool _focusedInitialOrder = false;
  String? _highlightedOrderId;
  DateTime? _supportSeenAt;

  @override
  void initState() {
    super.initState();
    _ordersStream = _buildOrdersStream();
    unawaited(_loadSupportSeenAt());
    _refreshTicker = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() {
        _ordersStream = _buildOrdersStream();
      });
    });
  }

  @override
  void dispose() {
    _refreshTicker?.cancel();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _buildOrdersStream() {
    final userId = context.read<AuthenticationProvider>().user?.id;
    if (userId == null || userId.trim().isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }

    return Stream<List<Map<String, dynamic>>>.fromFuture(
      context.read<OrderManagementProvider>().loadOrders(),
    );
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _ordersStream = _buildOrdersStream();
    });
    await _loadSupportSeenAt();
  }

  Future<void> _loadSupportSeenAt() async {
    final userId = context.read<AuthenticationProvider>().user?.id.trim() ?? '';
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() => _supportSeenAt = null);
      return;
    }

    final seenAt = await _supportNotificationStore.loadSeenAt(userId: userId);
    if (!mounted) return;
    setState(() => _supportSeenAt = seenAt);
  }

  GlobalKey _orderCardKey(String orderId) {
    return _orderCardKeys.putIfAbsent(orderId, GlobalKey.new);
  }

  void _focusInitialOrderIfNeeded(List<Map<String, dynamic>> orders) {
    if (_focusedInitialOrder) return;

    final targetOrderId = widget.initialOrderId?.toString().trim() ?? '';
    if (targetOrderId.isEmpty) {
      _focusedInitialOrder = true;
      return;
    }

    final hasTarget = orders.any(
      (order) => (order['id'] ?? '').toString().trim() == targetOrderId,
    );
    if (!hasTarget) {
      _focusedInitialOrder = true;
      return;
    }

    _focusedInitialOrder = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final orderContext = _orderCardKeys[targetOrderId]?.currentContext;
      if (orderContext == null) return;
      await Scrollable.ensureVisible(
        orderContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      if (!mounted) return;
      setState(() => _highlightedOrderId = targetOrderId);
    });
  }

  Future<void> _markSupportNotificationsSeen(
    List<Map<String, dynamic>> orders,
  ) async {
    if (_markingSupportNotificationsSeen) return;

    final targetOrderId = widget.initialOrderId ?? 0;
    if (targetOrderId <= 0) return;

    final userId = context.read<AuthenticationProvider>().user?.id.trim() ?? '';
    if (userId.isEmpty) return;

    final latestActivityAt = targetOrderId > 0
        ? latestSupportNotificationActivityAtForOrder(orders, targetOrderId)
        : latestSupportNotificationActivityAt(orders);
    if (latestActivityAt == null) return;

    _markingSupportNotificationsSeen = true;
    try {
      final seenAt = await _supportNotificationStore.loadSeenAt(userId: userId);
      if (seenAt != null && !latestActivityAt.isAfter(seenAt)) {
        return;
      }
      await _supportNotificationStore.saveSeenAt(
        userId: userId,
        seenAt: latestActivityAt,
      );
      if (!mounted) return;
      setState(() => _supportSeenAt = latestActivityAt);
    } finally {
      _markingSupportNotificationsSeen = false;
    }
  }

  String _normalizeSupportRequestStatus(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'pending':
      case 'address_applied':
      case 'resolved':
        return value;
      default:
        return '';
    }
  }

  List<Map<String, dynamic>> _extractSupportHistory(dynamic rawHistory) {
    if (rawHistory is! List) return const <Map<String, dynamic>>[];
    return rawHistory
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _latestSupportNote(List<Map<String, dynamic>> history) {
    for (final item in history) {
      final note = (item['support_note'] ?? '').toString().trim();
      if (note.isNotEmpty) return note;
    }
    return '';
  }

  String? _latestSupportNoteDateLabel(List<Map<String, dynamic>> history) {
    for (final item in history) {
      final note = (item['support_note'] ?? '').toString().trim();
      if (note.isEmpty) continue;
      final noteDate = (item['support_note_updated_at'] ?? '')
          .toString()
          .trim();
      if (noteDate.isNotEmpty) return _formatDateTime(noteDate);
      final statusDate = (item['support_request_status_updated_at'] ?? '')
          .toString()
          .trim();
      if (statusDate.isNotEmpty) return _formatDateTime(statusDate);
      final createdAt = (item['support_request_created_at'] ?? '')
          .toString()
          .trim();
      if (createdAt.isNotEmpty) return _formatDateTime(createdAt);
    }
    return null;
  }

  Map<String, dynamic>? _latestSupportHistoryEntry(
    List<Map<String, dynamic>> history,
  ) {
    if (history.isEmpty) return null;
    for (final item in history) {
      if (_normalizeSupportRequestStatus(item['support_request_status'])
          .isNotEmpty) {
        return item;
      }
    }
    return history.first;
  }

  String? _supportEntryActivityAt(Map<String, dynamic>? entry) {
    if (entry == null) return null;

    final noteUpdatedAt = (entry['support_note_updated_at'] ?? '')
        .toString()
        .trim();
    if (noteUpdatedAt.isNotEmpty) return noteUpdatedAt;

    final statusUpdatedAt = (entry['support_request_status_updated_at'] ?? '')
        .toString()
        .trim();
    if (statusUpdatedAt.isNotEmpty) return statusUpdatedAt;

    final createdAt = (entry['support_request_created_at'] ?? '')
        .toString()
        .trim();
    return createdAt.isEmpty ? null : createdAt;
  }

  DateTime? _latestSupportActivityAt(Map<String, dynamic> order) {
    final orderId = _toInt(order['id'], fallback: -1);
    if (orderId <= 0) return null;
    return latestSupportNotificationActivityAtForOrder(
      <Map<String, dynamic>>[order],
      orderId,
    );
  }

  bool _isOrderSupportUnread(Map<String, dynamic> order) {
    final latestActivityAt = _latestSupportActivityAt(order);
    if (latestActivityAt == null) return false;
    return _supportSeenAt == null || latestActivityAt.isAfter(_supportSeenAt!);
  }

  Future<void> _markOrderSupportSeen(Map<String, dynamic> order) async {
    final latestActivityAt = _latestSupportActivityAt(order);
    if (latestActivityAt == null) return;

    final userId = context.read<AuthenticationProvider>().user?.id.trim() ?? '';
    if (userId.isEmpty) return;

    if (_supportSeenAt != null && !latestActivityAt.isAfter(_supportSeenAt!)) {
      return;
    }

    await _supportNotificationStore.saveSeenAt(
      userId: userId,
      seenAt: latestActivityAt,
    );
    if (!mounted) return;
    setState(() => _supportSeenAt = latestActivityAt);
  }

  bool _needsAddressRecovery(Map<String, dynamic> order) {
    final normalizedStatus = _normalizeOrderStatus(order['status']);
    if (normalizedStatus == 'cancelled' || normalizedStatus == 'delivered') {
      return false;
    }

    final deliveryTypeRaw = (order['delivery_type'] ?? '').toString();
    if (_isPickupDeliveryType(deliveryTypeRaw)) {
      return false;
    }

    final address = AddressText.deliveryAddressOrEmpty(
      (order['address'] ?? '').toString(),
    );
    return address.isEmpty;
  }

  String _buildAddressRecoverySupportMessage(
    Map<String, dynamic> order, {
    String updatedAddress = '',
  }) {
    final orderId = (order['id'] ?? '').toString();
    final createdAt = _formatDateTime(order['created_at']);
    final deliveryType = _deliveryTypeLabel(order['delivery_type']);
    final paymentMethod = _paymentMethodLabel(order['payment_method']);
    final addressLine = updatedAddress.isEmpty
        ? 'I need help correcting the delivery address for this order.'
        : 'My updated delivery address is: $updatedAddress';

    return [
      'Order #$orderId needs a delivery address update.',
      addressLine,
      'Delivery type: $deliveryType',
      'Payment: $paymentMethod',
      'Order date: $createdAt',
      '',
      'Please help apply the correct address before delivery handoff.',
    ].join('\n');
  }

  Future<void> _openSupportForOrder(
    Map<String, dynamic> order, {
    String updatedAddress = '',
    Map<String, dynamic>? followUpEntry,
  }) async {
    if (!mounted) return;
    final orderId = _toInt(order['id'], fallback: -1);
    final sharedAddress = updatedAddress.isNotEmpty
        ? updatedAddress
        : parseUpdatedDeliveryAddressFromSupportMessage(
            (followUpEntry?['support_request_message'] ?? '').toString(),
          );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSupportScreen(
          initialRequestType: (followUpEntry?['request_type'] ?? 'delivery')
              .toString()
              .trim(),
          initialMessage: followUpEntry == null
              ? _buildAddressRecoverySupportMessage(
                  order,
                  updatedAddress: updatedAddress,
                )
              : null,
          initialFollowUpOrderId: orderId > 0 ? orderId : null,
          initialFollowUpStatus: _normalizeSupportRequestStatus(
            followUpEntry?['support_request_status'],
          ),
          initialFollowUpRequestType: (followUpEntry?['request_type'] ?? '')
              .toString()
              .trim(),
          initialFollowUpSupportNote: (followUpEntry?['support_note'] ?? '')
              .toString()
              .trim(),
          initialFollowUpActivityAt: _supportEntryActivityAt(followUpEntry),
          initialFollowUpSharedAddress: sharedAddress,
        ),
      ),
    );
    if (!mounted) return;
    await _loadSupportSeenAt();
  }

  Future<void> _updateSavedAddressForOrder(Map<String, dynamic> order) async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    if (user == null) return;

    CheckoutPrefill prefill = CheckoutPrefill.empty();
    try {
      prefill = await context
          .read<OrderManagementProvider>()
          .loadCheckoutPrefill();
    } catch (_) {}
    if (!mounted) return;

    final selected = await Navigator.push<CheckoutAddressSelectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutAddressSelectionScreen(
          selectedAddress: prefill.defaultAddress,
          historyAddresses: prefill.savedAddresses,
          contactName: prefill.contactName,
          contactPhone: prefill.contactPhone,
        ),
      ),
    );
    if (!mounted || selected == null) return;

    final nextAddress = AddressText.deliveryAddressOrEmpty(selected.address);
    if (nextAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a more specific address')),
      );
      return;
    }

    try {
      await context.read<OrderManagementProvider>().saveDefaultAddress(
        userId: user.id,
        address: nextAddress,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save your updated address')),
      );
      return;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved address updated. Contact support so we can apply it to order #${order['id']}.',
        ),
      ),
    );
    await _openSupportForOrder(order, updatedAddress: nextAddress);
  }

  List<Map<String, dynamic>> _extractItems(dynamic rawItems) {
    if (rawItems is List<dynamic>) {
      return rawItems
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (rawItems is String && rawItems.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawItems);
        if (decoded is List<dynamic>) {
          return decoded
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _money(dynamic value, AppSettingsProvider settings) {
    return settings.formatUsd(_toDouble(value));
  }

  bool _isPickupDeliveryType(String raw) {
    final value = raw.trim().toLowerCase();
    return value == 'real_meeting' || value == 'pickup';
  }

  String _deliveryTypeLabel(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (_isPickupDeliveryType(value)) return 'Store Pickup';
    return 'Drop-off';
  }

  String _paymentMethodLabel(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'aba_payway_qr') return 'ABA PayWay QR';
    return 'Cash on delivery';
  }

  String _normalizeOrderStatus(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'paiding' || value == 'paying') return 'order_received';
    if (value == 'pending' || value == 'paid') return 'order_received';
    if (value == 'shipped') return 'out_for_delivery';
    if (value.isEmpty) return 'order_received';
    return value;
  }

  String _orderStatusLabel(dynamic raw) {
    final normalized = _normalizeOrderStatus(raw);
    switch (normalized) {
      case 'order_received':
        return 'Order Received';
      case 'order_packed':
        return 'Order Packed';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      default:
        final text = normalized.replaceAll('_', ' ');
        return text[0].toUpperCase() + text.substring(1);
    }
  }

  int _statusStepIndex(String normalizedStatus, String deliveryType) {
    final isPickup = _isPickupDeliveryType(deliveryType);
    switch (normalizedStatus) {
      case 'order_received':
        return 0;
      case 'order_packed':
        return 1;
      case 'ready_for_pickup':
      case 'out_for_delivery':
        return 2;
      case 'delivered':
        return 3;
      case 'cancelled':
        return -1;
      default:
        if (isPickup && normalizedStatus == 'ready_for_pickup') return 2;
        return 0;
    }
  }

  Widget _buildDeliveryTimeline({
    required String normalizedStatus,
    required String deliveryTypeRaw,
  }) {
    final isPickup = _isPickupDeliveryType(deliveryTypeRaw);
    final stage2Label = isPickup ? 'Ready for Pickup' : 'Out for Delivery';
    final labels = <String>[
      'Order Received',
      'Order Packed',
      stage2Label,
      'Delivered',
    ];
    final step = _statusStepIndex(normalizedStatus, deliveryTypeRaw);
    final cancelled = normalizedStatus == 'cancelled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cancelled)
          const Text(
            'Delivery Progress: Cancelled',
            style: TextStyle(
              color: Color(0xFFB33030),
              fontWeight: FontWeight.w700,
            ),
          )
        else ...[
          const Text(
            'Delivery Progress',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(labels.length, (index) {
              final done = step >= index;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: done
                      ? const Color(0x1A0B7D69)
                      : const Color(0xFFF2F4F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: done
                        ? const Color(0xFF0B7D69)
                        : const Color(0xFFD9E0E5),
                  ),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                    color: done
                        ? const Color(0xFF0B7D69)
                        : const Color(0xFF56636D),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  String _formatDateTime(dynamic raw) {
    final source = (raw ?? '').toString();
    final dt = DateTime.tryParse(source)?.toLocal();
    if (dt == null) return source.isEmpty ? '-' : source;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _itemVariantLabel(Map<String, dynamic> item) {
    final size = (item['size'] ?? '').toString().trim();
    final color = (item['color'] ?? '').toString().trim();
    if (size.isEmpty && color.isEmpty) return '-';
    if (size.isEmpty) return color;
    if (color.isEmpty) return size;
    return '$size / $color';
  }

  Future<Uint8List> _buildReceiptPdf(Map<String, dynamic> order) async {
    final settings = context.read<AppSettingsProvider>();
    final pdf = pw.Document();
    final items = _extractItems(order['items']);
    final orderId = (order['id'] ?? '').toString();
    final status = _orderStatusLabel(order['status']);
    final deliveryType = _deliveryTypeLabel(order['delivery_type']);
    final paymentMethod = _paymentMethodLabel(order['payment_method']);
    final paymentReference = (order['payment_reference'] ?? '')
        .toString()
        .trim();
    final address = AddressText.deliveryAddressOrEmpty(
      (order['address'] ?? '').toString(),
    );
    final addressDetails = (order['address_details'] ?? '').toString().trim();
    final createdAt = _formatDateTime(order['created_at']);
    final total = _toDouble(order['total']);
    final customerEmail =
        context.read<AuthenticationProvider>().user?.email?.trim() ?? '';
    final totalQty = items.fold<int>(
      0,
      (sum, item) => sum + _toInt(item['qty'], fallback: 0),
    );

    final itemRows = items.map((item) {
      final name = (item['name'] ?? 'Item').toString();
      final qty = _toInt(item['qty'], fallback: 1);
      final price = _toDouble(item['price']);
      final subTotal = qty * price;
      return [
        name,
        _itemVariantLabel(item),
        qty.toString(),
        _money(price, settings),
        _money(subTotal, settings),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            'Order Receipt',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Order ID: $orderId'),
          pw.Text('Date: $createdAt'),
          pw.Text('Status: $status'),
          pw.Text('Payment: $paymentMethod'),
          if (paymentReference.isNotEmpty)
            pw.Text('Payment reference: $paymentReference'),
          if (customerEmail.isNotEmpty) pw.Text('Customer: $customerEmail'),
          pw.Text('Delivery type: $deliveryType'),
          pw.Text('Line items: ${items.length}'),
          pw.Text('Total quantity: $totalQty'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Shipping Address',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(address.isEmpty ? '-' : address),
          if (addressDetails.isNotEmpty) pw.Text('Details: $addressDetails'),
          pw.SizedBox(height: 16),
          pw.Text('Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (itemRows.isEmpty)
            pw.Text('No items')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Item', 'Variant', 'Qty', 'Price', 'Subtotal'],
              data: itemRows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF0B7D69),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColors.grey400),
            ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: ${_money(total, settings)}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> _saveReceiptPdf(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;

    setState(() => _exportingOrderIds.add(orderId));
    try {
      final bytes = await _buildReceiptPdf(order);
      await Printing.layoutPdf(
        name: 'receipt_order_$orderId.pdf',
        onLayout: (_) async => bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt PDF ready to save/share')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to generate receipt PDF')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingOrderIds.remove(orderId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.active) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to load orders'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _refreshOrders,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final docs = snapshot.data ?? const <Map<String, dynamic>>[];
          if (docs.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(_markSupportNotificationsSeen(docs));
            });
            _focusInitialOrderIfNeeded(docs);
          }
          if (docs.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshOrders,
              child: ListView(
                children: const [
                  SizedBox(height: 260),
                  Center(child: Text('No orders yet')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final order = docs[index];
                final orderId = (order['id'] ?? '').toString();
                final total = _toDouble(order['total']);
                final normalizedStatus = _normalizeOrderStatus(order['status']);
                final status = _orderStatusLabel(order['status']);
                final deliveryType = _deliveryTypeLabel(order['delivery_type']);
                final paymentMethod = _paymentMethodLabel(
                  order['payment_method'],
                );
                final paymentReference = (order['payment_reference'] ?? '')
                    .toString()
                    .trim();
                final address = AddressText.deliveryAddressOrEmpty(
                  (order['address'] ?? '').toString(),
                );
                final addressDetails = (order['address_details'] ?? '')
                    .toString()
                    .trim();
                final createdAt = _formatDateTime(order['created_at']);
                final exporting = _exportingOrderIds.contains(orderId);
                final needsAddressRecovery = _needsAddressRecovery(order);
                final supportRequestStatus = _normalizeSupportRequestStatus(
                  order['support_request_status'],
                );
                final rawSupportStatusUpdatedAt =
                    (order['support_request_status_updated_at'] ?? '')
                        .toString()
                        .trim();
                final supportRequestHistory = _extractSupportHistory(
                  order['support_request_history'],
                );
                final latestSupportEntry = _latestSupportHistoryEntry(
                  supportRequestHistory,
                );
                final latestSupportNote = _latestSupportNote(
                  supportRequestHistory,
                );
                final latestSupportNoteDateLabel = _latestSupportNoteDateLabel(
                  supportRequestHistory,
                );
                final hasUnreadSupportUpdate = _isOrderSupportUnread(order);
                final highlighted = orderId == _highlightedOrderId;

                return Container(
                  key: _orderCardKey(orderId),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? const Color(0xFFF3FAF7)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: highlighted
                          ? const Color(0xFF0B7D69)
                          : Colors.grey.shade300,
                      width: highlighted ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: ${settings.formatUsd(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('Order: #$orderId'),
                      const SizedBox(height: 4),
                      Text('Date: $createdAt'),
                      const SizedBox(height: 4),
                      Text('Status: $status'),
                      const SizedBox(height: 8),
                      _buildDeliveryTimeline(
                        normalizedStatus: normalizedStatus,
                        deliveryTypeRaw: (order['delivery_type'] ?? '')
                            .toString(),
                      ),
                      const SizedBox(height: 4),
                      Text('Delivery: $deliveryType'),
                      const SizedBox(height: 4),
                      Text('Payment: $paymentMethod'),
                      const SizedBox(height: 4),
                      Text('Address: ${address.isEmpty ? '-' : address}'),
                      if (paymentReference.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Payment Ref: $paymentReference'),
                      ],
                      if (addressDetails.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Details: $addressDetails'),
                      ],
                      if (supportRequestStatus.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OrderSupportStatusCard(
                          status: supportRequestStatus,
                          needsAddressRecovery: needsAddressRecovery,
                          isUnread: hasUnreadSupportUpdate,
                          updatedAtLabel: rawSupportStatusUpdatedAt.isEmpty
                              ? null
                              : _formatDateTime(rawSupportStatusUpdatedAt),
                          latestSupportNote: latestSupportNote,
                          latestSupportNoteUpdatedAtLabel:
                              latestSupportNoteDateLabel,
                          onMarkAsRead: hasUnreadSupportUpdate
                              ? () => _markOrderSupportSeen(order)
                              : null,
                          onReplyInSupport: !needsAddressRecovery
                              ? () => _openSupportForOrder(
                                  order,
                                  followUpEntry: latestSupportEntry,
                                )
                              : null,
                        ),
                      ],
                      if (supportRequestHistory.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OrderSupportHistorySection(
                          history: supportRequestHistory,
                          formatDateTimeLabel: _formatDateTime,
                        ),
                      ],
                      if (needsAddressRecovery) ...[
                        const SizedBox(height: 10),
                        OrderAddressRecoveryPanel(
                          supportStatus: supportRequestStatus,
                          onUpdateSavedAddress: () =>
                              _updateSavedAddressForOrder(order),
                          onContactSupport: () => _openSupportForOrder(
                            order,
                            followUpEntry: latestSupportEntry,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: exporting
                              ? null
                              : () => _saveReceiptPdf(order),
                          icon: exporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            exporting
                                ? 'Generating PDF...'
                                : 'Save Receipt PDF',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class OrderSupportStatusCard extends StatelessWidget {
  const OrderSupportStatusCard({
    super.key,
    required this.status,
    required this.needsAddressRecovery,
    this.isUnread = false,
    this.updatedAtLabel,
    this.latestSupportNote = '',
    this.latestSupportNoteUpdatedAtLabel,
    this.onMarkAsRead,
    this.onReplyInSupport,
  });

  final String status;
  final bool needsAddressRecovery;
  final bool isUnread;
  final String? updatedAtLabel;
  final String latestSupportNote;
  final String? latestSupportNoteUpdatedAtLabel;
  final VoidCallback? onMarkAsRead;
  final VoidCallback? onReplyInSupport;

  String get _statusLabel {
    switch (status) {
      case 'address_applied':
        return 'Address applied';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Pending';
    }
  }

  String get _summary {
    switch (status) {
      case 'address_applied':
        return needsAddressRecovery
            ? 'Support applied the latest address update, but delivery still needs a usable address.'
            : 'Support applied the latest address update for this order. Send another update below if anything changed again.';
      case 'resolved':
        return needsAddressRecovery
            ? 'Support marked this request resolved. If delivery is still blocked, send a new support request.'
            : 'Support marked your latest request for this order as resolved. Reopen it below if you still need help.';
      default:
        return needsAddressRecovery
            ? 'The support team is reviewing the delivery address issue for this order.'
            : 'The support team is reviewing your latest request for this order.';
    }
  }

  String get _replyActionLabel {
    switch (status) {
      case 'address_applied':
        return 'Send another update';
      case 'resolved':
        return 'Reopen in Support';
      default:
        return 'Reply in Support';
    }
  }

  IconData get _replyActionIcon {
    switch (status) {
      case 'address_applied':
        return Icons.edit_note_outlined;
      case 'resolved':
        return Icons.refresh_rounded;
      default:
        return Icons.support_agent_outlined;
    }
  }

  Color get _backgroundColor {
    switch (status) {
      case 'address_applied':
        return const Color(0xFFEAF4FF);
      case 'resolved':
        return const Color(0xFFEFFAF4);
      default:
        return const Color(0xFFFFF6EB);
    }
  }

  Color get _borderColor {
    switch (status) {
      case 'address_applied':
        return const Color(0xFF9CC2EC);
      case 'resolved':
        return const Color(0xFF9BD3AE);
      default:
        return const Color(0xFFF3C37A);
    }
  }

  Color get _accentColor {
    switch (status) {
      case 'address_applied':
        return const Color(0xFF1E5E9A);
      case 'resolved':
        return const Color(0xFF1F5F3A);
      default:
        return const Color(0xFF9A5400);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Support request',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _accentColor,
                  ),
                ),
              ),
              if (isUnread)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE6D7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'New',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB85A00),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_summary, style: TextStyle(color: _accentColor, height: 1.35)),
          if (latestSupportNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latest reply',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestSupportNote.trim(),
                    style: const TextStyle(height: 1.35),
                  ),
                  if (latestSupportNoteUpdatedAtLabel != null &&
                      latestSupportNoteUpdatedAtLabel!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reply updated: ${latestSupportNoteUpdatedAtLabel!.trim()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF56636D),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (updatedAtLabel != null && updatedAtLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Updated: ${updatedAtLabel!.trim()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accentColor,
              ),
            ),
          ],
          if (isUnread || onReplyInSupport != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (isUnread && onMarkAsRead != null)
                  TextButton.icon(
                    onPressed: onMarkAsRead,
                    icon: const Icon(Icons.done_rounded),
                    label: const Text('Mark as read'),
                  ),
                if (onReplyInSupport != null)
                  OutlinedButton.icon(
                    onPressed: onReplyInSupport,
                    icon: Icon(_replyActionIcon),
                    label: Text(_replyActionLabel),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class OrderSupportHistorySection extends StatelessWidget {
  const OrderSupportHistorySection({
    super.key,
    required this.history,
    required this.formatDateTimeLabel,
  });

  final List<Map<String, dynamic>> history;
  final String Function(dynamic) formatDateTimeLabel;

  String _statusLabel(String raw) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'address_applied':
        return 'Address applied';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Pending';
    }
  }

  String _eventSummary(String raw) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'address_applied':
        return 'Support applied the latest address on file.';
      case 'resolved':
        return 'Support marked this request resolved.';
      default:
        return 'Support request sent and waiting for review.';
    }
  }

  Color _statusColor(String raw) {
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'address_applied':
        return const Color(0xFF1E5E9A);
      case 'resolved':
        return const Color(0xFF1F5F3A);
      default:
        return const Color(0xFF9A5400);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E0E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Support activity (${history.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...history.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final status = (item['support_request_status'] ?? 'pending')
                .toString();
            final color = _statusColor(status);
            final updatedAddress =
                parseUpdatedDeliveryAddressFromSupportMessage(
                  (item['support_request_message'] ?? '').toString(),
                );
            final supportNote = (item['support_note'] ?? '').toString().trim();
            final requestType = (item['request_type'] ?? '').toString().trim();
            final rawDate = (item['support_request_status_updated_at'] ?? '')
                .toString()
                .trim();
            final rawNoteDate = (item['support_note_updated_at'] ?? '')
                .toString()
                .trim();
            final fallbackDate = (item['support_request_created_at'] ?? '')
                .toString()
                .trim();
            final dateLabel = rawNoteDate.isNotEmpty
                ? formatDateTimeLabel(rawNoteDate)
                : rawDate.isNotEmpty
                ? formatDateTimeLabel(rawDate)
                : formatDateTimeLabel(fallbackDate);

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == history.length - 1 ? 0 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _statusLabel(status),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            if (requestType.isNotEmpty)
                              Text(
                                requestType[0].toUpperCase() +
                                    requestType.substring(1).toLowerCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF56636D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              dateLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF56636D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _eventSummary(status),
                          style: const TextStyle(height: 1.35),
                        ),
                        if (supportNote.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Support reply: $supportNote',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E5E9A),
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (updatedAddress.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Address shared: $updatedAddress',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF56636D),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class OrderAddressRecoveryPanel extends StatelessWidget {
  const OrderAddressRecoveryPanel({
    super.key,
    this.supportStatus = '',
    required this.onUpdateSavedAddress,
    required this.onContactSupport,
  });

  final String supportStatus;
  final VoidCallback onUpdateSavedAddress;
  final VoidCallback onContactSupport;

  String get _normalizedSupportStatus => supportStatus.trim().toLowerCase();

  String get _title {
    switch (_normalizedSupportStatus) {
      case 'pending':
        return 'Support is reviewing your address update.';
      case 'address_applied':
        return 'Check the latest address update.';
      case 'resolved':
        return 'Request resolved, but delivery is still blocked.';
      default:
        return 'Address required before delivery can continue.';
    }
  }

  String get _message {
    switch (_normalizedSupportStatus) {
      case 'pending':
        return 'Your request is already with support. If your saved address changed again, update it and send a follow-up message.';
      case 'address_applied':
        return 'Support applied the latest address they received. If delivery still cannot continue, send a new address update.';
      case 'resolved':
        return 'The last request was marked resolved. Update your saved address and reopen it in support so the team can continue this order.';
      default:
        return 'Update your saved address, then contact support so the team can apply it to this order.';
    }
  }

  String get _contactButtonLabel {
    switch (_normalizedSupportStatus) {
      case 'pending':
        return 'Send follow-up';
      case 'address_applied':
        return 'Send another update';
      case 'resolved':
        return 'Reopen in Support';
      default:
        return 'Contact support';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6EB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3C37A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A5400),
            ),
          ),
          const SizedBox(height: 6),
          Text(_message, style: const TextStyle(color: Color(0xFF7A4A10))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onUpdateSavedAddress,
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Update saved address'),
              ),
              OutlinedButton.icon(
                onPressed: onContactSupport,
                icon: const Icon(Icons.support_agent_outlined),
                label: Text(_contactButtonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
