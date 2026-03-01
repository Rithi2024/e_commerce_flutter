import 'package:marketflow/core/error/failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Failure mapDataExceptionToFailure(
  Object error,
  StackTrace stackTrace, {
  String fallbackMessage = 'Unexpected error',
}) {
  if (error is Failure) {
    return error;
  }

  if (_isNetworkError(error)) {
    return NetworkFailure(
      'Network connection failed',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is AuthException) {
    final message = error.message.trim();
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('email not confirmed')) {
      return UnauthorizedFailure(
        message.isEmpty ? 'Authentication failed' : message,
        code: error.statusCode,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return DatabaseFailure(
      message.isEmpty ? 'Authentication request failed' : message,
      code: error.statusCode,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is PostgrestException) {
    final message = error.message.trim();
    final normalized = message.toLowerCase();
    final code = error.code?.trim();

    if (code == 'P0001' ||
        code == '42501' ||
        normalized.contains('admin only') ||
        normalized.contains('permission denied')) {
      return PermissionDeniedFailure(
        message.isEmpty ? 'Permission denied' : message,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (normalized.contains('not authenticated') ||
        normalized.contains('jwt') ||
        normalized.contains('token')) {
      return UnauthorizedFailure(
        message.isEmpty ? 'Unauthorized request' : message,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (normalized.contains('required') ||
        normalized.contains('invalid') ||
        normalized.contains('must be')) {
      return ValidationFailure(
        message.isEmpty ? 'Invalid request' : message,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (normalized.contains('not found')) {
      return NotFoundFailure(
        message.isEmpty ? 'Not found' : message,
        code: code,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return DatabaseFailure(
      message.isEmpty ? fallbackMessage : message,
      code: code,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is Exception) {
    return UnknownFailure(
      error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  return UnknownFailure(fallbackMessage, cause: error, stackTrace: stackTrace);
}

bool _isNetworkError(Object error) {
  final typeName = error.runtimeType.toString();
  return typeName == 'SocketException' ||
      typeName == 'HandshakeException' ||
      typeName == 'ClientException';
}
