import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWishlistRepository implements WishlistRepository {
  String? lastToggleId;

  @override
  Future<Set<String>> loadWishlistIds() async => {'p1', 'p2'};

  @override
  Future<bool> toggleWishlist(String productId) async {
    lastToggleId = productId;
    return true;
  }
}

void main() {
  test('WishlistUseCases delegates wishlist operations', () async {
    final repo = _FakeWishlistRepository();
    final useCases = WishlistUseCases(repo);

    final ids = await useCases.loadWishlistIds();
    final isFav = await useCases.toggleWishlist('p1');

    expect(ids, containsAll({'p1', 'p2'}));
    expect(repo.lastToggleId, 'p1');
    expect(isFav, isTrue);
  });
}
