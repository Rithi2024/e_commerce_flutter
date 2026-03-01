import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthUseCases {
  final AuthRepository _repository;

  const AuthUseCases(this._repository);

  User? currentUser() => _repository.currentUser();

  Stream<User?> onUserChanges() => _repository.onUserChanges();

  Future<User?> register({required String email, required String password}) {
    return _repository.register(email: email, password: password);
  }

  Future<User?> login({required String email, required String password}) {
    return _repository.login(email: email, password: password);
  }

  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) {
    return _repository.sendRegistrationEmails(
      email: email,
      fullName: fullName,
      promoOptIn: promoOptIn,
    );
  }

  Future<void> resendSignupVerification({required String email}) {
    return _repository.resendSignupVerification(email: email);
  }

  Future<void> verifySignupCode({required String email, required String code}) {
    return _repository.verifySignupCode(email: email, code: code);
  }

  Future<void> requestEmailChange({required String newEmail}) {
    return _repository.requestEmailChange(newEmail: newEmail);
  }

  Future<void> resendEmailChangeCode({required String newEmail}) {
    return _repository.resendEmailChangeCode(newEmail: newEmail);
  }

  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) {
    return _repository.confirmEmailChange(newEmail: newEmail, code: code);
  }

  Future<void> logout() => _repository.logout();

  Future<UserProfile?> fetchProfile() => _repository.fetchProfile();

  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) {
    return _repository.upsertProfile(
      name: name,
      phone: phone,
      address: address,
      promoEmailOptIn: promoEmailOptIn,
    );
  }
}
