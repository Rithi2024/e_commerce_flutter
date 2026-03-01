import 'package:marketflow/config/payway_config.dart';
import 'package:marketflow/core/network/local_cache_service.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/core/network/supabase_function_proxy.dart';
import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseOrderRepository implements OrderRepository {
  final SupabaseClient _db;
  final LocalCacheService _cache;
  final SupabaseDataProxy _dataProxy;
  final SupabaseFunctionProxy _functionProxy;

  static const Duration _ordersCacheAge = Duration(minutes: 2);
  static const String _pickupDeliveryType = 'real_meeting';
  static const String _legacyPickupDeliveryType = 'pickup';
  static const String _pickupAddressLabel = 'store pickup';

  SupabaseOrderRepository({
    required SupabaseClient db,
    LocalCacheService? cache,
  }) : _db = db,
       _cache = cache ?? const LocalCacheService(),
       _dataProxy = SupabaseDataProxy(db: db),
       _functionProxy = SupabaseFunctionProxy(db: db);

  @override
  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    required String status,
    required String paymentMethod,
    required String paymentReference,
    required String addressDetails,
    required String promoCode,
  }) async {
    final dynamic createdOrderId = await _dataProxy.rpc(
      'rpc_place_order',
      params: {
        'p_address': address,
        'p_status': status,
        'p_delivery_type': deliveryType,
        'p_address_details': addressDetails,
        'p_payment_method': paymentMethod,
        'p_payment_reference': paymentReference,
        'p_promo_code': promoCode.trim(),
      },
    );

    await _cache.remove(key: _ordersCacheKey);

    final parsedOrderId = parseOrderId(createdOrderId);
    if (parsedOrderId <= 0) {
      throw Exception('Order was not created. Please try again.');
    }
    return parsedOrderId;
  }

  static int parseOrderId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  @override
  Future<List<Map<String, dynamic>>> loadOrders() async {
    final freshCache = await _readOrdersFromCache(maxAge: _ordersCacheAge);
    if (freshCache != null) {
      return freshCache;
    }

    final staleCache = await _readOrdersFromCache();
    try {
      final dynamic rows = await _dataProxy.rpc('rpc_get_orders');
      final orders = _mapRowsToOrders(rows);
      orders.sort(
        (a, b) => _parseOrderCreatedAt(
          b['created_at'],
        ).compareTo(_parseOrderCreatedAt(a['created_at'])),
      );
      await _cache.writeJson(key: _ordersCacheKey, payload: orders);
      return orders;
    } catch (_) {
      if (staleCache != null) {
        return staleCache;
      }
      rethrow;
    }
  }

  @override
  Future<CheckoutPrefill> loadCheckoutPrefill() async {
    final results = await Future.wait<dynamic>([
      _loadProfileForCheckout(),
      loadOrders(),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final orders = (results[1] as List<Map<String, dynamic>>?) ?? const [];
    final unique = <String>{};

    final profileAddress = (profile?['address'] ?? '').toString().trim();
    if (profileAddress.isNotEmpty &&
        profileAddress.toLowerCase() != _pickupAddressLabel) {
      unique.add(profileAddress);
    }

    for (final row in orders) {
      final deliveryType = (row['delivery_type'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (_isPickupDeliveryType(deliveryType)) {
        continue;
      }
      final orderAddress = (row['address'] ?? '').toString().trim();
      if (orderAddress.isNotEmpty &&
          orderAddress.toLowerCase() != _pickupAddressLabel) {
        unique.add(orderAddress);
      }
    }

    final savedAddresses = unique.toList();

    return CheckoutPrefill(
      defaultAddress: savedAddresses.isNotEmpty ? savedAddresses.first : '',
      contactName: (profile?['name'] ?? '').toString().trim(),
      contactPhone: (profile?['phone'] ?? '').toString().trim(),
      savedAddresses: savedAddresses,
    );
  }

  bool _isPickupDeliveryType(String value) {
    return value == _pickupDeliveryType || value == _legacyPickupDeliveryType;
  }

  @override
  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  }) async {
    await _dataProxy.update(
      table: 'profiles',
      values: <String, dynamic>{'address': address},
      filters: <DataProxyFilter>[DataProxyFilter.eq('id', userId)],
    );
    await _cache.remove(key: _ordersCacheKey);
  }

  @override
  Future<Map<String, dynamic>> validatePromoCode({
    required String promoCode,
  }) async {
    final cleanCode = promoCode.trim();
    if (cleanCode.isEmpty) {
      return const {
        'valid': false,
        'message': 'Promo code is required',
        'code': '',
        'discount_percent': 0,
        'discount_amount': 0,
        'subtotal': 0,
        'total': 0,
      };
    }

    final raw = await _dataProxy.rpc(
      'rpc_validate_promo_code',
      params: {'p_code': cleanCode},
    );
    final mapped = _mapProfileResult(raw);
    if (mapped != null) {
      return mapped;
    }
    return _toMap(raw);
  }

  @override
  Future<Map<String, dynamic>> generatePayWayQr({
    required String tranId,
    required double amount,
    required List<CartItem> items,
    required String callbackUrl,
    required String currency,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required int lifetimeMinutes,
    required String paymentOption,
    required String qrImageTemplate,
  }) async {
    final dynamic payload;
    try {
      payload = await _invokePayWayFunction(
        body: {
          'operation': 'generate_qr',
          'tran_id': tranId,
          'amount': amount,
          'currency': currency,
          'payment_option': paymentOption,
          'purchase_type': 'purchase',
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'phone': phone,
          'callback_url': callbackUrl,
          'lifetime': lifetimeMinutes,
          'qr_image_template': qrImageTemplate,
          'items': _buildPayWayItems(items),
        },
      );
    } on FunctionException catch (error) {
      throw Exception(_extractPayWayError(error.details));
    }

    final responseMap = _normalizePayWayResponse(_toMap(payload));
    final status = _extractPayWayStatus(responseMap);
    final statusCode = _normalizePayWayStatusCode(status['code']);
    if (!_isPayWaySuccessStatusCode(statusCode)) {
      final message = _extractPayWayMessage(responseMap);
      throw Exception(
        message.isEmpty ? 'Could not generate PayWay QR' : message,
      );
    }
    return responseMap;
  }

  @override
  Future<Map<String, dynamic>> checkPayWayTransaction({
    required String tranId,
  }) async {
    final dynamic payload;
    try {
      payload = await _invokePayWayFunction(
        body: {'operation': 'check_transaction', 'tran_id': tranId},
      );
    } on FunctionException catch (error) {
      throw Exception(_extractPayWayError(error.details));
    }

    final responseMap = _normalizePayWayResponse(_toMap(payload));
    final status = _extractPayWayStatus(responseMap);
    final statusCode = _normalizePayWayStatusCode(status['code']);
    if (!_isPayWaySuccessStatusCode(statusCode)) {
      final message = _extractPayWayMessage(responseMap);
      throw Exception(
        message.isEmpty ? 'Could not verify PayWay transaction' : message,
      );
    }
    return responseMap;
  }

  @override
  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) async {
    final normalizedTranId = tranId.trim();
    if (normalizedTranId.isEmpty) {
      throw Exception('PayWay tran_id is required');
    }

    final payload = <String, dynamic>{
      'p_tran_id': normalizedTranId,
      'p_order_id': orderId,
      'p_amount': double.parse(amount.toStringAsFixed(2)),
      'p_currency': currency.trim().isEmpty ? 'USD' : currency.toUpperCase(),
      'p_check_response': checkResponse,
    };

    try {
      await _dataProxy.rpc('rpc_upsert_payway_transaction', params: payload);
      return;
    } catch (error) {
      if (!_isRpcMissing(error)) rethrow;
    }

    await _savePayWayTransactionDirect(
      tranId: normalizedTranId,
      orderId: orderId,
      amount: amount,
      currency: currency,
      checkResponse: checkResponse,
    );
  }

  @override
  bool isPayWayApproved(Map<String, dynamic> checkResponse) {
    final data = _extractPayWayData(checkResponse);
    final statusText = (data['payment_status'] ?? '').toString().toUpperCase();
    final statusCode = _toInt(data['payment_status_code'], fallback: -1);
    return statusText == 'APPROVED' ||
        statusText == 'PAID' ||
        statusText == 'PRE-AUTH' ||
        statusText == 'COMPLETED' ||
        statusText == 'SUCCESS' ||
        statusText == 'SETTLED' ||
        statusCode == 0;
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _extractPayWayError(dynamic raw) {
    final data = _toMap(raw);
    final errorCode = (data['code'] ?? '').toString().trim().toUpperCase();
    final errorMessage = (data['message'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (errorCode == 'NOT_FOUND' ||
        errorMessage.contains('REQUESTED FUNCTION WAS NOT FOUND')) {
      return 'PayWay service is not deployed. Deploy the Supabase Edge Function "Payway" (or "payway-qr").';
    }
    final message = _extractPayWayMessage(data);
    return message.isEmpty ? 'PayWay request failed' : message;
  }

  Map<String, dynamic> _extractPayWayData(Map<String, dynamic> raw) {
    final nested = _toMap(raw['data']);
    return nested.isNotEmpty ? nested : raw;
  }

  Map<String, dynamic> _extractPayWayStatus(Map<String, dynamic> raw) {
    final topLevelStatus = _toMap(raw['status']);
    if (topLevelStatus.isNotEmpty) {
      return topLevelStatus;
    }
    final nested = _toMap(raw['data']);
    return _toMap(nested['status']);
  }

  Map<String, dynamic> _normalizePayWayResponse(Map<String, dynamic> raw) {
    final nested = _toMap(raw['data']);
    final merged = <String, dynamic>{...nested, ...raw};

    if (!merged.containsKey('qrImage') && merged['qr_image'] != null) {
      merged['qrImage'] = merged['qr_image'];
    }
    if (!merged.containsKey('qrString') && merged['qr_string'] != null) {
      merged['qrString'] = merged['qr_string'];
    }
    if (!merged.containsKey('tran_id') && merged['tranId'] != null) {
      merged['tran_id'] = merged['tranId'];
    }

    return merged;
  }

  bool _isPayWaySuccessStatusCode(String code) {
    if (code.isEmpty) return true;
    return code == '0' || code == '00';
  }

  Future<void> _savePayWayTransactionDirect({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Not authenticated');
    }

    final data = _extractPayWayData(checkResponse);
    final status = _extractPayWayStatus(checkResponse);
    final paymentStatusCode = _toInt(data['payment_status_code'], fallback: -1);

    final row = <String, dynamic>{
      'user_id': userId,
      'order_id': orderId,
      'provider': 'payway',
      'tran_id': tranId,
      'amount': double.parse(amount.toStringAsFixed(2)),
      'currency': currency.trim().isEmpty ? 'USD' : currency.toUpperCase(),
      'payment_status': (data['payment_status'] ?? '').toString().toUpperCase(),
      'payment_status_code': paymentStatusCode >= 0 ? paymentStatusCode : null,
      'gateway_status_code': (status['code'] ?? '').toString(),
      'gateway_message': (status['message'] ?? '').toString(),
      'raw_response': checkResponse,
    };

    await _dataProxy.upsert(
      table: 'payway_transactions',
      values: row,
      onConflict: 'provider,tran_id',
    );
  }

  Future<Map<String, dynamic>?> _loadProfileForCheckout() async {
    try {
      final profileRaw = await _dataProxy.rpc('rpc_get_profile');
      final mapped = _mapProfileResult(profileRaw);
      if (mapped != null) {
        return mapped;
      }
    } catch (error) {
      if (!_isRpcMissing(error)) rethrow;
    }

    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _dataProxy.select(
      table: 'profiles',
      filters: <DataProxyFilter>[DataProxyFilter.eq('id', userId)],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }

    await _dataProxy.upsert(
      table: 'profiles',
      values: <String, dynamic>{'id': userId},
      onConflict: 'id',
    );
    final createdRows = await _dataProxy.select(
      table: 'profiles',
      filters: <DataProxyFilter>[DataProxyFilter.eq('id', userId)],
      limit: 1,
    );
    if (createdRows.isNotEmpty) {
      return Map<String, dynamic>.from(createdRows.first as Map);
    }
    return null;
  }

  Future<dynamic> _invokePayWayFunction({
    required Map<String, dynamic> body,
  }) async {
    Object? lastNotFoundError;
    for (final functionName in _candidatePayWayFunctionNames()) {
      try {
        final payload = await _functionProxy.invoke(functionName, body: body);
        return payload;
      } on FunctionException catch (error) {
        if (error.status == 404 && _isFunctionNotFoundResponse(error.details)) {
          lastNotFoundError = error;
          continue;
        }
        rethrow;
      }
    }
    if (lastNotFoundError != null) {
      throw lastNotFoundError;
    }
    throw const FunctionException(
      status: 404,
      details: {
        'code': 'NOT_FOUND',
        'message': 'Requested function was not found',
      },
    );
  }

  List<String> _candidatePayWayFunctionNames() {
    final configured = PayWayConfig.functionName.trim();
    final seen = <String>{};
    final names = <String>[configured, 'payway-qr', 'Payway', 'payway'];
    final result = <String>[];
    for (final name in names) {
      final value = name.trim();
      if (value.isEmpty) continue;
      if (seen.contains(value)) continue;
      seen.add(value);
      result.add(value);
    }
    return result;
  }

  bool _isFunctionNotFoundResponse(dynamic raw) {
    final data = _toMap(raw);
    final code = (data['code'] ?? '').toString().trim().toUpperCase();
    final message = (data['message'] ?? '').toString().trim().toUpperCase();
    return code == 'NOT_FOUND' ||
        message.contains('REQUESTED FUNCTION WAS NOT FOUND');
  }

  bool _isRpcMissing(Object error) {
    if (error is! PostgrestException) return false;
    final code = (error.code ?? '').trim().toUpperCase();
    final message = error.message.toUpperCase();
    return code == '404' ||
        code == 'PGRST202' ||
        message.contains('COULD NOT FIND THE FUNCTION') ||
        message.contains('SCHEMA CACHE');
  }

  Map<String, dynamic>? _mapProfileResult(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  String _normalizePayWayStatusCode(dynamic rawCode) {
    final raw = (rawCode ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final parsed = int.tryParse(raw);
    if (parsed == null) return raw.toUpperCase();
    return parsed.toString();
  }

  String _extractPayWayMessage(Map<String, dynamic> raw) {
    final status = _extractPayWayStatus(raw);
    final nestedData = _toMap(raw['data']);
    final message =
        (status['message'] ??
                raw['error'] ??
                raw['message'] ??
                nestedData['error'] ??
                nestedData['message'] ??
                '')
            .toString()
            .trim();
    return message;
  }

  List<Map<String, dynamic>> _buildPayWayItems(List<CartItem> items) {
    final mapped = items
        .map(
          (item) => <String, dynamic>{
            'name': item.name.trim().isEmpty ? 'Item' : item.name.trim(),
            'quantity': item.qty <= 0 ? 1 : item.qty,
            'price': double.parse(item.price.toStringAsFixed(2)),
          },
        )
        .toList();

    if (mapped.length <= 10) {
      return mapped;
    }

    final primary = mapped.take(9).toList();
    final overflow = mapped.skip(9);
    var overflowTotal = 0.0;
    var overflowCount = 0;
    for (final item in overflow) {
      overflowCount += 1;
      final quantity = _toInt(item['quantity'], fallback: 1);
      final price = (item['price'] is num)
          ? (item['price'] as num).toDouble()
          : 0.0;
      overflowTotal += quantity * price;
    }

    primary.add({
      'name': 'Other items ($overflowCount)',
      'quantity': 1,
      'price': double.parse(overflowTotal.toStringAsFixed(2)),
    });

    return primary;
  }

  DateTime _parseOrderCreatedAt(dynamic raw) {
    final String value = (raw ?? '').toString();
    return DateTime.tryParse(value)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String get _ordersCacheKey {
    final userId = _db.auth.currentUser?.id ?? 'guest';
    return 'cache.orders.$userId';
  }

  Future<List<Map<String, dynamic>>?> _readOrdersFromCache({
    Duration? maxAge,
  }) async {
    final cached = await _cache.readJson(key: _ordersCacheKey);
    if (cached == null) return null;
    if (maxAge != null && !cached.isFresh(maxAge)) return null;
    final payload = cached.payload;
    if (payload is! List) return null;
    return payload
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> _mapRowsToOrders(dynamic rows) {
    return (rows is List ? rows : const <dynamic>[])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
