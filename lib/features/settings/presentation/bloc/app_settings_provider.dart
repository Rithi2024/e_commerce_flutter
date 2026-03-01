import 'dart:async';
import 'dart:convert';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EventProductDiscount {
  final String eventId;
  final String eventTitle;
  final String productId;
  final double discountPercent;
  final DateTime updatedAt;

  const EventProductDiscount({
    required this.eventId,
    required this.eventTitle,
    required this.productId,
    required this.discountPercent,
    required this.updatedAt,
  });

  String get key => AppSettingsProvider._buildDiscountKey(eventId, productId);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event_id': eventId,
      'event_title': eventTitle,
      'product_id': productId,
      'discount_percent': discountPercent,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory EventProductDiscount.fromMap(Map<String, dynamic> data) {
    final percentRaw = (data['discount_percent'] as num?)?.toDouble() ?? 0;
    final percent = percentRaw.clamp(0, 95).toDouble();
    return EventProductDiscount(
      eventId: (data['event_id'] ?? '').toString().trim(),
      eventTitle: (data['event_title'] ?? '').toString().trim(),
      productId: (data['product_id'] ?? '').toString().trim(),
      discountPercent: percent,
      updatedAt:
          DateTime.tryParse((data['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class AppSettingsProvider extends ChangeNotifier {
  static const String _defaultCurrencyCode = 'USD';
  static const String paymentAbaPayWayQr = 'aba_payway_qr';
  static const String paymentCashOnDelivery = 'cash_on_delivery';
  static const Map<String, bool> _defaultPaymentMethods = <String, bool>{
    paymentAbaPayWayQr: true,
    paymentCashOnDelivery: true,
  };

  static const String _prefsCustomCategories = 'app_settings.categories';
  static const String _prefsEventDiscounts = 'app_settings.event_discounts';
  static const String _prefsPaymentMethods = 'app_settings.payment_methods';

  AppSettingsProvider() {
    unawaited(_loadFromPrefs());
  }

  bool _loading = true;
  String _currencyCode = _defaultCurrencyCode;
  String? _activeEventId;
  List<String> _customCategories = <String>[];
  Map<String, EventProductDiscount> _eventDiscountMap =
      <String, EventProductDiscount>{};
  Map<String, bool> _paymentMethods = Map<String, bool>.from(
    _defaultPaymentMethods,
  );

  bool get loading => _loading;
  String get currencyCode => _currencyCode;
  String? get activeEventId => _activeEventId;
  Map<String, bool> get paymentMethods =>
      Map<String, bool>.unmodifiable(_paymentMethods);
  List<String> get customCategories =>
      List<String>.unmodifiable(_customCategories);
  List<EventProductDiscount> get eventDiscounts {
    final list = _eventDiscountMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List<EventProductDiscount>.unmodifiable(list);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Currency is USD-only.
    _currencyCode = _defaultCurrencyCode;

    final categories =
        prefs.getStringList(_prefsCustomCategories) ?? <String>[];
    _customCategories = _sanitizeCategoryList(categories);

    final paymentMethodsRaw = prefs.getString(_prefsPaymentMethods);
    if (paymentMethodsRaw != null && paymentMethodsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(paymentMethodsRaw);
        if (decoded is Map) {
          final loaded = <String, bool>{..._defaultPaymentMethods};
          for (final entry in decoded.entries) {
            final method = _normalizePaymentMethodKey(entry.key.toString());
            if (method == null) continue;
            loaded[method] = entry.value == true;
          }
          _paymentMethods = loaded;
        }
      } catch (_) {}
    }

    final discountsJson = prefs.getString(_prefsEventDiscounts);
    if (discountsJson != null && discountsJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(discountsJson);
        if (decoded is List) {
          final map = <String, EventProductDiscount>{};
          for (final raw in decoded.whereType<Map>()) {
            final entry = EventProductDiscount.fromMap(
              Map<String, dynamic>.from(raw),
            );
            if (entry.eventId.isEmpty || entry.productId.isEmpty) continue;
            map[entry.key] = entry;
          }
          _eventDiscountMap = map;
        }
      } catch (_) {}
    }

    _loading = false;
    notifyListeners();
  }

  bool isPaymentMethodEnabled(String method) {
    final normalized = _normalizePaymentMethodKey(method);
    if (normalized == null) return false;
    return _paymentMethods[normalized] ?? false;
  }

  Future<void> setPaymentMethodEnabled({
    required String method,
    required bool enabled,
  }) async {
    final normalized = _normalizePaymentMethodKey(method);
    if (normalized == null) return;
    if ((_paymentMethods[normalized] ?? false) == enabled) return;

    final next = <String, bool>{..._paymentMethods, normalized: enabled};
    _paymentMethods = next;
    notifyListeners();
    await _persistPaymentMethods();
  }

  void setActiveEventId(String? value) {
    final normalized = value?.trim();
    final next = (normalized == null || normalized.isEmpty) ? null : normalized;
    if (_activeEventId == next) return;
    _activeEventId = next;
    notifyListeners();
  }

  double discountPercentForProduct({
    required String productId,
    String? eventId,
  }) {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) return 0;

    final cleanEventId = (eventId ?? _activeEventId ?? '').trim();
    if (cleanEventId.isEmpty) return 0;

    return _eventDiscountMap[_buildDiscountKey(cleanEventId, cleanProductId)]
            ?.discountPercent ??
        0;
  }

  List<EventProductDiscount> discountsForProduct(String productId) {
    final cleanProductId = productId.trim();
    if (cleanProductId.isEmpty) return const <EventProductDiscount>[];
    return eventDiscounts
        .where((entry) => entry.productId == cleanProductId)
        .toList();
  }

  EventProductDiscount? findEventDiscount({
    required String eventId,
    required String productId,
  }) {
    return _eventDiscountMap[_buildDiscountKey(eventId, productId)];
  }

  Future<void> upsertEventDiscount({
    required String eventId,
    required String eventTitle,
    required String productId,
    required double discountPercent,
  }) async {
    final cleanEventId = eventId.trim();
    final cleanProductId = productId.trim();
    if (cleanEventId.isEmpty || cleanProductId.isEmpty) {
      return;
    }

    final normalizedPercent = discountPercent.clamp(0, 95).toDouble();
    final discount = EventProductDiscount(
      eventId: cleanEventId,
      eventTitle: eventTitle.trim(),
      productId: cleanProductId,
      discountPercent: normalizedPercent,
      updatedAt: DateTime.now(),
    );
    _eventDiscountMap[discount.key] = discount;
    notifyListeners();
    await _persistDiscounts();
  }

  Future<void> removeEventDiscount({
    required String eventId,
    required String productId,
  }) async {
    _eventDiscountMap.remove(_buildDiscountKey(eventId, productId));
    notifyListeners();
    await _persistDiscounts();
  }

  Future<void> addCustomCategory(String category) async {
    final value = _normalizeCategoryName(category);
    if (value == null) return;
    if (_customCategories.any((item) => _equalsIgnoreCase(item, value))) {
      return;
    }

    _customCategories = _sanitizeCategoryList(<String>[
      ..._customCategories,
      value,
    ]);
    notifyListeners();
    await _persistCategories();
  }

  Future<void> removeCustomCategory(String category) async {
    final value = category.trim();
    if (value.isEmpty) return;
    _customCategories = _customCategories
        .where((item) => !_equalsIgnoreCase(item, value))
        .toList();
    notifyListeners();
    await _persistCategories();
  }

  List<String> categoriesForProducts(
    Iterable<Product> products, {
    bool includeAll = true,
  }) {
    final set = <String>{};
    if (includeAll) {
      set.add('All');
    }

    for (final product in products) {
      final category = _normalizeCategoryName(product.category ?? '');
      if (category != null) {
        set.add(category);
      }
    }

    for (final category in _customCategories) {
      final normalized = _normalizeCategoryName(category);
      if (normalized != null) {
        set.add(normalized);
      }
    }

    final list = set.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return list;
  }

  double applyDiscountUsd(double usdAmount, {double discountPercent = 0}) {
    final percent = discountPercent.clamp(0, 95).toDouble();
    final multiplier = 1 - (percent / 100);
    return usdAmount * multiplier;
  }

  double convertUsdToDisplay(double usdAmount, {double discountPercent = 0}) {
    final discountedUsd = applyDiscountUsd(
      usdAmount,
      discountPercent: discountPercent,
    );
    return double.parse(discountedUsd.toStringAsFixed(2));
  }

  String formatUsd(
    double usdAmount, {
    String? productId,
    String? eventId,
    double? overrideDiscountPercent,
  }) {
    final discountPercent =
        overrideDiscountPercent ??
        (productId == null
            ? 0
            : discountPercentForProduct(
                productId: productId,
                eventId: eventId,
              ));
    final converted = convertUsdToDisplay(
      usdAmount,
      discountPercent: discountPercent,
    );
    return '\$${_formatNumber(converted, fractionDigits: 2)}';
  }

  String formatExchangeRate() {
    return 'USD only';
  }

  Future<void> _persistCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsCustomCategories, _customCategories);
  }

  Future<void> _persistDiscounts() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _eventDiscountMap.values
        .map((item) => item.toMap())
        .toList();
    await prefs.setString(_prefsEventDiscounts, jsonEncode(payload));
  }

  Future<void> _persistPaymentMethods() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPaymentMethods, jsonEncode(_paymentMethods));
  }

  List<String> _sanitizeCategoryList(Iterable<String> source) {
    final result = <String>[];
    for (final raw in source) {
      final normalized = _normalizeCategoryName(raw);
      if (normalized == null) continue;
      if (result.any((item) => _equalsIgnoreCase(item, normalized))) continue;
      result.add(normalized);
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String? _normalizeCategoryName(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value;
  }

  String? _normalizePaymentMethodKey(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (!_defaultPaymentMethods.containsKey(value)) return null;
    return value;
  }

  bool _equalsIgnoreCase(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  String _formatNumber(double value, {required int fractionDigits}) {
    final fixed = value.toStringAsFixed(fractionDigits);
    final parts = fixed.split('.');
    final integer = parts.first;
    final sign = integer.startsWith('-') ? '-' : '';
    final digits = integer.replaceFirst('-', '');
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

    if (fractionDigits == 0) {
      return '$sign$grouped';
    }
    final fraction = parts.length > 1 ? parts[1] : '';
    return '$sign$grouped.$fraction';
  }

  static String _buildDiscountKey(String eventId, String productId) {
    return '${eventId.trim()}::${productId.trim()}';
  }
}
