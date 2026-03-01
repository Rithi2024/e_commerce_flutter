class BackendProxyConfig {
  static const endpoint = String.fromEnvironment(
    'BACKEND_PROXY_URL',
    defaultValue: '',
  );
  static const dataEndpoint = String.fromEnvironment(
    'BACKEND_DATA_PROXY_URL',
    defaultValue: '',
  );

  static const timeoutSeconds = int.fromEnvironment(
    'BACKEND_PROXY_TIMEOUT_SECONDS',
    defaultValue: 20,
  );

  static bool get isEnabled => endpoint.trim().isNotEmpty;
  static bool get isDataProxyEnabled => dataEndpoint.trim().isNotEmpty;
}
