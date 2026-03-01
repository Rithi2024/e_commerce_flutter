import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:marketflow/config/backend_proxy_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseFunctionProxy {
  final SupabaseClient _db;

  const SupabaseFunctionProxy({required SupabaseClient db}) : _db = db;

  Future<dynamic> invoke(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final normalizedFunction = functionName.trim();
    if (normalizedFunction.isEmpty) {
      throw const FunctionException(
        status: 400,
        details: {
          'code': 'INVALID_FUNCTION_NAME',
          'message': 'Function name is required',
        },
      );
    }

    final proxyUri = _proxyUri();
    if (proxyUri == null) {
      final response = await _db.functions.invoke(
        normalizedFunction,
        body: body,
      );
      return response.data;
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = _db.auth.currentSession?.accessToken.trim() ?? '';
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final payload = jsonEncode(<String, dynamic>{
      'function': normalizedFunction,
      'body': body,
    });

    http.Response response;
    try {
      response = await http
          .post(proxyUri, headers: headers, body: payload)
          .timeout(Duration(seconds: BackendProxyConfig.timeoutSeconds));
    } on TimeoutException {
      throw const FunctionException(
        status: 504,
        details: {
          'code': 'PROXY_TIMEOUT',
          'message': 'Backend proxy timed out',
        },
      );
    } catch (error) {
      throw FunctionException(
        status: 502,
        details: {'code': 'PROXY_REQUEST_FAILED', 'message': error.toString()},
      );
    }

    final decoded = _tryDecodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorDetails = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{
              'code': response.statusCode == 404
                  ? 'NOT_FOUND'
                  : 'PROXY_HTTP_${response.statusCode}',
              'message': response.body.trim().isEmpty
                  ? 'Proxy request failed'
                  : response.body.trim(),
            };
      throw FunctionException(
        status: response.statusCode,
        details: errorDetails,
      );
    }

    if (decoded is Map && decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  Uri? _proxyUri() {
    if (!BackendProxyConfig.isEnabled) return null;
    final raw = BackendProxyConfig.endpoint.trim();
    if (raw.isEmpty) return null;

    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;

    // Relative proxy endpoints only work in web builds.
    if (!parsed.hasScheme && !kIsWeb) return null;
    return parsed;
  }

  dynamic _tryDecodeJson(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const <String, dynamic>{};
    try {
      return jsonDecode(value);
    } catch (_) {
      return <String, dynamic>{'message': value};
    }
  }
}
