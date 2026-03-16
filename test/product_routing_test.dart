import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/config/storefront_config.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/presentation/helpers/product_share_content.dart';

void main() {
  test('Product route keys support readable slugs and legacy ids', () {
    final product = Product(
      id: 'shoe-1',
      name: 'Everyday Runner',
      price: 52,
      imageUrl: '',
      description: 'Lightweight running shoes',
      category: 'Shoes',
    );

    expect(product.slug, 'everyday-runner');
    expect(product.matchesRouteKey('shoe-1'), isTrue);
    expect(product.matchesRouteKey('everyday-runner'), isTrue);
    expect(product.matchesRouteKey('Everyday Runner'), isTrue);
  });

  test('Storefront config normalizes a public share URL', () {
    final uri = StorefrontConfig.parsePublicUri(
      'https://shop.marketflow.test/storefront',
    );

    expect(uri?.toString(), 'https://shop.marketflow.test/storefront/');
  });

  test('Share content builds a slug-based storefront link', () {
    final product = Product(
      id: 'shoe-1',
      name: 'Everyday Runner',
      price: 52,
      imageUrl: '',
      description: 'Lightweight running shoes',
      category: 'Shoes',
    );

    final shareContent = buildProductShareContent(
      product: product,
      collection: 'best-sellers',
      baseUri: Uri.parse('https://shop.marketflow.test/catalog'),
    );

    expect(
      shareContent.uri.toString(),
      'https://shop.marketflow.test/catalog/?collection=best-sellers&product=everyday-runner',
    );
    expect(
      shareContent.message,
      'Check out Everyday Runner on MarketFlow: https://shop.marketflow.test/catalog/?collection=best-sellers&product=everyday-runner',
    );
  });
}
