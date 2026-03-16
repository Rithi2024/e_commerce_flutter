import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_rating_summary.dart';

abstract class ProductRepository {
  Future<List<Product>> fetchProducts({
    required String query,
    required String category,
  });

  Future<Map<String, dynamic>?> fetchActiveEvent();

  Future<Map<String, int>> fetchVariantStocks({required String productId});

  Future<Set<String>> fetchBestSellerProductIds({
    required int days,
    required int limit,
  });

  Future<Map<String, ProductRatingSummary>> fetchProductRatingSummaries({
    required Iterable<String> productIds,
  });
}
