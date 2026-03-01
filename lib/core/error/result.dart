import 'package:marketflow/core/error/failure.dart';

sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    _ => null,
  };

  Failure? get failureOrNull => switch (this) {
    FailureResult<T>(:final failure) => failure,
    _ => null,
  };

  T get requireValue {
    final T? value = valueOrNull;
    if (value != null) {
      return value;
    }
    throw StateError('Result has no success value');
  }

  Failure get requireFailure {
    final Failure? failure = failureOrNull;
    if (failure != null) {
      return failure;
    }
    throw StateError('Result has no failure value');
  }

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    if (this is Success<T>) {
      return onSuccess((this as Success<T>).value);
    }
    return onFailure((this as FailureResult<T>).failure);
  }

  static Future<Result<T>> guard<T>(
    Future<T> Function() action, {
    Failure Function(Object error, StackTrace stackTrace)? mapError,
  }) async {
    try {
      return Success<T>(await action());
    } catch (error, stackTrace) {
      final failure =
          mapError?.call(error, stackTrace) ??
          UnknownFailure(
            'Unexpected error',
            cause: error,
            stackTrace: stackTrace,
          );
      return FailureResult<T>(failure);
    }
  }
}

final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

final class FailureResult<T> extends Result<T> {
  final Failure failure;
  const FailureResult(this.failure);
}
