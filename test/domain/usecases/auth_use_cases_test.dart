import 'dart:typed_data';

import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthRepository implements AuthRepository {
  int registerCalls = 0;
  int loginCalls = 0;
  int logoutCalls = 0;
  int fetchProfileCalls = 0;
  int upsertProfileCalls = 0;
  int resendSignupVerificationCalls = 0;
  int verifySignupCodeCalls = 0;
  int requestEmailChangeCalls = 0;
  int resendEmailChangeCodeCalls = 0;
  int confirmEmailChangeCalls = 0;
  int updatePasswordCalls = 0;
  int updateUserMetadataCalls = 0;
  int uploadProfileAvatarCalls = 0;

  @override
  User? currentUser() => null;

  @override
  Stream<User?> onUserChanges() => Stream<User?>.value(null);

  @override
  Future<User?> register({
    required String email,
    required String password,
  }) async {
    registerCalls++;
    return null;
  }

  @override
  Future<User?> login({required String email, required String password}) async {
    loginCalls++;
    return null;
  }

  @override
  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) async {}

  @override
  Future<void> resendSignupVerification({required String email}) async {
    resendSignupVerificationCalls++;
  }

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    verifySignupCodeCalls++;
  }

  @override
  Future<void> requestEmailChange({required String newEmail}) async {
    requestEmailChangeCalls++;
  }

  @override
  Future<void> resendEmailChangeCode({required String newEmail}) async {
    resendEmailChangeCodeCalls++;
  }

  @override
  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {
    confirmEmailChangeCalls++;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    updatePasswordCalls++;
  }

  @override
  Future<User?> updateUserMetadata({required Map<String, dynamic> data}) async {
    updateUserMetadataCalls++;
    return null;
  }

  @override
  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    uploadProfileAvatarCalls++;
    return 'https://example.com/avatar.png';
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  Future<UserProfile?> fetchProfile() async {
    fetchProfileCalls++;
    return const UserProfile(
      name: 'Tester',
      phone: '0123',
      address: 'Address',
      accountType: 'customer',
      promoEmailOptIn: false,
    );
  }

  @override
  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async {
    upsertProfileCalls++;
    return UserProfile(
      name: name,
      phone: phone,
      address: address,
      accountType: 'customer',
      promoEmailOptIn: promoEmailOptIn ?? false,
    );
  }
}

void main() {
  test('AuthUseCases delegates auth and profile operations', () async {
    final repo = _FakeAuthRepository();
    final useCases = AuthUseCases(repo);

    await useCases.register(email: 'a@b.com', password: 'secret');
    await useCases.login(email: 'a@b.com', password: 'secret');
    await useCases.resendSignupVerification(email: 'a@b.com');
    await useCases.verifySignupCode(email: 'a@b.com', code: '123456');
    await useCases.requestEmailChange(newEmail: 'new@b.com');
    await useCases.resendEmailChangeCode(newEmail: 'new@b.com');
    await useCases.confirmEmailChange(newEmail: 'new@b.com', code: '123456');
    await useCases.updatePassword(
      currentPassword: 'oldsecret',
      newPassword: 'supersecret',
    );
    await useCases.updateUserMetadata(
      data: const <String, dynamic>{'notify_order_updates': true},
    );
    await useCases.uploadProfileAvatar(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileName: 'avatar.png',
    );
    final profile = await useCases.fetchProfile();
    await useCases.upsertProfile(name: 'A', phone: '1', address: 'B');
    await useCases.logout();

    expect(repo.registerCalls, 1);
    expect(repo.loginCalls, 1);
    expect(repo.resendSignupVerificationCalls, 1);
    expect(repo.verifySignupCodeCalls, 1);
    expect(repo.requestEmailChangeCalls, 1);
    expect(repo.resendEmailChangeCodeCalls, 1);
    expect(repo.confirmEmailChangeCalls, 1);
    expect(repo.updatePasswordCalls, 1);
    expect(repo.updateUserMetadataCalls, 1);
    expect(repo.uploadProfileAvatarCalls, 1);
    expect(repo.fetchProfileCalls, 1);
    expect(repo.upsertProfileCalls, 1);
    expect(repo.logoutCalls, 1);
    expect(profile?.name, 'Tester');
  });
}
