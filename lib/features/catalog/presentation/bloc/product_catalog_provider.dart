import 'dart:async';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum CatalogSortOption {
  newest,
  priceLowToHigh,
  priceHighToLow,
  popular,
  topRated,
  mostReviewed,
}

extension CatalogSortOptionX on CatalogSortOption {
  String get label {
    switch (this) {
      case CatalogSortOption.newest:
        return 'Newest';
      case CatalogSortOption.priceLowToHigh:
        return 'Price low-high';
      case CatalogSortOption.priceHighToLow:
        return 'Price high-low';
      case CatalogSortOption.popular:
        return 'Popular';
      case CatalogSortOption.topRated:
        return 'Top rated';
      case CatalogSortOption.mostReviewed:
        return 'Most reviewed';
    }
  }
}

enum CatalogCollectionFilter {
  recentlyViewed,
  bestSellers,
  newArrivals,
  underTwentyFive,
}

extension CatalogCollectionFilterX on CatalogCollectionFilter {
  String get label {
    switch (this) {
      case CatalogCollectionFilter.recentlyViewed:
        return 'Recently viewed';
      case CatalogCollectionFilter.bestSellers:
        return 'Best sellers';
      case CatalogCollectionFilter.newArrivals:
        return 'New arrivals';
      case CatalogCollectionFilter.underTwentyFive:
        return 'Under \$25';
    }
  }

  String get slug {
    switch (this) {
      case CatalogCollectionFilter.recentlyViewed:
        return 'recently-viewed';
      case CatalogCollectionFilter.bestSellers:
        return 'best-sellers';
      case CatalogCollectionFilter.newArrivals:
        return 'new-arrivals';
      case CatalogCollectionFilter.underTwentyFive:
        return 'under-25';
    }
  }
}

CatalogCollectionFilter? catalogCollectionFilterFromSlug(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  switch (value) {
    case 'recently-viewed':
      return CatalogCollectionFilter.recentlyViewed;
    case 'best-sellers':
      return CatalogCollectionFilter.bestSellers;
    case 'new-arrivals':
      return CatalogCollectionFilter.newArrivals;
    case 'under-25':
      return CatalogCollectionFilter.underTwentyFive;
    default:
      return null;
  }
}

class ProductStockSummary {
  final int totalStock;

  const ProductStockSummary({required this.totalStock});

  bool get isOutOfStock => totalStock <= 0;
  bool get isLowStock => totalStock > 0 && totalStock <= 6;
}

class QuickAddVariantSelection {
  final String size;
  final String color;

  const QuickAddVariantSelection({required this.size, required this.color});
}

class ProductCatalogProvider extends ChangeNotifier {
  static const int _initialVisibleCount = 30;
  static const int _loadMoreCount = 30;
  static const String _prefsRecentlyViewedProductIds =
      'product_catalog.recently_viewed_product_ids';

  final ProductUseCases _useCases;
  final LogUseCases? _logUseCases;

