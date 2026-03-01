import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';

class ProductUseCases {
  final ProductRepository _repository;

  const ProductUseCases(this._repository);

  Future<List<Product>> fetchProducts({
    String query = '',
    String category = 'All',
  }) {
    return _repository.fetchProducts(query: query, category: category);
  }

  Future<Map<String, dynamic>?> fetchActiveEvent() {
    return _repository.fetchActiveEvent();
  }

  Future<Map<String, int>> fetchVariantStocks({required String productId}) {
    return _repository.fetchVariantStocks(productId: productId);
  }

  Future<Set<String>> fetchBestSellerProductIds({
    int days = 30,
    int limit = 5,
  }) {
    return _repository.fetchBestSellerProductIds(days: days, limit: limit);
  }
}
