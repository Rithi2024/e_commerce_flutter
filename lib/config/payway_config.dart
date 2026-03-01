class PayWayConfig {
  static const functionName = String.fromEnvironment(
    'PAYWAY_FUNCTION_NAME',
    defaultValue: 'Payway',
  );

  static const callbackUrl = String.fromEnvironment(
    'PAYWAY_CALLBACK_URL',
    defaultValue: '',
  );

  static const currency = String.fromEnvironment(
    'PAYWAY_CURRENCY',
    defaultValue: 'USD',
  );

  static const qrTemplate = String.fromEnvironment(
    'PAYWAY_QR_TEMPLATE',
    defaultValue: 'template3_color',
  );

  static const qrLifetimeMinutes = int.fromEnvironment(
    'PAYWAY_QR_LIFETIME_MINUTES',
    defaultValue: 15,
  );
}
