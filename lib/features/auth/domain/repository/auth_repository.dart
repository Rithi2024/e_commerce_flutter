import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRepository {
  User? currentUser();

  Stream<User?> onUserChanges();

  Future<User?> register({required String email, required String password});

  Future<User?> login({required String email, required String password});

  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  });

  Future<void> resendSignupVerification({required String email});

  Future<void> verifySignupCode({required String email, required String code});

  Future<void> requestEmailChange({required String newEmail});

  Future<void> resendEmailChangeCode({required String newEmail});

  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  });

  Future<void> logout();

  Future<UserProfile?> fetchProfile();

  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  });
}
