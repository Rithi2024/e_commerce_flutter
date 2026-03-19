String _normalizeAuthError(Object error) {
  final raw = error.toString().trim();
  return raw.replaceFirst('Exception: ', '').trim();
}

bool requiresEmailVerification(Object error) {
  final normalized = _normalizeAuthError(error);
  return normalized.toLowerCase().contains('email not confirmed');
}

String friendlyAuthErrorMessage(Object error) {
  final normalized = _normalizeAuthError(error);
  final lower = normalized.toLowerCase();

  if (lower.contains('invalid login credentials')) {
    return 'Invalid email or password.';
  }
  if (requiresEmailVerification(error)) {
    return 'Please verify using the code sent to your email.';
  }
  if (lower.contains('already registered') ||
      lower.contains('user already exists')) {
    return 'This email is already registered. Please sign in.';
  }
  if (lower.contains('too many requests') || lower.contains('rate limit')) {
    return 'Too many attempts. Please wait and try again.';
  }
  if (lower.contains('network') ||
      lower.contains('connection') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup')) {
    return 'Network error. Check your internet connection and try again.';
  }
  if (lower.contains('password') && lower.contains('at least')) {
    return 'Password must be at least 6 characters.';
  }
  if ((lower.contains('invalid') || lower.contains('expired')) &&
      (lower.contains('otp') ||
          lower.contains('code') ||
          lower.contains('token'))) {
    return 'Invalid or expired verification code.';
  }
  if (normalized.isNotEmpty && normalized.length <= 120) {
    return normalized;
  }
  return 'Something went wrong. Please try again.';
}
