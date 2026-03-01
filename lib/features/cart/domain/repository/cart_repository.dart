import 'package:marketflow/features/cart/domain/entities/cart_snapshot_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';

abstract class CartRepository {
  Future<CartSnapshot> loadCart();

  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  });

  Future<void> setCartQuantity({required String cartId, required int qty});

  Future<void> clearCart();
}
