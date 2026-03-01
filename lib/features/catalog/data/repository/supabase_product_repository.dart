import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/core/network/local_cache_service.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProductRepository implements ProductRepository {
  final LocalCacheService _cache;
  final SupabaseDataProxy _dataProxy;

  static const Duration _productsCacheAge = Duration(minutes: 10);
  static const Duration _eventCacheAge = Duration(seconds: 30);
  static const Duration _variantStockCacheAge = Duration(minutes: 5);
  static const Duration _bestSellerCacheAge = Duration(minutes: 10);

  SupabaseProductRepository({
    required SupabaseClient db,
    LocalCacheService? cache,
  }) : _cache = cache ?? const LocalCacheService(),
       _dataProxy = SupabaseDataProxy(db: db);

  @override
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  }) async {
    final cacheKey = 'cache.products.${_safe(query)}.${_safe(category)}';
    final freshCache = await _readProductsCache(
      cacheKey,
      maxAge: _productsCacheAge,
    );
    if (freshCache != null) {
      return freshCache;
    }

    final staleCache = await _readProductsCache(cacheKey);
    try {
      final dynamic rows = await _dataProxy.rpc(
        'rpc_list_products',
        params: {'p_query': query, 'p_category': category},
      );
      if (rows is! List) {
        return staleCache ?? const <Product>[];
      }

      await _cache.writeJson(key: cacheKey, payload: rows);
      return _mapRowsToProducts(rows);
    } catch (_) {
      if (staleCache != null) {
        return staleCache;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async {
    const cacheKey = 'cache.featured_event';
    final freshCache = await _readEventCache(cacheKey, maxAge: _eventCacheAge);
    if (freshCache != null) {
      return freshCache;
    }

    final staleCache = await _readEventCache(cacheKey);
    try {
      final activeEvent = await _loadActiveEventFromRpc();
      final featuredEvent = activeEvent ?? await _loadUpcomingEvent();
      if (featuredEvent != null) {
        await _cache.writeJson(key: cacheKey, payload: featuredEvent);
        return featuredEvent;
      }
      await _cache.writeJson(key: cacheKey, payload: <String, dynamic>{});
      return null;
    } catch (_) {
      if (staleCache != null) {
        return staleCache;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, int>> fetchVariantStocks({
    required String productId,
  }) async {
    final cacheKey = 'cache.variant_stock.${_safe(productId)}';
    final freshCache = await _readVariantStockCache(
      cacheKey,
      maxAge: _variantStockCacheAge,
    );
    if (freshCache != null) {
      return freshCache;
    }

    final staleCache = await _readVariantStockCache(cacheKey);
    try {
      final rows = await _dataProxy.rpc(
        'rpc_get_product_variant_stocks',
        params: {'p_product_id': productId},
      );
      if (rows is! List) {
        return staleCache ?? const <String, int>{};
      }

      await _cache.writeJson(key: cacheKey, payload: rows);
      return _mapRowsToVariantStocks(rows);
    } catch (_) {
      if (staleCache != null) {
        return staleCache;
      }
      rethrow;
    }
  }

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async {
    final normalizedDays = days <= 0 ? 30 : days;
    final normalizedLimit = limit <= 0 ? 5 : limit;
    final cacheKey = 'cache.best_sellers.$normalizedDays.$normalizedLimit';
    final freshCache = await _readBestSellerIdsCache(
      cacheKey,
      maxAge: _bestSellerCacheAge,
    );
    if (freshCache != null) {
      return freshCache;
    }

    final staleCache = await _readBestSellerIdsCache(cacheKey);
    try {
      final rows = await _dataProxy.rpc(
        'rpc_list_best_seller_product_ids',
        params: {'p_days': normalizedDays, 'p_limit': normalizedLimit},
      );
      if (rows is! List) {
        return staleCache ?? const <String>{};
      }
      await _cache.writeJson(key: cacheKey, payload: rows);
      return _mapRowsToProductIds(rows);
    } catch (_) {
      if (staleCache != null) {
        return staleCache;
      }
      rethrow;
    }
  }

  Future<List<Product>?> _readProductsCache(
    String key, {
    Duration? maxAge,
  }) async {
    final cached = await _cache.readJson(key: key);
    if (cached == null) return null;
    if (maxAge != null && !cached.isFresh(maxAge)) return null;
    final payload = cached.payload;
    if (payload is! List) return null;
    return _mapRowsToProducts(payload);
  }

  Future<Map<String, dynamic>?> _readEventCache(
    String key, {
    Duration? maxAge,
  }) async {
    final cached = await _cache.readJson(key: key);
    if (cached == null) return null;
    if (maxAge != null && !cached.isFresh(maxAge)) return null;
    final payload = cached.payload;
    if (payload is! Map) return null;
    final event = _normalizeEvent(Map<String, dynamic>.from(payload));
    if (!_isEventActiveOrUpcoming(event)) return null;
    return event;
  }

  Future<Map<String, dynamic>?> _loadActiveEventFromRpc() async {
    final row = await _dataProxy.rpc('rpc_get_active_event');
    if (row is Map<String, dynamic>) {
      final event = _normalizeEvent(row);
      return _isEventActiveOrUpcoming(event) ? event : null;
    }
    if (row is Map) {
      final event = _normalizeEvent(Map<String, dynamic>.from(row));
      return _isEventActiveOrUpcoming(event) ? event : null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadUpcomingEvent() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final dynamic rows = await _dataProxy.select(
      table: 'events',
      columns:
          'id,title,subtitle,badge,theme,is_active,starts_at,expires_at,updated_at',
      filters: <DataProxyFilter>[
        const DataProxyFilter.eq('is_active', true),
        DataProxyFilter.gt('starts_at', nowIso),
        DataProxyFilter.gt('expires_at', nowIso),
      ],
      orders: const <DataProxyOrder>[
        DataProxyOrder('starts_at', ascending: true),
        DataProxyOrder('expires_at', ascending: true),
        DataProxyOrder('updated_at', ascending: false),
      ],
      limit: 1,
    );
    if (rows is! List || rows.isEmpty) return null;

    final first = rows.first;
    if (first is! Map) return null;
    final event = _normalizeEvent(Map<String, dynamic>.from(first));
    return _isEventActiveOrUpcoming(event) ? event : null;
  }

  Map<String, dynamic> _normalizeEvent(Map<String, dynamic> row) {
    final event = Map<String, dynamic>.from(row);
    final now = DateTime.now().toUtc();
    final isEnabled = _asBool(event['is_active']);
    final startsAtRaw = (event['starts_at'] ?? '').toString().trim();
    final expiresAtRaw = (event['expires_at'] ?? '').toString().trim();
    final startsAt = DateTime.tryParse(startsAtRaw)?.toUtc() ?? now;
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    final theme = (event['theme'] ?? 'default').toString().trim().toLowerCase();

    String state = 'expired';
    if (isEnabled && expiresAt != null && expiresAt.isAfter(now)) {
      state = startsAt.isAfter(now) ? 'upcoming' : 'active';
    }

    event['theme'] = theme.isEmpty ? 'default' : theme;
    event['starts_at'] = startsAt.toIso8601String();
    event['expires_at'] = expiresAt?.toIso8601String() ?? expiresAtRaw;
    event['is_active'] = isEnabled;
    event['event_state'] = state;
    return event;
  }

  bool _isEventActiveOrUpcoming(Map<String, dynamic> event) {
    if (event.isEmpty) return false;
    if (!_asBool(event['is_active'])) return false;
    final expiresAtRaw = (event['expires_at'] ?? '').toString().trim();
    final now = DateTime.now().toUtc();
    final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
    if (expiresAt == null || !expiresAt.isAfter(now)) return false;
    return true;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 't' || text == 'yes';
  }

  Future<Map<String, int>?> _readVariantStockCache(
    String key, {
    Duration? maxAge,
  }) async {
    final cached = await _cache.readJson(key: key);
    if (cached == null) return null;
    if (maxAge != null && !cached.isFresh(maxAge)) return null;
    final payload = cached.payload;
    if (payload is! List) return null;
    return _mapRowsToVariantStocks(payload);
  }

  Future<Set<String>?> _readBestSellerIdsCache(
    String key, {
    Duration? maxAge,
  }) async {
    final cached = await _cache.readJson(key: key);
    if (cached == null) return null;
    if (maxAge != null && !cached.isFresh(maxAge)) return null;
    final payload = cached.payload;
    if (payload is! List) return null;
    return _mapRowsToProductIds(payload);
  }

  List<Product> _mapRowsToProducts(List<dynamic> rows) {
    return rows.whereType<Map>().map((Map raw) {
      final data = Map<String, dynamic>.from(raw);
      return Product.fromMap((data['id'] ?? '').toString(), data);
    }).toList();
  }

  Map<String, int> _mapRowsToVariantStocks(List<dynamic> rows) {
    final loaded = <String, int>{};
    for (final raw in rows.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final size = (row['size'] ?? '').toString();
      final color = (row['color'] ?? '').toString();
      final stock = (row['stock'] as num?)?.toInt() ?? 0;
      if (size.isEmpty || color.isEmpty) continue;
      loaded['$size::$color'] = stock;
    }
    return loaded;
  }

  Set<String> _mapRowsToProductIds(List<dynamic> rows) {
    final ids = <String>{};
    for (final raw in rows) {
      if (raw is String) {
        final normalized = raw.trim();
        if (normalized.isNotEmpty) {
          ids.add(normalized);
        }
        continue;
      }
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final productId = (row['product_id'] ?? row['productId'] ?? '')
          .toString()
          .trim();
      if (productId.isEmpty) continue;
      ids.add(productId);
    }
    return ids;
  }

  String _safe(String value) {
    return Uri.encodeComponent(value.trim().toLowerCase());
  }
}
