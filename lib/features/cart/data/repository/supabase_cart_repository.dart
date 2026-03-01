import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/cart/domain/entities/cart_snapshot_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/features/cart/domain/repository/cart_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCartRepository implements CartRepository {
  final SupabaseDataProxy _dataProxy;

  SupabaseCartRepository({required SupabaseClient db})
    : _dataProxy = SupabaseDataProxy(db: db);

  @override
  Future<CartSnapshot> loadCart() async {
    final dynamic rows = await _dataProxy.rpc('rpc_get_cart_items');
    final items = _parseCartItems(rows);

    final dynamic totalResult = await _dataProxy.rpc('rpc_cart_total');
    final total =
        (totalResult as num?)?.toDouble() ??
        items.fold<double>(
          0,
          (runningTotal, item) => runningTotal + item.subTotal,
        );

    return CartSnapshot(items: items, total: total);
  }

  @override
  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) async {
    final int qtyToAdd = quantity < 1 ? 1 : quantity;
    await _dataProxy.rpc(
      'rpc_add_to_cart',
      params: {
        'p_product_id': product.id,
        'p_name': product.name,
        'p_price': product.price,
        'p_image_url': product.imageUrl,
        'p_size': size,
        'p_color': color,
        'p_qty': qtyToAdd,
      },
    );
  }

  @override
  Future<void> setCartQuantity({
    required String cartId,
    required int qty,
  }) async {
    final int clampedQty = qty < 0 ? 0 : qty;
    await _dataProxy.rpc(
      'rpc_set_cart_qty',
      params: {'p_cart_key': cartId, 'p_qty': clampedQty},
    );
  }

  @override
  Future<void> clearCart() => _dataProxy.rpc('rpc_clear_cart');

  List<CartItem> _parseCartItems(dynamic rows) {
    if (rows is! List) {
      return const <CartItem>[];
    }
    return rows.whereType<Map>().map((Map raw) {
      final Map<String, dynamic> row = Map<String, dynamic>.from(raw);
      return CartItem.fromMap((row['cart_key'] ?? row['id']).toString(), {
        'productId': row['product_id'],
        'name': row['name'],
        'price': row['price'],
        'imageUrl': row['image_url'],
        'qty': row['qty'],
        'size': row['size'],
        'color': row['color'],
      });
    }).toList();
  }
}
