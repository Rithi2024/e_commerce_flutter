import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/core/widgets/favorite_icon_button.dart';
import 'package:marketflow/config/routes/app_routes.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/cart/presentation/pages/shopping_cart_screen.dart';
import 'package:marketflow/features/catalog/presentation/widgets/event_deal_chip.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';
import 'package:marketflow/core/widgets/app_brand_logo.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';

class ProductCatalogScreen extends StatefulWidget {
  final CatalogCollectionFilter? initialCollectionFilter;

  const ProductCatalogScreen({super.key, this.initialCollectionFilter});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  static const double _loadMoreTriggerOffset = 420;
  static const double _compactHeaderCollapseOffset = 24;

  Map<String, dynamic>? _activeEvent;
  Duration? _remainingEvent;
  Timer? _eventTicker;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _addingProductIds = <String>{};
  final Set<String> _wishlistBusyProductIds = <String>{};
  bool _compactHeaderCollapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleCatalogScroll);
    final productProvider = context.read<ProductCatalogProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.wait([productProvider.fetchProducts(), _loadActiveEvent()]);
      final initialCollection = widget.initialCollectionFilter;
      if (!mounted || initialCollection == null) return;
      if (initialCollection == CatalogCollectionFilter.eventDeals) {
        final products = _activeEventDealProducts(
          settings: context.read<AppSettingsProvider>(),
          catalog: productProvider,
        );
        productProvider.showEventDeals(products.map((product) => product.id));
      } else {
        productProvider.showCollection(initialCollection);
      }
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleCatalogScroll)
      ..dispose();
    _eventTicker?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCatalog() async {
    final productProvider = context.read<ProductCatalogProvider>();
    await Future.wait([productProvider.refresh(), _loadActiveEvent()]);
  }

  void _showCatalogMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _catalogActionError(Object error, String fallbackMessage) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = text.toLowerCase();
    if (lower.contains('not authenticated')) {
      return 'Please sign in again and try that action.';
    }
    if (lower.contains('out of stock')) {
      return 'This product is currently out of stock.';
    }
    if (text.isNotEmpty && text.length <= 120) {
      return text;
    }
    return fallbackMessage;
  }

  Product _discountedProductForCart(
    AppSettingsProvider settings,
    Product product,
  ) {
    final discountPercent = settings.discountPercentForProduct(
      productId: product.id,
    );
    final discountedUsd = settings.applyDiscountUsd(
      product.price,
      discountPercent: discountPercent,
    );
    if (discountedUsd == product.price) {
      return product;
    }
    return Product(
      id: product.id,
      name: product.name,
      price: double.parse(discountedUsd.toStringAsFixed(2)),
      imageUrl: product.imageUrl,
      description: product.description,
      category: product.category,
      createdAt: product.createdAt,
    );
  }

  Future<void> _handleQuickAdd(Product product) async {
    final productId = product.id.trim();
    if (_addingProductIds.contains(productId)) {
      return;
    }

    setState(() => _addingProductIds.add(productId));
    try {
      final catalog = context.read<ProductCatalogProvider>();
      final settings = context.read<AppSettingsProvider>();
      final cart = context.read<ShoppingCartProvider>();
      final variant = await catalog.resolveQuickAddVariant(productId);
      if (!mounted) return;
      if (variant == null) {
        _showCatalogMessage('This product is currently out of stock.');
        return;
      }

      final cartProduct = _discountedProductForCart(settings, product);
      await cart.addToCart(
        product: cartProduct,
        size: variant.size,
        color: variant.color,
        quantity: 1,
      );
      if (!mounted) return;
      _showCatalogMessage('${product.name} added to cart.');
    } catch (error) {
      _showCatalogMessage(
        _catalogActionError(error, 'Could not add item to cart.'),
      );
    } finally {
      if (mounted) {
        setState(() => _addingProductIds.remove(productId));
      }
    }
  }

  Future<void> _handleWishlistToggle(Product product) async {
    final productId = product.id.trim();
    if (_wishlistBusyProductIds.contains(productId)) {
      return;
    }

    setState(() => _wishlistBusyProductIds.add(productId));
    final wishlist = context.read<UserWishlistProvider>();
    final wasFavorite = wishlist.isFav(productId);
    try {
      await wishlist.toggle(productId);
      _showCatalogMessage(
        wasFavorite
            ? '${product.name} removed from favorites.'
            : '${product.name} saved to favorites.',
      );
    } catch (error) {
      _showCatalogMessage(
        _catalogActionError(error, 'Could not update favorites.'),
      );
    } finally {
      if (mounted) {
        setState(() => _wishlistBusyProductIds.remove(productId));
      }
    }
  }

  void _clearSearchAndFilters() {
    _searchController.clear();
    context.read<ProductCatalogProvider>().clearAllFilters();
    _syncCatalogRoute();
  }

  void _applySearchQuery(String value, {bool persist = true}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_searchController.text != normalized) {
      _searchController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }

    final catalog = context.read<ProductCatalogProvider>();
    if (persist) {
      catalog.useSearchTerm(normalized);
    } else {
      catalog.setQuery(normalized);
    }
  }

  List<Product> _activeEventDealProducts({
    required AppSettingsProvider settings,
    required ProductCatalogProvider catalog,
  }) {
    final activeEventId = (_activeEvent?['id'] ?? '').toString().trim();
    if (activeEventId.isEmpty) {
      return const <Product>[];
    }

    final discountsByProductId = _activeEventDealDiscountPercents(
      settings: settings,
    );
    if (discountsByProductId.isEmpty) {
      return const <Product>[];
    }

    final products =
        catalog.all
            .where((product) => discountsByProductId.containsKey(product.id))
            .toList()
          ..sort((a, b) {
            final aDiscount = discountsByProductId[a.id] ?? 0;
            final bDiscount = discountsByProductId[b.id] ?? 0;
            final discountCompare = bDiscount.compareTo(aDiscount);
            if (discountCompare != 0) {
              return discountCompare;
            }
            final aSavings = a.price * (aDiscount / 100);
            final bSavings = b.price * (bDiscount / 100);
            final savingsCompare = bSavings.compareTo(aSavings);
            if (savingsCompare != 0) {
              return savingsCompare;
            }
            final aPopular = catalog.isBestSeller(a.id) ? 1 : 0;
            final bPopular = catalog.isBestSeller(b.id) ? 1 : 0;
            if (aPopular != bPopular) {
              return bPopular.compareTo(aPopular);
            }
            final aCreated =
                a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bCreated =
                b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bCreated.compareTo(aCreated);
          });
    return products;
  }

  Map<String, double> _activeEventDealDiscountPercents({
    required AppSettingsProvider settings,
  }) {
    final activeEventId = (_activeEvent?['id'] ?? '').toString().trim();
    if (activeEventId.isEmpty) {
      return const <String, double>{};
    }

    return <String, double>{
      for (final entry in settings.eventDiscounts)
        if (entry.eventId == activeEventId && entry.discountPercent > 0)
          entry.productId.trim(): entry.discountPercent,
    };
  }

  double _activeEventMaxDiscountPercent({
    required AppSettingsProvider settings,
  }) {
    final activeEventId = (_activeEvent?['id'] ?? '').toString().trim();
    if (activeEventId.isEmpty) {
      return 0;
    }

    var maxDiscount = 0.0;
    for (final discount in settings.eventDiscounts) {
      if (discount.eventId != activeEventId) continue;
      if (discount.discountPercent > maxDiscount) {
        maxDiscount = discount.discountPercent;
      }
    }
    return maxDiscount;
  }

  void _syncActiveEventDealsCollection() {
    if (!mounted) return;
    final settings = context.read<AppSettingsProvider>();
    final catalog = context.read<ProductCatalogProvider>();
    final products = _activeEventDealProducts(
      settings: settings,
      catalog: catalog,
    );
    catalog.setEventDealProductIds(
      products.map((product) => product.id),
      discountPercents: _activeEventDealDiscountPercents(settings: settings),
    );
  }

  Future<void> _showCollectionView(CatalogCollectionFilter filter) async {
    _searchController.clear();
    if (filter == CatalogCollectionFilter.eventDeals) {
      final settings = context.read<AppSettingsProvider>();
      final products = _activeEventDealProducts(
        settings: settings,
        catalog: context.read<ProductCatalogProvider>(),
      );
      context.read<ProductCatalogProvider>().showEventDeals(
        products.map((product) => product.id),
        discountPercents: _activeEventDealDiscountPercents(settings: settings),
      );
    } else {
      context.read<ProductCatalogProvider>().showCollection(filter);
    }
    _syncCatalogRoute(filter);
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _browseAllProducts() async {
    _searchController.clear();
    context.read<ProductCatalogProvider>().clearAllFilters();
    _syncCatalogRoute();
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openProductDetails(Product product) async {
    if (!mounted) return;
    final collectionSlug = context
        .read<ProductCatalogProvider>()
        .activeCollectionFilter
        ?.slug;
    await Navigator.of(context).pushNamed(
      AppRoutes.catalogRoute(
        collection: collectionSlug,
        productKey: product.slug,
      ),
    );
  }

  void _syncCatalogRoute([CatalogCollectionFilter? filter]) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == null) {
      return;
    }
    final routeName = AppRoutes.catalogRoute(collection: filter?.slug);
    if (currentRoute == routeName) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  Future<void> _openFilterSheet(List<String> categories) async {
    final catalog = context.read<ProductCatalogProvider>();
    final filterCategories = categories
        .where((value) => value.trim().toLowerCase() != 'all')
        .toList();
    final minCatalogPrice = catalog.minCatalogPrice;
    final maxCatalogPrice = catalog.maxCatalogPrice;
    var selectedCategories = catalog.selectedCategories.toSet();
    var inStockOnly = catalog.inStockOnly;
    var minimumRating = catalog.minimumRatingFilter;
    var writtenReviewsOnly = catalog.writtenReviewsOnly;
    var range = RangeValues(catalog.selectedMinPrice, catalog.selectedMaxPrice);
    var applying = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FBF9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final safeMin = minCatalogPrice;
            final safeMax = maxCatalogPrice <= minCatalogPrice
                ? minCatalogPrice + 1
                : maxCatalogPrice;
            final selectedFilterCount =
                (selectedCategories.isNotEmpty ? 1 : 0) +
                ((range.start - safeMin).abs() > 0.01 ||
                        (range.end - safeMax).abs() > 0.01
                    ? 1
                    : 0) +
                (inStockOnly ? 1 : 0) +
                (minimumRating != null ? 1 : 0) +
                (writtenReviewsOnly ? 1 : 0);

            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.92,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    12,
                    18,
                    18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD2E2DB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filters',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF173D36),
                              ),
                            ),
                          ),
                          if (selectedFilterCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF5F0),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$selectedFilterCount active',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1C4A40),
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: applying
                                ? null
                                : () {
                                    setModalState(() {
                                      selectedCategories = <String>{};
                                      inStockOnly = false;
                                      minimumRating = null;
                                      writtenReviewsOnly = false;
                                      range = RangeValues(safeMin, safeMax);
                                    });
                                  },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Refine the catalog by price, stock, rating, and category.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64726D),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Price range',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF173D36),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _PricePill(label: 'Min', value: range.start),
                                  const SizedBox(width: 10),
                                  _PricePill(label: 'Max', value: range.end),
                                ],
                              ),
                              RangeSlider(
                                values: RangeValues(
                                  range.start.clamp(safeMin, safeMax),
                                  range.end.clamp(safeMin, safeMax),
                                ),
                                min: safeMin,
                                max: safeMax,
                                divisions: safeMax > safeMin
                                    ? (safeMax - safeMin).ceil().clamp(1, 100)
                                    : 1,
                                labels: RangeLabels(
                                  '\$${range.start.toStringAsFixed(0)}',
                                  '\$${range.end.toStringAsFixed(0)}',
                                ),
                                onChanged: applying
                                    ? null
                                    : (next) {
                                        setModalState(() => range = next);
                                      },
                              ),
                              SwitchListTile.adaptive(
                                value: inStockOnly,
                                onChanged: applying
                                    ? null
                                    : (value) {
                                        setModalState(
                                          () => inStockOnly = value,
                                        );
                                      },
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'In stock only',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: const Text(
                                  'Hide sold-out products from the grid.',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Ratings',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF173D36),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Any rating'),
                                    selected: minimumRating == null,
                                    onSelected: applying
                                        ? null
                                        : (_) {
                                            setModalState(
                                              () => minimumRating = null,
                                            );
                                          },
                                  ),
                                  ChoiceChip(
                                    label: const Text('4 stars & up'),
                                    selected: minimumRating == 4,
                                    onSelected: applying
                                        ? null
                                        : (_) {
                                            setModalState(
                                              () => minimumRating =
                                                  minimumRating == 4 ? null : 4,
                                            );
                                          },
                                  ),
                                  ChoiceChip(
                                    label: const Text('4.5+ only'),
                                    selected: minimumRating == 4.5,
                                    onSelected: applying
                                        ? null
                                        : (_) {
                                            setModalState(
                                              () => minimumRating =
                                                  minimumRating == 4.5
                                                  ? null
                                                  : 4.5,
                                            );
                                          },
                                  ),
                                  FilterChip(
                                    label: const Text('With written reviews'),
                                    selected: writtenReviewsOnly,
                                    onSelected: applying
                                        ? null
                                        : (value) {
                                            setModalState(
                                              () => writtenReviewsOnly = value,
                                            );
                                          },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Categories',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF173D36),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: filterCategories.map((category) {
                                  final selected = selectedCategories.contains(
                                    category,
                                  );
                                  return FilterChip(
                                    label: Text(category),
                                    selected: selected,
                                    onSelected: applying
                                        ? null
                                        : (_) {
                                            setModalState(() {
                                              if (selected) {
                                                selectedCategories.remove(
                                                  category,
                                                );
                                              } else {
                                                selectedCategories.add(
                                                  category,
                                                );
                                              }
                                            });
                                          },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: applying
                                  ? null
                                  : () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: applying
                                  ? null
                                  : () async {
                                      final navigator = Navigator.of(
                                        sheetContext,
                                      );
                                      setModalState(() => applying = true);
                                      await catalog.applyAdvancedFilters(
                                        categories: selectedCategories,
                                        minPrice: range.start,
                                        maxPrice: range.end,
                                        stockOnly: inStockOnly,
                                        minimumRating: minimumRating,
                                        writtenReviewsOnly: writtenReviewsOnly,
                                      );
                                      if (!navigator.mounted) return;
                                      navigator.pop();
                                    },
                              child: applying
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Apply filters'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _handleCatalogScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final shouldCollapse = position.pixels > _compactHeaderCollapseOffset;
    if (shouldCollapse != _compactHeaderCollapsed && mounted) {
      setState(() => _compactHeaderCollapsed = shouldCollapse);
    }
    if (position.maxScrollExtent <= 0) return;
    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining <= _loadMoreTriggerOffset) {
      context.read<ProductCatalogProvider>().loadMoreVisible();
    }
  }

  DateTime? _parseEventExpiry(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  DateTime? _parseEventStart(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 't' || text == 'yes';
  }

  String _eventState(Map<String, dynamic>? event) {
    if (event == null) return 'inactive';
    final providedState = (event['event_state'] ?? '').toString().trim();
    if (providedState.isNotEmpty) return providedState;

    final isEnabled = _asBool(event['is_active']);
    if (!isEnabled) return 'inactive';
    final now = DateTime.now().toUtc();
    final startsAt = _parseEventStart(event['starts_at']) ?? now;
    final expiresAt = _parseEventExpiry(event['expires_at']);
    if (expiresAt == null || !expiresAt.isAfter(now)) return 'expired';
    if (startsAt.isAfter(now)) return 'upcoming';
    return 'active';
  }

  bool _isEventActive(Map<String, dynamic>? event) {
    return _eventState(event) == 'active';
  }

  void _startEventTicker() {
    _eventTicker?.cancel();
    final event = _activeEvent;
    if (event == null) {
      _remainingEvent = null;
      return;
    }

    final startsAt = _parseEventStart(event['starts_at']);
    final expiry = _parseEventExpiry(event['expires_at']);
    if (expiry == null) {
      _remainingEvent = null;
      return;
    }

    void tick() {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      if (!expiry.isAfter(now)) {
        _eventTicker?.cancel();
        context.read<AppSettingsProvider>().setActiveEventId(null);
        setState(() {
          _activeEvent = null;
          _remainingEvent = null;
        });
        return;
      }

      final isUpcoming = startsAt != null && startsAt.isAfter(now);
      final nextState = isUpcoming ? 'upcoming' : 'active';
      final remaining = isUpcoming
          ? startsAt.difference(now)
          : expiry.difference(now);
      context.read<AppSettingsProvider>().setActiveEventId(
        nextState == 'active' ? (event['id'] ?? '').toString() : null,
      );
      setState(() {
        _remainingEvent = remaining;
        _activeEvent = Map<String, dynamic>.from(event)
          ..['event_state'] = nextState;
      });
    }

    tick();
    _eventTicker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _loadActiveEvent() async {
    try {
      final row = await context
          .read<ProductCatalogProvider>()
          .fetchActiveEvent();
      final nextEvent = row == null ? null : Map<String, dynamic>.from(row);
      final isActive = _isEventActive(nextEvent);
      if (!mounted) return;
      setState(() {
        _activeEvent = nextEvent;
      });
      context.read<AppSettingsProvider>().setActiveEventId(
        isActive ? (nextEvent?['id'] ?? '').toString() : null,
      );
      _syncActiveEventDealsCollection();
      _startEventTicker();
    } catch (_) {
      if (!mounted) return;
      _eventTicker?.cancel();
      context.read<AppSettingsProvider>().setActiveEventId(null);
      context.read<ProductCatalogProvider>().setEventDealProductIds(
        const <String>[],
      );
      setState(() {
        _activeEvent = null;
        _remainingEvent = null;
      });
    }
  }

  int _gridColumns(double width) {
    if (width >= 1700) return 5;
    if (width >= 1320) return 4;
    if (width >= 980) return 3;
    if (width >= 360) return 2;
    return 1;
  }

  double _gridAspectRatio(double width) {
    if (width >= 1320) return 0.76;
    if (width >= 980) return 0.74;
    if (width >= 430) return 0.76;
    if (width >= 360) return 0.66;
    return 0.86;
  }

  double _maxContentWidth(double width) {
    if (width >= 1800) return 1520;
    if (width >= 1440) return 1320;
    return 1160;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductCatalogProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final cart = context.watch<ShoppingCartProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = kIsWeb && screenWidth >= 980;
    final isCompactMobile = !useDesktopLayout;
    final showBrandText = screenWidth >= 420;
    final categories = settings.categoriesForProducts(prov.all);
    final columns = _gridColumns(screenWidth);
    final aspectRatio = _gridAspectRatio(screenWidth);
    final contentHorizontalPadding = useDesktopLayout ? 18.0 : 10.0;
    final showMiniCart = cart.items.isNotEmpty;
    final cartQty = cart.items.fold<int>(0, (sum, item) => sum + item.qty);
    final filteredIds = prov.filtered.map((product) => product.id).toSet();
    final recentlyViewed = prov.recentlyViewedProducts
        .where(
          (product) =>
              !prov.hasActiveFilters || filteredIds.contains(product.id),
        )
        .take(8)
        .toList();
    final bestSellerSpotlight = prov.filtered
        .where((product) => prov.isBestSeller(product.id))
        .take(8)
        .toList();
    final newArrivalSpotlight = prov.filtered
        .where(prov.isNewArrival)
        .take(8)
        .toList();
    final budgetSpotlight = prov.filtered
        .where((product) => product.price <= 25)
        .take(8)
        .toList();
    final showDiscoveryRails = isCompactMobile && !prov.hasActiveFilters;
    final activeEventDeals = _activeEventDealProducts(
      settings: settings,
      catalog: prov,
    );
    final activeEventMaxDiscount = _activeEventMaxDiscountPercent(
      settings: settings,
    );
    final activeEventTitle = (_activeEvent?['title'] ?? '').toString().trim();
    final activeEventSubtitle = (_activeEvent?['subtitle'] ?? '')
        .toString()
        .trim();
    final showEventDealsSummary =
        prov.activeCollectionFilter == CatalogCollectionFilter.eventDeals &&
        _activeEvent != null &&
        activeEventDeals.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FBF9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: useDesktopLayout ? 72 : 74,
        titleSpacing: isCompactMobile ? 16 : NavigationToolbar.kMiddleSpacing,
        title: Row(
          children: [
            const BrandLogo(size: 34, showWordmark: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBrandText)
                    Text(
                      Brand.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: useDesktopLayout ? 28 : 24,
                      ),
                    )
                  else
                    const Text(
                      'Shop',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  if (isCompactMobile)
                    Text(
                      prov.query.trim().isEmpty && !prov.hasCategoryFilter
                          ? 'Fresh picks for mobile'
                          : '${prov.filtered.length} matching items',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF66756F),
                      ),
                    ),
                ],
              ),
            ),
            if (isCompactMobile)
              _FilterCountPill(
                label: prov.hasCategoryFilter || prov.query.trim().isNotEmpty
                    ? 'Filtered'
                    : 'All items',
                value: prov.filtered.length,
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (prov.loading)
            _CatalogLoadingState(compact: isCompactMobile)
          else if (prov.error != null && prov.visible.isEmpty)
            _LoadProductsError(
              message: prov.error!,
              onRetry: () =>
                  context.read<ProductCatalogProvider>().fetchProducts(),
            )
          else
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: useDesktopLayout
                      ? _maxContentWidth(screenWidth)
                      : screenWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: contentHorizontalPadding,
                  ),
                  child: Column(
                    children: [
                      _CatalogTopSection(
                        categories: categories,
                        compact: isCompactMobile,
                        collapsed: isCompactMobile && _compactHeaderCollapsed,
                        filteredCount: prov.filtered.length,
                        visibleCount: prov.visible.length,
                        searchController: _searchController,
                        onApplySearchQuery: _applySearchQuery,
                        onClearAll: _clearSearchAndFilters,
                        onOpenFilters: () => _openFilterSheet(categories),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: const Color(0xFFF8FBF9),
                          child: ClipRect(
                            child: ScrollConfiguration(
                              behavior: const _NoOverscrollScrollBehavior(),
                              child: RefreshIndicator(
                                onRefresh: _refreshCatalog,
                                child: CustomScrollView(
                                  controller: _scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: ClampingScrollPhysics(),
                                  ),
                                  slivers: [
                                    if (_activeEvent != null)
                                      SliverToBoxAdapter(
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 320,
                                          ),
                                          switchInCurve: Curves.easeOutCubic,
                                          switchOutCurve: Curves.easeInCubic,
                                          child: _HeroBanner(
                                            key: ValueKey<String>(
                                              '${_activeEvent?['id'] ?? 'event'}:${_eventState(_activeEvent)}',
                                            ),
                                            event: _activeEvent!,
                                            remaining: _remainingEvent,
                                            dealCount: activeEventDeals.length,
                                            onBrowseDeals:
                                                activeEventDeals.isEmpty
                                                ? null
                                                : () => _showCollectionView(
                                                    CatalogCollectionFilter
                                                        .eventDeals,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    if (showEventDealsSummary)
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            0,
                                            12,
                                            8,
                                          ),
                                          child: _EventDealsSummaryCard(
                                            event: _activeEvent!,
                                            remaining: _remainingEvent,
                                            dealCount: activeEventDeals.length,
                                            maxDiscountPercent:
                                                activeEventMaxDiscount,
                                            onBrowseAll: _browseAllProducts,
                                          ),
                                        ),
                                      ),
                                    if (showDiscoveryRails &&
                                        (activeEventDeals.isNotEmpty ||
                                            recentlyViewed.isNotEmpty ||
                                            bestSellerSpotlight.isNotEmpty ||
                                            newArrivalSpotlight.isNotEmpty ||
                                            budgetSpotlight.isNotEmpty))
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            2,
                                            4,
                                            2,
                                            8,
                                          ),
                                          child: Column(
                                            children: [
                                              if (activeEventDeals.isNotEmpty)
                                                _CollectionStrip(
                                                  title:
                                                      '${activeEventTitle.isEmpty ? 'Event' : activeEventTitle} picks',
                                                  subtitle:
                                                      activeEventSubtitle
                                                          .isNotEmpty
                                                      ? activeEventSubtitle
                                                      : 'Limited-time discounts from the live event.',
                                                  products: activeEventDeals,
                                                  cardKeyPrefix:
                                                      'event-deals',
                                                  onViewAll: () =>
                                                      _showCollectionView(
                                                        CatalogCollectionFilter
                                                            .eventDeals,
                                                      ),
                                                  onTapProduct:
                                                      _openProductDetails,
                                                ),
                                              if (recentlyViewed.isNotEmpty)
                                                Padding(
                                                  padding: EdgeInsets.only(
                                                    top:
                                                        activeEventDeals
                                                            .isNotEmpty
                                                        ? 14
                                                        : 0,
                                                  ),
                                                  child: _CollectionStrip(
                                                    title: 'Recently viewed',
                                                    subtitle:
                                                        'Jump back into items you opened last.',
                                                    products: recentlyViewed,
                                                    cardKeyPrefix:
                                                        'recently-viewed',
                                                    onViewAll: () =>
                                                        _showCollectionView(
                                                          CatalogCollectionFilter
                                                              .recentlyViewed,
                                                        ),
                                                    onTapProduct:
                                                        _openProductDetails,
                                                  ),
                                                ),
                                              if (bestSellerSpotlight
                                                  .isNotEmpty) ...[
                                                if (recentlyViewed.isNotEmpty)
                                                  const SizedBox(height: 14),
                                                _CollectionStrip(
                                                  title: 'Best sellers',
                                                  subtitle:
                                                      'The products shoppers keep picking first.',
                                                  products: bestSellerSpotlight,
                                                  cardKeyPrefix:
                                                      'best-sellers',
                                                  onViewAll: () =>
                                                      _showCollectionView(
                                                        CatalogCollectionFilter
                                                            .bestSellers,
                                                      ),
                                                  onTapProduct:
                                                      _openProductDetails,
                                                ),
                                              ],
                                              if (newArrivalSpotlight
                                                  .isNotEmpty) ...[
                                                if (recentlyViewed.isNotEmpty ||
                                                    bestSellerSpotlight
                                                        .isNotEmpty)
                                                  const SizedBox(height: 14),
                                                _CollectionStrip(
                                                  title: 'New arrivals',
                                                  subtitle:
                                                      'Fresh drops that just landed in the catalog.',
                                                  products: newArrivalSpotlight,
                                                  cardKeyPrefix:
                                                      'new-arrivals',
                                                  onViewAll: () =>
                                                      _showCollectionView(
                                                        CatalogCollectionFilter
                                                            .newArrivals,
                                                      ),
                                                  onTapProduct:
                                                      _openProductDetails,
                                                ),
                                              ],
                                              if (budgetSpotlight
                                                  .isNotEmpty) ...[
                                                if (recentlyViewed.isNotEmpty ||
                                                    bestSellerSpotlight
                                                        .isNotEmpty ||
                                                    newArrivalSpotlight
                                                        .isNotEmpty)
                                                  const SizedBox(height: 14),
                                                _CollectionStrip(
                                                  title: 'Under \$25',
                                                  subtitle:
                                                      'Budget-friendly picks with easy quick adds.',
                                                  products: budgetSpotlight,
                                                  cardKeyPrefix: 'under-25',
                                                  onViewAll: () =>
                                                      _showCollectionView(
                                                        CatalogCollectionFilter
                                                            .underTwentyFive,
                                                      ),
                                                  onTapProduct:
                                                      _openProductDetails,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (prov.visible.isEmpty)
                                      const SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: _EmptyCatalogState(),
                                      )
                                    else
                                      SliverPadding(
                                        padding: EdgeInsets.fromLTRB(
                                          isCompactMobile ? 2 : 6,
                                          4,
                                          isCompactMobile ? 2 : 6,
                                          showMiniCart ? 96 : 12,
                                        ),
                                        sliver: SliverGrid(
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: columns,
                                                childAspectRatio: aspectRatio,
                                                crossAxisSpacing:
                                                    isCompactMobile ? 10 : 12,
                                                mainAxisSpacing: isCompactMobile
                                                    ? 10
                                                    : 12,
                                              ),
                                          delegate: SliverChildBuilderDelegate((
                                            context,
                                            i,
                                          ) {
                                            final p = prov.visible[i];
                                            return _AnimatedGridItem(
                                              key: ValueKey<String>(
                                                'catalog-item-${p.id}',
                                              ),
                                              index: i,
                                              child: _ProductCard(
                                                product: p,
                                                compact: isCompactMobile,
                                                isPopular: prov.isBestSeller(
                                                  p.id,
                                                ),
                                                isNewArrival: prov.isNewArrival(
                                                  p,
                                                ),
                                                stockSummary: prov
                                                    .stockSummaryFor(p.id),
                                                stockLoading: prov
                                                    .isStockSummaryLoading(
                                                      p.id,
                                                    ),
                                                ratingSummary: prov
                                                    .ratingSummaryFor(p.id),
                                                ratingLoading: prov
                                                    .isRatingSummaryLoading(
                                                      p.id,
                                                    ),
                                                isFavorite: context
                                                    .watch<
                                                      UserWishlistProvider
                                                    >()
                                                    .isFav(p.id),
                                                isWishlistBusy:
                                                    _wishlistBusyProductIds
                                                        .contains(p.id),
                                                isQuickAddBusy:
                                                    _addingProductIds.contains(
                                                      p.id,
                                                    ),
                                                onToggleFavorite: () =>
                                                    _handleWishlistToggle(p),
                                                onQuickAdd: () =>
                                                    _handleQuickAdd(p),
                                                onTap: () =>
                                                    _openProductDetails(p),
                                              ),
                                            );
                                          }, childCount: prov.visible.length),
                                        ),
                                      ),
                                    if (prov.canLoadMore)
                                      const SliverToBoxAdapter(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (showMiniCart)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: _MiniCartBar(
                itemCount: cartQty,
                totalLabel: settings.formatUsd(cart.total),
                onViewCart: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShoppingCartScreen(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadProductsError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _LoadProductsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _CatalogLoadingState extends StatelessWidget {
  final bool compact;

  const _CatalogLoadingState({required this.compact});

  @override
  Widget build(BuildContext context) {
    final columns = compact ? 2 : 3;
    final aspectRatio = compact ? 0.72 : 0.76;

    return ColoredBox(
      color: const Color(0xFFF8FBF9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        child: Column(
          children: [
            const _SkeletonBlock(height: 148, radius: 22),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: compact ? 6 : 9,
                itemBuilder: (context, index) => const _CatalogSkeletonCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSkeletonCard extends StatelessWidget {
  const _CatalogSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E5DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(child: _SkeletonBlock(radius: 20, topOnly: true)),
          Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBlock(height: 18, width: 62, radius: 999),
                SizedBox(height: 10),
                _SkeletonBlock(height: 16),
                SizedBox(height: 8),
                _SkeletonBlock(height: 16, width: 86),
                SizedBox(height: 12),
                _SkeletonBlock(height: 36, radius: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  final bool topOnly;

  const _SkeletonBlock({
    this.height = double.infinity,
    this.width,
    this.radius = 16,
    this.topOnly = false,
  });

  @override
  State<_SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<_SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.topOnly
        ? BorderRadius.vertical(top: Radius.circular(widget.radius))
        : BorderRadius.circular(widget.radius);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.62 + (_controller.value * 0.22),
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFFE7EEEA),
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class _FilterCountPill extends StatelessWidget {
  final String label;
  final int value;

  const _FilterCountPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E5DE)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6A7A73),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D36),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppliedFiltersSummary extends StatelessWidget {
  final List<String> labels;
  final VoidCallback onClearAll;

  const _AppliedFiltersSummary({
    required this.labels,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: labels
              .map((label) => _AppliedFilterBadge(label: label))
              .toList(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onClearAll,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Clear all'),
          ),
        ),
      ],
    );
  }
}

class _AppliedFilterBadge extends StatelessWidget {
  final String label;

  const _AppliedFilterBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD2E8DF)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1C4A40),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final bool compact;

  const _FilterButton({
    required this.count,
    required this.onTap,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters = count > 0;
    final countLabel = count > 9 ? '9+' : '$count';

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 12 : 13,
        ),
        backgroundColor: hasFilters ? const Color(0xFFF0FAF6) : Colors.white,
        side: BorderSide(
          color: hasFilters ? const Color(0xFFA8D4C6) : const Color(0xFFD8E6DF),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hasFilters
                  ? const Color(0xFFDFF3EC)
                  : const Color(0xFFF3F8F5),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: Color(0xFF173D36),
                ),
                if (hasFilters)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Color(0xFF0B7D69),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        countLabel,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A7A73),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasFilters
                      ? '$count refinement${count == 1 ? '' : 's'} selected'
                      : 'Price, stock, more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF173D36),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Color(0xFF6A7A73),
          ),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final String label;
  final double value;

  const _PricePill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8E6DF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6A7A73),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '\$${value.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF173D36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final CatalogSortOption value;
  final bool compact;

  const _SortMenu({required this.value, required this.compact});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductCatalogProvider>();
    final options = CatalogSortOption.values
        .where(
          (option) =>
              option != CatalogSortOption.bestDeals ||
              catalog.activeCollectionFilter ==
                  CatalogCollectionFilter.eventDeals,
        )
        .toList();
    return PopupMenuButton<CatalogSortOption>(
      onSelected: (next) =>
          context.read<ProductCatalogProvider>().setSortOption(next),
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem<CatalogSortOption>(
              value: option,
              child: Row(
                children: [
                  Expanded(child: Text(option.label)),
                  if (option == value)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 12 : 13,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E6DF)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8F5),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: Color(0xFF173D36),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sort by',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6A7A73),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF173D36),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: Color(0xFF6A7A73),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTopSection extends StatelessWidget {
  final List<String> categories;
  final bool compact;
  final bool collapsed;
  final int filteredCount;
  final int visibleCount;
  final TextEditingController searchController;
  final ValueChanged<String> onApplySearchQuery;
  final VoidCallback onClearAll;
  final VoidCallback onOpenFilters;

  const _CatalogTopSection({
    required this.categories,
    required this.compact,
    required this.collapsed,
    required this.filteredCount,
    required this.visibleCount,
    required this.searchController,
    required this.onApplySearchQuery,
    required this.onClearAll,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<ProductCatalogProvider>();
    final appliedLabels = _buildAppliedLabels(catalog);
    final isCompactCollapsed = compact && collapsed;
    final title = 'Browse the catalog';
    final subtitle = catalog.activeCollectionLabel != null
        ? '$filteredCount products in ${catalog.activeCollectionLabel!.toLowerCase()}'
        : 'Search, filter, and jump into details faster.';
    final suggestionItems = catalog.searchSuggestions(limit: compact ? 4 : 6);
    final showRecentSearches =
        catalog.query.trim().isEmpty && catalog.recentSearches.isNotEmpty;
    final showSearchDiscovery = suggestionItems.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.fromLTRB(
        0,
        isCompactCollapsed
            ? 4
            : compact
            ? 6
            : 8,
        0,
        isCompactCollapsed ? 4 : 6,
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 16,
        isCompactCollapsed
            ? 10
            : compact
            ? 12
            : 14,
        compact ? 14 : 16,
        isCompactCollapsed
            ? 10
            : compact
            ? 12
            : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8F5),
        borderRadius: BorderRadius.circular(
          isCompactCollapsed
              ? 18
              : compact
              ? 20
              : 22,
        ),
        border: Border.all(color: const Color(0xFFD9E7E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D16342B),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!compact) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF173D36),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Color(0xFF64726D),
                        ),
                      ),
                    ],
                  ),
                ),
                _FilterCountPill(label: 'Showing', value: visibleCount),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _SearchBar(
            compact: compact,
            controller: searchController,
            showLabel: !isCompactCollapsed,
            onSubmitted: (value) => onApplySearchQuery(value),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: isCompactCollapsed
                ? const SizedBox.shrink()
                : Column(
                    key: const ValueKey<String>('catalog-controls-expanded'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FilterCountPill(
                            label: 'Matches',
                            value: filteredCount,
                          ),
                          _FilterCountPill(
                            label: 'Active',
                            value: catalog.activeFilterCount,
                          ),
                          _FilterCountPill(
                            label: 'Saved searches',
                            value: catalog.recentSearches.length,
                          ),
                        ],
                      ),
                      if (showSearchDiscovery) ...[
                        const SizedBox(height: 12),
                        _SearchDiscoverySection(
                          compact: compact,
                          recent: showRecentSearches,
                          items: suggestionItems,
                          onApplyQuery: onApplySearchQuery,
                          onRemoveQuery: showRecentSearches
                              ? (value) => unawaited(
                                  context
                                      .read<ProductCatalogProvider>()
                                      .removeRecentSearch(value),
                                )
                              : null,
                          onClearAll: showRecentSearches
                              ? () => unawaited(
                                  context
                                      .read<ProductCatalogProvider>()
                                      .clearRecentSearches(),
                                )
                              : null,
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (compact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _SortMenu(
                                    value: catalog.sortOption,
                                    compact: compact,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _FilterButton(
                                    count: catalog.advancedFilterCount,
                                    compact: compact,
                                    onTap: onOpenFilters,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _SortMenu(
                                value: catalog.sortOption,
                                compact: compact,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterButton(
                                count: catalog.advancedFilterCount,
                                compact: compact,
                                onTap: onOpenFilters,
                              ),
                            ),
                          ],
                        ),
                      if (appliedLabels.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _AppliedFiltersSummary(
                          labels: appliedLabels,
                          onClearAll: onClearAll,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _CategoryChips(categories: categories, compact: compact),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<String> _buildAppliedLabels(ProductCatalogProvider catalog) {
    final labels = <String>[];
    final query = catalog.query.trim();
    if (query.isNotEmpty) {
      labels.add('Search: ${_truncateLabel(query)}');
    }
    if (catalog.activeCollectionLabel != null) {
      labels.add('Collection: ${catalog.activeCollectionLabel!}');
    }
    if (catalog.hasCategoryFilter) {
      final categories = catalog.selectedCategories.toList()..sort();
      labels.add(
        categories.length == 1
            ? 'Category: ${categories.first}'
            : '${categories.length} categories',
      );
    }
    if (catalog.hasPriceFilter) {
      final min = catalog.selectedMinPrice.toStringAsFixed(0);
      final max = catalog.selectedMaxPrice.toStringAsFixed(0);
      labels.add(min == max ? 'Price: \$$min' : 'Price: \$$min-\$$max');
    }
    if (catalog.minimumRatingFilter != null) {
      final rating = catalog.minimumRatingFilter!;
      labels.add(rating == 4.5 ? '4.5+ rating' : '4+ rating');
    }
    if (catalog.writtenReviewsOnly) {
      labels.add('Written reviews');
    }
    if (catalog.inStockOnly) {
      labels.add('In stock');
    }
    if (catalog.hasSortFilter) {
      labels.add('Sort: ${catalog.sortOption.label}');
    }
    return labels;
  }

  String _truncateLabel(String value) {
    final normalized = value.trim();
    if (normalized.length <= 18) {
      return normalized;
    }
    return '${normalized.substring(0, 15)}...';
  }
}

class _SearchBar extends StatelessWidget {
  final bool compact;
  final TextEditingController? controller;
  final bool showLabel;
  final ValueChanged<String>? onSubmitted;

  const _SearchBar({
    this.compact = false,
    this.controller,
    this.showLabel = true,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              compact ? 'Search catalog' : 'Search',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6A7A73),
              ),
            ),
          ),
        TextField(
          controller: controller,
          onChanged: (v) => context.read<ProductCatalogProvider>().setQuery(v),
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: compact
                ? 'Search products or categories'
                : 'Search shirts, pants, sneakers...',
            hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF86958F)),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF6A7A73),
            ),
            suffixIcon: context.watch<ProductCatalogProvider>().hasQueryFilter
                ? IconButton(
                    onPressed: () {
                      controller?.clear();
                      context.read<ProductCatalogProvider>().setQuery('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 18 : 16),
              borderSide: const BorderSide(color: Color(0xFFD8E6DF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 18 : 16),
              borderSide: const BorderSide(color: Color(0xFFD8E6DF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(compact ? 18 : 16),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchDiscoverySection extends StatelessWidget {
  final bool compact;
  final bool recent;
  final List<String> items;
  final ValueChanged<String> onApplyQuery;
  final ValueChanged<String>? onRemoveQuery;
  final VoidCallback? onClearAll;

  const _SearchDiscoverySection({
    required this.compact,
    required this.recent,
    required this.items,
    required this.onApplyQuery,
    this.onRemoveQuery,
    this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final title = recent ? 'Recent searches' : 'Suggested matches';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF5D6E67),
                ),
              ),
            ),
            if (recent && onClearAll != null)
              TextButton(
                onPressed: onClearAll,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final icon = recent ? Icons.history_rounded : Icons.travel_explore;
            if (recent) {
              return InputChip(
                avatar: Icon(icon, size: compact ? 16 : 18),
                label: Text(item),
                onPressed: () => onApplyQuery(item),
                onDeleted: onRemoveQuery == null
                    ? null
                    : () => onRemoveQuery!(item),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                backgroundColor: const Color(0xFFFFFFFF),
                side: const BorderSide(color: Color(0xFFD8E6DF)),
                visualDensity: VisualDensity.compact,
              );
            }
            return ActionChip(
              avatar: Icon(icon, size: compact ? 16 : 18),
              label: Text(item),
              onPressed: () => onApplyQuery(item),
              backgroundColor: const Color(0xFFFFFFFF),
              side: const BorderSide(color: Color(0xFFD8E6DF)),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final List<String> categories;
  final bool compact;

  const _CategoryChips({required this.categories, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductCatalogProvider>();

    final cats = categories.isEmpty ? const ['All'] : categories;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: compact ? 42 : 40,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          scrollDirection: Axis.horizontal,
          itemCount: cats.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final c = cats[i];
            final active = prov.isCategorySelected(c);

            return ChoiceChip(
              label: Text(c),
              selected: active,
              onSelected: (_) =>
                  context.read<ProductCatalogProvider>().setCategory(c),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              showCheckmark: false,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 10,
                vertical: compact ? 8 : 6,
              ),
              backgroundColor: Colors.white,
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              side: BorderSide(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade800,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyCatalogState extends StatelessWidget {
  const _EmptyCatalogState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5F0),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 34,
              color: Color(0xFF0B7D69),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D36),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try another keyword or switch back to All to see everything again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF64726D),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final Map<String, dynamic> event;
  final Duration? remaining;
  final int dealCount;
  final VoidCallback? onBrowseDeals;

  const _HeroBanner({
    super.key,
    required this.event,
    required this.remaining,
    required this.dealCount,
    required this.onBrowseDeals,
  });

  String _formatRemaining(Duration value) {
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  String _themeKey(Map<String, dynamic> value) {
    return (value['theme'] ?? 'default').toString().trim().toLowerCase();
  }

  LinearGradient _themeGradient(String theme) {
    switch (theme) {
      case 'christmas_sale':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7D69), Color(0xFFB71C1C)],
        );
      case 'valentine':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD33F6A), Color(0xFF8E2B8C)],
        );
      case 'new_year':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F4BA2), Color(0xFF1E8A8A)],
        );
      case 'black_friday':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1B), Color(0xFF4A4A4A)],
        );
      case 'summer_sale':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF8D2F), Color(0xFFE45555)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7D69), Color(0xFF0F5D85)],
        );
    }
  }

  IconData _themeIcon(String theme) {
    switch (theme) {
      case 'christmas_sale':
        return Icons.celebration;
      case 'valentine':
        return Icons.favorite;
      case 'new_year':
        return Icons.auto_awesome;
      case 'black_friday':
        return Icons.local_offer;
      case 'summer_sale':
        return Icons.wb_sunny;
      default:
        return Icons.local_fire_department_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventState = (event['event_state'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isActive = eventState == 'active';
    final isUpcoming = eventState == 'upcoming';
    final badge = (event['badge'] ?? '').toString().trim();
    final theme = _themeKey(event);
    final title = (event['title'] ?? (isUpcoming ? 'Coming Soon' : 'New Drop'))
        .toString()
        .trim();
    final subtitle =
        (event['subtitle'] ??
                (isUpcoming
                    ? 'Fresh arrivals are almost here'
                    : 'Streetwear Week\nUp to 35% OFF'))
            .toString();
    final headline = subtitle.trim().isEmpty ? title : '$title\n$subtitle';
    final timerLabel = remaining != null ? _formatRemaining(remaining!) : '';
    final timerPrefix = isUpcoming ? 'Starts in ' : 'Ends in ';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: _themeGradient(theme),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2A0E6E61),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.isEmpty ? 'Featured Event' : badge,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isUpcoming) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x40FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'UPCOMING',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  if (timerLabel.isNotEmpty && (isUpcoming || isActive)) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '$timerPrefix$timerLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (dealCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x24FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '$dealCount event ${dealCount == 1 ? 'deal' : 'deals'} live',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 6),
                  Text(
                    title.isEmpty ? 'Featured Event' : headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (onBrowseDeals != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0x20FFFFFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      onPressed: onBrowseDeals,
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      label: const Text('Shop event'),
                    ),
                  ],
                ],
              ),
            ),
            Icon(_themeIcon(theme), color: Colors.white, size: 42),
          ],
        ),
      ),
    );
  }
}

