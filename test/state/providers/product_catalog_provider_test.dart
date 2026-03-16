import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';

class _FakeProductRepository implements ProductRepository {
  _FakeProductRepository({
    required this.products,
    this.stocksByProductId = const <String, Map<String, int>>{},
    this.bestSellerProductIds = const <String>{},
    this.ratingSummaries = const <String, ProductRatingSummary>{},
  });

  final List<Product> products;
  final Map<String, Map<String, int>> stocksByProductId;
  final Set<String> bestSellerProductIds;
  final Map<String, ProductRatingSummary> ratingSummaries;

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
    return stocksByProductId[productId] ?? const <String, int>{};
  }

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async {
    return bestSellerProductIds;
  }

  @override
  Future<Map<String, ProductRatingSummary>> fetchProductRatingSummaries({
    required Iterable<String> productIds,
  }) async {
    return {
      for (final productId in productIds)
        productId:
            ratingSummaries[productId] ??
            const ProductRatingSummary(ratingCount: 0, averageRating: 0),
    };
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
      createdAt: DateTime(2026, 1, 1).add(Duration(days: index)),
    );
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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

  test('advanced filters keep only matching in-stock products', () async {
    final products = <Product>[
      Product(
        id: 'shoe-1',
        name: 'Daily Runner',
        price: 24,
        imageUrl: '',
        description: '',
        category: 'Shoes',
        createdAt: DateTime(2026, 3, 12),
      ),
      Product(
        id: 'shoe-2',
        name: 'Sold Out Sneaker',
        price: 28,
        imageUrl: '',
        description: '',
        category: 'Shoes',
        createdAt: DateTime(2026, 3, 10),
      ),
      Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 26,
        imageUrl: '',
        description: '',
        category: 'Shirts',
        createdAt: DateTime(2026, 3, 8),
      ),
    ];
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: products,
          stocksByProductId: const <String, Map<String, int>>{
            'shoe-1': <String, int>{'M::Black': 5},
            'shoe-2': <String, int>{'M::Black': 0},
            'shirt-1': <String, int>{'M::White': 7},
          },
        ),
      ),
    );

    await provider.fetchProducts();
    await provider.applyAdvancedFilters(
      categories: const <String>['Shoes'],
      minPrice: 20,
      maxPrice: 25,
      stockOnly: true,
    );

    expect(provider.filtered.map((product) => product.id), <String>['shoe-1']);
    expect(provider.inStockOnly, true);
    expect(provider.activeFilterCount, 3);
  });

  test('rating filter keeps only 4 stars and up products', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: <Product>[
            Product(
              id: 'favorite',
              name: 'Fan Favorite',
              price: 31,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 2),
            ),
            Product(
              id: 'steady',
              name: 'Steady Pick',
              price: 28,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 3),
            ),
            Product(
              id: 'newcomer',
              name: 'Newcomer',
              price: 24,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 4),
            ),
          ],
          ratingSummaries: const <String, ProductRatingSummary>{
            'favorite': ProductRatingSummary(
              ratingCount: 48,
              averageRating: 4.9,
              reviewCount: 14,
            ),
            'steady': ProductRatingSummary(
              ratingCount: 22,
              averageRating: 4.2,
              reviewCount: 7,
            ),
            'newcomer': ProductRatingSummary(
              ratingCount: 3,
              averageRating: 3.6,
              reviewCount: 0,
            ),
          },
        ),
      ),
    );

    await provider.fetchProducts();
    await provider.applyAdvancedFilters(
      categories: const <String>[],
      minPrice: 0,
      maxPrice: 100,
      stockOnly: false,
      minimumRating: 4,
    );

    expect(provider.filtered.map((product) => product.id), <String>[
      'steady',
      'favorite',
    ]);
    expect(provider.minimumRatingFilter, 4);
    expect(provider.activeFilterCount, 1);
  });

  test('written review filter keeps only products with review text', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: <Product>[
            Product(
              id: 'favorite',
              name: 'Fan Favorite',
              price: 31,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 2),
            ),
            Product(
              id: 'steady',
              name: 'Steady Pick',
              price: 28,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 3),
            ),
            Product(
              id: 'silent',
              name: 'Silent Listing',
              price: 24,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 4),
            ),
          ],
          ratingSummaries: const <String, ProductRatingSummary>{
            'favorite': ProductRatingSummary(
              ratingCount: 48,
              averageRating: 4.9,
              reviewCount: 14,
            ),
            'steady': ProductRatingSummary(
              ratingCount: 22,
              averageRating: 4.2,
              reviewCount: 2,
            ),
            'silent': ProductRatingSummary(
              ratingCount: 17,
              averageRating: 4.7,
              reviewCount: 0,
            ),
          },
        ),
      ),
    );

    await provider.fetchProducts();
    await provider.applyAdvancedFilters(
      categories: const <String>[],
      minPrice: 0,
      maxPrice: 100,
      stockOnly: false,
      writtenReviewsOnly: true,
    );

    expect(provider.filtered.map((product) => product.id), <String>[
      'steady',
      'favorite',
    ]);
    expect(provider.writtenReviewsOnly, isTrue);
    expect(provider.activeFilterCount, 1);
  });

  test('popular sort prioritizes best sellers', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: <Product>[
            Product(
              id: 'fresh',
              name: 'Fresh Drop',
              price: 30,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 15),
            ),
            Product(
              id: 'best-seller',
              name: 'Top Pick',
              price: 35,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 1),
            ),
          ],
          bestSellerProductIds: const <String>{'best-seller'},
        ),
      ),
    );

    await provider.fetchProducts();
    await provider.setSortOption(CatalogSortOption.popular);

    expect(provider.filtered.first.id, 'best-seller');
  });

  test('top rated sort prioritizes highest rated products', () async {
    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: <Product>[
            Product(
              id: 'steady',
              name: 'Steady Pick',
              price: 28,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 3),
            ),
            Product(
              id: 'favorite',
              name: 'Fan Favorite',
              price: 31,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 2),
            ),
          ],
          ratingSummaries: const <String, ProductRatingSummary>{
            'steady': ProductRatingSummary(
              ratingCount: 22,
              averageRating: 4.4,
              reviewCount: 5,
            ),
            'favorite': ProductRatingSummary(
              ratingCount: 48,
              averageRating: 4.9,
              reviewCount: 12,
            ),
          },
        ),
      ),
    );

    await provider.fetchProducts();
    await provider.setSortOption(CatalogSortOption.topRated);

    expect(provider.filtered.first.id, 'favorite');
  });

  test(
    'most reviewed sort prioritizes products with written reviews',
    () async {
      final provider = ProductCatalogProvider(
        useCases: ProductUseCases(
          _FakeProductRepository(
            products: <Product>[
              Product(
                id: 'steady',
                name: 'Steady Pick',
                price: 28,
                imageUrl: '',
                description: '',
                category: 'Shoes',
                createdAt: DateTime(2026, 3, 3),
              ),
              Product(
                id: 'favorite',
                name: 'Fan Favorite',
                price: 31,
                imageUrl: '',
                description: '',
                category: 'Shoes',
                createdAt: DateTime(2026, 3, 2),
              ),
              Product(
                id: 'silent',
                name: 'Silent Listing',
                price: 24,
                imageUrl: '',
                description: '',
                category: 'Shoes',
                createdAt: DateTime(2026, 3, 4),
              ),
            ],
            ratingSummaries: const <String, ProductRatingSummary>{
              'steady': ProductRatingSummary(
                ratingCount: 22,
                averageRating: 4.4,
                reviewCount: 5,
              ),
              'favorite': ProductRatingSummary(
                ratingCount: 48,
                averageRating: 4.9,
                reviewCount: 12,
              ),
              'silent': ProductRatingSummary(
                ratingCount: 120,
                averageRating: 4.8,
                reviewCount: 0,
              ),
            },
          ),
        ),
      );

      await provider.fetchProducts();
      await provider.setSortOption(CatalogSortOption.mostReviewed);

      expect(provider.filtered.map((product) => product.id).take(3), <String>[
        'favorite',
        'steady',
        'silent',
      ]);
    },
  );

  test(
    'recently viewed keeps newest selection first without duplicates',
    () async {
      final first = Product(
        id: 'shoe-1',
        name: 'Daily Runner',
        price: 24,
        imageUrl: '',
        description: '',
        category: 'Shoes',
        createdAt: DateTime(2026, 3, 12),
      );
      final second = Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 18,
        imageUrl: '',
        description: '',
        category: 'Shirts',
        createdAt: DateTime(2026, 3, 10),
      );
      final provider = ProductCatalogProvider(
        useCases: ProductUseCases(
          _FakeProductRepository(products: <Product>[first, second]),
        ),
      );

      await provider.fetchProducts();
      provider.recordRecentlyViewed(first);
      provider.recordRecentlyViewed(second);
      provider.recordRecentlyViewed(first);

      expect(
        provider.recentlyViewedProducts.map((product) => product.id),
        <String>['shoe-1', 'shirt-1'],
      );
    },
  );

  test('persisted recently viewed ids restore after fetch', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'product_catalog.recently_viewed_product_ids': <String>[
        'shirt-1',
        'shoe-1',
      ],
    });

    final provider = ProductCatalogProvider(
      useCases: ProductUseCases(
        _FakeProductRepository(
          products: <Product>[
            Product(
              id: 'shoe-1',
              name: 'Daily Runner',
              price: 24,
              imageUrl: '',
              description: '',
              category: 'Shoes',
              createdAt: DateTime(2026, 3, 12),
            ),
            Product(
              id: 'shirt-1',
              name: 'Weekend Tee',
              price: 18,
              imageUrl: '',
              description: '',
              category: 'Shirts',
              createdAt: DateTime(2026, 3, 10),
            ),
          ],
        ),
      ),
    );

    await provider.fetchProducts();

    expect(
      provider.recentlyViewedProducts.map((product) => product.id),
      <String>['shirt-1', 'shoe-1'],
    );
  });

  test(
    'showCollection narrows the catalog to recently viewed products',
    () async {
      final first = Product(
        id: 'shoe-1',
        name: 'Daily Runner',
        price: 24,
        imageUrl: '',
        description: '',
        category: 'Shoes',
        createdAt: DateTime(2026, 3, 12),
      );
      final second = Product(
        id: 'shirt-1',
        name: 'Weekend Tee',
        price: 18,
        imageUrl: '',
        description: '',
        category: 'Shirts',
        createdAt: DateTime(2026, 3, 10),
      );
      final provider = ProductCatalogProvider(
        useCases: ProductUseCases(
          _FakeProductRepository(products: <Product>[first, second]),
        ),
      );

      provider.recordRecentlyViewed(second);
      await provider.fetchProducts();
      provider.showCollection(CatalogCollectionFilter.recentlyViewed);

      expect(provider.activeCollectionLabel, 'Recently viewed');
      expect(provider.filtered.map((product) => product.id), <String>[
        'shirt-1',
      ]);
    },
  );
}
