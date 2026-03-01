import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:marketflow/config/backend_proxy_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataProxyFilter {
  final String column;
  final String op;
  final dynamic value;

  const DataProxyFilter(this.column, this.op, this.value);

  const DataProxyFilter.eq(String column, dynamic value)
    : this(column, 'eq', value);

  const DataProxyFilter.gt(String column, dynamic value)
    : this(column, 'gt', value);

  const DataProxyFilter.gte(String column, dynamic value)
    : this(column, 'gte', value);

  const DataProxyFilter.lt(String column, dynamic value)
    : this(column, 'lt', value);

  const DataProxyFilter.lte(String column, dynamic value)
    : this(column, 'lte', value);

  const DataProxyFilter.neq(String column, dynamic value)
    : this(column, 'neq', value);

  Map<String, dynamic> toJson() => {'column': column, 'op': op, 'value': value};
}

class DataProxyOrder {
  final String column;
  final bool ascending;
  final bool? nullsFirst;

  const DataProxyOrder(this.column, {this.ascending = true, this.nullsFirst});

  Map<String, dynamic> toJson() => {
    'column': column,
    'ascending': ascending,
    if (nullsFirst != null) 'nullsFirst': nullsFirst,
  };
}

class SupabaseDataProxy {
  final SupabaseClient _db;

  const SupabaseDataProxy({required SupabaseClient db}) : _db = db;

  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final normalizedName = functionName.trim();
    if (normalizedName.isEmpty) {
      throw const PostgrestException(
        message: 'RPC function name is required',
        code: 'INVALID_RPC_NAME',
      );
    }

    final proxyUri = _proxyUri();
    if (proxyUri == null) {
      return _db.rpc(normalizedName, params: params);
    }

