class AuthEmailConfig {
  static const functionName = String.fromEnvironment(
    'AUTH_EMAIL_FUNCTION_NAME',
    defaultValue: 'Resend-email',
  );
}
