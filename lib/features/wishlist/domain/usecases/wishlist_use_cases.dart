import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';

class WishlistUseCases {
  final WishlistRepository _repository;

  const WishlistUseCases(this._repository);

  Future<Set<String>> loadWishlistIds() => _repository.loadWishlistIds();

  Future<bool> toggleWishlist(String productId) {
    return _repository.toggleWishlist(productId);
  }
}
