class SupportConfig {
  static const email = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@yourstore.com',
  );

  static const phone = String.fromEnvironment(
    'SUPPORT_PHONE',
    defaultValue: '+10000000000',
  );

  static const whatsAppUrl = String.fromEnvironment(
    'SUPPORT_WHATSAPP_URL',
    defaultValue: '',
  );

  static const telegramUrl = String.fromEnvironment(
    'SUPPORT_TELEGRAM_URL',
    defaultValue: '',
  );

  static const facebookUrl = String.fromEnvironment(
    'SUPPORT_FACEBOOK_URL',
    defaultValue: '',
  );

  static const messengerUrl = String.fromEnvironment(
    'SUPPORT_MESSENGER_URL',
    defaultValue: '',
  );

  static const storeLocationUrl = String.fromEnvironment(
    'SUPPORT_STORE_LOCATION_URL',
    defaultValue: '',
  );

  static const faqUrl = String.fromEnvironment(
    'SUPPORT_FAQ_URL',
    defaultValue: '',
  );

  static const supportHours = String.fromEnvironment(
    'SUPPORT_HOURS',
    defaultValue: 'Mon - Sun, 7:00 AM - 10:00 PM',
  );
}
