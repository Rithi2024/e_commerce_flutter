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
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';
import 'package:marketflow/features/checkout/domain/usecases/order_use_cases.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/shell/presentation/pages/main_navigation_shell.dart';
import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'Shell opens support directly for a resolved alert and clears the badge',
    (WidgetTester tester) async {
      final orderProvider = OrderManagementProvider(
        useCases: OrderUseCases(_FakeOrderRepository()),
      );
      final productProvider = ProductCatalogProvider(
        useCases: ProductUseCases(_FakeProductRepository()),
      );
      final cartProvider = ShoppingCartProvider(
        useCases: CartUseCases(_FakeCartRepository()),
      );

      await cartProvider.load();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthenticationProvider>(
              create: (_) => AuthenticationProvider(
                useCases: AuthUseCases(_FakeAuthRepository()),
              ),
            ),
            ChangeNotifierProvider<OrderManagementProvider>.value(
              value: orderProvider,
            ),
            ChangeNotifierProvider<ProductCatalogProvider>.value(
              value: productProvider,
            ),
            ChangeNotifierProvider<AppSettingsProvider>(
              create: (_) => AppSettingsProvider(),
            ),
            ChangeNotifierProvider<UserWishlistProvider>(
              create: (_) => UserWishlistProvider(
                useCases: WishlistUseCases(_FakeWishlistRepository()),
              ),
            ),
            ChangeNotifierProvider<ShoppingCartProvider>.value(
              value: cartProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: false),
            home: const MainNavigationShell(),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('support-alert-banner')),
        findsOneWidget,
      );
      expect(find.text('Support resolved Order #3'), findsOneWidget);
      expect(find.text('New support update for Order #3.'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile-support-badge')),
        findsOneWidget,
      );

      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();

      expect(find.text('Customer Support'), findsOneWidget);
      expect(find.text('Reopening Order #3'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('support-alert-banner')), findsNothing);
      expect(find.byKey(const ValueKey('profile-support-badge')), findsNothing);
    },
  );

  testWidgets(
    'Shell shows a support snackbar when a new update arrives after resume',
    (WidgetTester tester) async {
      final orderProvider = OrderManagementProvider(
        useCases: OrderUseCases(
          _SequencedOrderRepository(
            responses: <List<Map<String, dynamic>>>[
              const <Map<String, dynamic>>[],
              const <Map<String, dynamic>>[],
              <Map<String, dynamic>>[_supportOrderFixture()],
            ],
          ),
        ),
      );
      final productProvider = ProductCatalogProvider(
        useCases: ProductUseCases(_FakeProductRepository()),
      );
      final cartProvider = ShoppingCartProvider(
        useCases: CartUseCases(_FakeCartRepository()),
      );

      await cartProvider.load();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthenticationProvider>(
              create: (_) => AuthenticationProvider(
                useCases: AuthUseCases(_FakeAuthRepository()),
              ),
            ),
            ChangeNotifierProvider<OrderManagementProvider>.value(
              value: orderProvider,
            ),
            ChangeNotifierProvider<ProductCatalogProvider>.value(
              value: productProvider,
            ),
            ChangeNotifierProvider<AppSettingsProvider>(
              create: (_) => AppSettingsProvider(),
            ),
            ChangeNotifierProvider<UserWishlistProvider>(
              create: (_) => UserWishlistProvider(
                useCases: WishlistUseCases(_FakeWishlistRepository()),
              ),
            ),
            ChangeNotifierProvider<ShoppingCartProvider>.value(
              value: cartProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: false),
            home: const MainNavigationShell(),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('support-alert-banner')), findsNothing);
      expect(find.text('Support resolved Order #3.'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Support resolved Order #3.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('support-alert-banner')),
        findsOneWidget,
      );
      expect(find.text('Support resolved Order #3'), findsOneWidget);
      expect(find.text('Reopen'), findsWidgets);
      expect(
        find.byKey(const ValueKey('profile-support-badge')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Shell keeps a dismissed support banner hidden after relaunch', (
    WidgetTester tester,
  ) async {
    final firstOrderProvider = OrderManagementProvider(
      useCases: OrderUseCases(_FakeOrderRepository()),
    );
    final firstProductProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    final firstCartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository()),
    );

    await firstCartProvider.load();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>.value(
            value: firstOrderProvider,
          ),
          ChangeNotifierProvider<ProductCatalogProvider>.value(
            value: firstProductProvider,
          ),
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<UserWishlistProvider>(
            create: (_) => UserWishlistProvider(
              useCases: WishlistUseCases(_FakeWishlistRepository()),
            ),
          ),
          ChangeNotifierProvider<ShoppingCartProvider>.value(
            value: firstCartProvider,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const MainNavigationShell(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-alert-banner')), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-alert-banner')), findsNothing);
    expect(find.byKey(const ValueKey('profile-support-badge')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final secondOrderProvider = OrderManagementProvider(
      useCases: OrderUseCases(_FakeOrderRepository()),
    );
    final secondProductProvider = ProductCatalogProvider(
      useCases: ProductUseCases(_FakeProductRepository()),
    );
    final secondCartProvider = ShoppingCartProvider(
      useCases: CartUseCases(_FakeCartRepository()),
    );
    await secondCartProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>.value(
            value: secondOrderProvider,
          ),
          ChangeNotifierProvider<ProductCatalogProvider>.value(
            value: secondProductProvider,
          ),
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<UserWishlistProvider>(
            create: (_) => UserWishlistProvider(
              useCases: WishlistUseCases(_FakeWishlistRepository()),
            ),
          ),
          ChangeNotifierProvider<ShoppingCartProvider>.value(
            value: secondCartProvider,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const MainNavigationShell(),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-alert-banner')), findsNothing);
    expect(find.byKey(const ValueKey('profile-support-badge')), findsOneWidget);
  });
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
  }) async {
    return _user;
  }

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
  }) async {
    return 'https://example.com/avatar.png';
  }

  @override
  Future<void> logout() async {}

  @override
  Future<UserProfile?> fetchProfile() async {
    return UserProfile(
      name: 'Market Flow',
      phone: '+85512345678',
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

class _FakeOrderRepository implements OrderRepository {
  @override
  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    required String status,
    required String paymentMethod,
    required String paymentReference,
    required String addressDetails,
    required String promoCode,
  }) async {
    return 1;
  }

  @override
  Future<List<Map<String, dynamic>>> loadOrders() async {
    return <Map<String, dynamic>>[_supportOrderFixture()];
  }

  @override
  Future<CheckoutPrefill> loadCheckoutPrefill() async => const CheckoutPrefill(
    contactName: 'Market Flow',
    contactPhone: '+85512345678',
    defaultAddress: 'Street 2004, Phnom Penh',
    savedAddresses: <String>['Street 2004, Phnom Penh'],
  );

  @override
  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  }) async {}

  @override
  Future<Map<String, dynamic>> validatePromoCode({
    required String promoCode,
  }) async => const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> generatePayWayQr({
    required String tranId,
    required double amount,
    required List<CartItem> items,
    required String callbackUrl,
    required String currency,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required int lifetimeMinutes,
    required String paymentOption,
    required String qrImageTemplate,
  }) async => const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> checkPayWayTransaction({
    required String tranId,
  }) async => const <String, dynamic>{};

  @override
  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) async {}

  @override
  bool isPayWayApproved(Map<String, dynamic> checkResponse) => false;
}

