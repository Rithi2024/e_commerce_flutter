class WebSessionConfig {
  static const isEnabled = bool.fromEnvironment(
    'WEB_SESSION_TIMEOUT_ENABLED',
    defaultValue: true,
  );

  static const timeoutMinutes = int.fromEnvironment(
    'WEB_SESSION_TIMEOUT_MINUTES',
    defaultValue: 30,
  );

  static Duration get timeout {
    final normalizedMinutes = timeoutMinutes < 1 ? 30 : timeoutMinutes;
    return Duration(minutes: normalizedMinutes);
  }
}
