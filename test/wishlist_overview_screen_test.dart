import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
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
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:marketflow/features/wishlist/presentation/pages/wishlist_overview_screen.dart';

void main() {
  testWidgets('wishlist quick add uses live event pricing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettingsProvider();
    await settings.upsertEventDiscount(
      eventId: 'event-1',
      eventTitle: 'Spring Launch',
      productId: 'shoe-1',
      discountPercent: 20,
    );

    final cartRepository = _FakeCartRepository();
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(cartRepository),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepositoryWithEvent()),
    );
    final wishlistProvider = UserWishlistProvider(
      useCases: WishlistUseCases(_FakeWishlistRepository()),
    );

    await tester.pumpWidget(
      _buildWishlistTestApp(
        settings: settings,
        cartProvider: cartProvider,
        productProvider: productProvider,
        wishlistProvider: wishlistProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Saved picks'), findsOneWidget);
    expect(find.text('Spring Launch deal'), findsWidgets);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('wishlist-product-card-shoe-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quick add'), findsOneWidget);

    await tester.tap(find.text('Quick add'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Everyday Runner added to cart.'), findsOneWidget);
    expect(cartRepository.addedProducts, hasLength(1));
    expect(cartRepository.addedProducts.single.id, 'shoe-1');
    expect(cartRepository.addedProducts.single.price, 41.6);
    expect(cartRepository.addedSize, 'M');
    expect(cartRepository.addedColor, 'Black');
  });

  testWidgets('wishlist search and filters narrow saved items', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettingsProvider();
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository()),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepositoryWithEvent(
          products: <Product>[
            _product(
              id: 'shoe-1',
              name: 'Everyday Runner',
              price: 52,
              description: 'Lightweight running shoes',
              category: 'Shoes',
              createdAt: DateTime.now().subtract(const Duration(days: 3)),
            ),
            _product(
              id: 'tee-1',
              name: 'Weekend Tee',
              price: 18,
              description: 'Soft cotton t-shirt',
              category: 'Tops',
              createdAt: DateTime.now().subtract(const Duration(days: 40)),
            ),
            _product(
              id: 'bag-1',
              name: 'City Pack',
              price: 34,
              description: 'Travel-ready backpack',
              category: 'Bags',
              createdAt: DateTime.now().subtract(const Duration(days: 8)),
            ),
          ],
          includeDefaultEvent: false,
          bestSellerIds: <String>{'shoe-1', 'bag-1'},
          variantStocksByProductId: <String, Map<String, int>>{
            'shoe-1': <String, int>{'M::Black': 8},
            'tee-1': <String, int>{'M::Sand': 4},
            'bag-1': <String, int>{'Standard::Olive': 6},
          },
        ),
      ),
    );
    final wishlistProvider = UserWishlistProvider(
      useCases: WishlistUseCases(
        _FakeWishlistRepository(
          initialIds: <String>{'shoe-1', 'tee-1', 'bag-1'},
        ),
      ),
    );

    await tester.pumpWidget(
      _buildWishlistTestApp(
        settings: settings,
        cartProvider: cartProvider,
        productProvider: productProvider,
        wishlistProvider: wishlistProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Saved picks'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-shoe-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-tee-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-bag-1')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Best sellers'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-shoe-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-bag-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-tee-1')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('wishlist-search-field')),
      'bag',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-bag-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wishlist-product-card-shoe-1')),
      findsNothing,
    );
  });

  testWidgets('wishlist event summary can add matched deals in bulk', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettingsProvider();
    await settings.upsertEventDiscount(
      eventId: 'event-1',
      eventTitle: 'Spring Launch',
      productId: 'shoe-1',
      discountPercent: 20,
    );
    await settings.upsertEventDiscount(
      eventId: 'event-1',
      eventTitle: 'Spring Launch',
      productId: 'tee-1',
      discountPercent: 15,
    );

    final cartRepository = _FakeCartRepository();
    final cartProvider = ShoppingCartProvider(
      useCases: CartUseCases(cartRepository),
    );
    final productProvider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepositoryWithEvent(
          products: <Product>[
            _product(
              id: 'shoe-1',
              name: 'Everyday Runner',
              price: 52,
              description: 'Lightweight running shoes',
              category: 'Shoes',
              createdAt: DateTime.now().subtract(const Duration(days: 3)),
            ),
            _product(
              id: 'tee-1',
              name: 'Weekend Tee',
              price: 18,
              description: 'Soft cotton t-shirt',
              category: 'Tops',
              createdAt: DateTime.now().subtract(const Duration(days: 10)),
            ),
          ],
          bestSellerIds: <String>{'shoe-1'},
          variantStocksByProductId: <String, Map<String, int>>{
            'shoe-1': <String, int>{'M::Black': 8},
            'tee-1': <String, int>{'M::Sand': 4},
          },
        ),
      ),
    );
    final wishlistProvider = UserWishlistProvider(
      useCases: WishlistUseCases(
        _FakeWishlistRepository(initialIds: <String>{'shoe-1', 'tee-1'}),
      ),
    );

    await tester.pumpWidget(
      _buildWishlistTestApp(
        settings: settings,
        cartProvider: cartProvider,
        productProvider: productProvider,
        wishlistProvider: wishlistProvider,
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Add matches'), findsOneWidget);

    await tester.tap(find.text('Add matches'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('2 matched items added to cart.'), findsOneWidget);
    expect(cartRepository.addedProducts, hasLength(2));
    expect(
      cartRepository.addedProducts.map((product) => product.id).toList(),
      <String>['shoe-1', 'tee-1'],
    );
    expect(
      cartRepository.addedProducts.map((product) => product.price).toList(),
      <double>[41.6, 15.3],
    );
  });
}

