import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/location/address_text.dart';

void main() {
  test('AddressText removes placeholder values and keeps real addresses', () {
    expect(AddressText.meaningfulOrEmpty(' Selected location '), isEmpty);
    expect(
      AddressText.meaningfulOrEmpty('Street 2004, Phnom Penh'),
      'Street 2004, Phnom Penh',
    );
  });

  test('AddressText keeps only unique meaningful addresses', () {
    expect(
      AddressText.uniqueMeaningful(const <String>[
        'Selected location',
        'Street 2004, Phnom Penh',
        'street 2004, phnom penh',
        '11.56210, 104.88880',
      ]),
      <String>['Street 2004, Phnom Penh', '11.56210, 104.88880'],
    );
  });

  test('AddressText keeps only delivery-ready addresses', () {
    expect(AddressText.deliveryAddressOrEmpty('11.56210, 104.88880'), isEmpty);
    expect(
      AddressText.deliveryAddressOrEmpty('Street 2004, Phnom Penh'),
      'Street 2004, Phnom Penh',
    );
    expect(
      AddressText.uniqueDeliveryAddresses(const <String>[
        'Selected location',
        '11.56210, 104.88880',
        'Street 2004, Phnom Penh',
        'street 2004, phnom penh',
      ]),
      <String>['Street 2004, Phnom Penh'],
    );
  });
}
