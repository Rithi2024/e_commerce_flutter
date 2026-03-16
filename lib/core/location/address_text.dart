class AddressText {
  static final RegExp _coordinatePairPattern = RegExp(
    r'^-?\d{1,3}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?$',
  );
  static const Set<String> _placeholderValues = <String>{
    'selected location',
    'current location',
    'my address',
    'choose address',
    'search location',
    'default delivery address',
    'no delivery address yet',
    'no delivery address saved yet',
    'no delivery address saved yet.',
    'use current location',
    'select in map',
  };

  static String normalize(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isPlaceholder(String raw) {
    final normalized = normalize(raw).toLowerCase();
    if (normalized.isEmpty) return false;
    return _placeholderValues.contains(normalized);
  }

  static bool isMeaningful(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return false;
    return !isPlaceholder(normalized);
  }

  static bool isCoordinatePair(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return false;
    return _coordinatePairPattern.hasMatch(normalized);
  }

  static String meaningfulOrEmpty(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty || isPlaceholder(normalized)) {
      return '';
    }
    return normalized;
  }

  static bool isDeliveryReady(String raw) {
    final normalized = meaningfulOrEmpty(raw);
    if (normalized.isEmpty) return false;
    return !isCoordinatePair(normalized);
  }

  static String deliveryAddressOrEmpty(String raw) {
    final normalized = meaningfulOrEmpty(raw);
    if (normalized.isEmpty || isCoordinatePair(normalized)) {
      return '';
    }
    return normalized;
  }

  static List<String> uniqueMeaningful(Iterable<String> values) {
    final results = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final normalized = meaningfulOrEmpty(value);
      if (normalized.isEmpty) continue;

      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        results.add(normalized);
      }
    }

    return results;
  }

  static List<String> uniqueDeliveryAddresses(Iterable<String> values) {
    final results = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final normalized = deliveryAddressOrEmpty(value);
      if (normalized.isEmpty) continue;

      final key = normalized.toLowerCase();
      if (seen.add(key)) {
        results.add(normalized);
      }
    }

    return results;
  }
}
