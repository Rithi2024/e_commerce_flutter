import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/core/support/support_draft_store.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';
import 'package:marketflow/features/checkout/domain/usecases/order_use_cases.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/settings/presentation/pages/user_profile_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Profile screen shows the expanded profile sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildProfileTestApp());

    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Account Snapshot'), findsOneWidget);
    expect(find.text('Profile completion'), findsOneWidget);
    expect(find.text('Saved Address'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('My Wishlist'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Order updates'), findsOneWidget);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('Profile shows support update notifications and order badges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildProfileTestApp(
        orderRepository: _FakeOrderRepository(
          orders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'support_request_status': 'resolved',
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
            },
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Support Updates'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);
    expect(find.text('Order #3'), findsOneWidget);
    expect(
      find.text(
        'Your address update has been applied and this support request is now resolved.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 new support update on Order #3'), findsOneWidget);
    expect(find.text('View Order #3'), findsOneWidget);
  });

  testWidgets('Profile opens My Orders on the updated order when support is unread', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildProfileTestApp(
        orderRepository: _FakeOrderRepository(
          orders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'support_request_status': 'resolved',
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
            },
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1 new support update on Order #3'), findsOneWidget);
    await tester.ensureVisible(find.text('My Orders'));
    await tester.tap(find.text('My Orders'));
    await tester.pumpAndSettle();

    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Order: #3'), findsOneWidget);
  });

  testWidgets('Profile shows saved support draft state', (
    WidgetTester tester,
  ) async {
    final draftStore = SupportDraftStore();
    await draftStore.saveDraft(
      scope: 'user-1',
      draft: const CustomerSupportDraft(
        requestType: 'payment',
        message: 'I need help checking my payment confirmation.',
      ),
    );

    await tester.pumpWidget(_buildProfileTestApp());

    await tester.pumpAndSettle();

    expect(find.text('Draft saved'), findsWidgets);
    expect(find.text('Resume Support Draft'), findsOneWidget);
  });

  testWidgets('Profile can clear a saved support draft', (
    WidgetTester tester,
  ) async {
    final draftStore = SupportDraftStore();
    await draftStore.saveDraft(
      scope: 'user-1',
      draft: const CustomerSupportDraft(
        requestType: 'delivery',
        message: 'Following up on Order #3.',
        followUp: SupportDraftFollowUp(
          orderId: 3,
          status: 'resolved',
          requestType: 'delivery',
          supportNote:
              'Your address update has been applied and this support request is now resolved.',
          sharedAddress:
              '56b, 56b Saint 143, Khan 7 Makara, Phnom Penh, Phnom Penh, Cambodia',
        ),
      ),
    );

    await tester.pumpWidget(_buildProfileTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Resume Support Draft'), findsOneWidget);
    expect(find.text('View Order #3'), findsOneWidget);

    final clearDraftButton = find.widgetWithText(TextButton, 'Clear draft');
    await tester.ensureVisible(clearDraftButton);
    await tester.tap(clearDraftButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Saved support draft cleared'), findsOneWidget);
    expect(find.text('Resume Support Draft'), findsNothing);
    expect(find.text('Customer Support'), findsOneWidget);
  });

  testWidgets('Profile opens support as a follow-up for the latest update', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildProfileTestApp(
        orderRepository: _FakeOrderRepository(
          orders: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'support_request_status': 'resolved',
              'support_request_history': <Map<String, dynamic>>[
                <String, dynamic>{
                  'request_type': 'delivery',
                  'support_request_status': 'resolved',
                  'support_request_status_updated_at': '2026-03-17T10:31:59Z',
                  'support_note':
                      'Your address update has been applied and this support request is now resolved.',
                  'support_note_updated_at': '2026-03-17T10:31:59Z',
                  'support_request_message':
                      'Order #3 needs a delivery address update.\nMy updated delivery address is: Street 2004, Phnom Penh',
                },
              ],
            },
          ],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Reopen in Support'), findsWidgets);
    expect(
      find.text('Reopen Order #3 in Support - 1 unread update'),
      findsOneWidget,
    );
    final replyInSupportButton = find.text('Reopen in Support').first;
    await tester.ensureVisible(replyInSupportButton);
    await tester.tap(replyInSupportButton);
    await tester.pumpAndSettle();

    expect(find.text('Customer Support'), findsOneWidget);
    expect(find.text('Reopening Order #3'), findsOneWidget);
    expect(find.text('Reopen request'), findsOneWidget);
    expect(
      find.textContaining('Address shared: Street 2004, Phnom Penh'),
      findsOneWidget,
    );
  });

  testWidgets('Change password dialog asks for the current password', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_buildProfileTestApp());

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change Password'));
    await tester.tap(find.text('Change Password'));
    await tester.pumpAndSettle();

    expect(find.text('Current password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('Profile hides placeholder saved addresses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildProfileTestApp(
        authRepository: _FakeAuthRepository(
          profileAddress: 'Selected location',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Selected location'), findsNothing);
    expect(find.text('No delivery address yet'), findsOneWidget);
    expect(find.text('No delivery address saved yet.'), findsOneWidget);
    expect(find.text('Add Address'), findsOneWidget);
  });

  testWidgets('Profile hides coordinate-only saved addresses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildProfileTestApp(
        authRepository: _FakeAuthRepository(
          profileAddress: '11.56210, 104.88880',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('11.56210, 104.88880'), findsNothing);
    expect(find.text('No delivery address yet'), findsOneWidget);
    expect(find.text('Add Address'), findsOneWidget);
  });
}

Widget _buildProfileTestApp({
  AuthRepository? authRepository,
  OrderRepository? orderRepository,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppSettingsProvider>(
        create: (_) => AppSettingsProvider(),
      ),
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(authRepository ?? _FakeAuthRepository()),
        ),
      ),
      ChangeNotifierProvider<OrderManagementProvider>(
        create: (_) => OrderManagementProvider(
          useCases: OrderUseCases(orderRepository ?? _FakeOrderRepository()),
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: false),
      home: const UserProfileScreen(),
    ),
  );
}

class _FakeAuthRepository implements AuthRepository {
  final String profileAddress;

  _FakeAuthRepository({this.profileAddress = 'Street 2004, Phnom Penh'});

  static const User _user = User(
    id: 'user-1',
    appMetadata: <String, dynamic>{},
    userMetadata: <String, dynamic>{
      'notify_order_updates': true,
      'notify_back_in_stock': true,
      'notify_security_alerts': true,
    },
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
      phone: '+855 12345678',
      address: profileAddress,
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
  final List<Map<String, dynamic>> orders;

  _FakeOrderRepository({this.orders = const <Map<String, dynamic>>[]});

  @override
  Future<void> sendOrderConfirmationEmail({
    required String email,
    required String userName,
    required int orderId,
    required double total,
    required String status,
    required List<CartItem> items,
  }) async {}

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
  Future<List<Map<String, dynamic>>> loadOrders() async => orders;

  @override
  Future<CheckoutPrefill> loadCheckoutPrefill() async =>
      CheckoutPrefill.empty();

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
