class ProfileIdentityText {
  static const List<String> _nameMetadataKeys = <String>[
    'name',
    'full_name',
    'fullName',
    'display_name',
    'displayName',
  ];

  static const List<String> _phoneMetadataKeys = <String>[
    'phone',
    'phone_number',
    'phoneNumber',
    'mobile',
  ];

  static String displayName({
    required String explicitName,
    Map<String, dynamic>? userMetadata,
    String email = '',
    String fallback = 'Your profile',
  }) {
    final resolvedName = _firstNonEmptyValue(
      explicitValue: explicitName,
      metadata: userMetadata,
      metadataKeys: _nameMetadataKeys,
    );
    if (resolvedName.isNotEmpty) return resolvedName;

    final derivedFromEmail = _friendlyNameFromEmail(email);
    if (derivedFromEmail.isNotEmpty) return derivedFromEmail;

    return fallback;
  }

  static String contactName({
    required String explicitName,
    Map<String, dynamic>? userMetadata,
    String email = '',
  }) {
    return displayName(
      explicitName: explicitName,
      userMetadata: userMetadata,
      email: email,
      fallback: '',
    );
  }

  static String contactPhone({
    required String explicitPhone,
    Map<String, dynamic>? userMetadata,
  }) {
    return _firstNonEmptyValue(
      explicitValue: explicitPhone,
      metadata: userMetadata,
      metadataKeys: _phoneMetadataKeys,
    );
  }

  static String _firstNonEmptyValue({
    required String explicitValue,
    Map<String, dynamic>? metadata,
    required List<String> metadataKeys,
  }) {
    final normalizedExplicit = explicitValue.trim();
    if (normalizedExplicit.isNotEmpty) return normalizedExplicit;

    final source = metadata ?? const <String, dynamic>{};
    for (final key in metadataKeys) {
      final value = (source[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _friendlyNameFromEmail(String email) {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return '';

    final localPart = normalizedEmail.split('@').first.trim();
    if (localPart.isEmpty) return '';

    final words = localPart
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map(
          (word) =>
              word[0].toUpperCase() +
              (word.length > 1 ? word.substring(1).toLowerCase() : ''),
        )
        .toList();
    if (words.isEmpty) return '';
    return words.join(' ');
  }
}
