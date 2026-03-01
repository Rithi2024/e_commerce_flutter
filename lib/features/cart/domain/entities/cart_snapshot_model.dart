import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';

class CartSnapshot {
  final List<CartItem> items;
  final double total;

  const CartSnapshot({required this.items, required this.total});
}
