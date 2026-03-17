import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/support/support_request_link.dart';

void main() {
  test('support request link parser extracts linked order id', () {
    expect(
      parseLinkedOrderIdFromSupportMessage(
        'Order #14 needs a delivery address update.',
      ),
      14,
    );
  });

  test('support request link parser extracts updated address', () {
    expect(
      parseUpdatedDeliveryAddressFromSupportMessage(
        'Order #14 needs a delivery address update.\n'
        'My updated delivery address is: Street 271, Phnom Penh',
      ),
      'Street 271, Phnom Penh',
    );
  });
}
