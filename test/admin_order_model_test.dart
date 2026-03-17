import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';

void main() {
  test('AdminOrder normalizes placeholder and coordinate-only addresses', () {
    final placeholder = AdminOrder.fromMap({
      'id': 1,
      'user_id': 'u1',
      'email': 'customer@example.com',
      'total': 24.5,
      'address': 'Selected location',
      'address_details': 'ASAP',
      'delivery_type': 'drop_off',
      'payment_method': 'cash_on_delivery',
      'cash_paid_confirmed': false,
      'payment_reference': '',
      'status': 'order_received',
      'items': const <Map<String, dynamic>>[],
    });

    final coordinateOnly = AdminOrder.fromMap({
      'id': 2,
      'user_id': 'u1',
      'email': 'customer@example.com',
      'total': 24.5,
      'address': '11.56210, 104.88880',
      'address_details': 'ASAP',
      'delivery_type': 'drop_off',
      'payment_method': 'cash_on_delivery',
      'cash_paid_confirmed': false,
      'payment_reference': '',
      'status': 'order_received',
      'items': const <Map<String, dynamic>>[],
    });

    final realAddress = AdminOrder.fromMap({
      'id': 3,
      'user_id': 'u1',
      'email': 'customer@example.com',
      'total': 24.5,
      'address': 'Street 2004, Phnom Penh',
      'address_details': 'ASAP',
      'delivery_type': 'drop_off',
      'payment_method': 'cash_on_delivery',
      'cash_paid_confirmed': false,
      'payment_reference': '',
      'status': 'order_received',
      'items': const <Map<String, dynamic>>[],
    });

    expect(placeholder.address, isEmpty);
    expect(coordinateOnly.address, isEmpty);
    expect(realAddress.address, 'Street 2004, Phnom Penh');
  });
}