class _EventDealsSummaryCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final Duration? remaining;
  final int dealCount;
  final double maxDiscountPercent;
  final Future<void> Function() onBrowseAll;

  const _EventDealsSummaryCard({
    required this.event,
    required this.remaining,
    required this.dealCount,
    required this.maxDiscountPercent,
    required this.onBrowseAll,
  });

  String _formatRemaining(Duration value) {
    final totalHours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (totalHours >= 24) {
      final days = value.inDays;
      final hours = totalHours.remainder(24);
      return '${days}d ${hours}h';
    }
    if (totalHours > 0) {
      return '${totalHours}h ${minutes}m';
    }
    return '${value.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    final eventState = (event['event_state'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isUpcoming = eventState == 'upcoming';
    final title = (event['title'] ?? 'Event deals').toString().trim();
    final subtitle = (event['subtitle'] ?? '').toString().trim();
    final badge = (event['badge'] ?? '').toString().trim();
    final timingLabel = remaining == null
        ? null
        : isUpcoming
        ? 'Starts in ${_formatRemaining(remaining!)}'
        : 'Ends in ${_formatRemaining(remaining!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD8E6DF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F16342B),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF5F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge.isEmpty ? 'Featured Event' : badge,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1C4A40),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F6F4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$dealCount live ${dealCount == 1 ? 'deal' : 'deals'} in this event',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF173D36),
                  ),
                ),
              ),
              if (maxDiscountPercent > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7EEE8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Save up to ${maxDiscountPercent.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A4B17),
                    ),
                  ),
                ),
              if (timingLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBF9),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFDCE9E3)),
                  ),
                  child: Text(
                    timingLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF5D6F68),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title.isEmpty ? 'Event deals' : '$title event',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D36),
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF64726D),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onBrowseAll,
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Browse all products'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedGridItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedGridItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<_AnimatedGridItem> createState() => _AnimatedGridItemState();
}

