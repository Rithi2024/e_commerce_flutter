import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/cart/domain/entities/cart_snapshot_model.dart';
import 'package:marketflow/features/cart/domain/repository/cart_repository.dart';
import 'package:marketflow/features/cart/domain/usecases/cart_use_cases.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/presentation/pages/product_catalog_screen.dart';
import 'package:marketflow/features/catalog/presentation/pages/product_details_screen.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';

void main() {
  testWidgets(
    'Mobile catalog shows discovery rails, ratings, and sticky cart actions',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final productProvider = ProductCatalogProvider(
        useCases: ProductUseCases(_FakeProductRepository()),
      );
      productProvider.recordRecentlyViewed(
        Product(
          id: 'shirt-1',
          name: 'Weekend Tee',
          price: 18,
          imageUrl: '',
          description: 'Soft cotton t-shirt',
          category: 'Tops',
          createdAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      final cartProvider = ShoppingCartProvider(
        useCases: CartUseCases(_FakeCartRepository()),
      );
      await cartProvider.load();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildCatalogTestApp(
          cartProvider: cartProvider,
          productProvider: productProvider,
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Shop all categories'), findsNothing);
    expect(find.text('Search catalog'), findsOneWidget);
    expect(find.text('Search products or categories'), findsOneWidget);
    expect(find.text('Price, stock, more'), findsOneWidget);
    expect(find.text('Everyday Runner'), findsWidgets);
    expect(find.text('Popular'), findsWidgets);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('4.8'), findsWidgets);
      expect(find.text('(24)'), findsWidgets);
      expect(find.text('Recently viewed'), findsOneWidget);
      expect(find.text('Best sellers'), findsOneWidget);
      expect(find.text('New arrivals'), findsOneWidget);
      expect(find.text('Under \$25'), findsOneWidget);
      expect(find.text('1 item in cart'), findsOneWidget);
      expect(find.text('View cart'), findsOneWidget);
      expect(find.text('Shoes'), findsWidgets);
    },
  );

  testWidgets('Filter sheet opens with advanced mobile controls', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('In stock only'), findsOneWidget);
    expect(find.text('4 stars & up'), findsOneWidget);
    expect(find.text('4.5+ only'), findsOneWidget);
    expect(find.text('With written reviews'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Apply filters'), findsOneWidget);
  });

  testWidgets('Recent search chips can reapply saved catalog searches', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'product_catalog.recent_searches': <String>['Runner', 'Shoes'],
    });
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('Runner'), findsOneWidget);

    await tester.tap(find.text('Runner'));
    await tester.pumpAndSettle();

    expect(productProvider.query, 'Runner');
    expect(find.text('Search: Runner'), findsOneWidget);
    expect(find.text('Everyday Runner'), findsWidgets);
  });

  testWidgets('Scrolling collapses the mobile header to only the search bar', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Search products or categories'), findsOneWidget);
    expect(find.text('Search catalog'), findsNothing);
    expect(find.text('Price, stock, more'), findsNothing);
    expect(find.text('Sort by'), findsNothing);
  });

  testWidgets('Rating filter keeps only four-star products in the grid', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Filters'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('4 stars & up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(productProvider.filtered.map((product) => product.id), <String>[
      'shoe-1',
    ]);
    expect(productProvider.minimumRatingFilter, 4);
    expect(find.text('4+ rating'), findsOneWidget);
  });

  testWidgets('Written review filter keeps only products with review text', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Filters'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('With written reviews'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(productProvider.filtered.map((product) => product.id), <String>[
      'shoe-1',
    ]);
    expect(productProvider.writtenReviewsOnly, isTrue);
    expect(find.text('Written reviews'), findsOneWidget);
  });

  testWidgets('See all switches the catalog into a collection view', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    productProvider.recordRecentlyViewed(
      Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 18,
        imageUrl: '',
        description: 'Soft cotton t-shirt',
        category: 'Tops',
        createdAt: DateTime.now().subtract(const Duration(days: 40)),
      ),
    );
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'See all').first);
    await tester.pumpAndSettle();

    expect(find.text('Collection: Recently viewed'), findsOneWidget);
    expect(productProvider.activeCollectionLabel, 'Recently viewed');
    expect(productProvider.filtered.map((product) => product.id), <String>[
      'shirt-1',
    ]);
  });

  testWidgets('Hero banner opens active event deals collection', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now().toUtc();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings.event_discounts': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'event_id': 'event-1',
          'event_title': 'Spring Launch',
          'product_id': 'shoe-1',
          'discount_percent': 20,
          'updated_at': now.toIso8601String(),
        },
        <String, Object?>{
          'event_id': 'event-1',
          'event_title': 'Spring Launch',
          'product_id': 'shirt-1',
          'discount_percent': 15,
          'updated_at': now.toIso8601String(),
        },
      ]),
    });
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepositoryWithEvent()),
    );
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    await productProvider.fetchProducts();
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('2 event deals live'), findsOneWidget);
    expect(find.text('Spring Launch picks'), findsOneWidget);
    expect(find.text('Spring Launch deal'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Shop event'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Shop event'));
    await tester.pumpAndSettle();

    expect(find.text('Collection: Event deals'), findsOneWidget);
    expect(productProvider.sortOption, CatalogSortOption.bestDeals);
    expect(productProvider.activeCollectionLabel, 'Event deals');
    expect(productProvider.filtered.map((product) => product.id), <String>[
      'shoe-1',
      'shirt-1',
    ]);
  });

  testWidgets('Initial collection filter applies on first load', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    productProvider.recordRecentlyViewed(
      Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 18,
        imageUrl: '',
        description: 'Soft cotton t-shirt',
        category: 'Tops',
        createdAt: DateTime.now().subtract(const Duration(days: 40)),
      ),
    );
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
        home: const ProductCatalogScreen(
          initialCollectionFilter: CatalogCollectionFilter.recentlyViewed,
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Collection: Recently viewed'), findsOneWidget);
    expect(productProvider.activeCollectionLabel, 'Recently viewed');
    expect(productProvider.filtered.map((product) => product.id), <String>[
      'shirt-1',
    ]);
  });

  testWidgets('Tapping a product card opens the product detail route', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now().toUtc();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings.event_discounts': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'event_id': 'event-1',
          'event_title': 'Spring Launch',
          'product_id': 'shoe-1',
          'discount_percent': 20,
          'updated_at': now.toIso8601String(),
        },
      ]),
    });
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepositoryWithEvent()),
    );
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    final eventDealCard = find.byKey(
      const ValueKey<String>('collection-product-card-event-deals-shoe-1'),
    );
    expect(eventDealCard, findsOneWidget);

    await tester.ensureVisible(eventDealCard);
    await tester.pumpAndSettle();
    await tester.tap(eventDealCard);
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Included in Spring Launch'), findsOneWidget);
    expect(find.text('More Spring Launch deals'), findsOneWidget);
    expect(find.text('Spring Launch pricing applied'), findsOneWidget);
    expect(find.text('You save \$10.40 today.'), findsOneWidget);
    expect(find.textContaining('Ends in '), findsWidgets);
    expect(
      find.widgetWithText(OutlinedButton, 'Shop event deals'),
      findsOneWidget,
    );
    expect(find.text('Spring Launch deal'), findsWidgets);
    expect(find.byTooltip('Share product'), findsOneWidget);

    final shopEventDealsButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Shop event deals'),
    );
    shopEventDealsButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Collection: Event deals'), findsOneWidget);
    expect(productProvider.activeCollectionLabel, 'Event deals');
  });

  testWidgets('Initial product route lands on the detail screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository.empty()),
    );
    await productProvider.fetchProducts();
    await cartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _buildCatalogTestApp(
        cartProvider: cartProvider,
        productProvider: productProvider,
        initialRoute: '/?product=everyday-runner',
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Add to Cart - \$52.00'), findsOneWidget);
  });
}

