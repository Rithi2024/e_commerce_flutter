import 'package:marketflow/features/cart/domain/entities/cart_snapshot_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/cart/domain/repository/cart_repository.dart';

class CartUseCases {
  final CartRepository _repository;

  const CartUseCases(this._repository);

  Future<CartSnapshot> loadCart() => _repository.loadCart();

  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) {
    return _repository.addToCart(
      product: product,
      size: size,
      color: color,
      quantity: quantity,
    );
  }

  Future<void> setCartQuantity({required String cartId, required int qty}) {
    return _repository.setCartQuantity(cartId: cartId, qty: qty);
  }

  Future<void> clearCart() => _repository.clearCart();
}
