class CartItem {
  final String id; // unique cart key (e.g. productId_size_color)
  final String productId;
  final String name;
  final double price;
  final String imageUrl;
  final String? size;
  final String? color;
  final int qty;

  CartItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.qty,
    this.size,
    this.color,
  });

  double get subTotal => price * qty;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'qty': qty,
      'size': size,
      'color': color,
    };
  }

  factory CartItem.fromMap(String id, Map<String, dynamic> data) {
    return CartItem(
      id: id,
      productId: (data['productId'] ?? data['product_id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      price: (data['price'] ?? 0).toDouble(),
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      qty: (data['qty'] as num?)?.toInt() ?? 1,
      size: data['size']?.toString(),
      color: data['color']?.toString(),
    );
  }
}
