import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';

class OrderHistoryListScreen extends StatefulWidget {
  const OrderHistoryListScreen({super.key});

  @override
  State<OrderHistoryListScreen> createState() => _OrderHistoryListScreenState();
}

class _OrderHistoryListScreenState extends State<OrderHistoryListScreen> {
  late Stream<List<Map<String, dynamic>>> _ordersStream;
  final Set<String> _exportingOrderIds = {};
  Timer? _refreshTicker;

  @override
  void initState() {
    super.initState();
    _ordersStream = _buildOrdersStream();
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
    final address = (order['address'] ?? '').toString();
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
                final addressDetails = (order['address_details'] ?? '')
                    .toString()
                    .trim();
                final createdAt = _formatDateTime(order['created_at']);
                final exporting = _exportingOrderIds.contains(orderId);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
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
                      if (paymentReference.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Payment Ref: $paymentReference'),
                      ],
                      if (addressDetails.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Details: $addressDetails'),
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
