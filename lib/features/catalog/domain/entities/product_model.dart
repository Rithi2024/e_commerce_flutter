class Product {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String description;
  final String? category;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.description,
    required this.category,
  });

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      name: (data['name'] ?? '').toString(),
      price: (data['price'] ?? 0).toDouble(),
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? 'All').toString(),
    );
  }
}
