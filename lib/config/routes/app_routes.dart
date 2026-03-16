class AppRoutes {
  static const String home = '/';
  static const String support = '/support';
  static const String staff = '/staff';
  static const String admin = '/admin';

  const AppRoutes._();

  static String homeWithQuery(Map<String, String> queryParameters) {
    return Uri(
      path: home,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  static String catalogRoute({
    String? collection,
    String? productKey,
    String? productId,
  }) {
    final query = <String, String>{};
    final normalizedCollection = (collection ?? '').trim();
    final normalizedProductKey = (productKey ?? productId ?? '').trim();
    if (normalizedCollection.isNotEmpty) {
      query['collection'] = normalizedCollection;
    }
    if (normalizedProductKey.isNotEmpty) {
      query['product'] = normalizedProductKey;
    }
    return homeWithQuery(query);
  }

  static Uri catalogUri({
    Uri? baseUri,
    String? collection,
    String? productKey,
    String? productId,
  }) {
    final route = Uri.parse(
      catalogRoute(
        collection: collection,
        productKey: productKey,
        productId: productId,
      ),
    );
    final normalizedBaseUri = _normalizedShareBaseUri(baseUri);
    if (normalizedBaseUri == null) {
      return route;
    }
    return normalizedBaseUri.replace(
      path: normalizedBaseUri.path.isEmpty ? '/' : normalizedBaseUri.path,
      queryParameters: route.queryParameters.isEmpty
          ? null
          : route.queryParameters,
    );
  }

  static Uri? _normalizedShareBaseUri(Uri? overrideBaseUri) {
    final candidate = overrideBaseUri ?? Uri.base;
    final isSupportedScheme =
        candidate.scheme == 'http' || candidate.scheme == 'https';
    if (!isSupportedScheme || candidate.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: candidate.scheme,
      host: candidate.host,
      port: candidate.hasPort ? candidate.port : null,
      path: _normalizedBasePath(candidate.path),
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
