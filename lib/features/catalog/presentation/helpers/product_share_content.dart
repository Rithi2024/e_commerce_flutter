import 'package:marketflow/config/routes/app_routes.dart';
import 'package:marketflow/config/storefront_config.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';

class ProductShareContent {
  const ProductShareContent({required this.uri, required this.message});

  final Uri uri;
  final String message;
}

ProductShareContent buildProductShareContent({
  required Product product,
  String? collection,
  Uri? baseUri,
}) {
  final uri = AppRoutes.catalogUri(
    baseUri: baseUri ?? StorefrontConfig.publicUri,
    collection: collection,
    productKey: product.slug,
  );
  return ProductShareContent(
    uri: uri,
    message: 'Check out ${product.name} on MarketFlow: $uri',
  );
}
