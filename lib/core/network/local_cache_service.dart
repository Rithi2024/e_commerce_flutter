import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalCacheService {
  const LocalCacheService();

  static const String _savedAtKey = 'saved_at_ms';
  static const String _payloadKey = 'payload';

  Future<void> writeJson({required String key, required Object payload}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      _savedAtKey: DateTime.now().millisecondsSinceEpoch,
      _payloadKey: payload,
    };
    await prefs.setString(key, jsonEncode(data));
  }

  Future<CacheReadResult?> readJson({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final map = Map<String, dynamic>.from(decoded);
      final savedAtMs = (map[_savedAtKey] as num?)?.toInt();
      final payload = map[_payloadKey];
      if (savedAtMs == null || payload == null) {
        return null;
      }
      return CacheReadResult(
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> remove({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

class CacheReadResult {
  final DateTime savedAt;
  final dynamic payload;

  const CacheReadResult({required this.savedAt, required this.payload});

  bool isFresh(Duration maxAge) {
    final age = DateTime.now().difference(savedAt);
    return age <= maxAge;
  }
}
