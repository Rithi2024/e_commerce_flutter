import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:marketflow/core/pricing/event_deal_pricing.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/config/routes/app_routes.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/presentation/widgets/event_deal_chip.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:marketflow/core/widgets/favorite_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';

enum _WishlistViewFilter { all, eventDeals, bestSellers, newArrivals }

enum _WishlistSortOption {
  newest,
  priceLowToHigh,
  priceHighToLow,
  biggestSavings,
}

class WishlistOverviewScreen extends StatefulWidget {
  const WishlistOverviewScreen({super.key});

  @override
  State<WishlistOverviewScreen> createState() => _WishlistOverviewScreenState();
}

class _WishlistOverviewScreenState extends State<WishlistOverviewScreen> {
  Map<String, dynamic>? _activeEvent;
  Duration? _remainingEvent;
  Timer? _eventTicker;
  final Set<String> _addingProductIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _WishlistViewFilter _activeFilter = _WishlistViewFilter.all;
  _WishlistSortOption _sortOption = _WishlistSortOption.newest;
  bool _addingMatchedDeals = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final auth = context.read<AuthenticationProvider>();
    final products = context.read<ProductCatalogProvider>();
    final wishlist = context.read<UserWishlistProvider>();
    final user = auth.user;

    if (user == null) {
      wishlist.clear();
      return;
    }

