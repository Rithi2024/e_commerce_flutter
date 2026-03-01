import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/cart/domain/entities/cart_snapshot_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/cart/domain/repository/cart_repository.dart';
import 'package:marketflow/features/cart/domain/usecases/cart_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCartRepository implements CartRepository {
  String? lastCartId;
  int? lastQty;
  Product? lastProduct;
  int clearCalls = 0;

  @override
  Future<CartSnapshot> loadCart() async {
    return CartSnapshot(
      items: [
        CartItem(
          id: 'c1',
          productId: 'p1',
          name: 'Item',
          price: 2,
          imageUrl: '',
          qty: 2,
        ),
      ],
      total: 4,
    );
  }

  @override
  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) async {
    lastProduct = product;
  }

  @override
  Future<void> setCartQuantity({
    required String cartId,
    required int qty,
  }) async {
    lastCartId = cartId;
    lastQty = qty;
  }

  @override
  Future<void> clearCart() async {
    clearCalls++;
  }
}

void main() {
  test('CartUseCases delegates cart operations', () async {
    final repo = _FakeCartRepository();
    final useCases = CartUseCases(repo);
    final product = Product(
      id: 'p1',
      name: 'Tee',
      price: 10,
      imageUrl: '',
      description: '',
      category: 'All',
    );

    final snapshot = await useCases.loadCart();
    await useCases.addToCart(product: product);
    await useCases.setCartQuantity(cartId: 'c1', qty: 3);
    await useCases.clearCart();

    expect(snapshot.total, 4);
    expect(repo.lastProduct?.id, 'p1');
    expect(repo.lastCartId, 'c1');
    expect(repo.lastQty, 3);
    expect(repo.clearCalls, 1);
  });
}
