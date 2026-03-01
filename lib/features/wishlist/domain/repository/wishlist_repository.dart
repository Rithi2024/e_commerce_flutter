abstract class WishlistRepository {
  Future<Set<String>> loadWishlistIds();

  Future<bool> toggleWishlist(String productId);
}