Widget _buildCatalogTestApp({
  required ShoppingCartProvider cartProvider,
  required ProductCatalogProvider productProvider,
  Widget? home,
  String initialRoute = '/',
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettingsProvider>(
        create: (_) => AppSettingsProvider(),
      ),
      ChangeNotifierProvider<ProductCatalogProvider>.value(
        value: productProvider,
      ),
      ChangeNotifierProvider<UserWishlistProvider>(
        create: (_) => UserWishlistProvider(
          useCases: WishlistUseCases(_FakeWishlistRepository()),
        ),
      ),
      ChangeNotifierProvider<ShoppingCartProvider>.value(value: cartProvider),
    ],
    child: MaterialApp(
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        final routeName = settings.name ?? '/';
        final routeUri = Uri.tryParse(routeName);
        final productKey = routeUri?.queryParameters['product'];
        final collectionFilter = catalogCollectionFilterFromSlug(
          routeUri?.queryParameters['collection'],
        );
        if (productKey != null) {
          for (final product in productProvider.all) {
            if (product.matchesRouteKey(productKey)) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => ProductDetailsScreen(product: product),
              );
            }
          }
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              home ??
              ProductCatalogScreen(initialCollectionFilter: collectionFilter),
        );
      },
    ),
  );
}

class _FakeProductRepository implements ProductRepository {
  @override
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  }) async {
    return <Product>[
      Product(
        id: 'shoe-1',
        name: 'Everyday Runner',
        price: 52,
        imageUrl: '',
        description: 'Lightweight running shoes',
        category: 'Shoes',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 18,
        imageUrl: '',
        description: 'Soft cotton t-shirt',
        category: 'Tops',
        createdAt: DateTime.now().subtract(const Duration(days: 40)),
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async => null;

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async => <String>{'shoe-1'};

  @override
  Future<Map<String, int>> fetchVariantStocks({
    required String productId,
  }) async {
    return <String, int>{'M::Black': 8, 'L::Black': 3};
  }

  @override
  Future<Map<String, ProductRatingSummary>> fetchProductRatingSummaries({
    required Iterable<String> productIds,
  }) async {
    return <String, ProductRatingSummary>{
      'shoe-1': const ProductRatingSummary(
        ratingCount: 24,
        averageRating: 4.8,
        reviewCount: 8,
      ),
      'shirt-1': const ProductRatingSummary(
        ratingCount: 0,
        averageRating: 0,
        reviewCount: 0,
      ),
    };
  }
}

class _FakeProductRepositoryWithEvent extends _FakeProductRepository {
  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async {
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'id': 'event-1',
      'title': 'Spring Launch',
      'subtitle': 'Fresh picks for the week',
      'badge': 'Featured Event',
      'theme': 'default',
      'is_active': true,
      'starts_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
      'event_state': 'active',
    };
  }
}

class _FakeWishlistRepository implements WishlistRepository {
  @override
  Future<Set<String>> loadWishlistIds() async => <String>{};

  @override
  Future<bool> toggleWishlist(String productId) async => true;
}

class _FakeCartRepository implements CartRepository {
  _FakeCartRepository()
    : _snapshot = CartSnapshot(
        items: <CartItem>[
          CartItem(
            id: 'cart-1',
            productId: 'shoe-1',
            name: 'Everyday Runner',
            price: 52,
            imageUrl: '',
            qty: 1,
            size: 'M',
            color: 'Black',
          ),
        ],
        total: 52,
      );

  _FakeCartRepository.empty()
    : _snapshot = const CartSnapshot(items: [], total: 0);

  final CartSnapshot _snapshot;

  @override
  Future<CartSnapshot> loadCart() async => _snapshot;

  @override
  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) async {}

  @override
  Future<void> setCartQuantity({
    required String cartId,
    required int qty,
  }) async {}

  @override
  Future<void> clearCart() async {}
}