  ProductCatalogProvider({
    required ProductUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  List<Product> _all = <Product>[];
  List<Product> _filtered = <Product>[];
  List<Product> visible = <Product>[];
  bool loading = false;
  String? error;
  List<Product> get all => List<Product>.unmodifiable(_all);
  List<Product> get filtered => List<Product>.unmodifiable(_filtered);
  bool get canLoadMore => visible.length < _filtered.length;
  Set<String> _bestSellerProductIds = <String>{};
  Set<String> get bestSellerProductIds =>
      Set<String>.unmodifiable(_bestSellerProductIds);
  final Map<String, Map<String, int>> _variantStockByProductId =
      <String, Map<String, int>>{};
  final Map<String, ProductStockSummary> _stockSummaryByProductId =
      <String, ProductStockSummary>{};
  final Set<String> _loadingStockProductIds = <String>{};
  final Map<String, ProductRatingSummary> _ratingSummaryByProductId =
      <String, ProductRatingSummary>{};
  final Set<String> _loadingRatingProductIds = <String>{};
  final List<String> _recentlyViewedProductIds = <String>[];
  final Map<String, Product> _recentlyViewedProductSnapshots =
      <String, Product>{};
  CatalogCollectionFilter? _activeCollectionFilter;
  bool _recentlyViewedLoaded = false;

  String query = '';
  String category = 'All';
  CatalogSortOption sortOption = CatalogSortOption.newest;
  final Set<String> _selectedCategories = <String>{};
  double? _minPriceFilter;
  double? _maxPriceFilter;
  double? _minimumRatingFilter;
  bool _writtenReviewsOnly = false;
  bool inStockOnly = false;

  Set<String> get selectedCategories =>
      Set<String>.unmodifiable(_selectedCategories);
  CatalogCollectionFilter? get activeCollectionFilter =>
      _activeCollectionFilter;
  String? get activeCollectionLabel => _activeCollectionFilter?.label;
  bool get hasCollectionFilter => _activeCollectionFilter != null;
  bool get hasCategoryFilter => _selectedCategories.isNotEmpty;
  bool get hasQueryFilter => query.trim().isNotEmpty;
  bool get hasSortFilter => sortOption != CatalogSortOption.newest;
  bool get hasPriceFilter => _minPriceFilter != null || _maxPriceFilter != null;
  bool get hasRatingFilter => _minimumRatingFilter != null;
  bool get hasWrittenReviewFilter => _writtenReviewsOnly;
  bool get hasStockFilter => inStockOnly;
  bool get hasAdvancedFilters =>
      hasCategoryFilter ||
      hasPriceFilter ||
      hasRatingFilter ||
      hasWrittenReviewFilter ||
      hasStockFilter;
  bool get hasActiveFilters =>
      hasCollectionFilter ||
      hasCategoryFilter ||
      hasQueryFilter ||
      hasSortFilter ||
      hasPriceFilter ||
      hasRatingFilter ||
      hasWrittenReviewFilter ||
      hasStockFilter;
  int get advancedFilterCount =>
      (hasCategoryFilter ? 1 : 0) +
      (hasPriceFilter ? 1 : 0) +
      (hasRatingFilter ? 1 : 0) +
      (hasWrittenReviewFilter ? 1 : 0) +
      (hasStockFilter ? 1 : 0);
  int get activeFilterCount =>
      (hasCollectionFilter ? 1 : 0) +
      (hasCategoryFilter ? 1 : 0) +
      (hasQueryFilter ? 1 : 0) +
      (hasSortFilter ? 1 : 0) +
      (hasPriceFilter ? 1 : 0) +
      (hasRatingFilter ? 1 : 0) +
      (hasWrittenReviewFilter ? 1 : 0) +
      (hasStockFilter ? 1 : 0);

  double get minCatalogPrice {
    if (_all.isEmpty) return 0;
    return _all.map((product) => product.price).reduce((a, b) => a < b ? a : b);
  }

  double get maxCatalogPrice {
    if (_all.isEmpty) return 0;
    return _all.map((product) => product.price).reduce((a, b) => a > b ? a : b);
  }

  double get selectedMinPrice => _minPriceFilter ?? minCatalogPrice;
  double get selectedMaxPrice => _maxPriceFilter ?? maxCatalogPrice;
  double? get minimumRatingFilter => _minimumRatingFilter;
  bool get writtenReviewsOnly => _writtenReviewsOnly;
  List<Product> get recentlyViewedProducts {
    final products = <Product>[];
    for (final productId in _recentlyViewedProductIds) {
      Product? product;
      for (final candidate in _all) {
        if (candidate.id == productId) {
          product = candidate;
          break;
        }
      }
      product ??= _recentlyViewedProductSnapshots[productId];
      if (product != null) {
        products.add(product);
      }
    }
    return List<Product>.unmodifiable(products);
  }

  bool isBestSeller(String productId) {
    return _bestSellerProductIds.contains(productId.trim());
  }

  bool isNewArrival(Product product) {
    final createdAt = product.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt).inDays <= 14;
  }

  ProductStockSummary? stockSummaryFor(String productId) {
    return _stockSummaryByProductId[productId.trim()];
  }

  bool isStockSummaryLoading(String productId) {
    return _loadingStockProductIds.contains(productId.trim());
  }

  ProductRatingSummary? ratingSummaryFor(String productId) {
    return _ratingSummaryByProductId[productId.trim()];
  }

  bool isRatingSummaryLoading(String productId) {
    return _loadingRatingProductIds.contains(productId.trim());
  }

  void recordRecentlyViewed(Product product) {
    final productId = product.id.trim();
    if (productId.isEmpty) {
      return;
    }

    _recentlyViewedLoaded = true;
    _recentlyViewedProductIds.remove(productId);
    _recentlyViewedProductIds.insert(0, productId);
    _recentlyViewedProductSnapshots[productId] = product;
    if (_recentlyViewedProductIds.length > 10) {
      final removed = _recentlyViewedProductIds.removeLast();
      _recentlyViewedProductSnapshots.remove(removed);
    }
    unawaited(_persistRecentlyViewed());
    notifyListeners();
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
      await _loadRecentlyViewedIfNeeded();
      _all = await _useCases.fetchProducts(query: '', category: 'All');
      _syncRecentlyViewedWithCatalog();
      try {
        _bestSellerProductIds = await _useCases.fetchBestSellerProductIds(
          days: 30,
          limit: 5,
        );
      } catch (_) {
        _bestSellerProductIds = <String>{};
      }
      if (_needsRatingSummaries) {
        await _ensureRatingSummariesFor(_all.map((product) => product.id));
      }
      applyFilters();
      unawaited(_primeVisibleCardMetadata());
      _logInfo(
        action: 'fetch_products',
        metadata: {
          'count': _all.length,
          'bestSellers': _bestSellerProductIds.length,
        },
      );
    } on PostgrestException catch (e) {
      _all = <Product>[];
      _filtered = <Product>[];
      visible = <Product>[];
      _bestSellerProductIds = <String>{};
      _variantStockByProductId.clear();
      _stockSummaryByProductId.clear();
      _loadingStockProductIds.clear();
      _ratingSummaryByProductId.clear();
      _loadingRatingProductIds.clear();
      error = e.message.isEmpty ? 'Failed to load products' : e.message;
      _logError(action: 'fetch_products', message: error ?? 'Unknown error');
    } catch (_) {
      _all = <Product>[];
      _filtered = <Product>[];
      visible = <Product>[];
      _bestSellerProductIds = <String>{};
      _variantStockByProductId.clear();
      _stockSummaryByProductId.clear();
      _loadingStockProductIds.clear();
      _ratingSummaryByProductId.clear();
      _loadingRatingProductIds.clear();
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
    final normalizedId = productId.trim();
    final cached = _variantStockByProductId[normalizedId];
    if (cached != null) {
      return cached;
    }
    try {
      final stocks = await _useCases.fetchVariantStocks(
        productId: normalizedId,
      );
      _variantStockByProductId[normalizedId] = stocks;
      _stockSummaryByProductId[normalizedId] = _buildStockSummary(stocks);
      _logInfo(
        action: 'fetch_variant_stocks',
        metadata: {'productId': normalizedId, 'variants': stocks.length},
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

  Future<void> setSortOption(CatalogSortOption next) async {
    if (sortOption == next) {
      return;
    }
    sortOption = next;
    notifyListeners();
    if (next == CatalogSortOption.topRated ||
        next == CatalogSortOption.mostReviewed) {
      await _ensureRatingSummariesFor(_all.map((product) => product.id));
    }
    applyFilters();
    notifyListeners();
  }

  Future<void> applyAdvancedFilters({
    required Iterable<String> categories,
    required double minPrice,
    required double maxPrice,
    required bool stockOnly,
    double? minimumRating,
    bool writtenReviewsOnly = false,
  }) async {
    final normalizedCategories = categories
        .map((raw) => raw.trim())
        .where((value) => value.isNotEmpty && value.toLowerCase() != 'all')
        .toSet();

    _selectedCategories
      ..clear()
      ..addAll(normalizedCategories);
    category = _selectedCategories.isEmpty ? 'All' : _selectedCategories.first;
    _minPriceFilter = _normalizeMinPrice(minPrice);
    _maxPriceFilter = _normalizeMaxPrice(maxPrice);
    _minimumRatingFilter = _normalizeMinimumRating(minimumRating);
    _writtenReviewsOnly = writtenReviewsOnly;
    inStockOnly = stockOnly;

    if (inStockOnly) {
      await _ensureStockSummariesFor(_all.map((product) => product.id));
    }
    if (_needsRatingSummaries) {
      await _ensureRatingSummariesFor(_all.map((product) => product.id));
    }

    applyFilters();
    notifyListeners();
  }

  void showCollection(CatalogCollectionFilter filter) {
    _activeCollectionFilter = filter;
    query = '';
    _selectedCategories.clear();
    category = 'All';
    _minPriceFilter = null;
    _maxPriceFilter = null;
    _minimumRatingFilter = null;
    _writtenReviewsOnly = false;
    inStockOnly = false;
    switch (filter) {
      case CatalogCollectionFilter.recentlyViewed:
        sortOption = CatalogSortOption.newest;
        break;
      case CatalogCollectionFilter.bestSellers:
        sortOption = CatalogSortOption.popular;
        break;
      case CatalogCollectionFilter.newArrivals:
        sortOption = CatalogSortOption.newest;
        break;
      case CatalogCollectionFilter.underTwentyFive:
        sortOption = CatalogSortOption.priceLowToHigh;
        break;
    }
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

  void clearAllFilters() {
    final hadChanges = hasActiveFilters;
    _activeCollectionFilter = null;
    query = '';
    _selectedCategories.clear();
    category = 'All';
    sortOption = CatalogSortOption.newest;
    _minPriceFilter = null;
    _maxPriceFilter = null;
    _minimumRatingFilter = null;
    _writtenReviewsOnly = false;
    inStockOnly = false;
    if (!hadChanges) {
      return;
    }
    applyFilters();
    notifyListeners();
  }

  void loadMoreVisible() {
    if (loading || !canLoadMore) {
      return;
    }
    final nextCount = visible.length + _loadMoreCount;
    final targetCount = nextCount > _filtered.length
        ? _filtered.length
        : nextCount;
    visible = _filtered.take(targetCount).toList();
    unawaited(_primeVisibleCardMetadata());
    notifyListeners();
  }

  void applyFilters() {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedCategories = _selectedCategories
        .map((value) => value.toLowerCase())
        .toSet();
    _filtered = _all.where((p) {
      final productName = p.name.toLowerCase();
      final productCategory = (p.category ?? '').toLowerCase();
      final qOk =
          normalizedQuery.isEmpty ||
          productName.contains(normalizedQuery) ||
          productCategory.contains(normalizedQuery);
      final cOk =
          normalizedCategories.isEmpty ||
          normalizedCategories.contains(productCategory);
      final priceOk =
          (_minPriceFilter == null || p.price >= _minPriceFilter!) &&
          (_maxPriceFilter == null || p.price <= _maxPriceFilter!);
      final ratingOk =
          _minimumRatingFilter == null ||
          ((_ratingSummaryByProductId[p.id]?.hasRatings ?? false) &&
              (_ratingSummaryByProductId[p.id]?.averageRating ?? 0) >=
                  _minimumRatingFilter!);
      final reviewOk =
          !_writtenReviewsOnly ||
          (_ratingSummaryByProductId[p.id]?.hasWrittenReviews ?? false);
      final stockOk =
          !inStockOnly ||
          ((_stockSummaryByProductId[p.id]?.isOutOfStock ?? false) == false);
      final collectionOk = _matchesActiveCollection(p);
      return qOk &&
          cOk &&
          priceOk &&
          ratingOk &&
          reviewOk &&
          stockOk &&
          collectionOk;
    }).toList();
    _sortFilteredProducts();
    final initialCount = _filtered.length > _initialVisibleCount
        ? _initialVisibleCount
        : _filtered.length;
    visible = _filtered.take(initialCount).toList();
    unawaited(_primeVisibleCardMetadata());
  }

  Future<void> refresh() {
    return fetchProducts();
  }

  Future<QuickAddVariantSelection?> resolveQuickAddVariant(
    String productId,
  ) async {
    final normalizedId = productId.trim();
    final stocks = await fetchVariantStocks(normalizedId);
    if (stocks.isEmpty) {
      return const QuickAddVariantSelection(size: 'M', color: 'Black');
    }

    final available =
        stocks.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key)
            .toList()
          ..sort();

    if (available.isEmpty) {
      return null;
    }

    final parts = available.first.split('::');
    if (parts.length != 2) {
      return const QuickAddVariantSelection(size: 'M', color: 'Black');
    }
    return QuickAddVariantSelection(size: parts[0], color: parts[1]);
  }

  void _sortFilteredProducts() {
    if (_activeCollectionFilter == CatalogCollectionFilter.recentlyViewed &&
        sortOption == CatalogSortOption.newest) {
      final order = <String, int>{
        for (var i = 0; i < _recentlyViewedProductIds.length; i++)
          _recentlyViewedProductIds[i]: i,
      };
      _filtered.sort((a, b) {
        final aIndex = order[a.id] ?? 1 << 20;
        final bIndex = order[b.id] ?? 1 << 20;
        return aIndex.compareTo(bIndex);
      });
      return;
    }

    switch (sortOption) {
      case CatalogSortOption.newest:
        _filtered.sort((a, b) {
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
      case CatalogSortOption.priceLowToHigh:
        _filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
      case CatalogSortOption.priceHighToLow:
        _filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
      case CatalogSortOption.popular:
        _filtered.sort((a, b) {
          final aPopular = isBestSeller(a.id) ? 1 : 0;
          final bPopular = isBestSeller(b.id) ? 1 : 0;
          if (aPopular != bPopular) {
            return bPopular.compareTo(aPopular);
          }
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
      case CatalogSortOption.topRated:
        _filtered.sort((a, b) {
          final aSummary =
              _ratingSummaryByProductId[a.id] ??
              const ProductRatingSummary(ratingCount: 0, averageRating: 0);
          final bSummary =
              _ratingSummaryByProductId[b.id] ??
              const ProductRatingSummary(ratingCount: 0, averageRating: 0);
          final aHasRatings = aSummary.hasRatings ? 1 : 0;
          final bHasRatings = bSummary.hasRatings ? 1 : 0;
          if (aHasRatings != bHasRatings) {
            return bHasRatings.compareTo(aHasRatings);
          }
          final ratingCompare = bSummary.averageRating.compareTo(
            aSummary.averageRating,
          );
          if (ratingCompare != 0) {
            return ratingCompare;
          }
          final countCompare = bSummary.ratingCount.compareTo(
            aSummary.ratingCount,
          );
          if (countCompare != 0) {
            return countCompare;
          }
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
      case CatalogSortOption.mostReviewed:
        _filtered.sort((a, b) {
          final aSummary =
              _ratingSummaryByProductId[a.id] ??
              const ProductRatingSummary(ratingCount: 0, averageRating: 0);
          final bSummary =
              _ratingSummaryByProductId[b.id] ??
              const ProductRatingSummary(ratingCount: 0, averageRating: 0);
          final aHasReviews = aSummary.hasWrittenReviews ? 1 : 0;
          final bHasReviews = bSummary.hasWrittenReviews ? 1 : 0;
          if (aHasReviews != bHasReviews) {
            return bHasReviews.compareTo(aHasReviews);
          }
          final reviewCompare = bSummary.reviewCount.compareTo(
            aSummary.reviewCount,
          );
          if (reviewCompare != 0) {
            return reviewCompare;
          }
          final ratingCountCompare = bSummary.ratingCount.compareTo(
            aSummary.ratingCount,
          );
          if (ratingCountCompare != 0) {
            return ratingCountCompare;
          }
          final ratingCompare = bSummary.averageRating.compareTo(
            aSummary.averageRating,
          );
          if (ratingCompare != 0) {
            return ratingCompare;
          }
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
    }
  }

  ProductStockSummary _buildStockSummary(Map<String, int> stocks) {
    final total = stocks.values.fold<int>(0, (sum, value) => sum + value);
    return ProductStockSummary(totalStock: total);
  }

  Future<void> _primeVisibleStockSummaries() async {
    await _ensureStockSummariesFor(visible.map((product) => product.id));
  }

  Future<void> _ensureStockSummariesFor(Iterable<String> productIds) async {
    final ids = productIds
        .map((productId) => productId.trim())
        .where((productId) => productId.isNotEmpty)
        .toSet()
        .toList();
    final missing = ids
        .where(
          (productId) =>
              !_stockSummaryByProductId.containsKey(productId) &&
              !_loadingStockProductIds.contains(productId),
        )
        .toList();

    if (missing.isEmpty) {
      return;
    }

    _loadingStockProductIds.addAll(missing);
    notifyListeners();
    try {
      final results = await Future.wait(
        missing.map((productId) async {
          try {
            final stocks = await _useCases.fetchVariantStocks(
              productId: productId,
            );
            return MapEntry<String, Map<String, int>>(productId, stocks);
          } catch (_) {
            return null;
          }
        }),
      );

      var changed = false;
      for (final result in results) {
        if (result == null) continue;
        _variantStockByProductId[result.key] = result.value;
        _stockSummaryByProductId[result.key] = _buildStockSummary(result.value);
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } finally {
      _loadingStockProductIds.removeAll(missing);
      notifyListeners();
    }
  }

  Future<void> _primeVisibleRatingSummaries() async {
    await _ensureRatingSummariesFor(visible.map((product) => product.id));
  }

  Future<void> _ensureRatingSummariesFor(Iterable<String> productIds) async {
    final ids = productIds
        .map((productId) => productId.trim())
        .where((productId) => productId.isNotEmpty)
        .toSet()
        .toList();
    final missing = ids
        .where(
          (productId) =>
              !_ratingSummaryByProductId.containsKey(productId) &&
              !_loadingRatingProductIds.contains(productId),
        )
        .toList();

    if (missing.isEmpty) {
      return;
    }

    _loadingRatingProductIds.addAll(missing);
    notifyListeners();

    var changed = false;
    try {
      final ratings = await _useCases.fetchProductRatingSummaries(
        productIds: missing,
      );
      for (final productId in missing) {
        _ratingSummaryByProductId[productId] =
            ratings[productId] ??
            const ProductRatingSummary(ratingCount: 0, averageRating: 0);
        changed = true;
      }
    } finally {
      _loadingRatingProductIds.removeAll(missing);
    }

    if (changed && sortOption == CatalogSortOption.topRated) {
      applyFilters();
    }
    notifyListeners();
  }

  Future<void> _primeVisibleCardMetadata() async {
    await Future.wait([
      _primeVisibleStockSummaries(),
      _primeVisibleRatingSummaries(),
    ]);
  }

  bool _matchesActiveCollection(Product product) {
    switch (_activeCollectionFilter) {
      case null:
        return true;
      case CatalogCollectionFilter.recentlyViewed:
        return _recentlyViewedProductIds.contains(product.id);
      case CatalogCollectionFilter.bestSellers:
        return isBestSeller(product.id);
      case CatalogCollectionFilter.newArrivals:
        return isNewArrival(product);
      case CatalogCollectionFilter.underTwentyFive:
        return product.price <= 25;
    }
  }

  Future<void> _loadRecentlyViewedIfNeeded() async {
    if (_recentlyViewedLoaded) {
      return;
    }
    _recentlyViewedLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = _normalizeRecentlyViewedIds(
        prefs.getStringList(_prefsRecentlyViewedProductIds) ?? const <String>[],
      );
      final merged = _normalizeRecentlyViewedIds(<String>[
        ..._recentlyViewedProductIds,
        ...stored,
      ]);
      _recentlyViewedProductIds
        ..clear()
        ..addAll(merged);
    } catch (_) {}
  }

  Future<void> _persistRecentlyViewed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsRecentlyViewedProductIds,
        _recentlyViewedProductIds,
      );
    } catch (_) {}
  }

  void _syncRecentlyViewedWithCatalog() {
    if (_recentlyViewedProductIds.isEmpty) {
      return;
    }

    final productsById = <String, Product>{
      for (final product in _all) product.id.trim(): product,
    };
    var changed = false;
    for (final productId in _recentlyViewedProductIds.toList()) {
      final product = productsById[productId];
      if (product != null) {
        _recentlyViewedProductSnapshots[productId] = product;
        continue;
      }
      if (!_recentlyViewedProductSnapshots.containsKey(productId)) {
        _recentlyViewedProductIds.remove(productId);
        changed = true;
      }
    }
    if (changed) {
      unawaited(_persistRecentlyViewed());
    }
  }

  List<String> _normalizeRecentlyViewedIds(Iterable<String> source) {
    final result = <String>[];
    for (final raw in source) {
      final productId = raw.trim();
      if (productId.isEmpty || result.contains(productId)) {
        continue;
      }
      result.add(productId);
      if (result.length >= 10) {
        break;
      }
    }
    return result;
  }

  double? _normalizeMinPrice(double value) {
    final catalogMin = minCatalogPrice;
    if (_all.isEmpty || value <= catalogMin + 0.01) {
      return null;
    }
    return value;
  }

  double? _normalizeMaxPrice(double value) {
    final catalogMax = maxCatalogPrice;
    if (_all.isEmpty || value >= catalogMax - 0.01) {
      return null;
    }
    return value;
  }

  double? _normalizeMinimumRating(double? value) {
    final next = value ?? 0;
    if (next <= 0) {
      return null;
    }
    return next.clamp(0, 5).toDouble();
  }

  bool get _needsRatingSummaries =>
      hasRatingFilter ||
      hasWrittenReviewFilter ||
      sortOption == CatalogSortOption.topRated ||
      sortOption == CatalogSortOption.mostReviewed;

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
