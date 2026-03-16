class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String description;
  final String? category;
  final DateTime? createdAt;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.description,
    required this.category,
    this.createdAt,
  });

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      name: (data['name'] ?? '').toString(),
      price: (data['price'] ?? 0).toDouble(),
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? 'All').toString(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }
}

String slugifyProductRouteKey(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 'product';
  }

  final buffer = StringBuffer();
  var previousWasSeparator = false;
  for (final rune in normalized.runes) {
    final isDigit = rune >= 48 && rune <= 57;
    final isLowercaseLetter = rune >= 97 && rune <= 122;
    if (isDigit || isLowercaseLetter) {
      buffer.writeCharCode(rune);
      previousWasSeparator = false;
      continue;
    }
    if (!previousWasSeparator && buffer.length > 0) {
      buffer.write('-');
      previousWasSeparator = true;
    }
  }

  final slug = buffer.toString().replaceFirst(RegExp(r'-+$'), '');
  return slug.isEmpty ? 'product' : slug;
}

extension ProductRouteKeyX on Product {
  String get slug => slugifyProductRouteKey(name);

  bool matchesRouteKey(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) {
      return false;
    }

    final normalizedId = id.trim().toLowerCase();
    return value == normalizedId ||
        value == slug ||
        slugifyProductRouteKey(value) == slug;
  }
}
