import 'package:marketflow/config/auth_email_config.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/core/network/supabase_function_proxy.dart';
import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _db;
  final SupabaseFunctionProxy _functionProxy;
  final SupabaseDataProxy _dataProxy;

  SupabaseAuthRepository({required SupabaseClient db})
    : _db = db,
      _functionProxy = SupabaseFunctionProxy(db: db),
      _dataProxy = SupabaseDataProxy(db: db);

  @override
  User? currentUser() => _db.auth.currentUser;

  @override
  Stream<User?> onUserChanges() {
    return _db.auth.onAuthStateChange.map((event) => event.session?.user);
  }

  @override
  Future<User?> register({
    required String email,
    required String password,
  }) async {
    await _db.auth.signUp(email: email, password: password);
    // Return only session-backed user. When email confirmation is required,
    // currentUser is null until OTP/link verification completes.
    return _db.auth.currentUser;
  }

  @override
  Future<User?> login({required String email, required String password}) async {
    final response = await _db.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user ?? _db.auth.currentUser;
  }

  @override
  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) return;

    final payload = <String, dynamic>{
      'operation': 'send_signup_confirmation',
      'email': cleanEmail,
      'full_name': fullName.trim(),
      'promo_opt_in': promoOptIn,
    };

    final functionNames = <String>{
      AuthEmailConfig.functionName.trim(),
      'resend-email',
      'auth-email',
      'registration-email',
    }.where((name) => name.isNotEmpty);

    Object? lastNotFound;
    for (final name in functionNames) {
      try {
        await _functionProxy.invoke(name, body: payload);
        return;
      } on FunctionException catch (error) {
        if (_isFunctionNotFound(error)) {
          lastNotFound = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastNotFound != null) {
      throw lastNotFound;
    }
  }

  @override
  Future<void> resendSignupVerification({required String email}) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw AuthException('Email is required');
    }
    await _db.auth.resend(email: cleanEmail, type: OtpType.signup);
  }

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    final cleanEmail = email.trim();
    final cleanCode = code.trim();
    if (cleanEmail.isEmpty) {
      throw AuthException('Email is required');
    }
    if (cleanCode.isEmpty) {
      throw AuthException('Verification code is required');
    }
    await _db.auth.verifyOTP(
      email: cleanEmail,
      token: cleanCode,
      type: OtpType.signup,
    );
  }

  @override
  Future<void> requestEmailChange({required String newEmail}) async {
    final cleanEmail = newEmail.trim();
    if (cleanEmail.isEmpty) {
      throw AuthException('New email is required');
    }
    await _db.auth.updateUser(UserAttributes(email: cleanEmail));
  }

  @override
  Future<void> resendEmailChangeCode({required String newEmail}) async {
    final cleanEmail = newEmail.trim();
    if (cleanEmail.isEmpty) {
      throw AuthException('New email is required');
    }
    await _db.auth.resend(email: cleanEmail, type: OtpType.emailChange);
  }

  @override
  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {
    final cleanEmail = newEmail.trim();
    final cleanCode = code.trim();
    if (cleanEmail.isEmpty) {
      throw AuthException('New email is required');
    }
    if (cleanCode.isEmpty) {
      throw AuthException('Confirmation code is required');
    }
    await _db.auth.verifyOTP(
      email: cleanEmail,
      token: cleanCode,
      type: OtpType.emailChange,
    );
  }

  @override
  Future<void> logout() => _db.auth.signOut();

  @override
  Future<UserProfile?> fetchProfile() async {
    try {
      final profile = await _dataProxy.rpc('rpc_get_profile');
      final mapped = _mapFromRpcResult(profile);
      if (mapped != null) {
        return UserProfile.fromMap(mapped);
      }
    } catch (error) {
      if (!_isRpcMissing(error)) rethrow;
    }

    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _dataProxy.select(
      table: 'profiles',
      filters: <DataProxyFilter>[DataProxyFilter.eq('id', userId)],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return UserProfile.fromMap(Map<String, dynamic>.from(rows.first as Map));
    }

    await _dataProxy.upsert(
      table: 'profiles',
      values: <String, dynamic>{'id': userId},
      onConflict: 'id',
    );
    final createdRows = await _dataProxy.select(
      table: 'profiles',
      filters: <DataProxyFilter>[DataProxyFilter.eq('id', userId)],
      limit: 1,
    );
    if (createdRows.isNotEmpty) {
      return UserProfile.fromMap(
        Map<String, dynamic>.from(createdRows.first as Map),
      );
    }

    return null;
  }

  bool _isRpcMissing(Object error) {
    if (error is! PostgrestException) return false;
    final code = (error.code ?? '').trim().toUpperCase();
    final message = error.message.toUpperCase();
    return code == '404' ||
        code == 'PGRST202' ||
        message.contains('COULD NOT FIND THE FUNCTION') ||
        message.contains('SCHEMA CACHE');
  }

  Map<String, dynamic>? _mapFromRpcResult(dynamic profile) {
    if (profile is Map<String, dynamic>) return profile;
    if (profile is Map) return Map<String, dynamic>.from(profile);
    if (profile is List && profile.isNotEmpty) {
      final first = profile.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  @override
  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async {
    try {
      await _dataProxy.rpc(
        'rpc_upsert_profile',
        params: {
          'p_name': name,
          'p_phone': phone,
          'p_address': address,
          'p_promo_email_opt_in': promoEmailOptIn,
        },
      );
    } catch (error) {
      if (!_isRpcMissing(error)) rethrow;
      final userId = _db.auth.currentUser?.id;
      if (userId == null) return null;
      final row = <String, dynamic>{
        'id': userId,
        'name': name,
        'phone': phone,
        'address': address,
      };
      if (promoEmailOptIn != null) {
        row['promo_email_opt_in'] = promoEmailOptIn;
      }
      await _dataProxy.upsert(table: 'profiles', values: row, onConflict: 'id');
    }
    return fetchProfile();
  }

  bool _isFunctionNotFound(FunctionException error) {
    if (error.status != 404) return false;
    final details = error.details;
    if (details is Map) {
      final code = (details['code'] ?? '').toString().trim().toUpperCase();
      final message = (details['message'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      return code == 'NOT_FOUND' ||
          message.contains('REQUESTED FUNCTION WAS NOT FOUND');
    }
    return true;
  }
}