    return _postProxy(proxyUri, <String, dynamic>{
      'kind': 'rpc',
      'rpc': normalizedName,
      'params': params ?? const <String, dynamic>{},
    });
  }

  Future<List<dynamic>> select({
    required String table,
    String columns = '*',
    List<DataProxyFilter> filters = const <DataProxyFilter>[],
    List<DataProxyOrder> orders = const <DataProxyOrder>[],
    int? limit,
  }) async {
    final normalizedTable = table.trim();
    if (normalizedTable.isEmpty) {
      throw const PostgrestException(
        message: 'Table name is required',
        code: 'INVALID_TABLE_NAME',
      );
    }

    final proxyUri = _proxyUri();
    if (proxyUri == null) {
      dynamic query = _db.from(normalizedTable).select(columns);
      query = _applyFilters(query, filters);
      query = _applyOrders(query, orders);
      if (limit != null) {
        query = query.limit(limit);
      }
      final result = await query;
      return _asList(result);
    }

    final result = await _postProxy(proxyUri, <String, dynamic>{
      'kind': 'table',
      'action': 'select',
      'table': normalizedTable,
      'columns': columns,
      'filters': filters.map((item) => item.toJson()).toList(),
      'orders': orders.map((item) => item.toJson()).toList(),
      ...?limit == null ? null : <String, dynamic>{'limit': limit},
    });
    return _asList(result);
  }

  Future<dynamic> update({
    required String table,
    required Map<String, dynamic> values,
    List<DataProxyFilter> filters = const <DataProxyFilter>[],
    bool returning = false,
    String columns = '*',
  }) async {
    final normalizedTable = table.trim();
    if (normalizedTable.isEmpty) {
      throw const PostgrestException(
        message: 'Table name is required',
        code: 'INVALID_TABLE_NAME',
      );
    }

    final proxyUri = _proxyUri();
    if (proxyUri == null) {
      dynamic query = _db.from(normalizedTable).update(values);
      query = _applyFilters(query, filters);
      if (returning) {
        query = query.select(columns);
      }
      return await query;
    }

    return _postProxy(proxyUri, <String, dynamic>{
      'kind': 'table',
      'action': 'update',
      'table': normalizedTable,
      'values': values,
      'filters': filters.map((item) => item.toJson()).toList(),
      'returning': returning,
      'columns': columns,
    });
  }

  Future<dynamic> upsert({
    required String table,
    required dynamic values,
    String? onConflict,
    bool returning = false,
    String columns = '*',
  }) async {
    final normalizedTable = table.trim();
    if (normalizedTable.isEmpty) {
      throw const PostgrestException(
        message: 'Table name is required',
        code: 'INVALID_TABLE_NAME',
      );
    }

    final proxyUri = _proxyUri();
    if (proxyUri == null) {
      dynamic query = _db
          .from(normalizedTable)
          .upsert(values, onConflict: onConflict);
      if (returning) {
        query = query.select(columns);
      }
      return await query;
    }

    return _postProxy(proxyUri, <String, dynamic>{
      'kind': 'table',
      'action': 'upsert',
      'table': normalizedTable,
      'values': values,
      if (onConflict != null && onConflict.trim().isNotEmpty)
        'onConflict': onConflict.trim(),
      'returning': returning,
      'columns': columns,
    });
  }

  dynamic _applyFilters(dynamic query, List<DataProxyFilter> filters) {
    dynamic current = query;
    for (final filter in filters) {
      final op = filter.op.trim().toLowerCase();
      switch (op) {
        case 'eq':
          current = current.eq(filter.column, filter.value);
          break;
        case 'neq':
          current = current.neq(filter.column, filter.value);
          break;
        case 'gt':
          current = current.gt(filter.column, filter.value);
          break;
        case 'gte':
          current = current.gte(filter.column, filter.value);
          break;
        case 'lt':
          current = current.lt(filter.column, filter.value);
          break;
        case 'lte':
          current = current.lte(filter.column, filter.value);
          break;
        default:
          throw PostgrestException(
            message: 'Unsupported filter operator: ${filter.op}',
            code: 'UNSUPPORTED_FILTER_OP',
          );
      }
    }
    return current;
  }

  dynamic _applyOrders(dynamic query, List<DataProxyOrder> orders) {
    dynamic current = query;
    for (final order in orders) {
      if (order.nullsFirst == null) {
        current = current.order(order.column, ascending: order.ascending);
      } else {
        current = current.order(
          order.column,
          ascending: order.ascending,
          nullsFirst: order.nullsFirst,
        );
      }
    }
    return current;
  }

  Future<dynamic> _postProxy(Uri proxyUri, Map<String, dynamic> payload) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = _db.auth.currentSession?.accessToken.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await http
          .post(proxyUri, headers: headers, body: jsonEncode(payload))
          .timeout(Duration(seconds: BackendProxyConfig.timeoutSeconds));
    } on TimeoutException {
      throw const PostgrestException(
        message: 'Backend data proxy timed out',
        code: 'PROXY_TIMEOUT',
      );
    } catch (error) {
      throw PostgrestException(
        message: error.toString(),
        code: 'PROXY_REQUEST_FAILED',
      );
    }

    final decoded = _decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map<String, dynamic>) {
        throw PostgrestException(
          message: (decoded['message'] ?? 'Database request failed').toString(),
          code: decoded['code']?.toString(),
          details: decoded['details'],
          hint: decoded['hint']?.toString(),
        );
      }
      throw PostgrestException(
        message: response.body.trim().isEmpty
            ? 'Database request failed'
            : response.body.trim(),
        code: 'PROXY_HTTP_${response.statusCode}',
      );
    }

    return decoded;
  }

  dynamic _decodeResponse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  List<dynamic> _asList(dynamic raw) {
    if (raw is List<dynamic>) return raw;
    if (raw == null) return const <dynamic>[];
    if (raw is List) return List<dynamic>.from(raw);
    return <dynamic>[raw];
  }

  Uri? _proxyUri() {
    if (!BackendProxyConfig.isDataProxyEnabled) return null;
    final raw = BackendProxyConfig.dataEndpoint.trim();
    if (raw.isEmpty) return null;

    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    if (!parsed.hasScheme && !kIsWeb) return null;
    return parsed;
  }
}
