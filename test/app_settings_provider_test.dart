import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'falls back to latest saved discount when no active event is set',
    () async {
      final settings = AppSettingsProvider();

      await settings.upsertEventDiscount(
        eventId: 'event-old',
        eventTitle: 'Old Event',
        productId: 'product-1',
        discountPercent: 10,
      );
      await settings.upsertEventDiscount(
        eventId: 'event-new',
        eventTitle: 'Spring Launch',
        productId: 'product-1',
        discountPercent: 20,
      );

      expect(settings.discountPercentForProduct(productId: 'product-1'), 20);
      expect(
        settings.activeDiscountForProduct(productId: 'product-1')?.eventId,
        'event-new',
      );
      expect(
        settings.activeDiscountForProduct(productId: 'product-1')?.eventTitle,
        'Spring Launch',
      );
    },
  );

  test('explicit event id still wins over the fallback discount', () async {
    final settings = AppSettingsProvider();

    await settings.upsertEventDiscount(
      eventId: 'event-old',
      eventTitle: 'Old Event',
      productId: 'product-1',
      discountPercent: 10,
    );
    await settings.upsertEventDiscount(
      eventId: 'event-new',
      eventTitle: 'Spring Launch',
      productId: 'product-1',
      discountPercent: 20,
    );

    expect(
      settings.discountPercentForProduct(
        productId: 'product-1',
        eventId: 'event-old',
      ),
      10,
    );
    expect(
      settings
          .activeDiscountForProduct(
            productId: 'product-1',
            eventId: 'event-old',
          )
          ?.eventTitle,
      'Old Event',
    );
  });
}
