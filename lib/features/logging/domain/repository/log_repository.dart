import 'package:marketflow/core/error/result.dart';

abstract class LogRepository {
  Future<Result<void>> log({
    required String level,
    required String feature,
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
    String? userId,
  });
}
