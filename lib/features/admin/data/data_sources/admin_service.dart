import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AdminDataSource {
  Future<Map<String, dynamic>?> getProfile();

  Future<void> signOut();

  Future<List<dynamic>> listProducts({required String query});

  Future<List<dynamic>> listProfiles();

  Future<void> setAccountType({
    required String userId,
    required String accountType,
  });

  Future<List<dynamic>> listOrders();

  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  });

  Future<void> confirmCashPayment({required int orderId});

  Future<List<dynamic>> listSupportRequests();

  Future<List<dynamic>> listEvents();

  Future<void> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  });

  Future<void> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  });

  Future<void> deleteEvent({required String eventId});

  Future<List<dynamic>> getProductVariantStocks({required String productId});

  Future<void> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  });

  Future<void> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  });

  Future<void> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  });

  Future<void> deleteProduct({required String productId});
}

class AdminService implements AdminDataSource {
  final SupabaseClient _db;
  final SupabaseDataProxy _dataProxy;

  AdminService({required SupabaseClient db})
    : _db = db,
      _dataProxy = SupabaseDataProxy(db: db);

  @override
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final profile = await _dataProxy.rpc('rpc_get_profile');
      final mapped = _mapFromRpcResult(profile);
      if (mapped != null) {
        return mapped;
      }
    } catch (error) {
      if (!_isRpcMissing(error)) rethrow;
    }

    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      return null;
    }

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

  bool _isRpcMissing(Object error) {
    if (error is! PostgrestException) return false;
    final code = (error.code ?? '').trim().toUpperCase();
    final message = error.message.toUpperCase();
    return code == '404' ||
        code == 'PGRST202' ||
        message.contains('COULD NOT FIND THE FUNCTION') ||
        message.contains('SCHEMA CACHE');
  }

  Map<String, dynamic>? _mapFromRpcResult(dynamic profile) {
    if (profile is Map<String, dynamic>) return profile;
    if (profile is Map) return Map<String, dynamic>.from(profile);
    if (profile is List && profile.isNotEmpty) {
      final first = profile.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<List<dynamic>> listProducts({required String query}) async {
    final rows = await _dataProxy.rpc(
      'rpc_list_products',
      params: {'p_query': query, 'p_category': 'All'},
    );
    return rows as List<dynamic>;
  }

  @override
  Future<List<dynamic>> listProfiles() async {
    final rows = await _dataProxy.rpc('rpc_admin_list_profiles');
    return rows as List<dynamic>;
  }

  @override
  Future<void> setAccountType({
    required String userId,
    required String accountType,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_set_account_type',
      params: {'p_user_id': userId, 'p_account_type': accountType},
    );
  }

  @override
  Future<List<dynamic>> listOrders() async {
    final rows = await _dataProxy.rpc('rpc_admin_list_orders');
    return rows as List<dynamic>;
  }

  @override
  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) {
    return _dataProxy.rpc(
      'rpc_staff_update_order_status',
      params: {'p_order_id': orderId, 'p_status': status},
    );
  }

  @override
  Future<void> confirmCashPayment({required int orderId}) {
    return _dataProxy.rpc(
      'rpc_admin_confirm_cash_payment',
      params: {'p_order_id': orderId},
    );
  }

  @override
  Future<List<dynamic>> listSupportRequests() async {
    final rows = await _dataProxy.rpc('rpc_staff_list_support_requests');
    return rows as List<dynamic>;
  }

  @override
  Future<List<dynamic>> listEvents() async {
    final rows = await _dataProxy.rpc('rpc_admin_list_events');
    return rows as List<dynamic>;
  }

  @override
  Future<void> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_create_event',
      params: {
        'p_title': title,
        'p_subtitle': subtitle,
        'p_badge': badge,
        'p_theme': theme,
        'p_is_active': isActive,
        'p_starts_at': startsAtIsoUtc,
        'p_expires_at': expiresAtIsoUtc,
      },
    );
  }

  @override
  Future<void> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_update_event',
      params: {
        'p_event_id': eventId,
        'p_title': title,
        'p_subtitle': subtitle,
        'p_badge': badge,
        'p_theme': theme,
        'p_is_active': isActive,
        'p_starts_at': startsAtIsoUtc,
        'p_expires_at': expiresAtIsoUtc,
      },
    );
  }

  @override
  Future<void> deleteEvent({required String eventId}) {
    return _dataProxy.rpc(
      'rpc_admin_delete_event',
      params: {'p_event_id': eventId},
    );
  }

  @override
  Future<List<dynamic>> getProductVariantStocks({
    required String productId,
  }) async {
    final rows = await _dataProxy.rpc(
      'rpc_admin_get_product_variant_stocks',
      params: {'p_product_id': productId},
    );
    return rows as List<dynamic>;
  }

  @override
  Future<void> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_set_product_variant_stocks',
      params: {'p_product_id': productId, 'p_items': items},
    );
  }

  @override
  Future<void> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_create_product',
      params: {
        'p_name': name,
        'p_price': price,
        'p_image_url': imageUrl,
        'p_description': description,
        'p_category': category,
      },
    );
  }

  @override
  Future<void> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) {
    return _dataProxy.rpc(
      'rpc_admin_update_product',
      params: {
        'p_product_id': productId,
        'p_name': name,
        'p_price': price,
        'p_image_url': imageUrl,
        'p_description': description,
        'p_category': category,
      },
    );
  }

  @override
  Future<void> deleteProduct({required String productId}) {
    return _dataProxy.rpc(
      'rpc_admin_delete_product',
      params: {'p_product_id': productId},
    );
  }
}
