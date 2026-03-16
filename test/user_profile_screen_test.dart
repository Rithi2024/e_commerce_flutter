import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/settings/presentation/pages/user_profile_screen.dart';

void main() {
  testWidgets('Profile screen shows the expanded profile sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(_FakeAuthRepository()),
        ),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const UserProfileScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Saved Address'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('My Wishlist'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Order updates'), findsOneWidget);
    expect(find.text('Email verified'), findsOneWidget);
  });

  testWidgets('Change password dialog asks for the current password', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(_FakeAuthRepository()),
        ),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const UserProfileScreen(),
        ),
      ),
    );

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
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(
            _FakeAuthRepository(profileAddress: 'Selected location'),
          ),
        ),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const UserProfileScreen(),
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
      ChangeNotifierProvider<AuthenticationProvider>(
        create: (_) => AuthenticationProvider(
          useCases: AuthUseCases(
            _FakeAuthRepository(profileAddress: '11.56210, 104.88880'),
          ),
        ),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const UserProfileScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('11.56210, 104.88880'), findsNothing);
    expect(find.text('No delivery address yet'), findsOneWidget);
    expect(find.text('Add Address'), findsOneWidget);
  });
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