Widget _buildWishlistTestApp({
  required AppSettingsProvider settings,
  required ShoppingCartProvider cartProvider,
  required ProductCatalogProvider productProvider,
  required UserWishlistProvider wishlistProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(_FakeAuthRepository()),
        ),
      ),
      ChangeNotifierProvider<ProductCatalogProvider>.value(
        value: productProvider,
      ),
      ChangeNotifierProvider<UserWishlistProvider>.value(value: wishlistProvider),
      ChangeNotifierProvider<ShoppingCartProvider>.value(value: cartProvider),
    ],
    child: const MaterialApp(home: WishlistOverviewScreen()),
  );
}

Product _product({
  required String id,
  required String name,
  required double price,
  required String description,
  required String category,
  required DateTime createdAt,
}) {
  return Product(
    id: id,
    name: name,
    price: price,
    imageUrl: '',
    description: description,
    category: category,
    createdAt: createdAt,
  );
}

class _FakeAuthRepository implements AuthRepository {
  static const User _user = User(
    id: 'user-1',
    appMetadata: <String, dynamic>{},
    userMetadata: <String, dynamic>{},
    aud: 'authenticated',
    email: 'tester@example.com',
    createdAt: '2026-03-16T00:00:00.000Z',
    emailConfirmedAt: '2026-03-16T00:05:00.000Z',
  );

  @override
  User? currentUser() => _user;

  @override
  Stream<User?> onUserChanges() => const Stream<User?>.empty();

  @override
  Future<User?> register({
    required String email,
    required String password,
  }) async => _user;

  @override
  Future<User?> login({required String email, required String password}) async {
    return _user;
  }

  @override
  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) async {}

  @override
  Future<void> resendSignupVerification({required String email}) async {}

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<void> requestEmailChange({required String newEmail}) async {}

  @override
  Future<void> resendEmailChangeCode({required String newEmail}) async {}

  @override
  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {}

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<User?> updateUserMetadata({required Map<String, dynamic> data}) async {
    return _user;
  }

  @override
  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async => 'https://example.com/avatar.png';

  @override
  Future<void> logout() async {}

  @override
  Future<UserProfile?> fetchProfile() async {
    return const UserProfile(
      name: 'Market Flow',
      phone: '+855 12345678',
      address: 'Street 2004, Phnom Penh',
      accountType: 'customer',
      promoEmailOptIn: true,
    );
  }

  @override
  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async {
    return UserProfile(
      name: name,
      phone: phone,
      address: address,
      accountType: 'customer',
      promoEmailOptIn: promoEmailOptIn ?? false,
    );
  }
}

class _FakeProductRepositoryWithEvent implements ProductRepository {
  _FakeProductRepositoryWithEvent({
    List<Product>? products,
    Map<String, dynamic>? activeEvent,
    this.includeDefaultEvent = true,
    Set<String>? bestSellerIds,
    Map<String, Map<String, int>>? variantStocksByProductId,
  }) : _products =
           products ??
           <Product>[
             _product(
               id: 'shoe-1',
               name: 'Everyday Runner',
               price: 52,
               description: 'Lightweight running shoes',
               category: 'Shoes',
               createdAt: DateTime.now().subtract(const Duration(days: 3)),
             ),
           ],
       _activeEvent = activeEvent,
       _bestSellerIds = bestSellerIds ?? <String>{'shoe-1'},
       _variantStocksByProductId =
           variantStocksByProductId ??
           <String, Map<String, int>>{
             'shoe-1': <String, int>{'M::Black': 8},
           };

  final List<Product> _products;
  final Map<String, dynamic>? _activeEvent;
  final bool includeDefaultEvent;
  final Set<String> _bestSellerIds;
  final Map<String, Map<String, int>> _variantStocksByProductId;

  @override
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  }) async => _products;

  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async {
    if (_activeEvent != null) {
      return _activeEvent;
    }
    if (!includeDefaultEvent) {
      return null;
    }
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'id': 'event-1',
      'title': 'Spring Launch',
      'is_active': true,
      'starts_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
      'event_state': 'active',
    };
  }

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async => _bestSellerIds;

  @override
  Future<Map<String, int>> fetchVariantStocks({
    required String productId,
  }) async => _variantStocksByProductId[productId] ?? <String, int>{};

  @override
  Future<Map<String, ProductRatingSummary>> fetchProductRatingSummaries({
    required Iterable<String> productIds,
  }) async => <String, ProductRatingSummary>{};
}

class _FakeWishlistRepository implements WishlistRepository {
  _FakeWishlistRepository({Set<String>? initialIds})
    : _initialIds = initialIds ?? <String>{'shoe-1'};

  final Set<String> _initialIds;

  @override
  Future<Set<String>> loadWishlistIds() async => _initialIds;

  @override
  Future<bool> toggleWishlist(String productId) async => false;
}

class _FakeCartRepository implements CartRepository {
  final List<Product> addedProducts = <Product>[];
  String? addedSize;
  String? addedColor;

  @override
  Future<CartSnapshot> loadCart() async =>
      const CartSnapshot(items: <CartItem>[], total: 0);

  @override
  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) async {
    addedProducts.add(product);
    addedSize = size;
    addedColor = color;
  }

  @override
  Future<void> setCartQuantity({
    required String cartId,
    required int qty,
  }) async {}

  @override
  Future<void> clearCart() async {}
}
