import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/logging/domain/repository/log_repository.dart';

class LogUseCases {
  final LogRepository _repository;

  const LogUseCases(this._repository);

  Future<Result<void>> info({
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  }) {
    return log(
      level: 'info',
      feature: feature,
      action: action,
      message: message,
      metadata: metadata,
      userId: userId,
    );
  }

  Future<Result<void>> warning({
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  }) {
    return log(
      level: 'warning',
      feature: feature,
      action: action,
      message: message,
      metadata: metadata,
      userId: userId,
    );
  }

  Future<Result<void>> error({
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  }) {
    return log(
      level: 'error',
      feature: feature,
      action: action,
      message: message,
      metadata: metadata,
      userId: userId,
    );
  }

  Future<Result<void>> log({
    required String level,
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  }) {
    return _repository.log(
      level: level,
      feature: feature,
      action: action,
      message: message,
      metadata: metadata,
      userId: userId,
    );
  }
}
