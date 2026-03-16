import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';

class _FakeProductRepository implements ProductRepository {
  _FakeProductRepository({required this.products});

  final List<Product> products;

  @override
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  }) async {
    return products;
  }

  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async => null;

  @override
  Future<Map<String, int>> fetchVariantStocks({
    required String productId,
  }) async {
    return const <String, int>{};
  }

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async {
    return const <String>{};
  }
}

List<Product> _buildProducts(int count) {
  return List<Product>.generate(count, (index) {
    final isShoes = index.isEven;
    return Product(
      id: 'p$index',
      name: 'Product $index',
      price: 10 + index.toDouble(),
      imageUrl: '',
      description: '',
      category: isShoes ? 'Shoes' : 'Shirts',
    );
  });
}

void main() {
  test('fetchProducts uses staged visibility pagination', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(products: _buildProducts(65)),
      ),
    );

    await provider.fetchProducts();

    expect(provider.visible.length, 30);
    expect(provider.canLoadMore, true);

    provider.loadMoreVisible();
    expect(provider.visible.length, 60);

    provider.loadMoreVisible();
    expect(provider.visible.length, 65);
    expect(provider.canLoadMore, false);
  });

  test('category state helpers follow selected filters', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(products: _buildProducts(4)),
      ),
    );

    await provider.fetchProducts();

    provider.setCategory('Shoes');
    expect(provider.isCategorySelected('Shoes'), true);
    expect(provider.isCategorySelected('All'), false);
    expect(provider.filtered.length, 2);

    provider.clearCategoryFilters();
    expect(provider.isCategorySelected('All'), true);
    expect(provider.filtered.length, 4);
  });
}
