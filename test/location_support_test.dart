import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/checkout/presentation/pages/location_support.dart';

void main() {
  test('LocationAddressFormatter identifies delivery-ready address text', () {
    expect(
      LocationAddressFormatter.isResolvedDeliveryAddress(
        'Street 2004, Phnom Penh',
      ),
      isTrue,
    );
    expect(
      LocationAddressFormatter.isResolvedDeliveryAddress('11.56210, 104.88880'),
      isFalse,
    );
    expect(
      LocationAddressFormatter.isResolvedDeliveryAddress('Selected location'),
      isFalse,
    );
  });
}
