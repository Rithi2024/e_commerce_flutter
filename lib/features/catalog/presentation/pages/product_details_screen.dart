import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/config/routes/app_routes.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/presentation/helpers/product_review_content.dart';
import 'package:marketflow/features/catalog/presentation/helpers/product_share_content.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marketflow/core/widgets/favorite_icon_button.dart';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/cart/presentation/widgets/add_to_cart_prompt.dart';
import 'package:marketflow/features/cart/presentation/pages/shopping_cart_screen.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;
  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  static const List<String> _sizes = ['S', 'M', 'L', 'XL'];
  static const Map<String, Color> _colors = {
    'Black': Color(0xFF1F1F1F),
    'White': Color(0xFFF5F5F5),
    'Blue': Color(0xFF2862E9),
    'Red': Color(0xFFE43F3F),
  };

  String size = "M";
  String colorName = "Black";
  int quantity = 1;
  bool _loadingStock = true;
  Map<String, int> _variantStock = {};
  bool _loadingRating = true;
  bool _submittingRating = false;
  bool _canRateProduct = false;
  bool _ratingFeatureAvailable = true;
  int _ratingCount = 0;
  double _avgRating = 0;
  int? _myRating;
  String _myReview = '';
  ProductRatingBreakdown _ratingBreakdown = const ProductRatingBreakdown();
  List<ProductReviewEntry> _reviewEntries = const <ProductReviewEntry>[];
  bool _showAllReviews = false;
  ProductReviewSortOption _reviewSortOption = ProductReviewSortOption.recent;
  int? _selectedReviewRating;
  bool _onlyMyReviews = false;
  SupabaseDataProxy? _dataProxy;

  @override
  void initState() {
    super.initState();
    try {
      _dataProxy = SupabaseDataProxy(db: Supabase.instance.client);
    } catch (_) {
      _dataProxy = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductCatalogProvider>().recordRecentlyViewed(
        widget.product,
      );
    });
    Future.microtask(() async {
      await Future.wait([_loadVariantStock(), _loadRatingState()]);
    });
  }

  String _variantKey(String s, String c) => '$s::$c';

  int _stockFor(String s, String c) {
    return _variantStock[_variantKey(s, c)] ?? 0;
  }

  bool _sizeEnabled(String s) {
    if (_variantStock.isEmpty) return true;
    return _colors.keys.any((color) => _stockFor(s, color) > 0);
  }

  bool _colorEnabledForSelectedSize(String c) {
    if (_variantStock.isEmpty) return true;
    return _stockFor(size, c) > 0;
  }

  int get _selectedStock => _stockFor(size, colorName);
  bool get _selectedVariantOutOfStock =>
      _variantStock.isNotEmpty && _selectedStock <= 0;

  int get _maxQty {
    if (_variantStock.isEmpty) return 99;
    if (_selectedStock <= 0) return 1;
    return _selectedStock.clamp(1, 99);
  }

  void _syncQuantityWithSelection() {
    quantity = quantity.clamp(1, _maxQty);
  }

  Future<void> _loadVariantStock() async {
    try {
      final loaded = await context
          .read<ProductCatalogProvider>()
          .fetchVariantStocks(widget.product.id);

      if (!mounted) return;
      setState(() {
        _variantStock = loaded;
        _loadingStock = false;
        _syncQuantityWithSelection();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _variantStock = {};
        _loadingStock = false;
      });
    }
  }

  bool _isMissingRatingTable(PostgrestException error) {
    final code = (error.code ?? '').trim().toUpperCase();
    final message = error.message.toLowerCase();
    return code == '42P01' ||
        message.contains('product_ratings') ||
        message.contains('relation') && message.contains('does not exist');
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Map<String, dynamic>> _extractOrderItems(dynamic rawItems) {
    if (rawItems is List<dynamic>) {
      return rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  bool _hasPurchasedProduct(
    List<Map<String, dynamic>> orders,
    String productId,
  ) {
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'cancelled') continue;
      final items = _extractOrderItems(order['items']);
      for (final item in items) {
        final itemProductId = (item['productId'] ?? item['product_id'] ?? '')
            .toString()
            .trim();
        if (itemProductId == productId) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _loadRatingState() async {
    final dataProxy = _dataProxy;
    if (dataProxy == null) {
      if (!mounted) return;
      setState(() {
        _ratingFeatureAvailable = false;
        _ratingCount = 0;
        _avgRating = 0;
        _myRating = null;
        _myReview = '';
        _ratingBreakdown = const ProductRatingBreakdown();
        _reviewEntries = const <ProductReviewEntry>[];
        _showAllReviews = false;
        _canRateProduct = false;
        _loadingRating = false;
      });
      return;
    }

    final productId = widget.product.id;
    final userId = context.read<AuthenticationProvider>().user?.id;

    var ratingFeatureAvailable = true;
    var ratingCount = 0;
    var averageRating = 0.0;
    int? myRating;
    var myReview = '';
    var ratingBreakdown = const ProductRatingBreakdown();
    var reviewEntries = const <ProductReviewEntry>[];
    var canRateProduct = false;

    try {
      final rows = List<Map<String, dynamic>>.from(
        await dataProxy.select(
          table: 'product_ratings',
          columns: 'user_id,rating,review,updated_at',
          filters: <DataProxyFilter>[
            DataProxyFilter.eq('product_id', productId),
          ],
          orders: const <DataProxyOrder>[
            DataProxyOrder('updated_at', ascending: false, nullsFirst: false),
          ],
        ),
      );

      final ratings = rows
          .map((row) => _toInt(row['rating']))
          .where((value) => value >= 1 && value <= 5)
          .toList();
      ratingCount = ratings.length;
      if (ratings.isNotEmpty) {
        final total = ratings.fold<int>(0, (sum, value) => sum + value);
        averageRating = total / ratings.length;
      }

      ratingBreakdown = buildProductRatingBreakdown(rows);
      reviewEntries = buildProductReviewEntries(
        rows: rows,
        currentUserId: userId,
      );

      if (userId != null) {
        for (final row in rows) {
          final reviewUserId = (row['user_id'] ?? '').toString().trim();
          if (reviewUserId != userId) {
            continue;
          }
          final value = _toInt(row['rating'], fallback: 0);
          if (value >= 1 && value <= 5) {
            myRating = value;
          }
          myReview = (row['review'] ?? '').toString();
          break;
        }
      }
    } on PostgrestException catch (error) {
      if (_isMissingRatingTable(error)) {
        ratingFeatureAvailable = false;
      }
    } catch (_) {}

    if (userId != null && ratingFeatureAvailable) {
      try {
        final orderRows = await dataProxy.select(
          table: 'orders',
          columns: 'status,items',
          filters: <DataProxyFilter>[DataProxyFilter.eq('user_id', userId)],
        );
        canRateProduct = _hasPurchasedProduct(
          List<Map<String, dynamic>>.from(orderRows),
          productId,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _ratingFeatureAvailable = ratingFeatureAvailable;
      _ratingCount = ratingCount;
      _avgRating = averageRating;
      _myRating = myRating;
      _myReview = myReview;
      _ratingBreakdown = ratingBreakdown;
      _reviewEntries = reviewEntries;
      _showAllReviews = _showAllReviews && reviewEntries.length > 3;
      _canRateProduct = canRateProduct;
      _loadingRating = false;
    });
  }

  Future<void> _submitRating({
    required int rating,
    required String review,
  }) async {
    final userId = context.read<AuthenticationProvider>().user?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to rate products')),
      );
      return;
    }
    if (!_canRateProduct) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can rate only products you bought')),
      );
      return;
    }
    final dataProxy = _dataProxy;
    if (dataProxy == null) {
      return;
    }

    setState(() => _submittingRating = true);
    try {
      await dataProxy.upsert(
        table: 'product_ratings',
        values: <String, dynamic>{
          'user_id': userId,
          'product_id': widget.product.id,
          'rating': rating.clamp(1, 5),
          'review': review.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,product_id',
      );

      if (!mounted) return;
      await _loadRatingState();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for your rating')));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      final message = _isMissingRatingTable(error)
          ? 'Ratings are not configured in database yet'
          : (error.message.isEmpty ? 'Failed to submit rating' : error.message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _submittingRating = false);
      }
    }
  }

  Future<void> _openRatingDialog() async {
    if (!_ratingFeatureAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ratings are not available right now')),
      );
      return;
    }
    int selected = (_myRating ?? 5).clamp(1, 5);
    final controller = TextEditingController(text: _myReview);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Rate this product'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(5, (index) {
                      final value = index + 1;
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          value <= selected ? Icons.star : Icons.star_border,
                          color: const Color(0xFFFFB547),
                        ),
                        onPressed: () => setDialogState(() => selected = value),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Review (optional)',
                      hintText: 'Write your experience...',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    final reviewText = controller.text;
    controller.dispose();

    if (confirmed != true) return;
    await _submitRating(rating: selected, review: reviewText);
  }

  void _changeQuantity(int delta) {
    setState(() {
      quantity = (quantity + delta).clamp(1, _maxQty).toInt();
    });
  }

  Future<void> _toggleFavorite(Product product) async {
    final user = context.read<AuthenticationProvider>().user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login to use favorites")),
      );
      return;
    }

    try {
      await context.read<UserWishlistProvider>().toggle(product.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to update favorites")),
      );
    }
  }

  Future<void> _addToCart(Product product) async {
    final user = context.read<AuthenticationProvider>().user;
    final settings = context.read<AppSettingsProvider>();
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please login to add items to cart")),
      );
      return;
    }

    if (_selectedVariantOutOfStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selected size/color is out of stock")),
      );
      return;
    }

    final qtyToAdd = quantity.clamp(1, _maxQty);
    final discountPercent = settings.discountPercentForProduct(
      productId: product.id,
    );
    final discountedUsd = settings.applyDiscountUsd(
      product.price,
      discountPercent: discountPercent,
    );
    final cartProduct = discountedUsd == product.price
        ? product
        : Product(
            id: product.id,
            name: product.name,
            price: double.parse(discountedUsd.toStringAsFixed(2)),
            imageUrl: product.imageUrl,
            description: product.description,
            category: product.category,
            createdAt: product.createdAt,
          );
    try {
      await context.read<ShoppingCartProvider>().addToCart(
        product: cartProduct,
        size: size,
        color: colorName,
        quantity: qtyToAdd,
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final msg = e.message.isEmpty ? 'Not enough stock' : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _loadVariantStock();
      return;
    }

    if (!mounted) return;
    final unitText = qtyToAdd > 1 ? 'items' : 'item';
    final goToCart = await showAddToCartChoice(
      context,
      message: "Added $qtyToAdd $unitText ($size, $colorName) to cart",
    );
    if (!mounted || !goToCart) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShoppingCartScreen()),
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

  Future<void> _shareProduct(Product product) async {
    if (!mounted) return;
    final collectionSlug = context
        .read<ProductCatalogProvider>()
        .activeCollectionFilter
        ?.slug;
    final shareContent = buildProductShareContent(
      product: product,
      collection: collectionSlug,
    );

    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: shareContent.message,
          title: product.name,
          subject: '${product.name} | MarketFlow',
        ),
      );
      if (result.status != ShareResultStatus.unavailable) {
        return;
      }
    } catch (_) {}

    await Clipboard.setData(ClipboardData(text: shareContent.uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product link copied to clipboard')),
    );
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final collectionSlug = context
        .read<ProductCatalogProvider>()
        .activeCollectionFilter
        ?.slug;
    navigator.pushReplacementNamed(
      AppRoutes.catalogRoute(collection: collectionSlug),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final settings = context.watch<AppSettingsProvider>();
    final productProvider = context.watch<ProductCatalogProvider>();
    final isFavorite = context.watch<UserWishlistProvider>().isFav(p.id);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactLayout = screenWidth < 420;
    final selectedStock = _selectedStock;
    final discountPercent = settings.discountPercentForProduct(productId: p.id);
    final hasDiscount = discountPercent > 0;
    final isBestSeller = productProvider.isBestSeller(p.id);
    final topBadgeLabel = hasDiscount
        ? '${discountPercent.toStringAsFixed(0)}% OFF'
        : (isBestSeller ? 'Best Seller' : null);
    final displayUnitPrice = settings.formatUsd(
      p.price,
      productId: p.id,
      overrideDiscountPercent: discountPercent,
    );
    final originalUnitPrice = settings.formatUsd(
      p.price,
      overrideDiscountPercent: 0,
    );
    final displayTotalPrice = settings.formatUsd(
      p.price * quantity,
      productId: p.id,
      overrideDiscountPercent: discountPercent,
    );
    final recommended = productProvider.visible
        .where((item) => item.id != p.id)
        .take(6)
        .toList();
    final writtenReviewCount = _ratingBreakdown.writtenReviewCount;
    final filteredReviewEntries = filterAndSortProductReviews(
      reviews: _reviewEntries,
      sortOption: _reviewSortOption,
      exactRating: _selectedReviewRating,
      currentUserOnly: _onlyMyReviews,
    );
    final visibleReviewEntries = _showAllReviews
        ? filteredReviewEntries
        : filteredReviewEntries.take(3).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: ScrollConfiguration(
        behavior: const _NoStretchScrollBehavior(),
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: compactLayout ? 320 : 360,
              clipBehavior: Clip.hardEdge,
              backgroundColor: const Color(0xFFF6F7F9),
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 2,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _handleBackNavigation,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Share product',
                  onPressed: () => _shareProduct(p),
                  icon: const Icon(Icons.share_outlined),
                ),
                FavoriteIconButton(
                  tooltip: isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  onPressed: () => _toggleFavorite(p),
                  isFavorite: isFavorite,
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'product-image-${p.id}',
                      transitionOnUserGestures: true,
                      child: _ProductImage(imageUrl: p.imageUrl),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [Color(0x77000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    if (topBadgeLabel != null)
                      Positioned(
                        left: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            topBadgeLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1C1C1C),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if ((p.category ?? '').trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDEFF2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              p.category!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB547),
                          size: 18,
                        ),
                        Text(
                          _ratingCount > 0
                              ? _avgRating.toStringAsFixed(1)
                              : '--',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _ratingCount == 1
                              ? '(1 rating)'
                              : '($_ratingCount ratings)',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        if (writtenReviewCount > 0)
                          Text(
                            writtenReviewCount == 1
                                ? '• 1 written review'
                                : '• $writtenReviewCount written reviews',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingRating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_ratingFeatureAvailable)
                      OutlinedButton.icon(
                        onPressed: (_canRateProduct && !_submittingRating)
                            ? _openRatingDialog
                            : null,
                        icon: _submittingRating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.rate_review_outlined, size: 16),
                        label: Text(
                          _myRating == null ? 'Rate' : 'Update Rating',
                        ),
                      ),
                    if (!_loadingRating &&
                        _ratingFeatureAvailable &&
                        !_canRateProduct) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Buy this product to rate it',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_myRating != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Your rating: $_myRating/5',
                        style: const TextStyle(
                          color: Color(0xFF0B7D69),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          displayUnitPrice,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasDiscount)
                          Text(
                            originalUnitPrice,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingStock)
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Checking stock...'),
                        ],
                      )
                    else if (_variantStock.isEmpty)
                      Text(
                        'Stock updates at checkout',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        selectedStock <= 0
                            ? '$size / $colorName is out of stock'
                            : '$size / $colorName: $selectedStock in stock',
                        style: TextStyle(
                          color: selectedStock <= 0
                              ? const Color(0xFFB33030)
                              : const Color(0xFF0B7D69),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 20),

                    const _SectionTitle("Description"),
                    const SizedBox(height: 8),
                    Text(
                      p.description.isEmpty ? "No description" : p.description,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1.45,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    if (!_loadingRating && _ratingFeatureAvailable) ...[
                      const SizedBox(height: 24),
                      const _SectionTitle("Customer Reviews"),
                      const SizedBox(height: 8),
                      Text(
                        _reviewEntries.isEmpty
                            ? 'Ratings are available, but no written reviews have been shared yet.'
                            : 'Recent feedback from verified buyers, plus a live rating breakdown.',
                        style: TextStyle(
                          height: 1.45,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _RatingBreakdownCard(
                        averageRating: _avgRating,
                        ratingCount: _ratingCount,
                        writtenReviewCount: writtenReviewCount,
                        breakdown: _ratingBreakdown,
                      ),
                      const SizedBox(height: 12),
                      if (_reviewEntries.isEmpty)
                        _ReviewEmptyState(canRateProduct: _canRateProduct)
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _ReviewFilterChip(
                                      label: 'All',
                                      selected:
                                          _selectedReviewRating == null &&
                                          !_onlyMyReviews,
                                      onSelected: () {
                                        setState(() {
                                          _selectedReviewRating = null;
                                          _onlyMyReviews = false;
                                          _showAllReviews = false;
                                        });
                                      },
                                    ),
                                    _ReviewFilterChip(
                                      label: '5 stars',
                                      selected: _selectedReviewRating == 5,
                                      onSelected: () {
                                        setState(() {
                                          _selectedReviewRating =
                                              _selectedReviewRating == 5
                                              ? null
                                              : 5;
                                          _onlyMyReviews = false;
                                          _showAllReviews = false;
                                        });
                                      },
                                    ),
                                    _ReviewFilterChip(
                                      label: '4 stars',
                                      selected: _selectedReviewRating == 4,
                                      onSelected: () {
                                        setState(() {
                                          _selectedReviewRating =
                                              _selectedReviewRating == 4
                                              ? null
                                              : 4;
                                          _onlyMyReviews = false;
                                          _showAllReviews = false;
                                        });
                                      },
                                    ),
                                    if (_myRating != null)
                                      _ReviewFilterChip(
                                        label: 'Your review',
                                        selected: _onlyMyReviews,
                                        onSelected: () {
                                          setState(() {
                                            _onlyMyReviews = !_onlyMyReviews;
                                            if (_onlyMyReviews) {
                                              _selectedReviewRating = null;
                                            }
                                            _showAllReviews = false;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _ReviewSortMenu(
                              value: _reviewSortOption,
                              onSelected: (next) {
                                setState(() {
                                  _reviewSortOption = next;
                                  _showAllReviews = false;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (filteredReviewEntries.isEmpty)
                          _FilteredReviewEmptyState(
                            hasCurrentUserReview: _myRating != null,
                          )
                        else ...[
                          ...visibleReviewEntries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ReviewCard(entry: entry),
                            ),
                          ),
                          if (filteredReviewEntries.length > 3)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showAllReviews = !_showAllReviews;
                                  });
                                },
                                child: Text(
                                  _showAllReviews
                                      ? 'Show fewer reviews'
                                      : 'Show all ${filteredReviewEntries.length} reviews',
                                ),
                              ),
                            ),
                        ],
                      ],
                    ],
                    const SizedBox(height: 24),

                    const _SectionTitle("Select Size"),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _sizes.map((s) {
                        final active = s == size;
                        final enabled = _sizeEnabled(s);
                        return ChoiceChip(
                          label: Text(s),
                          selected: active,
                          onSelected: enabled
                              ? (_) {
                                  setState(() {
                                    size = s;
                                    quantity = quantity.clamp(1, _maxQty);
                                  });
                                }
                              : null,
                          selectedColor: const Color(0xFF1E1E1E),
                          labelStyle: TextStyle(
                            color: !enabled
                                ? Colors.grey.shade500
                                : active
                                ? Colors.white
                                : Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: !enabled
                                  ? Colors.grey.shade300
                                  : active
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),
                    const _SectionTitle("Select Color"),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _colors.entries.map((entry) {
                        final active = entry.key == colorName;
                        final enabled = _colorEnabledForSelectedSize(entry.key);
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: entry.value,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.grey.shade400,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(entry.key),
                            ],
                          ),
                          selected: active,
                          onSelected: enabled
                              ? (_) {
                                  setState(() {
                                    colorName = entry.key;
                                    quantity = quantity.clamp(1, _maxQty);
                                  });
                                }
                              : null,
                          selectedColor: const Color(0xFFEBEEF3),
                          labelStyle: TextStyle(
                            color: enabled
                                ? Colors.black
                                : Colors.grey.shade500,
                            fontWeight: active && enabled
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: active
                                  ? (enabled
                                        ? const Color(0xFF1E1E1E)
                                        : Colors.grey.shade300)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),
                    if (screenWidth < 560)
                      const Column(
                        children: [
                          _InfoTile(
                            icon: Icons.local_shipping_outlined,
                            title: "Fast Delivery",
                            subtitle: "2-4 business days",
                          ),
                          SizedBox(height: 10),
                          _InfoTile(
                            icon: Icons.assignment_return_outlined,
                            title: "Easy Returns",
                            subtitle: "30-day policy",
                          ),
                        ],
                      )
                    else
                      const Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.local_shipping_outlined,
                              title: "Fast Delivery",
                              subtitle: "2-4 business days",
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _InfoTile(
                              icon: Icons.assignment_return_outlined,
                              title: "Easy Returns",
                              subtitle: "30-day policy",
                            ),
                          ),
                        ],
                      ),

                    if (recommended.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      const _SectionTitle("You May Also Like"),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: recommended.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final item = recommended[index];
                            return _RecommendationCard(
                              product: item,
                              onTap: () => _openProductDetails(item),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x19000000),
                blurRadius: 18,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: screenWidth < 420
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: quantity > 1
                                ? () => _changeQuantity(-1)
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text(
                            quantity.toString(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            onPressed:
                                !_selectedVariantOutOfStock &&
                                    quantity < _maxQty
                                ? () => _changeQuantity(1)
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _selectedVariantOutOfStock
                            ? null
                            : () => _addToCart(p),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: Text(
                          _selectedVariantOutOfStock
                              ? "Out of Stock"
                              : "Add to Cart - $displayTotalPrice",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF151515),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: quantity > 1
                                ? () => _changeQuantity(-1)
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text(
                            quantity.toString(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            onPressed:
                                !_selectedVariantOutOfStock &&
                                    quantity < _maxQty
                                ? () => _changeQuantity(1)
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _selectedVariantOutOfStock
                              ? null
                              : () => _addToCart(p),
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(
                            _selectedVariantOutOfStock
                                ? "Out of Stock"
                                : "Add to Cart - $displayTotalPrice",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF151515),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String imageUrl;

  const _ProductImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FBFC), Color(0xFFF0F4F7)],
          ),
        ),
        child: Center(
          child: Icon(Icons.image_outlined, size: 60, color: Color(0xFF9AA4AE)),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9FBFC), Color(0xFFF0F4F7)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Image.network(
          imageUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 60,
              color: Color(0xFF9AA4AE),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
    );
  }
}

class _RatingBreakdownCard extends StatelessWidget {
  const _RatingBreakdownCard({
    required this.averageRating,
    required this.ratingCount,
    required this.writtenReviewCount,
    required this.breakdown,
  });

  final double averageRating;
  final int ratingCount;
  final int writtenReviewCount;
  final ProductRatingBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final hasRatings = ratingCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRatings ? averageRating.toStringAsFixed(1) : '--',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF173D36),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 2,
                    children: List<Widget>.generate(5, (index) {
                      return Icon(
                        hasRatings && index < averageRating.round()
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: const Color(0xFFFFB547),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ratingCount == 1 ? '1 rating' : '$ratingCount ratings',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    writtenReviewCount == 1
                        ? '1 written review'
                        : '$writtenReviewCount written reviews',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: List<Widget>.generate(5, (index) {
                    final stars = 5 - index;
                    return Padding(
                      padding: EdgeInsets.only(bottom: index == 4 ? 0 : 8),
                      child: _RatingBreakdownRow(
                        stars: stars,
                        count: breakdown.countFor(stars),
                        fraction: breakdown.fractionFor(stars),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          if (!hasRatings) ...[
            const SizedBox(height: 12),
            Text(
              'No ratings yet. Buy this product to leave the first one.',
              style: TextStyle(height: 1.4, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingBreakdownRow extends StatelessWidget {
  const _RatingBreakdownRow({
    required this.stars,
    required this.count,
    required this.fraction,
  });

  final int stars;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$stars',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF173D36),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB547)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: fraction.clamp(0, 1),
              backgroundColor: const Color(0xFFE6ECE9),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF0B7D69),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewEmptyState extends StatelessWidget {
  const _ReviewEmptyState({required this.canRateProduct});

  final bool canRateProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No written reviews yet',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            canRateProduct
                ? 'You can be the first buyer to share a quick review.'
                : 'Buy this product first to unlock written reviews.',
            style: TextStyle(height: 1.4, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _FilteredReviewEmptyState extends StatelessWidget {
  const _FilteredReviewEmptyState({required this.hasCurrentUserReview});

  final bool hasCurrentUserReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E8EC)),
      ),
      child: Text(
        hasCurrentUserReview
            ? 'No reviews match the current filter. Try another rating or switch back to all reviews.'
            : 'No reviews match the current filter yet.',
        style: TextStyle(height: 1.4, color: Colors.grey.shade700),
      ),
    );
  }
}

class _ReviewFilterChip extends StatelessWidget {
  const _ReviewFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ReviewSortMenu extends StatelessWidget {
  const _ReviewSortMenu({required this.value, required this.onSelected});

  final ProductReviewSortOption value;
  final ValueChanged<ProductReviewSortOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ProductReviewSortOption>(
      onSelected: onSelected,
      itemBuilder: (context) => ProductReviewSortOption.values
          .map(
            (option) => PopupMenuItem<ProductReviewSortOption>(
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8E6DF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18),
            const SizedBox(width: 6),
            Text(
              value.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.entry});

  final ProductReviewEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F6F4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.isCurrentUser ? 'You' : 'Verified buyer',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF173D36),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                formatProductReviewTimestamp(entry.updatedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 2,
            children: List<Widget>.generate(5, (index) {
              return Icon(
                index < entry.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 18,
                color: const Color(0xFFFFB547),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            entry.review,
            style: const TextStyle(height: 1.5, color: Color(0xFF1F2A26)),
          ),
        ],
      ),
    );
  }
}

class _NoStretchScrollBehavior extends MaterialScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E8EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _RecommendationCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final discount = settings.discountPercentForProduct(productId: product.id);
    final priceLabel = settings.formatUsd(
      product.price,
      productId: product.id,
      overrideDiscountPercent: discount,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 148,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7E8EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: _ProductImage(imageUrl: product.imageUrl),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                priceLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