    final tasks = <Future<void>>[wishlist.load(), _loadActiveEvent()];
    if (products.all.isEmpty && !products.loading) {
      tasks.add(products.fetchProducts());
    }
    try {
      await Future.wait(tasks);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to refresh favorites')),
      );
    }
  }

  @override
  void dispose() {
    _eventTicker?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _parseEventStart(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  DateTime? _parseEventExpiry(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  bool _eventFlag(dynamic value) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 't' || text == 'yes';
  }

  String _eventState(Map<String, dynamic>? event) {
    if (event == null) return 'inactive';
    final providedState = (event['event_state'] ?? '').toString().trim();
    if (providedState.isNotEmpty) return providedState;

    if (!_eventFlag(event['is_active'])) return 'inactive';
    final now = DateTime.now().toUtc();
    final startsAt = _parseEventStart(event['starts_at']) ?? now;
    final expiresAt = _parseEventExpiry(event['expires_at']);
    if (expiresAt == null || !expiresAt.isAfter(now)) return 'expired';
    if (startsAt.isAfter(now)) return 'upcoming';
    return 'active';
  }

  String _formatEventRemaining(Duration value) {
    if (value.inDays > 0) {
      final hours = value.inHours.remainder(24);
      return '${value.inDays}d ${hours}h';
    }
    if (value.inHours > 0) {
      return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
    }
    final minutes = value.inMinutes;
    if (minutes > 0) {
      return '${minutes}m';
    }
    return '${value.inSeconds.clamp(0, 59)}s';
  }

  String? _eventTimingLabel() {
    final event = _activeEvent;
    final remaining = _remainingEvent;
    if (event == null || remaining == null) return null;
    switch (_eventState(event)) {
      case 'upcoming':
        return 'Starts in ${_formatEventRemaining(remaining)}';
      case 'active':
        return 'Ends in ${_formatEventRemaining(remaining)}';
      default:
        return null;
    }
  }

  void _startEventTicker() {
    _eventTicker?.cancel();
    final event = _activeEvent;
    if (event == null) {
      _remainingEvent = null;
      return;
    }

    final startsAt = _parseEventStart(event['starts_at']);
    final expiresAt = _parseEventExpiry(event['expires_at']);
    if (expiresAt == null) {
      _remainingEvent = null;
      return;
    }

    void tick() {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      if (!expiresAt.isAfter(now)) {
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
          : expiresAt.difference(now);
      final eventId = (event['id'] ?? '').toString().trim();
      context.read<AppSettingsProvider>().setActiveEventId(
        nextState == 'active' ? eventId : null,
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
      final event = await context
          .read<ProductCatalogProvider>()
          .fetchActiveEvent();
      if (!mounted) return;
      final nextEvent = event == null ? null : Map<String, dynamic>.from(event);
      final nextState = _eventState(nextEvent);
      final eventId = (nextEvent?['id'] ?? '').toString().trim();
      context.read<AppSettingsProvider>().setActiveEventId(
        nextState == 'active' ? eventId : null,
      );
      setState(() {
        _activeEvent = nextEvent;
      });
      _startEventTicker();
    } catch (_) {
      if (!mounted) return;
      _eventTicker?.cancel();
      context.read<AppSettingsProvider>().setActiveEventId(null);
      setState(() {
        _activeEvent = null;
        _remainingEvent = null;
      });
    }
  }

  EventProductDiscount? _resolvedEventDiscount(
    Product product,
    AppSettingsProvider settings,
  ) {
    final activeEvent = _activeEvent;
    if (activeEvent != null && _eventState(activeEvent) == 'active') {
      final eventId = (activeEvent['id'] ?? '').toString().trim();
      if (eventId.isNotEmpty) {
        final mapped = settings.findEventDiscount(
          eventId: eventId,
          productId: product.id,
        );
        if (mapped != null && mapped.discountPercent > 0) {
          return mapped;
        }
      }
    }
    final activeDiscount = settings.activeDiscountForProduct(
      productId: product.id,
    );
    if (activeDiscount != null) {
      return activeDiscount;
    }
    final discounts = settings.discountsForProduct(product.id);
    if (discounts.isEmpty) {
      return null;
    }
    return discounts.first;
  }

  EventDealPricing? _eventPricingForProduct(
    Product product,
    EventProductDiscount eventDiscount,
    AppSettingsProvider settings,
  ) {
    return resolveEventDealPricing(
      eventTitle: eventDiscount.eventTitle,
      discountPercent: eventDiscount.discountPercent,
      discountedUnitUsd: settings.applyDiscountUsd(
        product.price,
        discountPercent: eventDiscount.discountPercent,
      ),
      quantity: 1,
    );
  }

  String _formatDiscountPercent(double value) {
    if (value <= 0) {
      return '0';
    }
    final rounded = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return rounded;
  }

  String _normalizeSearchQuery(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _updateSearchQuery(String raw) {
    final normalized = _normalizeSearchQuery(raw);
    if (_searchQuery == normalized) {
      return;
    }
    setState(() => _searchQuery = normalized);
  }

  bool _matchesSearch(Product product, String query) {
    if (query.isEmpty) {
      return true;
    }
    final normalized = query.toLowerCase();
    final haystacks = <String>[
      product.name,
      product.category ?? '',
      product.description,
    ];
    return haystacks.any(
      (value) => value.toLowerCase().contains(normalized),
    );
  }

  double _discountPercentForProduct(
    Product product,
    Map<String, EventProductDiscount> eventDiscountByProductId,
  ) {
    return eventDiscountByProductId[product.id]?.discountPercent ?? 0;
  }

  double _effectivePriceUsd(
    Product product,
    AppSettingsProvider settings, {
    required Map<String, EventProductDiscount> eventDiscountByProductId,
  }) {
    return settings.applyDiscountUsd(
      product.price,
      discountPercent: _discountPercentForProduct(
        product,
        eventDiscountByProductId,
      ),
    );
  }

  bool _matchesFilter(
    Product product,
    ProductCatalogProvider catalog, {
    required Map<String, EventProductDiscount> eventDiscountByProductId,
  }) {
    switch (_activeFilter) {
      case _WishlistViewFilter.all:
        return true;
      case _WishlistViewFilter.eventDeals:
        return eventDiscountByProductId.containsKey(product.id);
      case _WishlistViewFilter.bestSellers:
        return catalog.isBestSeller(product.id);
      case _WishlistViewFilter.newArrivals:
        return catalog.isNewArrival(product);
    }
  }

  List<Product> _visibleItems(
    List<Product> items,
    ProductCatalogProvider catalog,
    AppSettingsProvider settings, {
    required Map<String, EventProductDiscount> eventDiscountByProductId,
  }) {
    final visible = items
        .where(
          (product) =>
              _matchesSearch(product, _searchQuery) &&
              _matchesFilter(
                product,
                catalog,
                eventDiscountByProductId: eventDiscountByProductId,
              ),
        )
        .toList();

    switch (_sortOption) {
      case _WishlistSortOption.newest:
        visible.sort((a, b) {
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
      case _WishlistSortOption.priceLowToHigh:
        visible.sort((a, b) {
          final aPrice = _effectivePriceUsd(
            a,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final bPrice = _effectivePriceUsd(
            b,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final priceCompare = aPrice.compareTo(bPrice);
          if (priceCompare != 0) {
            return priceCompare;
          }
          return a.name.compareTo(b.name);
        });
        break;
      case _WishlistSortOption.priceHighToLow:
        visible.sort((a, b) {
          final aPrice = _effectivePriceUsd(
            a,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final bPrice = _effectivePriceUsd(
            b,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final priceCompare = bPrice.compareTo(aPrice);
          if (priceCompare != 0) {
            return priceCompare;
          }
          return a.name.compareTo(b.name);
        });
        break;
      case _WishlistSortOption.biggestSavings:
        visible.sort((a, b) {
          final aDiscount = _discountPercentForProduct(
            a,
            eventDiscountByProductId,
          );
          final bDiscount = _discountPercentForProduct(
            b,
            eventDiscountByProductId,
          );
          final discountCompare = bDiscount.compareTo(aDiscount);
          if (discountCompare != 0) {
            return discountCompare;
          }
          final aSavings = a.price - _effectivePriceUsd(
            a,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final bSavings = b.price - _effectivePriceUsd(
            b,
            settings,
            eventDiscountByProductId: eventDiscountByProductId,
          );
          final savingsCompare = bSavings.compareTo(aSavings);
          if (savingsCompare != 0) {
            return savingsCompare;
          }
          final aCreated =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bCreated =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bCreated.compareTo(aCreated);
        });
        break;
    }

    return visible;
  }

  void _showWishlistMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _wishlistActionError(Object error, String fallbackMessage) {
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
    Product product, {
    double? discountPercent,
  }) {
    final resolvedDiscount =
        discountPercent ??
        settings.discountPercentForProduct(productId: product.id);
    final discountedUsd = settings.applyDiscountUsd(
      product.price,
      discountPercent: resolvedDiscount,
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

  Future<bool> _addProductToCart(
    Product product, {
    double? discountPercent,
  }) async {
    final catalog = context.read<ProductCatalogProvider>();
    final settings = context.read<AppSettingsProvider>();
    final cart = context.read<ShoppingCartProvider>();
    final variant = await catalog.resolveQuickAddVariant(product.id);
    if (!mounted) {
      return false;
    }
    if (variant == null) {
      return false;
    }

    await cart.addToCart(
      product: _discountedProductForCart(
        settings,
        product,
        discountPercent: discountPercent,
      ),
      size: variant.size,
      color: variant.color,
      quantity: 1,
    );
    return true;
  }

  Future<void> _handleQuickAdd(Product product) async {
    final productId = product.id.trim();
    if (_addingProductIds.contains(productId)) {
      return;
    }

    setState(() => _addingProductIds.add(productId));
    try {
      final added = await _addProductToCart(product);
      if (!mounted) {
        return;
      }
      if (!added) {
        _showWishlistMessage('This product is currently out of stock.');
        return;
      }
      _showWishlistMessage('${product.name} added to cart.');
    } catch (error) {
      _showWishlistMessage(
        _wishlistActionError(error, 'Could not add item to cart.'),
      );
    } finally {
      if (mounted) {
        setState(() => _addingProductIds.remove(productId));
      }
    }
  }

  Future<void> _handleAddMatchingDeals(
    List<Product> products, {
    required Map<String, EventProductDiscount> eventDiscountByProductId,
  }) async {
    if (_addingMatchedDeals || products.isEmpty) {
      return;
    }
    final productIds = products.map((product) => product.id.trim()).toSet();
    if (productIds.any(_addingProductIds.contains)) {
      return;
    }

    setState(() {
      _addingMatchedDeals = true;
      _addingProductIds.addAll(productIds);
    });

    var addedCount = 0;
    var skippedCount = 0;
    try {
      for (final product in products) {
        final added = await _addProductToCart(
          product,
          discountPercent: eventDiscountByProductId[product.id]?.discountPercent,
        );
        if (!mounted) {
          return;
        }
        if (added) {
          addedCount += 1;
        } else {
          skippedCount += 1;
        }
      }

      if (!mounted) {
        return;
      }
      if (addedCount == 0) {
        _showWishlistMessage('Matched deal items are currently out of stock.');
      } else if (skippedCount == 0) {
        final noun = addedCount == 1 ? 'item' : 'items';
        _showWishlistMessage('$addedCount matched $noun added to cart.');
      } else {
        final addedNoun = addedCount == 1 ? 'item' : 'items';
        final skippedNoun = skippedCount == 1 ? 'item' : 'items';
        _showWishlistMessage(
          '$addedCount $addedNoun added to cart. $skippedCount $skippedNoun skipped because they are out of stock.',
        );
      }
    } catch (error) {
      _showWishlistMessage(
        _wishlistActionError(error, 'Could not add matched deal items to cart.'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingMatchedDeals = false;
          _addingProductIds.removeAll(productIds);
        });
      }
    }
  }

  String _filterLabel(_WishlistViewFilter filter) {
    switch (filter) {
      case _WishlistViewFilter.all:
        return 'All';
      case _WishlistViewFilter.eventDeals:
        return 'Deals';
      case _WishlistViewFilter.bestSellers:
        return 'Best sellers';
      case _WishlistViewFilter.newArrivals:
        return 'New arrivals';
    }
  }

  String _sortLabel(_WishlistSortOption option) {
    switch (option) {
      case _WishlistSortOption.newest:
        return 'Newest';
      case _WishlistSortOption.priceLowToHigh:
        return 'Price: Low to high';
      case _WishlistSortOption.priceHighToLow:
        return 'Price: High to low';
      case _WishlistSortOption.biggestSavings:
        return 'Biggest savings';
    }
  }

  Future<void> _toggleFavorite(Product product) async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    if (user == null) return;

    try {
      await context.read<UserWishlistProvider>().toggle(product.id);
      if (!mounted) return;
      _showWishlistMessage('"${product.name}" updated in favorites');
    } catch (_) {
      if (!mounted) return;
      _showWishlistMessage('Failed to update favorites');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthenticationProvider>();
    final products = context.watch<ProductCatalogProvider>();
    final wishlist = context.watch<UserWishlistProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useWebLayout = kIsWeb && screenWidth >= 980;
    final compactLayout = screenWidth < 420;
    final user = auth.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to use favorites')),
      );
    }

    final items = products.all
        .where((p) => wishlist.ids.contains(p.id))
        .toList();
    final eventDiscountByProductId = <String, EventProductDiscount>{};
    final eventDealLines = <EventDealPricing>[];
    double maxDiscountPercent = 0;
    for (final item in items) {
      final discount = _resolvedEventDiscount(item, settings);
      if (discount == null) {
        continue;
      }
      eventDiscountByProductId[item.id] = discount;
      if (discount.discountPercent > maxDiscountPercent) {
        maxDiscountPercent = discount.discountPercent;
      }
      final pricing = _eventPricingForProduct(item, discount, settings);
      if (pricing != null) {
        eventDealLines.add(pricing);
      }
    }
    final eventItems = items
        .where((product) => eventDiscountByProductId.containsKey(product.id))
        .toList();
    final eventSummary = summarizeEventDealPricing(eventDealLines);
    final visibleItems = _visibleItems(
      items,
      products,
      settings,
      eventDiscountByProductId: eventDiscountByProductId,
    );
    final bestSellerCount = items
        .where((product) => products.isBestSeller(product.id))
        .length;
    final newArrivalCount = items
        .where((product) => products.isNewArrival(product))
        .length;
    final initialLoading =
        (wishlist.loading && wishlist.ids.isEmpty) ||
        (products.loading && products.all.isEmpty);
    final showingFilteredEmptyState =
        items.isNotEmpty && visibleItems.isEmpty && !initialLoading;
    final eventTitle = ((_activeEvent?['title'] ?? '').toString().trim())
            .isNotEmpty
        ? (_activeEvent?['title'] ?? '').toString().trim()
        : (eventItems.isNotEmpty
              ? (_resolvedEventDiscount(eventItems.first, settings)?.eventTitle ??
                    'Event')
              : 'Event');

    final content = initialLoading
        ? const Center(child: CircularProgressIndicator())
        : wishlist.error != null && items.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wishlist.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refreshData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (items.isEmpty)
                  const _WishlistEmptyStatePanel()
                else ...[
                  _WishlistControlsPanel(
                    searchController: _searchController,
                    searchQuery: _searchQuery,
                    activeFilter: _activeFilter,
                    activeSortLabel: _sortLabel(_sortOption),
                    totalItems: items.length,
                    visibleItems: visibleItems.length,
                    dealItems: eventItems.length,
                    bestSellerItems: bestSellerCount,
                    newArrivalItems: newArrivalCount,
                    filterLabelBuilder: _filterLabel,
                    onSearchChanged: _updateSearchQuery,
                    onClearSearch: () {
                      _searchController.clear();
                      _updateSearchQuery('');
                    },
                    onSelectFilter: (filter) =>
                        setState(() => _activeFilter = filter),
                    onSelectSort: (sortOption) =>
                        setState(() => _sortOption = sortOption),
                  ),
                  if (eventItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    WishlistEventSummaryCard(
                      eventTitle: eventTitle,
                      matchingItemCount: eventItems.length,
                      totalSavingsLabel: eventSummary.hasDeals
                          ? settings.formatUsd(
                              eventSummary.totalSavingsUsd,
                              overrideDiscountPercent: 0,
                            )
                          : null,
                      maxDiscountLabel: maxDiscountPercent > 0
                          ? 'Up to ${_formatDiscountPercent(maxDiscountPercent)}% off'
                          : null,
                      timingLabel: _eventTimingLabel(),
                      addMatchesBusy: _addingMatchedDeals,
                      onShopEvent: () => Navigator.of(context).pushNamed(
                        AppRoutes.catalogRoute(
                          collection: CatalogCollectionFilter.eventDeals.slug,
                        ),
                      ),
                      onAddMatches: () => _handleAddMatchingDeals(
                        eventItems,
                        eventDiscountByProductId: eventDiscountByProductId,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (showingFilteredEmptyState)
                    _WishlistFilteredEmptyState(
                      hasQuery: _searchQuery.isNotEmpty,
                      activeFilterLabel: _filterLabel(_activeFilter),
                      onResetFilters: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _activeFilter = _WishlistViewFilter.all;
                          _sortOption = _WishlistSortOption.newest;
                        });
                      },
                    )
                  else
                    ...[
                      for (var i = 0; i < visibleItems.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final item = visibleItems[i];
                            final eventDiscount =
                                eventDiscountByProductId[item.id];
                            final discountPercent =
                                eventDiscount?.discountPercent ?? 0;
                            final timingLabel =
                                eventDiscount != null &&
                                    (_activeEvent?['id'] ?? '')
                                            .toString()
                                            .trim() ==
                                        eventDiscount.eventId
                                ? _eventTimingLabel()
                                : null;
                            final discountedPrice = settings.formatUsd(
                              item.price,
                              productId: item.id,
                              overrideDiscountPercent: discountPercent,
                            );
                            final originalPrice = settings.formatUsd(
                              item.price,
                              overrideDiscountPercent: 0,
                            );
                            final savingsLabel = eventDiscount == null
                                ? null
                                : settings.formatUsd(
                                    item.price -
                                        settings.applyDiscountUsd(
                                          item.price,
                                          discountPercent: discountPercent,
                                        ),
                                    overrideDiscountPercent: 0,
                                  );
                            final routeCollection = eventDiscount != null
                                ? CatalogCollectionFilter.eventDeals.slug
                                : null;
                            return _WishlistProductCard(
                              key: ValueKey<String>(
                                'wishlist-product-card-${item.id}',
                              ),
                              product: item,
                              discountedPrice: discountedPrice,
                              originalPrice: originalPrice,
                              savingsLabel: savingsLabel,
                              timingLabel: timingLabel,
                              eventDiscount: eventDiscount,
                              isBestSeller: products.isBestSeller(item.id),
                              isNewArrival: products.isNewArrival(item),
                              isAddingToCart: _addingProductIds.contains(
                                item.id,
                              ),
                              onOpenDetails: () => Navigator.of(context)
                                  .pushNamed(
                                    AppRoutes.catalogRoute(
                                      productKey: item.slug,
                                      collection: routeCollection,
                                    ),
                                  ),
                              onQuickAdd: () => _handleQuickAdd(item),
                              onRemoveFavorite: () => _toggleFavorite(item),
                            );
                          },
                        ),
                        if (i != visibleItems.length - 1)
                          const SizedBox(height: 10),
                      ],
                    ],
                ],
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          'Favorites',
          style: TextStyle(fontSize: compactLayout ? 22 : 28),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh favorites',
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: useWebLayout
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: content,
              ),
            )
          : content,
    );
  }
}

class _WishlistControlsPanel extends StatelessWidget {
  const _WishlistControlsPanel({
    required this.searchController,
    required this.searchQuery,
    required this.activeFilter,
    required this.activeSortLabel,
    required this.totalItems,
    required this.visibleItems,
    required this.dealItems,
    required this.bestSellerItems,
    required this.newArrivalItems,
    required this.filterLabelBuilder,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSelectFilter,
    required this.onSelectSort,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final _WishlistViewFilter activeFilter;
  final String activeSortLabel;
  final int totalItems;
  final int visibleItems;
  final int dealItems;
  final int bestSellerItems;
  final int newArrivalItems;
  final String Function(_WishlistViewFilter) filterLabelBuilder;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_WishlistViewFilter> onSelectFilter;
  final ValueChanged<_WishlistSortOption> onSelectSort;

  String _sortLabel(_WishlistSortOption option) {
    switch (option) {
      case _WishlistSortOption.newest:
        return 'Newest';
      case _WishlistSortOption.priceLowToHigh:
        return 'Price: Low to high';
      case _WishlistSortOption.priceHighToLow:
        return 'Price: High to low';
      case _WishlistSortOption.biggestSavings:
        return 'Biggest savings';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FBF9), Color(0xFFEAF4F0)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD5E6DE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saved picks',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF173D36),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Search favorites, spot live deals, and move ready items into the cart faster.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Color(0xFF5B716B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<_WishlistSortOption>(
                  tooltip: 'Sort favorites',
                  onSelected: onSelectSort,
                  itemBuilder: (context) => _WishlistSortOption.values
                      .map(
                        (option) => PopupMenuItem<_WishlistSortOption>(
                          value: option,
                          child: Text(_sortLabel(option)),
                        ),
                      )
                      .toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD5E6DE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.swap_vert_rounded,
                          size: 18,
                          color: Color(0xFF1C4A40),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          activeSortLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF173D36),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey<String>('wishlist-search-field'),
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search favorites',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFD5E6DE)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: Color(0xFFD5E6DE)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(
                    color: Color(0xFF2F6B5D),
                    width: 1.4,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WishlistStatChip(label: 'Saved', value: '$totalItems'),
                _WishlistStatChip(label: 'Showing', value: '$visibleItems'),
                _WishlistStatChip(label: 'Deals', value: '$dealItems'),
                _WishlistStatChip(
                  label: 'Best sellers',
                  value: '$bestSellerItems',
                ),
                _WishlistStatChip(
                  label: 'New arrivals',
                  value: '$newArrivalItems',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _WishlistViewFilter.values
                  .map(
                    (filter) => ChoiceChip(
                      label: Text(filterLabelBuilder(filter)),
                      selected: filter == activeFilter,
                      onSelected: (_) => onSelectFilter(filter),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WishlistStatChip extends StatelessWidget {
  const _WishlistStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E6DE)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF173D36),
              ),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF62756F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WishlistEmptyStatePanel extends StatelessWidget {
  const _WishlistEmptyStatePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FBF9), Color(0xFFEAF4F0)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD5E6DE)),
      ),
      child: const Column(
        children: [
          FavoriteIcon(isFavorite: false, size: 64),
          SizedBox(height: 14),
          Text(
            'Your favorites are empty',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D36),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Save products from the catalog to keep event deals and quick adds close by.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF5B716B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistFilteredEmptyState extends StatelessWidget {
  const _WishlistFilteredEmptyState({
    required this.hasQuery,
    required this.activeFilterLabel,
    required this.onResetFilters,
  });

  final bool hasQuery;
  final String activeFilterLabel;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final message = hasQuery
        ? 'No saved items match your current search.'
        : activeFilterLabel == 'All'
        ? 'No favorites are visible right now.'
        : 'No saved items match the "$activeFilterLabel" filter.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE7E2)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.manage_search_rounded,
            size: 34,
            color: Color(0xFF2A685A),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF173D36),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try another search or reset the current filter set.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: Color(0xFF62756F),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onResetFilters,
            child: const Text('Reset filters'),
          ),
        ],
      ),
    );
  }
}

class _WishlistProductCard extends StatelessWidget {
  const _WishlistProductCard({
    super.key,
    required this.product,
    required this.discountedPrice,
    required this.originalPrice,
    required this.savingsLabel,
    required this.timingLabel,
    required this.eventDiscount,
    required this.isBestSeller,
    required this.isNewArrival,
    required this.isAddingToCart,
    required this.onOpenDetails,
    required this.onQuickAdd,
    required this.onRemoveFavorite,
  });

  final Product product;
  final String discountedPrice;
  final String originalPrice;
  final String? savingsLabel;
  final String? timingLabel;
  final EventProductDiscount? eventDiscount;
  final bool isBestSeller;
  final bool isNewArrival;
  final bool isAddingToCart;
  final VoidCallback onOpenDetails;
  final VoidCallback onQuickAdd;
  final VoidCallback onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    final category = (product.category ?? '').trim();
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpenDetails,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE7E2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12172F28),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 88,
                  height: 96,
                  child: product.imageUrl.isEmpty
                      ? Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF4F8F6), Color(0xFFE7EFEB)],
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_outlined,
                            color: Color(0xFF90A19A),
                            size: 28,
                          ),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF4F8F6), Color(0xFFE7EFEB)],
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.network(
                            product.imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Color(0xFF90A19A),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF173D36),
                      ),
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF61756E),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (eventDiscount != null)
                          EventDealChip(
                            eventTitle: eventDiscount!.eventTitle,
                            backgroundColor: const Color(0xFFE9F5F0),
                            foregroundColor: const Color(0xFF173D36),
                            borderColor: const Color(0xFFD6E6DF),
                            fontSize: 10.5,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                          ),
                        if (isBestSeller)
                          const _WishlistInlineBadge(
                            icon: Icons.trending_up_rounded,
                            label: 'Best seller',
                            background: Color(0xFFFFF4DE),
                            foreground: Color(0xFF8C5C12),
                            borderColor: Color(0xFFF0D8A5),
                          ),
                        if (isNewArrival)
                          const _WishlistInlineBadge(
                            icon: Icons.fiber_new_rounded,
                            label: 'New',
                            background: Color(0xFFEFF7F3),
                            foreground: Color(0xFF1E5D4E),
                            borderColor: Color(0xFFD6E6DF),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          discountedPrice,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111111),
                            fontSize: 15,
                          ),
                        ),
                        if (eventDiscount != null)
                          Text(
                            originalPrice,
                            style: const TextStyle(
                              color: Color(0xFF7F8B87),
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if ((savingsLabel ?? '').trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE8EE),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Save $savingsLabel',
                              style: const TextStyle(
                                color: Color(0xFFB62B53),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if ((timingLabel ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        timingLabel!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C4A40),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: isAddingToCart ? null : onQuickAdd,
                          icon: Icon(
                            isAddingToCart
                                ? Icons.hourglass_top_rounded
                                : Icons.add_shopping_cart_outlined,
                            size: 18,
                          ),
                          label: Text(
                            isAddingToCart ? 'Adding...' : 'Quick add',
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FavoriteIconButton(
                          tooltip: 'Remove from favorites',
                          onPressed: onRemoveFavorite,
                          isFavorite: true,
                          size: 18,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          splashRadius: 16,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
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

class _WishlistInlineBadge extends StatelessWidget {
  const _WishlistInlineBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class WishlistEventSummaryCard extends StatelessWidget {
  const WishlistEventSummaryCard({
    super.key,
    required this.eventTitle,
    required this.matchingItemCount,
    required this.onShopEvent,
    required this.onAddMatches,
    this.timingLabel,
    this.totalSavingsLabel,
    this.maxDiscountLabel,
    this.addMatchesBusy = false,
  });

  final String eventTitle;
  final int matchingItemCount;
  final String? timingLabel;
  final String? totalSavingsLabel;
  final String? maxDiscountLabel;
  final VoidCallback onShopEvent;
  final VoidCallback onAddMatches;
  final bool addMatchesBusy;

  @override
  Widget build(BuildContext context) {
    final safeTimingLabel = (timingLabel ?? '').trim();
    final safeSavingsLabel = (totalSavingsLabel ?? '').trim();
    final safeMaxDiscountLabel = (maxDiscountLabel ?? '').trim();
    final itemLabel = matchingItemCount == 1 ? 'favorite' : 'favorites';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD2E8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EventDealChip(
            eventTitle: eventTitle,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF173D36),
            borderColor: const Color(0xFFD6E6DF),
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          const SizedBox(height: 10),
          Text(
            '$matchingItemCount saved $itemLabel match this live event.',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF173D36),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            safeTimingLabel.isEmpty
                ? 'Open the event collection to compare all live deal picks.'
                : '$safeTimingLabel. Open the event collection to compare all live deal picks.',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF557168),
              height: 1.35,
            ),
          ),
          if (safeSavingsLabel.isNotEmpty ||
              safeMaxDiscountLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (safeSavingsLabel.isNotEmpty)
                  _WishlistEventMetaChip(
                    icon: Icons.savings_outlined,
                    label: 'Save $safeSavingsLabel',
                  ),
                if (safeMaxDiscountLabel.isNotEmpty)
                  _WishlistEventMetaChip(
                    icon: Icons.trending_down_outlined,
                    label: safeMaxDiscountLabel,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: addMatchesBusy ? null : onAddMatches,
                icon: Icon(
                  addMatchesBusy
                      ? Icons.hourglass_top_rounded
                      : Icons.add_shopping_cart_rounded,
                  size: 18,
                ),
                label: Text(
                  addMatchesBusy ? 'Adding...' : 'Add matches',
                ),
              ),
              OutlinedButton.icon(
                onPressed: onShopEvent,
                icon: const Icon(Icons.local_offer_outlined, size: 18),
                label: const Text('Shop event deals'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WishlistEventMetaChip extends StatelessWidget {
  const _WishlistEventMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD2E8DF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1F5A4D)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF173D36),
            ),
          ),
        ],
      ),
    );
  }
}
