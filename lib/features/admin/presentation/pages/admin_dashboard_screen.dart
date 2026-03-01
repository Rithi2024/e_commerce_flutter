import 'dart:convert';

import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/core/platform/file_export_saver.dart';
import 'package:marketflow/core/widgets/logout_prompt_dialog.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_accounts_tab.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_events_tab.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_orders_filter_panel.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_orders_tab.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_products_tab.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_super_dashboard_tab.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_support_requests_tab.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/admin/presentation/bloc/admin_dashboard_provider.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart' as xml;

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const String _productImagesBucket = 'product-images';
  static const int _maxProductImageBytes = 8 * 1024 * 1024;
  static const Set<String> _imageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
  };
  static const List<String> _variantSizes = ['S', 'M', 'L', 'XL'];
  static const List<String> _variantColors = ['Black', 'White', 'Blue', 'Red'];
  static const List<String> _orderStatuses = [
    'all',
    'order_received',
    'order_packed',
    'ready_for_pickup',
    'out_for_delivery',
    'delivered',
    'cancelled',
  ];
  static const List<String> _orderDeliveryTypes = [
    'all',
    'drop_off',
    'real_meeting',
  ];
  static const List<_EventThemeOption> _eventThemes = <_EventThemeOption>[
    _EventThemeOption('default', 'Default'),
    _EventThemeOption('christmas_sale', 'Christmas Sale'),
    _EventThemeOption('valentine', 'Valentine'),
    _EventThemeOption('new_year', 'New Year'),
    _EventThemeOption('black_friday', 'Black Friday'),
    _EventThemeOption('summer_sale', 'Summer Sale'),
  ];
  static const String _deliveryQrPrefix = 'MF-ORDER-';

  final _searchController = TextEditingController();
  final _orderFilterController = TextEditingController();
  final _tabController = ValueNotifier<int>(0);

  bool _exportingOrders = false;
  bool _exportingStock = false;
  String _productCategoryFilter = 'All';
  String _orderStatusFilter = 'all';
  String _orderDeliveryFilter = 'all';
  String _orderSearchFilter = '';
  DateTime? _ordersFromDate;
  DateTime? _ordersToDate;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    _ordersToDate = day;
    _ordersFromDate = day.subtract(const Duration(days: 30));
    Future.microtask(_initialize);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _orderFilterController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  double _dialogWidth(BuildContext context, double preferred) {
    final maxAllowed = MediaQuery.sizeOf(context).width - 32;
    if (maxAllowed <= 0) return preferred;
    return preferred < maxAllowed ? preferred : maxAllowed;
  }

  Future<void> _initialize() async {
    final admin = context.read<AdminDashboardProvider>();
    final result = await admin.initialize();
    if (!mounted || result.isSuccess) return;

    final failure = result.requireFailure;
    if (!admin.hasDashboardAccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Staff access required')));
      await Navigator.of(context).maybePop();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load staff data: ${failure.message}')),
    );
  }

  Future<void> _loadProducts() async {
    final result = await context.read<AdminDashboardProvider>().loadProducts(
      query: _searchController.text.trim(),
    );
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to load products: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  Future<void> _setAccountType({
    required String userId,
    required String accountType,
  }) async {
    final result = await context.read<AdminDashboardProvider>().setAccountType(
      userId: userId,
      accountType: accountType,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account role updated')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to update role: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  Future<void> _loadOrders() async {
    final result = await context.read<AdminDashboardProvider>().loadOrders();
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to load orders: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  Future<void> _loadSupportRequests() async {
    final result = await context
        .read<AdminDashboardProvider>()
        .loadSupportRequests();
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to load support requests: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  String _deliveryStageStatus(String status) {
    final normalized = _normalizeOrderStatus(status);
    if (normalized == 'pending' || normalized == 'paid') {
      return 'order_received';
    }
    if (normalized == 'shipped') return 'out_for_delivery';
    return normalized;
  }

  String _buildDeliveryQrPayload(AdminOrder order) {
    return '$_deliveryQrPrefix${order.id}';
  }

  int? _parseOrderIdFromDeliveryQr(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.isEmpty) return null;
    final normalizedPrefix = _deliveryQrPrefix.toUpperCase();
    if (value.startsWith(normalizedPrefix)) {
      final idPart = value.substring(normalizedPrefix.length).trim();
      return int.tryParse(idPart);
    }
    return int.tryParse(value);
  }

  String? _nextAutoStatusForOrder(AdminOrder order, {bool riderOnly = false}) {
    final current = _deliveryStageStatus(order.status);
    final delivery = order.deliveryType.trim().toLowerCase();
    final isPickup = delivery == 'real_meeting' || delivery == 'pickup';

    if (riderOnly) {
      if (current == 'order_received' || current == 'order_packed') {
        return 'out_for_delivery';
      }
      if (current == 'ready_for_pickup' || current == 'out_for_delivery') {
        return 'delivered';
      }
      return null;
    }

    switch (current) {
      case 'order_received':
        return 'order_packed';
      case 'order_packed':
        return isPickup ? 'ready_for_pickup' : 'out_for_delivery';
      case 'ready_for_pickup':
      case 'out_for_delivery':
        return 'delivered';
      default:
        return null;
    }
  }

  List<String> _statusUpdateOptionsForOrder(AdminOrder order) {
    final admin = context.read<AdminDashboardProvider>();
    if (!admin.canUpdateDeliveryStatus) {
      return const <String>[];
    }

    final current = _deliveryStageStatus(order.status);
    if (current == 'cancelled' || current == 'delivered') {
      return const <String>[];
    }

    final riderOnly = admin.hasRiderAccess && !admin.hasAdminAccess;
    final nextStatus = _nextAutoStatusForOrder(order, riderOnly: riderOnly);
    if (nextStatus == null) {
      return const <String>[];
    }

    final options = <String>[nextStatus];
    if (admin.hasAdminAccess && current != 'cancelled') {
      options.add('cancelled');
    }
    return options;
  }

  Future<void> _updateOrderStatus(
    AdminOrder order,
    String nextStatus, {
    bool skipConfirmation = false,
    String? confirmationTitle,
  }) async {
    final currentStatus = _deliveryStageStatus(order.status);
    final normalizedNext = _deliveryStageStatus(nextStatus);
    if (normalizedNext.isEmpty || normalizedNext == currentStatus) return;

    if (!skipConfirmation) {
      final isDeliveryConfirmation = normalizedNext == 'delivered';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            confirmationTitle ??
                (isDeliveryConfirmation
                    ? 'Confirm Delivery'
                    : 'Update Order Status'),
          ),
          content: Text(
            'Set order #${order.id} status to "${_statusLabel(normalizedNext)}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final result = await context
        .read<AdminDashboardProvider>()
        .updateOrderStatus(orderId: order.id, status: normalizedNext);
    if (!mounted) return;
    if (result.isSuccess) {
      final confirmedDelivery = normalizedNext == 'delivered';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirmedDelivery
                ? 'Order #${order.id} delivery confirmed'
                : 'Order #${order.id} status updated to ${_statusLabel(normalizedNext)}',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to update order status: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  Future<void> _showDeliveryQr(AdminOrder order) async {
    final payload = _buildDeliveryQrPayload(order);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delivery QR: Order #${order.id}'),
        content: SizedBox(
          width: _dialogWidth(context, 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: payload,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                payload,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan this code to auto-advance delivery stage.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndAdvanceWithQr() async {
    final codeController = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Scan Delivery QR'),
          content: SizedBox(
            width: _dialogWidth(context, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scan with a scanner device or paste the QR code value.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'QR Code',
                    hintText: 'Example: MF-ORDER-123',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Scan'),
            ),
          ],
        ),
      );
      if (submitted != true || !mounted) return;

      final parsedOrderId = _parseOrderIdFromDeliveryQr(codeController.text);
      if (parsedOrderId == null || parsedOrderId <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid QR code format')));
        return;
      }

      final admin = context.read<AdminDashboardProvider>();
      final matchedOrder = admin.orders.where((o) => o.id == parsedOrderId);
      if (matchedOrder.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order #$parsedOrderId was not found')),
        );
        return;
      }
      final order = matchedOrder.first;
      final riderOnly = admin.hasRiderAccess && !admin.hasAdminAccess;
      final nextStatus = _nextAutoStatusForOrder(order, riderOnly: riderOnly);
      if (nextStatus == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order #${order.id} is already completed or not eligible for auto-advance',
            ),
          ),
        );
        return;
      }

      await _updateOrderStatus(
        order,
        nextStatus,
        confirmationTitle: 'Confirm QR Delivery Update',
      );
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _confirmCashPayment(AdminOrder order) async {
    final paymentMethod = order.paymentMethod.trim().toLowerCase();
    if (paymentMethod != 'cash_on_delivery' || order.cashPaidConfirmed) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Cash Payment'),
        content: Text(
          'Confirm cash payment for order #${order.id} (${_formatMoney(order.total)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await context
        .read<AdminDashboardProvider>()
        .confirmCashPayment(orderId: order.id);
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cash payment confirmed for order #${order.id}'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to confirm cash payment: ${result.requireFailure.message}',
        ),
      ),
    );
  }

  Future<void> _logoutAdmin() async {
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

  String _formatCountdown(Duration value) {
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  String _variantKey(String size, String color) => '$size::$color';

  String _deliveryTypeLabel(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'real_meeting' || value == 'pickup') return 'Store Pickup';
    return 'Drop-off';
  }

  String _paymentMethodLabel(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value == 'aba_payway_qr') return 'ABA PayWay QR';
    return 'Cash on delivery';
  }

  String _paymentMethodAdminLabel(String method) {
    switch (method) {
      case AppSettingsProvider.paymentAbaPayWayQr:
        return 'ABA PayWay QR';
      case AppSettingsProvider.paymentCashOnDelivery:
        return 'Cash on Delivery';
      default:
        return method;
    }
  }

  String _statusLabel(String status) {
    final normalized = _normalizeOrderStatus(status);
    if (normalized.isEmpty || normalized == 'all') return 'All statuses';
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

  String _normalizeOrderStatus(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'paiding' || normalized == 'paying') {
      return 'order_received';
    }
    if (normalized == 'pending' || normalized == 'paid') {
      return 'order_received';
    }
    if (normalized == 'shipped') return 'out_for_delivery';
    return normalized.isEmpty ? 'order_received' : normalized;
  }

  String _formatMoney(
    double usd, {
    String? productId,
    double? overrideDiscountPercent,
  }) {
    final settings = context.read<AppSettingsProvider>();
    return settings.formatUsd(
      usd,
      productId: productId,
      overrideDiscountPercent: overrideDiscountPercent,
    );
  }

  String _formatDateTimeLocal(dynamic raw) {
    final source = (raw ?? '').toString();
    final dt = DateTime.tryParse(source)?.toLocal();
    if (dt == null) return source.isEmpty ? '-' : source;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _formatDateShort(DateTime? value) {
    if (value == null) return 'Any';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _formatDateTimeShort(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  Future<DateTime?> _pickLocalDateTime({
    required DateTime initial,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(now.year - 5),
      lastDate: lastDate ?? DateTime(now.year + 8),
    );
    if (pickedDate == null) return null;

    if (!mounted) return null;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  String _defaultBadgeForTheme(String value) {
    switch (value) {
      case 'christmas_sale':
        return 'Christmas Sale';
      case 'valentine':
        return 'Valentine Special';
      case 'new_year':
        return 'New Year Offer';
      case 'black_friday':
        return 'Black Friday';
      case 'summer_sale':
        return 'Summer Sale';
      default:
        return 'Featured Event';
    }
  }

  DateTime? _orderDateLocal(AdminOrder order) {
    return order.createdAt?.toLocal();
  }

  bool _isOrderInSelectedPeriod(AdminOrder order) {
    final createdAt = _orderDateLocal(order);
    if (createdAt == null) return false;

    if (_ordersFromDate != null) {
      final start = DateTime(
        _ordersFromDate!.year,
        _ordersFromDate!.month,
        _ordersFromDate!.day,
      );
      if (createdAt.isBefore(start)) return false;
    }
    if (_ordersToDate != null) {
      final end = DateTime(
        _ordersToDate!.year,
        _ordersToDate!.month,
        _ordersToDate!.day,
        23,
        59,
        59,
        999,
      );
      if (createdAt.isAfter(end)) return false;
    }
    return true;
  }

  bool _matchesOrderFilters(AdminOrder order) {
    if (!_isOrderInSelectedPeriod(order)) return false;

    final status = _normalizeOrderStatus(order.status);
    if (_orderStatusFilter != 'all' && status != _orderStatusFilter) {
      return false;
    }

    final delivery = order.deliveryType.trim().toLowerCase();
    if (_orderDeliveryFilter != 'all' && delivery != _orderDeliveryFilter) {
      return false;
    }

    final query = _orderSearchFilter.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack = [
        order.id.toString(),
        order.email,
        order.userId,
        status,
        delivery,
        order.paymentMethod,
        order.paymentReference,
        order.address,
        order.addressDetails,
        order.total.toString(),
      ].join(' ').toLowerCase();
      if (!haystack.contains(query)) return false;
    }

    return true;
  }

  List<AdminOrder> get _filteredOrders {
    return context
        .read<AdminDashboardProvider>()
        .orders
        .where(_matchesOrderFilters)
        .toList();
  }

  List<Product> _filterProducts(List<Product> source) {
    final filter = _productCategoryFilter.trim().toLowerCase();
    if (filter.isEmpty || filter == 'all') {
      return source;
    }
    return source.where((product) {
      final category = (product.category ?? 'All').trim().toLowerCase();
      return category == filter;
    }).toList();
  }

  Future<void> _pickOrdersFromDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _ordersFromDate ?? _ordersToDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _ordersFromDate = picked;
      if (_ordersToDate != null && _ordersToDate!.isBefore(picked)) {
        _ordersToDate = picked;
      }
    });
  }

  Future<void> _pickOrdersToDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _ordersToDate ?? _ordersFromDate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _ordersToDate = picked;
      if (_ordersFromDate != null && _ordersFromDate!.isAfter(picked)) {
        _ordersFromDate = picked;
      }
    });
  }

  void _resetOrderFilters() {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    setState(() {
      _ordersToDate = day;
      _ordersFromDate = day.subtract(const Duration(days: 30));
      _orderStatusFilter = 'all';
      _orderDeliveryFilter = 'all';
      _orderSearchFilter = '';
      _orderFilterController.clear();
    });
  }

  List<int> _applyWorksheetAutoFilter({
    required List<int> xlsxBytes,
    required String sheetName,
    required int columnCount,
    required int rowCount,
  }) {
    if (columnCount <= 0 || rowCount <= 1) return xlsxBytes;
    try {
      final archive = ZipDecoder().decodeBytes(xlsxBytes);

      ArchiveFile? workbookFile;
      ArchiveFile? relsFile;
      for (final file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookFile = file;
        } else if (file.name == 'xl/_rels/workbook.xml.rels') {
          relsFile = file;
        }
      }
      if (workbookFile == null || relsFile == null) {
        return xlsxBytes;
      }

      final workbookBytes = _archiveFileBytes(workbookFile);
      final relsBytes = _archiveFileBytes(relsFile);
      if (workbookBytes == null || relsBytes == null) {
        return xlsxBytes;
      }

      final workbookDoc = xml.XmlDocument.parse(utf8.decode(workbookBytes));
      final relsDoc = xml.XmlDocument.parse(utf8.decode(relsBytes));

      final relationshipNamespace =
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

      xml.XmlElement? sheetElement;
      for (final element in workbookDoc.findAllElements('sheet')) {
        if (element.getAttribute('name') == sheetName) {
          sheetElement = element;
          break;
        }
      }
      if (sheetElement == null) return xlsxBytes;

      var relationId = sheetElement.getAttribute(
        'id',
        namespace: relationshipNamespace,
      );
      if (relationId == null || relationId.isEmpty) {
        for (final attribute in sheetElement.attributes) {
          if (attribute.name.local == 'id') {
            relationId = attribute.value;
            break;
          }
        }
      }
      if (relationId == null || relationId.isEmpty) return xlsxBytes;

      xml.XmlElement? relationshipElement;
      for (final element in relsDoc.findAllElements('Relationship')) {
        if (element.getAttribute('Id') == relationId) {
          relationshipElement = element;
          break;
        }
      }
      if (relationshipElement == null) return xlsxBytes;

      var target = relationshipElement.getAttribute('Target') ?? '';
      target = target.replaceAll('\\', '/');
      if (target.startsWith('/')) {
        target = target.substring(1);
      }
      final worksheetPath = target.startsWith('xl/') ? target : 'xl/$target';

      ArchiveFile? worksheetFile;
      for (final file in archive.files) {
        if (file.name == worksheetPath) {
          worksheetFile = file;
          break;
        }
      }
      if (worksheetFile == null) return xlsxBytes;

      final worksheetBytes = _archiveFileBytes(worksheetFile);
      if (worksheetBytes == null) return xlsxBytes;

      final worksheetDoc = xml.XmlDocument.parse(utf8.decode(worksheetBytes));
      final worksheetElement = worksheetDoc.rootElement;
      final filterRange =
          'A1:${_excelColumnName(columnCount)}${rowCount < 2 ? 2 : rowCount}';

      final existingFilters = worksheetElement.childElements
          .where((element) => element.name.local == 'autoFilter')
          .toList();
      if (existingFilters.isNotEmpty) {
        existingFilters.first.setAttribute('ref', filterRange);
        for (final extra in existingFilters.skip(1)) {
          extra.remove();
        }
      } else {
        final autoFilter = xml.XmlElement(
          xml.XmlName('autoFilter'),
          <xml.XmlAttribute>[xml.XmlAttribute(xml.XmlName('ref'), filterRange)],
        );
        final worksheetChildren = worksheetElement.children;
        var inserted = false;
        for (var i = worksheetChildren.length - 1; i >= 0; i--) {
          final child = worksheetChildren[i];
          if (child is xml.XmlElement && child.name.local == 'sheetData') {
            worksheetChildren.insert(i + 1, autoFilter);
            inserted = true;
            break;
          }
        }
        if (!inserted) {
          worksheetChildren.add(autoFilter);
        }
      }

      final updatedWorksheetBytes = utf8.encode(
        worksheetDoc.toXmlString(pretty: false),
      );
      archive.files.removeWhere((file) => file.name == worksheetPath);
      archive.addFile(
        ArchiveFile(
          worksheetPath,
          updatedWorksheetBytes.length,
          updatedWorksheetBytes,
        ),
      );
      final output = ZipEncoder().encode(archive);
      return output ?? xlsxBytes;
    } catch (_) {
      return xlsxBytes;
    }
  }

  List<int>? _archiveFileBytes(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      return content;
    }
    if (content is String) {
      return utf8.encode(content);
    }
    return null;
  }

  String _excelColumnName(int oneBasedColumnIndex) {
    var value = oneBasedColumnIndex;
    if (value <= 0) return 'A';
    final buffer = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      buffer.writeCharCode(65 + remainder);
      value = (value - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  String _buildOrderFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final from = _formatDateShort(_ordersFromDate).replaceAll('-', '');
    final to = _formatDateShort(_ordersToDate).replaceAll('-', '');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'orders_summary_${from}_${to}_$stamp.xlsx';
  }

  String _buildStockFileName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'stock_summary_$stamp.xlsx';
  }

  Future<void> _exportOrdersExcel() async {
    final admin = context.read<AdminDashboardProvider>();
    if (_exportingOrders || admin.loadingOrders) return;
    final filtered = _filteredOrders;
    if (filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No orders to export')));
      return;
    }

    setState(() => _exportingOrders = true);
    try {
      final workbook = xl.Excel.createExcel();
      const ordersSheetName = 'Orders';
      const summarySheetName = 'Summary';
      final defaultSheetName = workbook.getDefaultSheet();
      if (defaultSheetName != null && defaultSheetName != ordersSheetName) {
        workbook.rename(defaultSheetName, ordersSheetName);
      }
      final ordersSheet = workbook[ordersSheetName];
      final summarySheet = workbook[summarySheetName];

      ordersSheet.appendRow([
        xl.TextCellValue('Order ID'),
        xl.TextCellValue('Created At'),
        xl.TextCellValue('Customer Email'),
        xl.TextCellValue('User ID'),
        xl.TextCellValue('Status'),
        xl.TextCellValue('Delivery Type'),
        xl.TextCellValue('Payment Method'),
        xl.TextCellValue('Payment Reference'),
        xl.TextCellValue('Address'),
        xl.TextCellValue('Address Details'),
        xl.TextCellValue('Items Count'),
        xl.TextCellValue('Total Qty'),
        xl.TextCellValue('Total'),
        xl.TextCellValue('Items'),
      ]);

      double revenue = 0;
      int totalQty = 0;
      final statusCounts = <String, int>{};
      final deliveryCounts = <String, int>{};
      final productQty = <String, int>{};

      for (final order in filtered) {
        final orderId = order.id.toString();
        final createdAt = _formatDateTimeLocal(
          order.createdAt?.toIso8601String(),
        );
        final email = order.email;
        final userId = order.userId;
        final status = _normalizeOrderStatus(order.status);
        final delivery = order.deliveryType.trim().toLowerCase();
        final paymentMethod = order.paymentMethod.trim().toLowerCase();
        final paymentReference = order.paymentReference.trim();
        final address = order.address;
        final addressDetails = order.addressDetails;
        final total = order.total;
        final items = order.items;
        final itemCount = items.length;
        int orderQty = 0;
        final itemTexts = <String>[];

        for (final item in items) {
          final name = item.name.trim().isEmpty ? 'Item' : item.name.trim();
          final qty = item.qty <= 0 ? 1 : item.qty;
          final size = item.size.trim();
          final color = item.color.trim();
          final variant = [size, color].where((v) => v.isNotEmpty).join('/');
          orderQty += qty;
          totalQty += qty;
          if (name.isNotEmpty) {
            productQty[name] = (productQty[name] ?? 0) + qty;
          }
          itemTexts.add(
            variant.isEmpty ? '$name x$qty' : '$name ($variant) x$qty',
          );
        }

        revenue += total;
        statusCounts[status] = (statusCounts[status] ?? 0) + 1;
        deliveryCounts[delivery] = (deliveryCounts[delivery] ?? 0) + 1;

        ordersSheet.appendRow([
          xl.TextCellValue(orderId),
          xl.TextCellValue(createdAt),
          xl.TextCellValue(email),
          xl.TextCellValue(userId),
          xl.TextCellValue(_statusLabel(status)),
          xl.TextCellValue(_deliveryTypeLabel(delivery)),
          xl.TextCellValue(_paymentMethodLabel(paymentMethod)),
          xl.TextCellValue(paymentReference),
          xl.TextCellValue(address),
          xl.TextCellValue(addressDetails),
          xl.IntCellValue(itemCount),
          xl.IntCellValue(orderQty),
          xl.DoubleCellValue(total),
          xl.TextCellValue(itemTexts.join(' | ')),
        ]);
      }

      summarySheet.appendRow([
        xl.TextCellValue('Metric'),
        xl.TextCellValue('Value'),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Generated At'),
        xl.TextCellValue(
          _formatDateTimeLocal(DateTime.now().toIso8601String()),
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Period'),
        xl.TextCellValue(
          '${_formatDateShort(_ordersFromDate)} to ${_formatDateShort(_ordersToDate)}',
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Search Filter'),
        xl.TextCellValue(
          _orderSearchFilter.isEmpty ? 'All' : _orderSearchFilter,
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Status Filter'),
        xl.TextCellValue(_statusLabel(_orderStatusFilter)),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Delivery Filter'),
        xl.TextCellValue(
          _orderDeliveryFilter == 'all'
              ? 'All delivery types'
              : _deliveryTypeLabel(_orderDeliveryFilter),
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Orders'),
        xl.IntCellValue(filtered.length),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Revenue'),
        xl.DoubleCellValue(revenue),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Average Order Value'),
        xl.DoubleCellValue(filtered.isEmpty ? 0 : revenue / filtered.length),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Total Quantity'),
        xl.IntCellValue(totalQty),
      ]);
      summarySheet.appendRow([xl.TextCellValue(''), xl.TextCellValue('')]);
      summarySheet.appendRow([
        xl.TextCellValue('Orders By Status'),
        xl.TextCellValue('Count'),
      ]);
      for (final entry in statusCounts.entries) {
        summarySheet.appendRow([
          xl.TextCellValue(_statusLabel(entry.key)),
          xl.IntCellValue(entry.value),
        ]);
      }
      summarySheet.appendRow([xl.TextCellValue(''), xl.TextCellValue('')]);
      summarySheet.appendRow([
        xl.TextCellValue('Orders By Delivery'),
        xl.TextCellValue('Count'),
      ]);
      for (final entry in deliveryCounts.entries) {
        summarySheet.appendRow([
          xl.TextCellValue(_deliveryTypeLabel(entry.key)),
          xl.IntCellValue(entry.value),
        ]);
      }

      final topProducts = productQty.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (topProducts.isNotEmpty) {
        summarySheet.appendRow([xl.TextCellValue(''), xl.TextCellValue('')]);
        summarySheet.appendRow([
          xl.TextCellValue('Top Products'),
          xl.TextCellValue('Qty'),
        ]);
        for (final entry in topProducts) {
          summarySheet.appendRow([
            xl.TextCellValue(entry.key),
            xl.IntCellValue(entry.value),
          ]);
        }
      }

      for (var i = 0; i < 14; i++) {
        ordersSheet.setColumnAutoFit(i);
      }
      for (var i = 0; i < 2; i++) {
        summarySheet.setColumnAutoFit(i);
      }

      final bytes = workbook.save();
      if (bytes == null) {
        throw Exception('Could not build excel file');
      }

      final bytesWithFilter = _applyWorksheetAutoFilter(
        xlsxBytes: bytes,
        sheetName: ordersSheetName,
        columnCount: 14,
        rowCount: filtered.length + 1,
      );

      final filePath = await saveExportedFile(
        bytesWithFilter,
        _buildOrderFileName(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel exported to $filePath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _exportingOrders = false);
      }
    }
  }

  Future<void> _exportStockExcel() async {
    final admin = context.read<AdminDashboardProvider>();
    final settings = context.read<AppSettingsProvider>();
    if (_exportingStock || admin.loadingProducts) return;

    final filteredProducts = _filterProducts(admin.products);
    if (filteredProducts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No products to export')));
      return;
    }

    setState(() => _exportingStock = true);
    try {
      final workbook = xl.Excel.createExcel();
      const stockSheetName = 'Stock';
      const summarySheetName = 'Summary';
      final defaultSheetName = workbook.getDefaultSheet();
      if (defaultSheetName != null && defaultSheetName != stockSheetName) {
        workbook.rename(defaultSheetName, stockSheetName);
      }
      final stockSheet = workbook[stockSheetName];
      final summarySheet = workbook[summarySheetName];

      stockSheet.appendRow([
        xl.TextCellValue('Product ID'),
        xl.TextCellValue('Product Name'),
        xl.TextCellValue('Category'),
        xl.TextCellValue('Price'),
        xl.TextCellValue('Discount %'),
        xl.TextCellValue('Total Stock'),
        xl.TextCellValue('Size'),
        xl.TextCellValue('Color'),
        xl.TextCellValue('Variant Stock'),
      ]);

      var totalStock = 0;
      var stockDataRows = 0;
      for (final product in filteredProducts) {
        final stockResult = await admin.getProductVariantStocks(
          productId: product.id,
        );
        final variantMap = stockResult.isSuccess
            ? stockResult.requireValue
            : const <String, int>{};
        final discount = settings.discountPercentForProduct(
          productId: product.id,
        );
        final productStock = variantMap.values.fold<int>(
          0,
          (sum, v) => sum + v,
        );
        totalStock += productStock;

        final variants = variantMap.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        if (variants.isEmpty) {
          stockSheet.appendRow([
            xl.TextCellValue(product.id),
            xl.TextCellValue(product.name),
            xl.TextCellValue((product.category ?? 'All').trim()),
            xl.TextCellValue(_formatMoney(product.price)),
            xl.DoubleCellValue(discount),
            xl.IntCellValue(productStock),
            xl.TextCellValue('-'),
            xl.TextCellValue('-'),
            xl.IntCellValue(0),
          ]);
          stockDataRows += 1;
          continue;
        }

        for (var i = 0; i < variants.length; i++) {
          final entry = variants[i];
          final parts = entry.key.split('::');
          final size = parts.isNotEmpty ? parts.first : '-';
          final color = parts.length > 1 ? parts[1] : '-';
          stockSheet.appendRow([
            xl.TextCellValue(i == 0 ? product.id : ''),
            xl.TextCellValue(i == 0 ? product.name : ''),
            xl.TextCellValue(i == 0 ? (product.category ?? 'All').trim() : ''),
            xl.TextCellValue(i == 0 ? _formatMoney(product.price) : ''),
            i == 0 ? xl.DoubleCellValue(discount) : xl.TextCellValue(''),
            i == 0 ? xl.IntCellValue(productStock) : xl.TextCellValue(''),
            xl.TextCellValue(size),
            xl.TextCellValue(color),
            xl.IntCellValue(entry.value),
          ]);
        }
        stockDataRows += variants.length;
      }

      summarySheet.appendRow([
        xl.TextCellValue('Metric'),
        xl.TextCellValue('Value'),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Generated At'),
        xl.TextCellValue(
          _formatDateTimeLocal(DateTime.now().toIso8601String()),
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Search Filter'),
        xl.TextCellValue(
          _searchController.text.trim().isEmpty
              ? 'All'
              : _searchController.text.trim(),
        ),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Category Filter'),
        xl.TextCellValue(_productCategoryFilter),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Display Currency'),
        xl.TextCellValue(settings.currencyCode),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Exchange Rate'),
        xl.TextCellValue(settings.formatExchangeRate()),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Products'),
        xl.IntCellValue(filteredProducts.length),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Total Stock Units'),
        xl.IntCellValue(totalStock),
      ]);

      for (var i = 0; i < 9; i++) {
        stockSheet.setColumnAutoFit(i);
      }
      for (var i = 0; i < 2; i++) {
        summarySheet.setColumnAutoFit(i);
      }

      final bytes = workbook.save();
      if (bytes == null) {
        throw Exception('Could not build excel file');
      }

      final bytesWithFilter = _applyWorksheetAutoFilter(
        xlsxBytes: bytes,
        sheetName: stockSheetName,
        columnCount: 9,
        rowCount: stockDataRows + 1,
      );

      final filePath = await saveExportedFile(
        bytesWithFilter,
        _buildStockFileName(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stock excel exported to $filePath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Stock export failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _exportingStock = false);
      }
    }
  }

  Future<void> _openEventEditor({AdminEvent? event}) async {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController(text: event?.title ?? '');
    final subtitle = TextEditingController(text: event?.subtitle ?? '');
    final badge = TextEditingController(text: event?.badge ?? '');
    final nowLocal = DateTime.now();
    var startsAtLocal =
        event?.startsAt?.toLocal() ?? nowLocal.add(const Duration(minutes: 10));
    var expiresAtLocal =
        event?.expiresAt?.toLocal() ??
        startsAtLocal.add(const Duration(hours: 24));
    if (!expiresAtLocal.isAfter(startsAtLocal)) {
      expiresAtLocal = startsAtLocal.add(const Duration(hours: 1));
    }
    var theme = event?.theme.trim().toLowerCase() ?? 'default';
    if (!_eventThemes.any((option) => option.value == theme)) {
      theme = 'default';
    }
    bool isActive = event?.isActive ?? false;
    String dateTimeError = '';

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(event == null ? 'Add Event' : 'Edit Event'),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: title,
                          decoration: const InputDecoration(labelText: 'Title'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Title required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: subtitle,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Subtitle',
                            hintText: 'Shown on second line',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: badge,
                          decoration: const InputDecoration(
                            labelText: 'Badge',
                            hintText: 'Example: New Drop',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: theme,
                          decoration: const InputDecoration(labelText: 'Theme'),
                          items: _eventThemes
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option.value,
                                  child: Text(option.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              theme = value;
                              if (badge.text.trim().isEmpty) {
                                badge.text = _defaultBadgeForTheme(value);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.play_circle_outline),
                          title: const Text('Start Date & Time'),
                          subtitle: Text(_formatDateTimeShort(startsAtLocal)),
                          trailing: TextButton(
                            onPressed: () async {
                              final picked = await _pickLocalDateTime(
                                initial: startsAtLocal,
                              );
                              if (picked == null) return;
                              setDialogState(() {
                                startsAtLocal = picked;
                                if (!expiresAtLocal.isAfter(startsAtLocal)) {
                                  expiresAtLocal = startsAtLocal.add(
                                    const Duration(hours: 1),
                                  );
                                }
                                dateTimeError = '';
                              });
                            },
                            child: const Text('Select'),
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.stop_circle_outlined),
                          title: const Text('End Date & Time'),
                          subtitle: Text(_formatDateTimeShort(expiresAtLocal)),
                          trailing: TextButton(
                            onPressed: () async {
                              final picked = await _pickLocalDateTime(
                                initial: expiresAtLocal,
                                firstDate: DateTime(
                                  startsAtLocal.year,
                                  startsAtLocal.month,
                                  startsAtLocal.day,
                                ),
                              );
                              if (picked == null) return;
                              setDialogState(() {
                                expiresAtLocal = picked;
                                dateTimeError = '';
                              });
                            },
                            child: const Text('Select'),
                          ),
                        ),
                        if (dateTimeError.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              dateTimeError,
                              style: const TextStyle(
                                color: Color(0xFFB33030),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: isActive,
                          onChanged: (value) {
                            setDialogState(() => isActive = value);
                          },
                          title: const Text('Set as active event'),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      if (!expiresAtLocal.isAfter(startsAtLocal)) {
                        setDialogState(
                          () => dateTimeError =
                              'End date/time must be after start date/time',
                        );
                        return;
                      }
                      Navigator.pop(context, true);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (confirmed != true || !mounted) return;

      final admin = context.read<AdminDashboardProvider>();
      final result = await admin.saveEvent(
        eventId: event?.id,
        title: title.text.trim(),
        subtitle: subtitle.text.trim(),
        badge: badge.text.trim(),
        theme: theme,
        isActive: isActive,
        startsAtIsoUtc: startsAtLocal.toUtc().toIso8601String(),
        expiresAtIsoUtc: expiresAtLocal.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event saved')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: ${result.requireFailure.message}'),
        ),
      );
    } finally {
      title.dispose();
      subtitle.dispose();
      badge.dispose();
    }
  }

  Future<void> _deleteEvent(AdminEvent event) async {
    final eventId = event.id;
    final eventTitle = event.title;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "$eventTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final admin = context.read<AdminDashboardProvider>();
    final result = await admin.removeEvent(eventId: eventId);
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event deleted')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Delete failed: ${result.requireFailure.message}'),
      ),
    );
  }

  Future<void> _openStockEditor(Product product) async {
    final stockResult = await context
        .read<AdminDashboardProvider>()
        .getProductVariantStocks(productId: product.id);
    if (!mounted) return;
    if (stockResult.isFailure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open stock editor: ${stockResult.requireFailure.message}',
          ),
        ),
      );
      return;
    }

    final stockMap = stockResult.requireValue;
    final controllers = <String, TextEditingController>{};
    for (final size in _variantSizes) {
      for (final color in _variantColors) {
        final key = _variantKey(size, color);
        final value = stockMap[key] ?? 0;
        controllers[key] = TextEditingController(text: value.toString());
      }
    }

    if (!mounted) {
      for (final c in controllers.values) {
        c.dispose();
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stock: ${product.name}'),
        content: SizedBox(
          width: _dialogWidth(context, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final size in _variantSizes)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Size $size',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final color in _variantColors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 90, child: Text(color)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller:
                                      controllers[_variantKey(size, color)],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Stock',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final allControllers = controllers.values.toList();
    if (confirmed != true) {
      for (final c in allControllers) {
        c.dispose();
      }
      return;
    }
    if (!mounted) {
      for (final c in allControllers) {
        c.dispose();
      }
      return;
    }

    try {
      final admin = context.read<AdminDashboardProvider>();
      final payload = <Map<String, dynamic>>[];
      for (final size in _variantSizes) {
        for (final color in _variantColors) {
          final key = _variantKey(size, color);
          final text = controllers[key]!.text.trim();
          final stock = int.tryParse(text) ?? 0;
          payload.add({
            'size': size,
            'color': color,
            'stock': stock < 0 ? 0 : stock,
          });
        }
      }

      final result = await admin.setProductVariantStocks(
        productId: product.id,
        items: payload,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Stock updated')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock update failed: ${result.requireFailure.message}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open stock editor: $e')),
      );
    } finally {
      for (final c in allControllers) {
        c.dispose();
      }
    }
  }

  String _productSubtitle(Product product) {
    final settings = context.read<AppSettingsProvider>();
    final category = (product.category ?? 'All').trim();
    final discount = settings.discountPercentForProduct(productId: product.id);
    final discountText = discount > 0
        ? ' | Event Discount ${discount.toStringAsFixed(0)}%'
        : '';
    return '${settings.formatUsd(product.price, overrideDiscountPercent: 0)} - $category$discountText';
  }

  Future<void> _openDiscountEditor(Product product) async {
    final admin = context.read<AdminDashboardProvider>();
    final settings = context.read<AppSettingsProvider>();
    final events = admin.events;
    if (events.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create an event first')));
      return;
    }

    final activeEvent = events.where((event) => event.isActive).toList();
    var selectedEventId = activeEvent.isNotEmpty
        ? activeEvent.first.id
        : events.first.id;
    var selectedEventTitle = events
        .firstWhere((event) => event.id == selectedEventId)
        .title;
    var removeDiscount = false;
    final initialDiscount = settings.findEventDiscount(
      eventId: selectedEventId,
      productId: product.id,
    );
    final percentController = TextEditingController(
      text: initialDiscount?.discountPercent.toStringAsFixed(0) ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentDiscount = settings.findEventDiscount(
            eventId: selectedEventId,
            productId: product.id,
          );
          return AlertDialog(
            title: Text('Event Discount: ${product.name}'),
            content: SizedBox(
              width: _dialogWidth(context, 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('discount_event_$selectedEventId'),
                    initialValue: selectedEventId,
                    decoration: const InputDecoration(
                      labelText: 'Event',
                      border: OutlineInputBorder(),
                    ),
                    items: events
                        .map(
                          (event) => DropdownMenuItem<String>(
                            value: event.id,
                            child: Text(
                              event.title.trim().isEmpty
                                  ? event.id
                                  : event.title,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final nextEvent = events.firstWhere(
                        (event) => event.id == value,
                      );
                      setDialogState(() {
                        selectedEventId = value;
                        selectedEventTitle = nextEvent.title;
                        final existing = settings.findEventDiscount(
                          eventId: selectedEventId,
                          productId: product.id,
                        );
                        percentController.text = existing == null
                            ? ''
                            : existing.discountPercent.toStringAsFixed(0);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: percentController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Discount Percent',
                      hintText: 'Example: 10',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (currentDiscount != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Current: ${currentDiscount.discountPercent.toStringAsFixed(0)}% for this event',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              if (currentDiscount != null)
                TextButton(
                  onPressed: () {
                    removeDiscount = true;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Remove'),
                ),
              ElevatedButton(
                onPressed: () {
                  removeDiscount = false;
                  Navigator.pop(context, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      percentController.dispose();
      return;
    }

    if (removeDiscount) {
      await settings.removeEventDiscount(
        eventId: selectedEventId,
        productId: product.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event discount removed')));
      percentController.dispose();
      setState(() {});
      return;
    }

    final parsed = double.tryParse(percentController.text.trim());
    percentController.dispose();
    if (parsed == null || parsed < 0 || parsed > 95) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a discount between 0 and 95')),
      );
      return;
    }

    await settings.upsertEventDiscount(
      eventId: selectedEventId,
      eventTitle: selectedEventTitle,
      productId: product.id,
      discountPercent: parsed,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Event discount saved')));
    setState(() {});
  }

  Future<void> _showEventItems(AdminEvent event) async {
    final admin = context.read<AdminDashboardProvider>();
    final settings = context.read<AppSettingsProvider>();
    final eventItems = settings.eventDiscounts
        .where((entry) => entry.eventId == event.id)
        .toList();
    final productsById = <String, Product>{
      for (final product in admin.products) product.id: product,
    };
    final eventTitle = event.title.trim().isEmpty
        ? 'Untitled Event'
        : event.title;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Event Items: $eventTitle'),
          content: SizedBox(
            width: _dialogWidth(context, 520),
            child: eventItems.isEmpty
                ? const Text('No items found for this event')
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: eventItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = eventItems[index];
                        final product = productsById[item.productId];
                        final productTitle = product?.name ?? 'Unknown product';
                        final originalPrice = product == null
                            ? '-'
                            : _formatMoney(
                                product.price,
                                overrideDiscountPercent: 0,
                              );
                        final discountedPrice = product == null
                            ? '-'
                            : _formatMoney(
                                product.price,
                                overrideDiscountPercent: item.discountPercent,
                              );

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(productTitle),
                          subtitle: Text(
                            'Discount ${item.discountPercent.toStringAsFixed(0)}% | '
                            '$originalPrice -> $discountedPrice\n'
                            'Updated ${_formatDateTimeLocal(item.updatedAt.toIso8601String())}',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            item.productId,
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPaymentMethodManager() async {
    final settings = context.read<AppSettingsProvider>();
    var abaEnabled = settings.isPaymentMethodEnabled(
      AppSettingsProvider.paymentAbaPayWayQr,
    );
    var cashOnDeliveryEnabled = settings.isPaymentMethodEnabled(
      AppSettingsProvider.paymentCashOnDelivery,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Payment Methods'),
            content: SizedBox(
              width: _dialogWidth(context, 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _paymentMethodAdminLabel(
                        AppSettingsProvider.paymentAbaPayWayQr,
                      ),
                    ),
                    value: abaEnabled,
                    onChanged: (value) {
                      setDialogState(() => abaEnabled = value);
                    },
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _paymentMethodAdminLabel(
                        AppSettingsProvider.paymentCashOnDelivery,
                      ),
                    ),
                    value: cashOnDeliveryEnabled,
                    onChanged: (value) {
                      setDialogState(() => cashOnDeliveryEnabled = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Disable methods you do not want customers to use.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    if (!abaEnabled && !cashOnDeliveryEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one payment method must stay enabled'),
        ),
      );
      return;
    }

    await settings.setPaymentMethodEnabled(
      method: AppSettingsProvider.paymentAbaPayWayQr,
      enabled: abaEnabled,
    );
    await settings.setPaymentMethodEnabled(
      method: AppSettingsProvider.paymentCashOnDelivery,
      enabled: cashOnDeliveryEnabled,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Payment methods updated')));
  }

  Future<void> _openCategoryManager() async {
    final admin = context.read<AdminDashboardProvider>();
    final settings = context.read<AppSettingsProvider>();
    final formKey = GlobalKey<FormState>();
    final newCategoryController = TextEditingController();
    var removeCategory = '';
    var replacementCategory = 'All';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final allCategories = settings.categoriesForProducts(admin.products);
          final removable = allCategories.where((c) => c != 'All').toList();
          if (removeCategory.isEmpty && removable.isNotEmpty) {
            removeCategory = removable.first;
          }
          final replacements = allCategories
              .where((c) => c != removeCategory)
              .toList();
          if (!replacements.contains(replacementCategory) &&
              replacements.isNotEmpty) {
            replacementCategory = replacements.first;
          }

          return AlertDialog(
            title: const Text('Manage Categories'),
            content: SizedBox(
              width: _dialogWidth(context, 460),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Category',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: newCategoryController,
                        decoration: const InputDecoration(
                          labelText: 'Category name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(),
                      const SizedBox(height: 10),
                      const Text(
                        'Remove Category',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (removable.isEmpty)
                        const Text('No removable categories')
                      else ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'remove_category_$removeCategory',
                          ),
                          initialValue: removeCategory,
                          decoration: const InputDecoration(
                            labelText: 'Category to remove',
                            border: OutlineInputBorder(),
                          ),
                          items: removable
                              .map(
                                (category) => DropdownMenuItem<String>(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              removeCategory = value;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'replacement_category_$replacementCategory',
                          ),
                          initialValue: replacementCategory,
                          decoration: const InputDecoration(
                            labelText: 'Replace with',
                            border: OutlineInputBorder(),
                          ),
                          items: replacements
                              .map(
                                (category) => DropdownMenuItem<String>(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              replacementCategory = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      newCategoryController.dispose();
      return;
    }

    final newCategory = newCategoryController.text.trim();
    newCategoryController.dispose();
    if (newCategory.isNotEmpty) {
      await settings.addCustomCategory(newCategory);
    }

    if (removeCategory.trim().isNotEmpty &&
        removeCategory.trim().toLowerCase() != 'all') {
      final affected = admin.products
          .where(
            (product) =>
                (product.category ?? 'All').trim().toLowerCase() ==
                removeCategory.trim().toLowerCase(),
          )
          .toList();
      for (final product in affected) {
        final result = await admin.saveProduct(
          productId: product.id,
          name: product.name,
          price: product.price,
          imageUrl: product.imageUrl,
          description: product.description,
          category: replacementCategory,
        );
        if (result.isFailure) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to replace category: ${result.requireFailure.message}',
              ),
            ),
          );
          return;
        }
      }
      await settings.removeCustomCategory(removeCategory);
    }

    if (!mounted) return;
    await _loadProducts();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Category changes applied')));
    setState(() {});
  }

  String _sanitizeFileName(String raw) {
    final normalized = raw.trim().toLowerCase();
    final cleaned = normalized.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    if (cleaned.isEmpty) return 'product_image';
    return cleaned;
  }

  String _guessImageExtension(PlatformFile file) {
    final ext = (file.extension ?? '').trim().toLowerCase();
    if (_imageExtensions.contains(ext)) return ext;
    final match = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(file.name);
    final fromName = (match?.group(1) ?? '').trim().toLowerCase();
    if (_imageExtensions.contains(fromName)) return fromName;
    return 'jpg';
  }

  String _contentTypeForImageExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/webp';
    }
  }

  Future<String?> _pickAndUploadProductImage() async {
    final userId =
        context.read<AuthenticationProvider>().user?.id ?? 'anonymous';
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read selected image');
    }
    if (bytes.length > _maxProductImageBytes) {
      throw Exception('Image must be 8MB or smaller');
    }

    final extension = _guessImageExtension(file);
    var fileName = _sanitizeFileName(file.name);
    if (!fileName.contains('.')) {
      fileName = '$fileName.$extension';
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '$userId/product_${timestamp}_$fileName';

    final storageBucket = Supabase.instance.client.storage.from(
      _productImagesBucket,
    );

    try {
      await storageBucket.uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: _contentTypeForImageExtension(extension),
        ),
      );
    } on StorageException catch (error) {
      final message = error.message.trim();
      throw Exception(message.isEmpty ? 'Failed to upload image' : message);
    }

    return storageBucket.getPublicUrl(storagePath);
  }

  Future<void> _openProductEditor({Product? product}) async {
    final admin = context.read<AdminDashboardProvider>();
    final settings = context.read<AppSettingsProvider>();
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: product?.name ?? '');
    final price = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(2),
    );
    final imageUrl = TextEditingController(text: product?.imageUrl ?? '');
    final description = TextEditingController(text: product?.description ?? '');
    final addCategoryController = TextEditingController();
    var uploadingImage = false;
    var imageUploadError = '';
    var categories = settings.categoriesForProducts(admin.products);
    var selectedCategory = (product?.category ?? 'All').trim();
    if (!categories.contains(selectedCategory)) {
      categories = <String>[...categories, selectedCategory];
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(product == null ? 'Add Product' : 'Edit Product'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Name required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Price'),
                      validator: (value) {
                        final v = double.tryParse((value ?? '').trim());
                        if (v == null || v < 0) return 'Valid price required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    if (imageUrl.text.trim().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 130,
                          width: double.infinity,
                          child: Image.network(
                            imageUrl.text.trim(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Text('Image preview unavailable'),
                            ),
                          ),
                        ),
                      ),
                    if (imageUrl.text.trim().isNotEmpty)
                      const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: uploadingImage
                                ? null
                                : () async {
                                    setDialogState(() {
                                      uploadingImage = true;
                                      imageUploadError = '';
                                    });
                                    try {
                                      final uploadedUrl =
                                          await _pickAndUploadProductImage();
                                      if (!context.mounted) return;
                                      if (uploadedUrl != null &&
                                          uploadedUrl.trim().isNotEmpty) {
                                        setDialogState(() {
                                          imageUrl.text = uploadedUrl.trim();
                                        });
                                      }
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      setDialogState(() {
                                        imageUploadError = error
                                            .toString()
                                            .replaceFirst('Exception: ', '')
                                            .trim();
                                      });
                                    } finally {
                                      if (context.mounted) {
                                        setDialogState(() {
                                          uploadingImage = false;
                                        });
                                      }
                                    }
                                  },
                            icon: uploadingImage
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.image_outlined),
                            label: Text(
                              uploadingImage
                                  ? 'Uploading...'
                                  : 'Select Product Image',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Clear image',
                          onPressed: imageUrl.text.trim().isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    imageUrl.clear();
                                    imageUploadError = '';
                                  });
                                },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      ],
                    ),
                    if (imageUploadError.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        imageUploadError,
                        style: const TextStyle(color: Color(0xFFB33030)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: imageUrl,
                      decoration: const InputDecoration(
                        labelText: 'Image URL',
                        helperText: 'Use URL directly or select image above',
                      ),
                      onChanged: (_) {
                        setDialogState(() => imageUploadError = '');
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'editor_category_$selectedCategory',
                      ),
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedCategory = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: addCategoryController,
                            decoration: const InputDecoration(
                              labelText: 'New category',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            final value = addCategoryController.text.trim();
                            if (value.isEmpty) return;
                            await settings.addCustomCategory(value);
                            categories = settings.categoriesForProducts(
                              admin.products,
                            );
                            if (!categories.contains(value)) {
                              categories = <String>[...categories, value];
                            }
                            setDialogState(() {
                              selectedCategory = value;
                              addCategoryController.clear();
                            });
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: uploadingImage
                    ? null
                    : () {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(context, true);
                      },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      name.dispose();
      price.dispose();
      imageUrl.dispose();
      description.dispose();
      addCategoryController.dispose();
      return;
    }
    if (!mounted) return;

    final parsedPrice = double.parse(price.text.trim());
    final result = await admin.saveProduct(
      productId: product?.id,
      name: name.text.trim(),
      price: parsedPrice,
      imageUrl: imageUrl.text.trim(),
      description: description.text.trim(),
      category: selectedCategory,
    );
    name.dispose();
    price.dispose();
    imageUrl.dispose();
    description.dispose();
    addCategoryController.dispose();

    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product saved')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Save failed: ${result.requireFailure.message}')),
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final admin = context.read<AdminDashboardProvider>();
    final result = await admin.removeProduct(productId: product.id);
    if (!mounted) return;
    if (result.isSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product deleted')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Delete failed: ${result.requireFailure.message}'),
      ),
    );
  }

  Widget _buildSupportRequestsTab(AdminDashboardProvider admin) {
    return AdminSupportRequestsTab(
      loadingSupportRequests: admin.loadingSupportRequests,
      supportRequests: admin.supportRequests,
      formatDateTimeLocal: _formatDateTimeLocal,
    );
  }

  Widget _buildOrdersTab(
    AdminDashboardProvider admin, {
    required bool canConfirmCashPayments,
    required bool canUpdateDeliveryStatus,
    bool canExportOrders = true,
  }) {
    final filteredOrders = _filteredOrders;
    return AdminOrdersTab(
      loadingOrders: admin.loadingOrders,
      submitting: admin.submitting,
      canConfirmCashPayments: canConfirmCashPayments,
      canUpdateDeliveryStatus: canUpdateDeliveryStatus,
      totalOrdersCount: admin.orders.length,
      filteredOrders: filteredOrders,
      filterPanel: AdminOrdersFilterPanel(
        fromDate: _ordersFromDate,
        toDate: _ordersToDate,
        orderStatusFilter: _orderStatusFilter,
        orderDeliveryFilter: _orderDeliveryFilter,
        orderSearchFilter: _orderSearchFilter,
        orderFilterController: _orderFilterController,
        orderStatuses: _orderStatuses,
        orderDeliveryTypes: _orderDeliveryTypes,
        filteredOrdersCount: filteredOrders.length,
        totalOrdersCount: admin.orders.length,
        canExportOrders: canExportOrders,
        exportingOrders: canExportOrders ? _exportingOrders : false,
        onPickFromDate: _pickOrdersFromDate,
        onPickToDate: _pickOrdersToDate,
        onStatusChanged: (value) {
          if (value == null) return;
          setState(() => _orderStatusFilter = value);
        },
        onDeliveryChanged: (value) {
          if (value == null) return;
          setState(() => _orderDeliveryFilter = value);
        },
        onSearchChanged: (value) {
          setState(() => _orderSearchFilter = value.trim());
        },
        onClearSearch: () {
          _orderFilterController.clear();
          setState(() => _orderSearchFilter = '');
        },
        onResetFilters: _resetOrderFilters,
        onExportOrders: canExportOrders ? _exportOrdersExcel : () {},
        formatDateShort: _formatDateShort,
        statusLabel: _statusLabel,
        deliveryTypeLabel: _deliveryTypeLabel,
      ),
      onConfirmCashPayment: _confirmCashPayment,
      onUpdateOrderStatus: _updateOrderStatus,
      statusUpdateOptionsForOrder: _statusUpdateOptionsForOrder,
      deliveryTypeLabel: _deliveryTypeLabel,
      paymentMethodLabel: _paymentMethodLabel,
      statusLabel: _statusLabel,
      formatDateTimeLocal: _formatDateTimeLocal,
      formatMoney: _formatMoney,
      canUseDeliveryQr: canUpdateDeliveryStatus,
      onShowDeliveryQr: _showDeliveryQr,
      onScanAndAdvanceWithQr: _scanAndAdvanceWithQr,
    );
  }

  Widget _buildStaffFloatingActionButton(
    AdminDashboardProvider admin,
    List<_StaffModule> modules,
  ) {
    return ValueListenableBuilder<int>(
      valueListenable: _tabController,
      builder: (context, tab, child) {
        if (modules.isEmpty) return const SizedBox.shrink();
        final selectedTab = tab >= modules.length ? 0 : tab;
        final module = modules[selectedTab];

        if (module.isProductsModule) {
          return FloatingActionButton.extended(
            onPressed: admin.submitting ? null : () => _openProductEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          );
        }

        if (module.isEventsModule) {
          return FloatingActionButton.extended(
            onPressed: admin.submitting ? null : () => _openEventEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Add Event'),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildWebStaffSideNav({
    required String title,
    required List<_StaffModule> modules,
    bool compact = false,
  }) {
    final navWidth = compact ? 88.0 : 270.0;

    return Container(
      width: navWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD5E4DE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A163D33),
            blurRadius: 20,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(10, 14, 10, 10)
                : const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: compact
                ? Tooltip(
                    message: title,
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F4EF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_outlined,
                          color: Color(0xFF17644F),
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F4EF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_outlined,
                          color: Color(0xFF17644F),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _tabController,
              builder: (context, tab, child) {
                final selectedTab = tab >= modules.length ? 0 : tab;
                return ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: modules.length,
                  itemBuilder: (context, index) {
                    final module = modules[index];
                    final selected = index == selectedTab;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: selected
                            ? const Color(0xFFE8F6F1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _tabController.value = index,
                          child: Padding(
                            padding: compact
                                ? const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 11,
                                  )
                                : const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 11,
                                  ),
                            child: compact
                                ? Tooltip(
                                    message: module.label,
                                    child: Center(
                                      child: Icon(
                                        module.icon,
                                        color: selected
                                            ? const Color(0xFF0B7A62)
                                            : const Color(0xFF4D635A),
                                      ),
                                    ),
                                  )
                                : Row(
                                    children: [
                                      Icon(
                                        module.icon,
                                        color: selected
                                            ? const Color(0xFF0B7A62)
                                            : const Color(0xFF4D635A),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          module.label,
                                          style: TextStyle(
                                            color: selected
                                                ? const Color(0xFF0A664F)
                                                : const Color(0xFF2A3D37),
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthenticationProvider>();
    final admin = context.watch<AdminDashboardProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final productCategories = settings.categoriesForProducts(admin.products);
    if (!productCategories.contains(_productCategoryFilter)) {
      _productCategoryFilter = 'All';
    }
    final filteredProducts = _filterProducts(admin.products);

    if (admin.checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!admin.hasDashboardAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff Access Required')),
        body: const Center(child: Text('Staff access required')),
      );
    }

    if (admin.hasSupportAgentAccess &&
        !admin.hasAdminAccess &&
        !admin.hasCashierAccess &&
        !admin.hasRiderAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Support Panel'),
          actions: [
            IconButton(
              onPressed: admin.submitting ? null : _loadSupportRequests,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _logoutAdmin,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: _buildSupportRequestsTab(admin),
      );
    }

    if (admin.hasRiderAccess && !admin.hasAdminAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Delivery Panel'),
          actions: [
            IconButton(
              onPressed: admin.submitting ? null : _loadOrders,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _logoutAdmin,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: _buildOrdersTab(
          admin,
          canConfirmCashPayments: false,
          canUpdateDeliveryStatus: true,
          canExportOrders: false,
        ),
      );
    }

    if (admin.hasCashierAccess && !admin.hasAdminAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cashier Panel'),
          actions: [
            IconButton(
              onPressed: admin.submitting ? null : _loadOrders,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _logoutAdmin,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: _buildOrdersTab(
          admin,
          canConfirmCashPayments: true,
          canUpdateDeliveryStatus: false,
        ),
      );
    }

    final modules = <_StaffModule>[];

    if (admin.hasSuperAdminAccess) {
      modules.add(
        _StaffModule(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          view: SuperAdminDashboardTab(
            orders: admin.orders,
            products: admin.products,
            profiles: admin.profiles,
            loadingOrders: admin.loadingOrders,
            loadingProducts: admin.loadingProducts,
            loadingUsers: admin.loadingUsers,
          ),
        ),
      );
    }

    if (admin.canManageProductsAndEvents) {
      modules.add(
        _StaffModule(
          label: 'Products',
          icon: Icons.inventory_2_outlined,
          isProductsModule: true,
          view: AdminProductsTab(
            loadingProducts: admin.loadingProducts,
            products: filteredProducts,
            submitting: admin.submitting,
            searchController: _searchController,
            categories: productCategories,
            selectedCategory: _productCategoryFilter,
            exportingStock: _exportingStock,
            onSearch: _loadProducts,
            onCategoryChanged: (value) {
              if (value == null) return;
              setState(() => _productCategoryFilter = value);
            },
            onOpenCategoryManager: _openCategoryManager,
            onExportStock: _exportStockExcel,
            onOpenStockEditor: _openStockEditor,
            onManageDiscount: _openDiscountEditor,
            onEditProduct: (product) => _openProductEditor(product: product),
            onDeleteProduct: _deleteProduct,
            subtitleBuilder: _productSubtitle,
          ),
        ),
      );
    }

    if (admin.canViewAccounts) {
      modules.add(
        _StaffModule(
          label: 'Accounts',
          icon: Icons.manage_accounts_outlined,
          view: AdminAccountsTab(
            loadingUsers: admin.loadingUsers,
            profiles: admin.profiles,
            submitting: admin.submitting,
            currentUserId: auth.user?.id ?? '',
            canManageRoles: admin.canManageRoles,
            onSetAccountType: (profile, nextRole) async {
              await _setAccountType(userId: profile.id, accountType: nextRole);
            },
          ),
        ),
      );
    }

    if (admin.canViewOrders) {
      modules.add(
        _StaffModule(
          label: 'Orders',
          icon: Icons.receipt_long_outlined,
          view: _buildOrdersTab(
            admin,
            canConfirmCashPayments: admin.canConfirmCashPayments,
            canUpdateDeliveryStatus: admin.canUpdateDeliveryStatus,
          ),
        ),
      );
    }

    if (admin.canManageProductsAndEvents) {
      modules.add(
        _StaffModule(
          label: 'Events',
          icon: Icons.campaign_outlined,
          isEventsModule: true,
          view: AdminEventsTab(
            loadingEvents: admin.loadingEvents,
            events: admin.events,
            submitting: admin.submitting,
            formatCountdown: _formatCountdown,
            onTapEvent: _showEventItems,
            onEditEvent: (event) => _openEventEditor(event: event),
            onDeleteEvent: _deleteEvent,
          ),
        ),
      );
    }

    if (admin.canViewSupportRequests) {
      modules.add(
        _StaffModule(
          label: 'Support',
          icon: Icons.support_agent,
          view: _buildSupportRequestsTab(admin),
        ),
      );
    }

    if (modules.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff Panel')),
        body: const Center(child: Text('No dashboard modules assigned')),
      );
    }

    if (_tabController.value >= modules.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.value = 0;
      });
    }

    final views = modules.map((module) => module.view).toList();
    final panelTitle = admin.hasSuperAdminAccess
        ? 'Super Admin Panel'
        : 'Staff Panel';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobileLayout = screenWidth < 960;
    final compactSideNav = !isMobileLayout && screenWidth < 1320;

    Future<void> refreshDashboard() async {
      final result = await admin.refreshAll();
      if (!context.mounted || result.isSuccess) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refresh failed: ${result.requireFailure.message}'),
        ),
      );
    }

    List<Widget> headerActions() {
      return <Widget>[
        if (admin.canManageProductsAndEvents)
          IconButton(
            tooltip: 'Payment Methods',
            onPressed: admin.submitting ? null : _openPaymentMethodManager,
            icon: const Icon(Icons.payments_outlined),
          ),
        IconButton(
          onPressed: admin.submitting ? null : refreshDashboard,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Logout',
          onPressed: _logoutAdmin,
          icon: const Icon(Icons.logout),
        ),
      ];
    }

    final dashboardCard = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD8E4DD)),
        ),
        child: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: _tabController,
              builder: (context, tab, child) {
                final selectedTab = tab >= modules.length ? 0 : tab;
                final currentModule = modules[selectedTab];
                if (isMobileLayout) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              currentModule.icon,
                              color: const Color(0xFF0A7B64),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentModule.label,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(spacing: 2, children: headerActions()),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(currentModule.icon, color: const Color(0xFF0A7B64)),
                      const SizedBox(width: 8),
                      Text(
                        currentModule.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      ...headerActions(),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _tabController,
                builder: (context, tab, child) {
                  final selectedTab = tab >= modules.length ? 0 : tab;
                  return IndexedStack(index: selectedTab, children: views);
                },
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      floatingActionButton: _buildStaffFloatingActionButton(admin, modules),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF5F1), Color(0xFFF8F3E9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1640),
              child: Padding(
                padding: EdgeInsets.all(
                  isMobileLayout ? 12 : (compactSideNav ? 12 : 16),
                ),
                child: isMobileLayout
                    ? Column(
                        children: [
                          ValueListenableBuilder<int>(
                            valueListenable: _tabController,
                            builder: (context, tab, child) {
                              final selectedTab = tab >= modules.length
                                  ? 0
                                  : tab;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List<Widget>.generate(
                                    modules.length,
                                    (index) {
                                      final module = modules[index];
                                      final selected = index == selectedTab;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          selected: selected,
                                          avatar: Icon(module.icon, size: 18),
                                          label: Text(module.label),
                                          onSelected: (_) =>
                                              _tabController.value = index,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Expanded(child: dashboardCard),
                        ],
                      )
                    : Row(
                        children: [
                          _buildWebStaffSideNav(
                            title: panelTitle,
                            modules: modules,
                            compact: compactSideNav,
                          ),
                          SizedBox(width: compactSideNav ? 12 : 16),
                          Expanded(child: dashboardCard),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffModule {
  const _StaffModule({
    required this.label,
    required this.icon,
    required this.view,
    this.isProductsModule = false,
    this.isEventsModule = false,
  });

  final String label;
  final IconData icon;
  final Widget view;
  final bool isProductsModule;
  final bool isEventsModule;
}

class _EventThemeOption {
  const _EventThemeOption(this.value, this.label);

  final String value;
  final String label;
}
