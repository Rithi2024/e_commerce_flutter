class Failure {
  final String message;
  final String? code;
  final Object? cause;
  final StackTrace? stackTrace;

  const Failure(this.message, {this.code, this.cause, this.stackTrace});

  @override
  String toString() {
    if (code == null || code!.trim().isEmpty) {
      return message;
    }
    return '[$code] $message';
  }
}

class UnauthorizedFailure extends Failure {
  UnauthorizedFailure(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

class PermissionDeniedFailure extends Failure {
  PermissionDeniedFailure(
    super.message, {
    super.code,
    super.cause,
    super.stackTrace,
  });
}

class ValidationFailure extends Failure {
  ValidationFailure(super.message, {super.code, super.cause, super.stackTrace});
}

class NotFoundFailure extends Failure {
  NotFoundFailure(super.message, {super.code, super.cause, super.stackTrace});
}

class NetworkFailure extends Failure {
  NetworkFailure(super.message, {super.code, super.cause, super.stackTrace});
}

class DatabaseFailure extends Failure {
  DatabaseFailure(super.message, {super.code, super.cause, super.stackTrace});
}

class UnknownFailure extends Failure {
  UnknownFailure(super.message, {super.code, super.cause, super.stackTrace});
}