class _SequencedOrderRepository extends _FakeOrderRepository {
  _SequencedOrderRepository({required this.responses});

  final List<List<Map<String, dynamic>>> responses;
  int _callCount = 0;

  @override
  Future<List<Map<String, dynamic>>> loadOrders() async {
    final index = _callCount < responses.length
        ? _callCount
        : responses.length - 1;
    _callCount += 1;
    return responses[index];
  }
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
    return <String, int>{'M::Black': 8};
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
  @override
  Future<CartSnapshot> loadCart() async =>
      const CartSnapshot(items: <CartItem>[], total: 0);

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

Map<String, dynamic> _supportOrderFixture() {
  return <String, dynamic>{
    'id': 3,
    'status': 'order_received',
    'delivery_type': 'drop_off',
    'payment_method': 'cash_on_delivery',
    'address': '56b, 56b Saint 143, Khan 7 Makara, Phnom Penh, Cambodia',
    'address_details': 'Delivery time: ASAP',
    'total': 52.0,
    'created_at': '2026-03-17T10:31:59Z',
    'items': const <Map<String, dynamic>>[],
    'support_request_status': 'resolved',
    'support_request_status_updated_at': '2026-03-17T10:31:59Z',
    'support_request_history': <Map<String, dynamic>>[
      <String, dynamic>{
        'request_type': 'delivery',
        'support_request_status': 'resolved',
        'support_request_status_updated_at': '2026-03-17T10:31:59Z',
        'support_note':
            'Your address update has been applied and this support request is now resolved.',
        'support_note_updated_at': '2026-03-17T10:31:59Z',
      },
    ],
  };
}
