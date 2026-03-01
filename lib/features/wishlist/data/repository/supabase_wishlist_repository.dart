import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseWishlistRepository implements WishlistRepository {
  final SupabaseDataProxy _dataProxy;

  SupabaseWishlistRepository({required SupabaseClient db})
    : _dataProxy = SupabaseDataProxy(db: db);

  @override
  Future<Set<String>> loadWishlistIds() async {
    final dynamic rows = await _dataProxy.rpc('rpc_get_wishlist_ids');
    return (rows is List ? rows : const <dynamic>[])
        .whereType<Map>()
        .map((row) => (row['product_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  @override
  Future<bool> toggleWishlist(String productId) async {
    final result = await _dataProxy.rpc(
      'rpc_toggle_wishlist',
      params: {'p_product_id': productId},
    );
    return result == true || result?.toString() == 'true';
  }
}