class _AnimatedGridItemState extends State<_AnimatedGridItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _fadeAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slideAnimation = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _startWithStagger();
  }

  Future<void> _startWithStagger() async {
    final delayMs = 48 + ((widget.index % 10) * 24);
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    if (!mounted) return;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

class _CollectionStrip extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Product> products;
  final String cardKeyPrefix;
  final VoidCallback onViewAll;
  final ValueChanged<Product> onTapProduct;

  const _CollectionStrip({
    required this.title,
    required this.subtitle,
    required this.products,
    required this.cardKeyPrefix,
    required this.onViewAll,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF173D36),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFD8E6DF)),
              ),
              child: Text(
                '${products.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF173D36),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(onPressed: onViewAll, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: Color(0xFF64726D),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 224,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return _CollectionProductCard(
                cardKeyPrefix: cardKeyPrefix,
                product: product,
                onTap: () => onTapProduct(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CollectionProductCard extends StatelessWidget {
  final String cardKeyPrefix;
  final Product product;
  final VoidCallback onTap;

  const _CollectionProductCard({
    required this.cardKeyPrefix,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final catalog = context.watch<ProductCatalogProvider>();
    final discount = settings.discountPercentForProduct(productId: product.id);
    final eventDiscount = settings.activeDiscountForProduct(
      productId: product.id,
    );
    final hasDiscount = discount > 0;
    final isPopular = catalog.isBestSeller(product.id);
    final isNewArrival = catalog.isNewArrival(product);
    final ratingSummary = catalog.ratingSummaryFor(product.id);
    final priceLabel = settings.formatUsd(
      product.price,
      productId: product.id,
      overrideDiscountPercent: discount,
    );
    final originalPrice = settings.formatUsd(
      product.price,
      overrideDiscountPercent: 0,
    );
    final category = (product.category ?? '').trim();
    final overlayShadow = <Shadow>[
      const Shadow(
        color: Color(0xB3000000),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ];

    return InkWell(
      key: ValueKey<String>(
        'collection-product-card-$cardKeyPrefix-${product.id}',
      ),
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 156,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E5DE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1217362E),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: product.imageUrl.isEmpty
                    ? Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF1F5F3), Color(0xFFE4ECE8)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_outlined,
                          size: 34,
                          color: Color(0xFF6A7B73),
                        ),
                      )
                    : Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF1F5F3), Color(0xFFE4ECE8)],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF6A7B73),
                          ),
                        ),
                      ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.black.withValues(alpha: 0.26),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.46, 0.86],
                    ),
                  ),
                ),
              ),
              if (hasDiscount || isPopular || isNewArrival)
                Positioned(
                  top: 10,
                  left: 10,
                  child: hasDiscount
                      ? _ProductBadge(
                          label: '-${discount.toStringAsFixed(0)}%',
                          background: const Color(0xFFFCE4DA),
                          foreground: const Color(0xFF9B3E1D),
                          borderColor: const Color(0xFFF3BEA8),
                        )
                      : isPopular
                      ? const _ProductBadge(
                          label: 'Popular',
                          background: Color(0xFFFFF3D9),
                          foreground: Color(0xFF8C5C12),
                          borderColor: Color(0xFFF2D79E),
                          icon: Icons.trending_up_rounded,
                        )
                      : const _ProductBadge(
                          label: 'New',
                          background: Color(0xFFEAF5F0),
                          foreground: Color(0xFF1B5D4E),
                        ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category.isNotEmpty &&
                        category.toLowerCase() != 'all') ...[
                      Text(
                        category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: Colors.white.withValues(alpha: 0.92),
                          shadows: overlayShadow,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: Colors.white,
                        shadows: overlayShadow,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (eventDiscount != null) ...[
                      EventDealChip(
                        eventTitle: eventDiscount.eventTitle,
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                        borderColor: Colors.white.withValues(alpha: 0.22),
                        fontSize: 10.5,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (ratingSummary != null && ratingSummary.hasRatings)
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFFFD54F),
                          ),
                          Text(
                            ratingSummary.averageRating.toStringAsFixed(1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: overlayShadow,
                            ),
                          ),
                          Text(
                            '(${ratingSummary.ratingCount})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.88),
                              shadows: overlayShadow,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'No reviews yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.88),
                          shadows: overlayShadow,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: overlayShadow,
                      ),
                    ),
                    if (hasDiscount)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          originalPrice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.78),
                            decoration: TextDecoration.lineThrough,
                            decorationColor: Colors.white.withValues(
                              alpha: 0.85,
                            ),
                            shadows: overlayShadow,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool compact;
  final bool isPopular;
  final bool isNewArrival;
  final ProductStockSummary? stockSummary;
  final bool stockLoading;
  final ProductRatingSummary? ratingSummary;
  final bool ratingLoading;
  final bool isFavorite;
  final bool isWishlistBusy;
  final bool isQuickAddBusy;
  final VoidCallback onToggleFavorite;
  final VoidCallback onQuickAdd;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.compact,
    required this.isPopular,
    required this.isNewArrival,
    required this.stockSummary,
    required this.stockLoading,
    required this.ratingSummary,
    required this.ratingLoading,
    required this.isFavorite,
    required this.isWishlistBusy,
    required this.isQuickAddBusy,
    required this.onToggleFavorite,
    required this.onQuickAdd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final discount = settings.discountPercentForProduct(productId: product.id);
    final eventDiscount = settings.activeDiscountForProduct(
      productId: product.id,
    );
    final hasDiscount = discount > 0;
    final category = (product.category ?? '').trim();
    final isOutOfStock = stockSummary?.isOutOfStock == true;
    final isLowStock = stockSummary?.isLowStock == true;
    final displayPrice = settings.formatUsd(
      product.price,
      productId: product.id,
      overrideDiscountPercent: discount,
    );
    final originalPrice = settings.formatUsd(
      product.price,
      overrideDiscountPercent: 0,
    );
    final overlayShadow = <Shadow>[
      const Shadow(
        color: Color(0xB3000000),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ];

    return InkWell(
      key: ValueKey<String>('catalog-product-card-${product.id}'),
      borderRadius: BorderRadius.circular(compact ? 20 : 18),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 20 : 18),
          border: Border.all(color: const Color(0xFFD8E5DE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1217362E),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(compact ? 20 : 18),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: 'product-image-${product.id}',
                        transitionOnUserGestures: true,
                        child: product.imageUrl.isEmpty
                            ? Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF1F5F3),
                                      Color(0xFFE4ECE8),
                                    ],
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_outlined,
                                  size: 42,
                                  color: Color(0xFF6A7B73),
                                ),
                              )
                            : Image.network(
                                product.imageUrl,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFF1F5F3),
                                        Color(0xFFE4ECE8),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: Color(0xFF6A7B73),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.72),
                              Colors.black.withValues(alpha: 0.26),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.46, 0.86],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (hasDiscount)
                                  _ProductBadge(
                                    label: '-${discount.toStringAsFixed(0)}%',
                                    background: const Color(0xFFFCE4DA),
                                    foreground: const Color(0xFF9B3E1D),
                                    borderColor: const Color(0xFFF3BEA8),
                                  ),
                                if (isOutOfStock)
                                  const _ProductBadge(
                                    label: 'Out of stock',
                                    background: Color(0xFF7A2E2E),
                                    foreground: Colors.white,
                                  )
                                else if (isLowStock)
                                  _ProductBadge(
                                    label: 'Low stock',
                                    background: const Color(0xFFF7E2C8),
                                    foreground: const Color(0xFF8A4B17),
                                  ),
                                if (isNewArrival)
                                  const _ProductBadge(
                                    label: 'New',
                                    background: Color(0xFFEAF5F0),
                                    foreground: Color(0xFF1B5D4E),
                                  ),
                                if (isPopular)
                                  const _ProductBadge(
                                    label: 'Popular',
                                    background: Color(0xFFFFF3D9),
                                    foreground: Color(0xFF8C5C12),
                                    borderColor: Color(0xFFF2D79E),
                                    icon: Icons.trending_up_rounded,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.34),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 7,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: FavoriteIconButton(
                              isFavorite: isFavorite,
                              onPressed: isWishlistBusy
                                  ? null
                                  : onToggleFavorite,
                              size: 17,
                              padding: const EdgeInsets.all(5),
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              splashRadius: 16,
                              visualDensity: VisualDensity.compact,
                              tooltip: isFavorite
                                  ? 'Remove from favorites'
                                  : 'Save to favorites',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (category.isNotEmpty &&
                              category.toLowerCase() != 'all') ...[
                            Text(
                              category.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: Colors.white.withValues(alpha: 0.92),
                                shadows: overlayShadow,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              color: Colors.white,
                              shadows: overlayShadow,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (eventDiscount != null) ...[
                            EventDealChip(
                              eventTitle: eventDiscount.eventTitle,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.16,
                              ),
                              foregroundColor: Colors.white,
                              borderColor: Colors.white.withValues(alpha: 0.22),
                              fontSize: 10.5,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            children: [
                              if (ratingLoading)
                                Flexible(
                                  child: Text(
                                    'Loading reviews...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      shadows: overlayShadow,
                                    ),
                                  ),
                                )
                              else if (ratingSummary != null &&
                                  ratingSummary!.hasRatings) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 15,
                                  color: Color(0xFFFFD54F),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    ratingSummary!.averageRating
                                        .toStringAsFixed(1),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      shadows: overlayShadow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '(${ratingSummary!.ratingCount})',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.88,
                                      ),
                                      shadows: overlayShadow,
                                    ),
                                  ),
                                ),
                              ] else
                                Flexible(
                                  child: Text(
                                    'No reviews yet',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(
                                        alpha: 0.88,
                                      ),
                                      shadows: overlayShadow,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Text(
                                  displayPrice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    shadows: overlayShadow,
                                  ),
                                ),
                              ),
                              if (hasDiscount) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      originalPrice,
                                      maxLines: 1,
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white.withValues(
                                          alpha: 0.78,
                                        ),
                                        decoration: TextDecoration.lineThrough,
                                        decorationColor: Colors.white
                                            .withValues(alpha: 0.85),
                                        shadows: overlayShadow,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                compact ? 8 : 10,
                compact ? 10 : 12,
                compact ? 10 : 12,
              ),
              child: stockLoading
                  ? const Text(
                      'Checking stock...',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6A7B73),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: isOutOfStock || isQuickAddBusy
                            ? null
                            : onQuickAdd,
                        icon: isQuickAddBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isOutOfStock
                                    ? Icons.block_rounded
                                    : Icons.add_shopping_cart_rounded,
                                size: 18,
                              ),
                        label: Text(isOutOfStock ? 'Sold out' : 'Quick add'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final Color? borderColor;

  const _ProductBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 3),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCartBar extends StatelessWidget {
  final int itemCount;
  final String totalLabel;
  final VoidCallback onViewCart;

  const _MiniCartBar({
    required this.itemCount,
    required this.totalLabel,
    required this.onViewCart,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF173D36),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F102B25),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shopping_bag_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'} in cart',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Current total $totalLabel',
                      style: const TextStyle(
                        color: Color(0xFFCEE6DD),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onViewCart,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF173D36),
                ),
                child: const Text('View cart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoOverscrollScrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
