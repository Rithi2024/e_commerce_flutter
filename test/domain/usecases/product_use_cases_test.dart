import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProductRepository implements ProductRepository {
  String? lastQuery;
  String? lastCategory;
  String? lastStockProductId;
  int? lastBestSellerDays;
  int? lastBestSellerLimit;
  Iterable<String>? lastRatingProductIds;

  @override
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  }) async {
    lastQuery = query;
    lastCategory = category;
    return [
      Product(
        id: 'p1',
        name: 'Product',
        price: 1,
        imageUrl: '',
        description: '',
        category: 'All',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchActiveEvent() async {
    return {'title': 'Sale'};
  }

  @override
  Future<Map<String, int>> fetchVariantStocks({
    required String productId,
  }) async {
    lastStockProductId = productId;
    return {'M::Black': 2};
  }

  @override
  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  }) async {
    lastBestSellerDays = days;
    lastBestSellerLimit = limit;
    return {'p1', 'p2', 'p3', 'p4', 'p5'};
  }

  @override
  Future<Map<String, ProductRatingSummary>> fetchProductRatingSummaries({
    required Iterable<String> productIds,
  }) async {
    lastRatingProductIds = productIds;
    return <String, ProductRatingSummary>{
      'p1': const ProductRatingSummary(
        ratingCount: 12,
        averageRating: 4.6,
        reviewCount: 5,
      ),
    };
  }
}

void main() {
  test('ProductUseCases delegates product operations', () async {
    final repo = _FakeProductRepository();
    final useCases = ProductUseCases(repo);

    final products = await useCases.fetchProducts(
      query: 'shirt',
      category: 'All',
    );
    final event = await useCases.fetchActiveEvent();
    final stocks = await useCases.fetchVariantStocks(productId: 'p1');
    final bestSellers = await useCases.fetchBestSellerProductIds(
      days: 30,
      limit: 5,
    );
    final ratingSummaries = await useCases.fetchProductRatingSummaries(
      productIds: const <String>['p1', 'p2'],
    );

    expect(products.length, 1);
    expect(repo.lastQuery, 'shirt');
    expect(repo.lastCategory, 'All');
    expect(event?['title'], 'Sale');
    expect(repo.lastStockProductId, 'p1');
    expect(stocks['M::Black'], 2);
    expect(repo.lastBestSellerDays, 30);
    expect(repo.lastBestSellerLimit, 5);
    expect(bestSellers.length, 5);
    expect(repo.lastRatingProductIds, containsAll(<String>['p1', 'p2']));
    expect(ratingSummaries['p1']?.averageRating, 4.6);
    expect(ratingSummaries['p1']?.reviewCount, 5);
  });
}
