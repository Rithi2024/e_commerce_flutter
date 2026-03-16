class StorefrontConfig {
  static const publicUrl = String.fromEnvironment(
    'STOREFRONT_PUBLIC_URL',
    defaultValue: '',
  );

  static Uri? get publicUri => parsePublicUri(publicUrl);

  static Uri? parsePublicUri(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }

    final isSupportedScheme = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isSupportedScheme || uri.host.isEmpty) {
      return null;
    }

    final normalizedPath = _normalizedBasePath(uri.path);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: normalizedPath,
    );
  }

  static String _normalizedBasePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '/';
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}
