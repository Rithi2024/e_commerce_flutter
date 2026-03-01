import 'dart:async';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductCatalogProvider extends ChangeNotifier {
  final ProductUseCases _useCases;
  final LogUseCases? _logUseCases;

  ProductCatalogProvider({
    required ProductUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  List<Product> _all = <Product>[];
  List<Product> visible = <Product>[];
  bool loading = false;
  String? error;
  List<Product> get all => List<Product>.unmodifiable(_all);
  Set<String> _bestSellerProductIds = <String>{};
  Set<String> get bestSellerProductIds =>
      Set<String>.unmodifiable(_bestSellerProductIds);

  String query = '';
  String category = 'All';
  final Set<String> _selectedCategories = <String>{};

  Set<String> get selectedCategories =>
      Set<String>.unmodifiable(_selectedCategories);
  bool get hasCategoryFilter => _selectedCategories.isNotEmpty;

  bool isBestSeller(String productId) {
    return _bestSellerProductIds.contains(productId.trim());
  }

  bool isCategorySelected(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
      return _selectedCategories.isEmpty;
    }
    return _selectedCategories.contains(normalized);
  }

  Future<void> fetchProducts() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      _all = await _useCases.fetchProducts(query: '', category: 'All');
      try {
        _bestSellerProductIds = await _useCases.fetchBestSellerProductIds(
          days: 30,
          limit: 5,
        );
      } catch (_) {
        _bestSellerProductIds = <String>{};
      }
      applyFilters();
      _logInfo(
        action: 'fetch_products',
        metadata: {
          'count': _all.length,
          'bestSellers': _bestSellerProductIds.length,
        },
      );
    } on PostgrestException catch (e) {
      _all = <Product>[];
      visible = <Product>[];
      _bestSellerProductIds = <String>{};
      error = e.message.isEmpty ? 'Failed to load products' : e.message;
      _logError(action: 'fetch_products', message: error ?? 'Unknown error');
    } catch (_) {
      _all = <Product>[];
      visible = <Product>[];
      _bestSellerProductIds = <String>{};
      error = 'Failed to load products';
      _logError(action: 'fetch_products', message: error ?? 'Unknown error');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> fetchActiveEvent() async {
    try {
      final event = await _useCases.fetchActiveEvent();
      _logInfo(
        action: 'fetch_active_event',
        metadata: {'hasEvent': event != null},
      );
      return event;
    } catch (error) {
      _logError(action: 'fetch_active_event', message: error.toString());
      rethrow;
    }
  }

  Future<Map<String, int>> fetchVariantStocks(String productId) async {
    try {
      final stocks = await _useCases.fetchVariantStocks(productId: productId);
      _logInfo(
        action: 'fetch_variant_stocks',
        metadata: {'productId': productId, 'variants': stocks.length},
      );
      return stocks;
    } catch (error) {
      _logError(action: 'fetch_variant_stocks', message: error.toString());
      rethrow;
    }
  }

  void setQuery(String q) {
    if (query == q) {
      return;
    }
    query = q;
    applyFilters();
    notifyListeners();
  }

  void setCategory(String c) {
    final normalized = c.trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
      clearCategoryFilters();
      return;
    }
    if (category == normalized &&
        _selectedCategories.length == 1 &&
        _selectedCategories.contains(normalized)) {
      return;
    }

    category = normalized;
    _selectedCategories
      ..clear()
      ..add(normalized);
    applyFilters();
    notifyListeners();
  }

  void toggleCategory(String c) {
    final normalized = c.trim();
    if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
      clearCategoryFilters();
      return;
    }

    if (_selectedCategories.contains(normalized)) {
      _selectedCategories.remove(normalized);
    } else {
      _selectedCategories.add(normalized);
    }
    category = _selectedCategories.isEmpty ? 'All' : _selectedCategories.first;
    applyFilters();
    notifyListeners();
  }

  void setCategoryFilters(Iterable<String> categories) {
    final next = categories
        .map((raw) => raw.trim())
        .where((value) => value.isNotEmpty && value.toLowerCase() != 'all')
        .toSet();
    final same =
        next.length == _selectedCategories.length &&
        _selectedCategories.containsAll(next);
    if (same) {
      return;
    }
    _selectedCategories
      ..clear()
      ..addAll(next);
    category = _selectedCategories.isEmpty ? 'All' : _selectedCategories.first;
    applyFilters();
    notifyListeners();
  }

  void clearCategoryFilters() {
    if (_selectedCategories.isEmpty && category == 'All') {
      return;
    }
    _selectedCategories.clear();
    category = 'All';
    applyFilters();
    notifyListeners();
  }

  void applyFilters() {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedCategories = _selectedCategories
        .map((value) => value.toLowerCase())
        .toSet();
    visible = _all.where((p) {
      final productName = p.name.toLowerCase();
      final productCategory = (p.category ?? '').toLowerCase();
      final qOk =
          normalizedQuery.isEmpty ||
          productName.contains(normalizedQuery) ||
          productCategory.contains(normalizedQuery);
      final cOk =
          normalizedCategories.isEmpty ||
          normalizedCategories.contains(productCategory);
      return qOk && cOk;
    }).toList();
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
        feature: 'product_catalog',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logError({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.error(
        feature: 'product_catalog',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }
}
