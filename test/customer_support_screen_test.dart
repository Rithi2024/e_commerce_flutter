import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/features/support/presentation/pages/customer_support_screen.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'customer support screen accepts prefilled delivery recovery info',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final draftStore = SupportDraftStore();
      await draftStore.saveDraft(
        scope: 'anonymous',
        draft: const CustomerSupportDraft(
          requestType: 'payment',
          message: 'Old saved draft should not override explicit context.',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerSupportScreen(
            initialRequestType: 'delivery',
            initialMessage:
                'Order #3 needs a delivery address update.\nMy updated delivery address is: Street 2004, Phnom Penh',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customer Support'), findsOneWidget);
      expect(find.text('Delivery issue'), findsOneWidget);
      expect(
        find.textContaining('Order #3 needs a delivery address update.'),
        findsOneWidget,
      );
      expect(find.textContaining('Street 2004, Phnom Penh'), findsOneWidget);
    },
  );

  testWidgets(
    'customer support screen accepts initial follow-up context',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerSupportScreen(
            initialFollowUpOrderId: 3,
            initialFollowUpStatus: 'resolved',
            initialFollowUpRequestType: 'delivery',
            initialFollowUpSupportNote:
                'Your address update has been applied and this support request is now resolved.',
            initialFollowUpSharedAddress: 'Street 2004, Phnom Penh',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reopening Order #3'), findsOneWidget);
      expect(find.text('Discard draft'), findsOneWidget);
      expect(find.text('Reopen request'), findsOneWidget);
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Delivery issue'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reopening support request for Order #3.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Latest support reply: Your address update has been applied',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Address shared: Street 2004, Phnom Penh'),
        findsOneWidget,
      );
    },
  );

  testWidgets('customer support screen restores a saved follow-up draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final draftStore = SupportDraftStore();
    await draftStore.saveDraft(
      scope: 'user-1',
      draft: const CustomerSupportDraft(
        requestType: 'delivery',
        message:
            'Following up on Order #3.\nPlease confirm the delivery update.',
        followUp: SupportDraftFollowUp(
          orderId: 3,
          status: 'resolved',
          requestType: 'delivery',
          supportNote:
              'Your address update has been applied and this support request is now resolved.',
          sharedAddress: 'Street 2004, Phnom Penh',
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reopening Order #3'), findsOneWidget);
    expect(find.text('Discard draft'), findsOneWidget);
    expect(find.text('Reopen request'), findsOneWidget);
    expect(
      find.text(
        'Saved automatically on this device until you send or discard it.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Delivery issue'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Please confirm the delivery update.'),
      findsOneWidget,
    );
  });

  testWidgets('customer support screen shows and clears a saved general draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final draftStore = SupportDraftStore();
    await draftStore.saveDraft(
      scope: 'user-1',
      draft: const CustomerSupportDraft(
        requestType: 'payment',
        message: 'I need help checking my payment confirmation.',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Draft saved locally'), findsOneWidget);
    expect(find.text('Clear draft'), findsOneWidget);
    expect(
      find.text(
        'Payment issue draft will stay on this device until you send or clear it.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Payment issue'),
      findsOneWidget,
    );
    expect(
      find.textContaining('I need help checking my payment confirmation.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('clear_general_draft')));
    await tester.pumpAndSettle();

    expect(find.text('Draft saved locally'), findsNothing);
    expect(find.text('Clear draft'), findsNothing);
    expect(
      find.textContaining('I need help checking my payment confirmation.'),
      findsNothing,
    );
    expect(find.text('Send Anonymous Message'), findsOneWidget);
  });

  testWidgets('customer support screen shows recent linked support updates', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Recent support updates'), findsOneWidget);
    expect(find.text('Order #3'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
    expect(
      find.text(
        'Your address update has been applied and this support request is now resolved.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Address shared: Street 2004, Phnom Penh'),
      findsOneWidget,
    );
  });

  testWidgets('customer support screen filters recent updates by status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Order #3'), findsOneWidget);
    expect(find.text('Order #4'), findsOneWidget);

    await tester.ensureVisible(find.text('Open (1)'));
    await tester.tap(find.text('Open (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Order #3'), findsNothing);
    expect(find.text('Order #4'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('customer support screen opens the linked order directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final viewOrderButton = find.byKey(const ValueKey<String>('view_order_3'));
    await tester.scrollUntilVisible(
      viewOrderButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(viewOrderButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Order: #3'), findsOneWidget);
  });

  testWidgets('customer support screen uses status-aware follow-up labels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reopen request'), findsOneWidget);
    expect(find.text('Send follow-up'), findsOneWidget);
  });

  testWidgets('customer support screen drafts a follow-up for an update', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final followUpButton = find.byKey(const ValueKey<String>('follow_up_3'));
    await tester.scrollUntilVisible(
      followUpButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(followUpButton);
    await tester.pumpAndSettle();

    expect(find.text('Reopen draft ready for Order #3'), findsOneWidget);
    expect(find.text('Reopening Order #3'), findsOneWidget);
    expect(find.text('Discard draft'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Reopen request'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Delivery issue'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Reopening support request for Order #3.'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Latest support reply: Your address update has been applied',
      ),
      findsOneWidget,
    );
  });

  testWidgets('customer support screen can discard a follow-up draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    final followUpButton = find.byKey(const ValueKey<String>('follow_up_3'));
    await tester.scrollUntilVisible(
      followUpButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(followUpButton);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('discard_follow_up')));
    await tester.pumpAndSettle();

    expect(find.text('Reopening Order #3'), findsNothing);
    expect(find.text('Discard draft'), findsNothing);
    expect(
      find.widgetWithText(ElevatedButton, 'Reopen request'),
      findsNothing,
    );
    expect(find.text('Send Anonymous Message'), findsOneWidget);
    expect(
      find.textContaining('Reopening support request for Order #3.'),
      findsNothing,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>(
            create: (_) => AppSettingsProvider(),
          ),
          ChangeNotifierProvider<AuthenticationProvider>(
            create: (_) => AuthenticationProvider(
              useCases: AuthUseCases(_FakeAuthRepository()),
            ),
          ),
          ChangeNotifierProvider<OrderManagementProvider>(
            create: (_) => OrderManagementProvider(
              useCases: OrderUseCases(_FakeOrderRepository()),
            ),
          ),
        ],
        child: const MaterialApp(home: CustomerSupportScreen()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reopening Order #3'), findsNothing);
    expect(
      find.textContaining('Reopening support request for Order #3.'),
      findsNothing,
    );
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
  Future<List<Map<String, dynamic>>> loadOrders() async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 3,
        'support_request_history': <Map<String, dynamic>>[
          <String, dynamic>{
            'request_type': 'delivery',
            'support_request_status': 'resolved',
            'support_request_status_updated_at': '2026-03-17T10:31:59Z',
            'support_request_message':
                'Order #3 needs a delivery address update.\nMy updated delivery address is: Street 2004, Phnom Penh',
            'support_note':
                'Your address update has been applied and this support request is now resolved.',
            'support_note_updated_at': '2026-03-17T10:31:59Z',
          },
        ],
      },
      <String, dynamic>{
        'id': 4,
        'support_request_history': <Map<String, dynamic>>[
          <String, dynamic>{
            'request_type': 'delivery',
            'support_request_status': 'pending',
            'support_request_status_updated_at': '2026-03-18T08:15:00Z',
            'support_request_message':
                'Order #4 needs a delivery address update.\nMy updated delivery address is: Tuol Kork, Phnom Penh',
          },
        ],
      },
    ];
  }

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
