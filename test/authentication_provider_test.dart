import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('web session timeout logs out the current web user', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository(
      initialUser: _FakeAuthRepository.user,
    );
    final provider = AuthenticationProvider(
      useCases: AuthUseCases(repository),
      webSessionTimeout: const Duration(seconds: 1),
      webSessionActivityThrottle: Duration.zero,
      enableWebSessionTimeoutOverride: true,
    );
    addTearDown(provider.dispose);

    expect(provider.user?.id, _FakeAuthRepository.user.id);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(repository.logoutCalls, 1);
    expect(provider.user, isNull);
    expect(
      provider.takePendingWebSessionNotice(),
      contains('timed out after 1 second'),
    );
    expect(provider.takePendingWebSessionNotice(), isNull);
  });

  testWidgets('web session activity resets the inactivity timer', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository(
      initialUser: _FakeAuthRepository.user,
    );
    final provider = AuthenticationProvider(
      useCases: AuthUseCases(repository),
      webSessionTimeout: const Duration(seconds: 1),
      webSessionActivityThrottle: Duration.zero,
      enableWebSessionTimeoutOverride: true,
    );
    addTearDown(provider.dispose);

    await tester.pump(const Duration(milliseconds: 800));
    provider.recordWebSessionActivity(force: true);
    await tester.pump(const Duration(milliseconds: 800));

    expect(repository.logoutCalls, 0);
    expect(provider.user?.id, _FakeAuthRepository.user.id);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(repository.logoutCalls, 1);
    expect(provider.user, isNull);
  });

  testWidgets('web session timeout starts after login succeeds', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository(loginUser: _FakeAuthRepository.user);
    final provider = AuthenticationProvider(
      useCases: AuthUseCases(repository),
      webSessionTimeout: const Duration(seconds: 1),
      webSessionActivityThrottle: Duration.zero,
      enableWebSessionTimeoutOverride: true,
    );
    addTearDown(provider.dispose);

    await provider.login('tester@example.com', 'secret123');
    expect(provider.user?.id, _FakeAuthRepository.user.id);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(repository.logoutCalls, 1);
    expect(provider.user, isNull);
  });
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({User? initialUser, this.loginUser})
    : _currentUser = initialUser;

  static const User user = User(
    id: 'user-1',
    appMetadata: <String, dynamic>{},
    userMetadata: <String, dynamic>{},
    aud: 'authenticated',
    email: 'tester@example.com',
    createdAt: '2026-03-18T00:00:00.000Z',
    emailConfirmedAt: '2026-03-18T00:05:00.000Z',
  );

  final User? loginUser;

  int logoutCalls = 0;
  User? _currentUser;

  @override
  User? currentUser() => _currentUser;

  @override
  Stream<User?> onUserChanges() => const Stream<User?>.empty();

  @override
  Future<User?> login({required String email, required String password}) async {
    _currentUser = loginUser;
    return _currentUser;
  }

  @override
  Future<User?> register({
    required String email,
    required String password,
  }) async {
    _currentUser = loginUser;
    return _currentUser;
  }

  @override
  Future<void> resendSignupVerification({required String email}) async {}

  @override
  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) async {}

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
    return _currentUser;
  }

  @override
  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    return 'https://example.com/avatar.png';
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    _currentUser = null;
  }

  @override
  Future<UserProfile?> fetchProfile() async => null;

  @override
  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async => null;
}
