import 'dart:async';

import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/core/error/failure.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/admin/domain/usecases/admin_use_cases.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:flutter/material.dart';

class AdminDashboardProvider extends ChangeNotifier {
  final AdminUseCases _useCases;
  final LogUseCases? _logUseCases;

  AdminDashboardProvider({
    required AdminUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  bool checkingAccess = true;
  bool hasAdminAccess = false;
  bool hasSuperAdminAccess = false;
  bool hasCashierAccess = false;
  bool hasSupportAgentAccess = false;
  bool hasRiderAccess = false;
  bool loadingProducts = true;
  bool loadingUsers = true;
  bool loadingOrders = true;
  bool loadingEvents = true;
  bool loadingSupportRequests = true;
  bool submitting = false;
  String productQuery = '';
  String? error;

  List<Product> _products = <Product>[];
  List<AdminProfile> _profiles = <AdminProfile>[];
  List<AdminOrder> _orders = <AdminOrder>[];
  List<AdminEvent> _events = <AdminEvent>[];
  List<AdminSupportRequest> _supportRequests = <AdminSupportRequest>[];

  List<Product> get products => List<Product>.unmodifiable(_products);
  List<AdminProfile> get profiles => List<AdminProfile>.unmodifiable(_profiles);
  List<AdminOrder> get orders => List<AdminOrder>.unmodifiable(_orders);
  List<AdminEvent> get events => List<AdminEvent>.unmodifiable(_events);
  List<AdminSupportRequest> get supportRequests =>
      List<AdminSupportRequest>.unmodifiable(_supportRequests);
  bool get hasDashboardAccess =>
      hasAdminAccess ||
      hasCashierAccess ||
      hasSupportAgentAccess ||
      hasRiderAccess;
  bool get canManageRoles => hasSuperAdminAccess;
  bool get canViewAccounts => hasAdminAccess;
  bool get canManageProductsAndEvents => hasAdminAccess;
  bool get canViewOrders =>
      hasAdminAccess || hasCashierAccess || hasRiderAccess;
  bool get canConfirmCashPayments => hasAdminAccess || hasCashierAccess;
  bool get canUpdateDeliveryStatus => hasAdminAccess || hasRiderAccess;
  bool get canViewSupportRequests => hasSupportAgentAccess;

  Future<Result<void>> initialize() async {
    checkingAccess = true;
    hasAdminAccess = false;
    hasSuperAdminAccess = false;
    hasCashierAccess = false;
    hasSupportAgentAccess = false;
    hasRiderAccess = false;
    error = null;
    notifyListeners();

    final profileResult = await _useCases.getProfile();
    if (profileResult.isFailure) {
      final failure = profileResult.requireFailure;
      checkingAccess = false;
      hasAdminAccess = false;
      error = failure.message;
      notifyListeners();

      if (failure is UnauthorizedFailure || failure.code == 'P0001') {
        await _useCases.signOut();
      }

      _logFailure(
        action: 'initialize',
        failure: failure,
        metadata: {'stage': 'profile'},
      );
      return FailureResult<void>(failure);
    }

    final profile = profileResult.requireValue;
    final role = AccountRole.fromRaw(profile?.accountType);
    hasSuperAdminAccess = role.isSuperAdmin;
    hasAdminAccess = role.isAdmin;
    hasCashierAccess = role.isCashier;
    hasSupportAgentAccess = role.isSupportAgent;
    hasRiderAccess = role.isRider;
    if (!hasDashboardAccess) {
      final failure = PermissionDeniedFailure('Staff access required');
      checkingAccess = false;
      error = failure.message;
      notifyListeners();
      _logWarning(
        action: 'initialize',
        message: failure.message,
        metadata: {
          'accountType': profile?.accountType ?? AccountRole.customerValue,
        },
      );
      return FailureResult<void>(failure);
    }

    final tasks = <Future<Result<void>>>[];
    if (canViewOrders) {
      tasks.add(loadOrders(notify: false));
    }
    if (canManageProductsAndEvents) {
      tasks.add(loadProducts(query: productQuery, notify: false));
      tasks.add(loadEvents(notify: false));
    }
    if (canViewAccounts) {
      tasks.add(loadProfiles(notify: false));
    }
    if (canViewSupportRequests) {
      tasks.add(loadSupportRequests(notify: false));
    }
    final results = await Future.wait<Result<void>>(tasks);

    checkingAccess = false;
    notifyListeners();

    for (final result in results) {
      if (result.isFailure) {
        return FailureResult<void>(result.requireFailure);
      }
    }

    _logInfo(action: 'initialize', message: 'Staff dashboard initialized');
    return const Success<void>(null);
  }

  Future<Result<void>> refreshAll() async {
    final tasks = <Future<Result<void>>>[];
    if (canViewOrders) {
      tasks.add(loadOrders(notify: false));
    }
    if (canManageProductsAndEvents) {
      tasks.add(loadProducts(query: productQuery, notify: false));
      tasks.add(loadEvents(notify: false));
    }
    if (canViewAccounts) {
      tasks.add(loadProfiles(notify: false));
    }
    if (canViewSupportRequests) {
      tasks.add(loadSupportRequests(notify: false));
    }
    final results = await Future.wait<Result<void>>(tasks);
    notifyListeners();

    for (final result in results) {
      if (result.isFailure) {
        return FailureResult<void>(result.requireFailure);
      }
    }
    return const Success<void>(null);
  }

  Future<Result<void>> loadProducts({String? query, bool notify = true}) async {
    if (!canManageProductsAndEvents) {
      loadingProducts = false;
      _products = <Product>[];
      if (notify) notifyListeners();
      return const Success<void>(null);
    }
    if (query != null) {
      productQuery = query.trim();
    }

    loadingProducts = true;
    if (notify) notifyListeners();

    final result = await _useCases.listProducts(query: productQuery);
    loadingProducts = false;

    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      if (notify) notifyListeners();
      _logFailure(
        action: 'load_products',
        failure: failure,
        metadata: {'query': productQuery},
      );
      return FailureResult<void>(failure);
    }

    _products = result.requireValue;
    error = null;
    if (notify) notifyListeners();
    _logInfo(
      action: 'load_products',
      metadata: {'query': productQuery, 'count': _products.length},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> loadProfiles({bool notify = true}) async {
    if (!hasAdminAccess) {
      loadingUsers = false;
      _profiles = <AdminProfile>[];
      if (notify) notifyListeners();
      return const Success<void>(null);
    }
    loadingUsers = true;
    if (notify) notifyListeners();

    final result = await _useCases.listProfiles();
    loadingUsers = false;

    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      if (notify) notifyListeners();
      _logFailure(action: 'load_profiles', failure: failure);
      return FailureResult<void>(failure);
    }

    _profiles = result.requireValue;
    error = null;
    if (notify) notifyListeners();
    _logInfo(action: 'load_profiles', metadata: {'count': _profiles.length});
    return const Success<void>(null);
  }

  Future<Result<void>> loadOrders({bool notify = true}) async {
    if (!canViewOrders) {
      loadingOrders = false;
      _orders = <AdminOrder>[];
      if (notify) notifyListeners();
      return const Success<void>(null);
    }
    loadingOrders = true;
    if (notify) notifyListeners();

    final result = await _useCases.listOrders();
    loadingOrders = false;

    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      if (notify) notifyListeners();
      _logFailure(action: 'load_orders', failure: failure);
      return FailureResult<void>(failure);
    }

    _orders = result.requireValue;
    error = null;
    if (notify) notifyListeners();
    _logInfo(action: 'load_orders', metadata: {'count': _orders.length});
    return const Success<void>(null);
  }

  Future<Result<void>> confirmCashPayment({required int orderId}) async {
    if (!canConfirmCashPayments) {
      return FailureResult<void>(
        PermissionDeniedFailure('Cash confirmation access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final result = await _useCases.confirmCashPayment(orderId: orderId);
    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(
        action: 'confirm_cash_payment',
        failure: failure,
        metadata: {'orderId': orderId},
      );
      return FailureResult<void>(failure);
    }

    final loadResult = await loadOrders(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(action: 'confirm_cash_payment', metadata: {'orderId': orderId});
    return const Success<void>(null);
  }

  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    if (!canUpdateDeliveryStatus) {
      return FailureResult<void>(
        PermissionDeniedFailure('Order status update access required'),
      );
    }
    final nextStatus = status.trim().toLowerCase();
    String normalizeDeliveryStatus(String raw) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'pending' || normalized == 'paid') {
        return 'order_received';
      }
      if (normalized == 'shipped') return 'out_for_delivery';
      return normalized;
    }

    final normalizedNextStatus = normalizeDeliveryStatus(nextStatus);
    if (hasRiderAccess &&
        !hasAdminAccess &&
        normalizedNextStatus != 'out_for_delivery' &&
        normalizedNextStatus != 'delivered') {
      return FailureResult<void>(
        PermissionDeniedFailure(
          'Rider can update only out for delivery or delivered statuses',
        ),
      );
    }
    if (hasRiderAccess && !hasAdminAccess) {
      String currentStatus = '';
      for (final order in _orders) {
        if (order.id == orderId) {
          currentStatus = normalizeDeliveryStatus(order.status);
          break;
        }
      }
      if (normalizedNextStatus == 'out_for_delivery' &&
          currentStatus.isNotEmpty &&
          currentStatus != 'order_packed' &&
          currentStatus != 'order_received') {
        return FailureResult<void>(
          PermissionDeniedFailure(
            'Rider can mark out for delivery only after order is received or packed',
          ),
        );
      }
      if (normalizedNextStatus == 'delivered' &&
          currentStatus.isNotEmpty &&
          currentStatus != 'out_for_delivery' &&
          currentStatus != 'ready_for_pickup') {
        return FailureResult<void>(
          PermissionDeniedFailure(
            'Rider can mark delivered only after out for delivery or ready for pickup',
          ),
        );
      }
    }
    submitting = true;
    notifyListeners();

    final result = await _useCases.updateOrderStatus(
      orderId: orderId,
      status: normalizedNextStatus,
    );
    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(
        action: 'update_order_status',
        failure: failure,
        metadata: {'orderId': orderId, 'status': normalizedNextStatus},
      );
      return FailureResult<void>(failure);
    }

    final loadResult = await loadOrders(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(
      action: 'update_order_status',
      metadata: {'orderId': orderId, 'status': normalizedNextStatus},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> loadEvents({bool notify = true}) async {
    if (!canManageProductsAndEvents) {
      loadingEvents = false;
      _events = <AdminEvent>[];
      if (notify) notifyListeners();
      return const Success<void>(null);
    }
    loadingEvents = true;
    if (notify) notifyListeners();

    final result = await _useCases.listEvents();
    loadingEvents = false;

    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      if (notify) notifyListeners();
      _logFailure(action: 'load_events', failure: failure);
      return FailureResult<void>(failure);
    }

    _events = result.requireValue;
    error = null;
    if (notify) notifyListeners();
    _logInfo(action: 'load_events', metadata: {'count': _events.length});
    return const Success<void>(null);
  }

  Future<Result<void>> loadSupportRequests({bool notify = true}) async {
    if (!canViewSupportRequests) {
      loadingSupportRequests = false;
      _supportRequests = <AdminSupportRequest>[];
      if (notify) notifyListeners();
      return const Success<void>(null);
    }
    loadingSupportRequests = true;
    if (notify) notifyListeners();

    final result = await _useCases.listSupportRequests();
    loadingSupportRequests = false;

    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      if (notify) notifyListeners();
      _logFailure(action: 'load_support_requests', failure: failure);
      return FailureResult<void>(failure);
    }

    _supportRequests = result.requireValue;
    error = null;
    if (notify) notifyListeners();
    _logInfo(
      action: 'load_support_requests',
      metadata: {'count': _supportRequests.length},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> saveEvent({
    String? eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<void>(
        PermissionDeniedFailure('Admin event access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final Result<void> result;
    if (eventId == null) {
      result = await _useCases.createEvent(
        title: title,
        subtitle: subtitle,
        badge: badge,
        theme: theme,
        isActive: isActive,
        startsAtIsoUtc: startsAtIsoUtc,
        expiresAtIsoUtc: expiresAtIsoUtc,
      );
    } else {
      result = await _useCases.updateEvent(
        eventId: eventId,
        title: title,
        subtitle: subtitle,
        badge: badge,
        theme: theme,
        isActive: isActive,
        startsAtIsoUtc: startsAtIsoUtc,
        expiresAtIsoUtc: expiresAtIsoUtc,
      );
    }

    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(
        action: eventId == null ? 'create_event' : 'update_event',
        failure: failure,
      );
      return FailureResult<void>(failure);
    }

    final loadResult = await loadEvents(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(
      action: eventId == null ? 'create_event' : 'update_event',
      metadata: {'eventId': eventId ?? 'new'},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> removeEvent({required String eventId}) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<void>(
        PermissionDeniedFailure('Admin event access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final result = await _useCases.deleteEvent(eventId: eventId);
    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(action: 'delete_event', failure: failure);
      return FailureResult<void>(failure);
    }

    final loadResult = await loadEvents(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(action: 'delete_event', metadata: {'eventId': eventId});
    return const Success<void>(null);
  }

  Future<Result<Map<String, int>>> getProductVariantStocks({
    required String productId,
  }) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<Map<String, int>>(
        PermissionDeniedFailure('Product stock access required'),
      );
    }
    final result = await _useCases.getProductVariantStocks(
      productId: productId,
    );
    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(action: 'get_variant_stocks', failure: failure);
    } else {
      _logInfo(
        action: 'get_variant_stocks',
        metadata: {'productId': productId},
      );
    }
    return result;
  }

  Future<Result<void>> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<void>(
        PermissionDeniedFailure('Product stock update access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final result = await _useCases.setProductVariantStocks(
      productId: productId,
      items: items,
    );

    submitting = false;
    if (result.isFailure) {
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(action: 'set_variant_stocks', failure: failure);
      return FailureResult<void>(failure);
    }

    error = null;
    notifyListeners();
    _logInfo(
      action: 'set_variant_stocks',
      metadata: {'productId': productId, 'variants': items.length},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> saveProduct({
    String? productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<void>(
        PermissionDeniedFailure('Product management access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final Result<void> result;
    if (productId == null) {
      result = await _useCases.createProduct(
        name: name,
        price: price,
        imageUrl: imageUrl,
        description: description,
        category: category,
      );
    } else {
      result = await _useCases.updateProduct(
        productId: productId,
        name: name,
        price: price,
        imageUrl: imageUrl,
        description: description,
        category: category,
      );
    }

    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(
        action: productId == null ? 'create_product' : 'update_product',
        failure: failure,
      );
      return FailureResult<void>(failure);
    }

    final loadResult = await loadProducts(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(
      action: productId == null ? 'create_product' : 'update_product',
      metadata: {'productId': productId ?? 'new', 'name': name},
    );
    return const Success<void>(null);
  }

  Future<Result<void>> removeProduct({required String productId}) async {
    if (!canManageProductsAndEvents) {
      return FailureResult<void>(
        PermissionDeniedFailure('Product management access required'),
      );
    }
    submitting = true;
    notifyListeners();

    final result = await _useCases.deleteProduct(productId: productId);
    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(action: 'delete_product', failure: failure);
      return FailureResult<void>(failure);
    }

    final loadResult = await loadProducts(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(action: 'delete_product', metadata: {'productId': productId});
    return const Success<void>(null);
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  }) async {
    if (!canManageRoles) {
      return FailureResult<void>(
        PermissionDeniedFailure('Super admin access required'),
      );
    }

    submitting = true;
    notifyListeners();

    final result = await _useCases.setAccountType(
      userId: userId,
      accountType: accountType,
    );
    if (result.isFailure) {
      submitting = false;
      final failure = result.requireFailure;
      error = failure.message;
      notifyListeners();
      _logFailure(
        action: 'set_account_type',
        failure: failure,
        metadata: {'userId': userId, 'accountType': accountType},
      );
      return FailureResult<void>(failure);
    }

    final loadResult = await loadProfiles(notify: false);
    submitting = false;
    notifyListeners();

    if (loadResult.isFailure) {
      return FailureResult<void>(loadResult.requireFailure);
    }

    _logInfo(
      action: 'set_account_type',
      metadata: {'userId': userId, 'accountType': accountType},
    );
    return const Success<void>(null);
  }

  void _logInfo({
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.info(
        feature: 'admin_dashboard',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logWarning({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.warning(
        feature: 'admin_dashboard',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logFailure({
    required String action,
    required Failure failure,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    final payload = <String, dynamic>{
      ...metadata,
      if (failure.code != null) 'code': failure.code,
    };
    unawaited(
      logger.error(
        feature: 'admin_dashboard',
        action: action,
        message: failure.message,
        metadata: payload,
      ),
    );
  }
}
