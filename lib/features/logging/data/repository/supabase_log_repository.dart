import 'package:marketflow/core/error/failure_mapper.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/features/logging/domain/repository/log_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseLogRepository implements LogRepository {
  final SupabaseClient _db;
  final SupabaseDataProxy _dataProxy;

  SupabaseLogRepository({required SupabaseClient db})
    : _db = db,
      _dataProxy = SupabaseDataProxy(db: db);

  @override
  Future<Result<void>> log({
    required String level,
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  }) async {
    try {
      await _dataProxy.rpc(
        'rpc_app_log',
        params: {
          'p_level': level,
          'p_feature': feature,
          'p_action': action,
          'p_message': message,
          'p_metadata': metadata,
          'p_user_id': userId ?? _db.auth.currentUser?.id,
        },
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Could not save log entry',
        ),
      );
    }
  }
}
