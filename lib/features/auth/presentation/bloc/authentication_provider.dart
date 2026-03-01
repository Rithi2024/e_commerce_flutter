import 'dart:async';

import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthenticationProvider extends ChangeNotifier {
  final AuthUseCases _useCases;
  final LogUseCases? _logUseCases;
  StreamSubscription<User?>? _authSub;

  User? user;
  String accountType = AccountRole.customerValue;
  AccountRole get accountRole => AccountRole.fromRaw(accountType);

  String get normalizedAccountType => accountRole.normalized;

  bool get isSuperAdmin => accountRole.isSuperAdmin;

  bool get isAdmin => accountRole.isAdmin;

  bool get isCashier => accountRole.isCashier;

  bool get isSupportAgent => accountRole.isSupportAgent;

  bool get isRider => accountRole.isRider;

  bool get isStaff => accountRole.isStaff;

  AuthenticationProvider({
    required AuthUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases {
    user = _useCases.currentUser();
    if (user != null) {
      refreshAccountType(notify: false);
    }

    _authSub = _useCases.onUserChanges().listen((updatedUser) async {
      user = updatedUser;
      if (user == null) {
        accountType = AccountRole.customerValue;
        notifyListeners();
        _logInfo(
          action: 'auth_state_changed',
          metadata: {'state': 'signed_out'},
        );
        return;
      }
      await refreshAccountType(notify: false);
      notifyListeners();
      _logInfo(
        action: 'auth_state_changed',
        metadata: {'state': 'signed_in', 'userId': user?.id},
      );
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String phone,
    bool promoEmailOptIn = false,
  }) async {
    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();
    final phoneDigits = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalizedName.isEmpty) {
      throw ArgumentError('Full name is required');
    }
    if (normalizedPhone.isEmpty || phoneDigits.length < 8) {
      throw ArgumentError('Phone number is required');
    }

    try {
      await _useCases.register(email: email, password: password);
      user = _useCases.currentUser();

      // If email confirmation is required, no auth session exists yet.
      // In that case, skip profile upsert and rely on OTP verification first.
      if (user != null) {
        await _useCases.upsertProfile(
          name: normalizedName,
          phone: normalizedPhone,
          address: '',
          promoEmailOptIn: promoEmailOptIn,
        );
        await refreshAccountType(notify: false);
        notifyListeners();
      } else {
        try {
          await _useCases.resendSignupVerification(email: email.trim());
        } catch (resendError) {
          _logWarning(
            action: 'resend_signup_verification_after_register',
            message: resendError.toString(),
            metadata: {'email': email},
          );
        }
      }

      _logInfo(
        action: 'register',
        metadata: {
          'email': email,
          'userId': user?.id,
          'hasName': normalizedName.isNotEmpty,
          'hasPhone': normalizedPhone.isNotEmpty,
        },
      );
    } catch (error) {
      _logError(
        action: 'register',
        message: error.toString(),
        metadata: {'email': email, 'hasName': true, 'hasPhone': true},
      );
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    try {
      user = await _useCases.login(email: email, password: password);
      await refreshAccountType(notify: false);
      notifyListeners();
      _logInfo(action: 'login', metadata: {'email': email, 'userId': user?.id});
    } catch (error) {
      _logError(
        action: 'login',
        message: error.toString(),
        metadata: {'email': email},
      );
      rethrow;
    }
  }

  Future<void> resendSignupVerification({required String email}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw ArgumentError('Email is required');
    }
    try {
      await _useCases.resendSignupVerification(email: cleanEmail);
      _logInfo(
        action: 'resend_signup_verification',
        metadata: {'email': cleanEmail, 'userId': user?.id},
      );
    } catch (error) {
      _logError(
        action: 'resend_signup_verification',
        message: error.toString(),
        metadata: {'email': cleanEmail, 'userId': user?.id},
      );
      rethrow;
    }
  }

  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    final cleanEmail = email.trim();
    final cleanCode = code.trim();
    if (cleanEmail.isEmpty) {
      throw ArgumentError('Email is required');
    }
    if (cleanCode.isEmpty) {
      throw ArgumentError('Verification code is required');
    }
    try {
      await _useCases.verifySignupCode(email: cleanEmail, code: cleanCode);
      user = _useCases.currentUser();
      if (user != null) {
        await refreshAccountType(notify: false);
      }
      notifyListeners();
      _logInfo(
        action: 'verify_signup_code',
        metadata: {'email': cleanEmail, 'userId': user?.id},
      );
    } catch (error) {
      _logError(
        action: 'verify_signup_code',
        message: error.toString(),
        metadata: {'email': cleanEmail},
      );
      rethrow;
    }
  }

  Future<void> requestEmailChange({required String newEmail}) async {
    final cleanEmail = newEmail.trim();
    try {
      await _useCases.requestEmailChange(newEmail: cleanEmail);
      _logInfo(
        action: 'request_email_change',
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
    } catch (error) {
      _logError(
        action: 'request_email_change',
        message: error.toString(),
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
      rethrow;
    }
  }

  Future<void> resendEmailChangeCode({required String newEmail}) async {
    final cleanEmail = newEmail.trim();
    try {
      await _useCases.resendEmailChangeCode(newEmail: cleanEmail);
      _logInfo(
        action: 'resend_email_change_code',
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
    } catch (error) {
      _logError(
        action: 'resend_email_change_code',
        message: error.toString(),
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
      rethrow;
    }
  }

  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {
    final cleanEmail = newEmail.trim();
    try {
      await _useCases.confirmEmailChange(newEmail: cleanEmail, code: code);
      user = _useCases.currentUser();
      notifyListeners();
      _logInfo(
        action: 'confirm_email_change',
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
    } catch (error) {
      _logError(
        action: 'confirm_email_change',
        message: error.toString(),
        metadata: {'newEmail': cleanEmail, 'userId': user?.id},
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      final previousUserId = user?.id;
      await _useCases.logout();
      user = null;
      accountType = AccountRole.customerValue;
      notifyListeners();
      _logInfo(action: 'logout', metadata: {'userId': previousUserId});
    } catch (error) {
      _logError(action: 'logout', message: error.toString());
      rethrow;
    }
  }

  Future<UserProfile?> loadProfile() {
    return _useCases.fetchProfile();
  }

  Future<UserProfile?> saveProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async {
    final profile = await _useCases.upsertProfile(
      name: name,
      phone: phone,
      address: address,
      promoEmailOptIn: promoEmailOptIn,
    );
    if (profile != null) {
      accountType = profile.accountType.isEmpty
          ? AccountRole.customerValue
          : profile.accountType;
      notifyListeners();
      _logInfo(
        action: 'save_profile',
        metadata: {'accountType': accountType, 'userId': user?.id},
      );
    }
    return profile;
  }

  Future<void> refreshAccountType({bool notify = true}) async {
    if (user == null) {
      accountType = AccountRole.customerValue;
      if (notify) notifyListeners();
      return;
    }

    try {
      final profile = await _useCases.fetchProfile();
      final nextType = profile?.accountType.trim();
      accountType = (nextType == null || nextType.isEmpty)
          ? AccountRole.customerValue
          : nextType;
    } catch (_) {
      accountType = AccountRole.customerValue;
      _logWarning(
        action: 'refresh_account_type',
        message: 'Falling back to customer account type',
      );
    }

    if (notify) notifyListeners();
  }

  void _logInfo({
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.info(
        feature: 'auth',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logWarning({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.warning(
        feature: 'auth',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logError({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.error(
        feature: 'auth',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
