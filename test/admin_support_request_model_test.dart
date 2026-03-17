import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';

void main() {
  test(
    'AdminSupportRequest parses linked order and updated delivery address',
    () {
      const request = AdminSupportRequest(
        id: 1,
        userId: '',
        email: '',
        requestType: 'delivery',
        message:
            'Order #3 needs a delivery address update.\n'
            'My updated delivery address is: 56b Saint 143, Phnom Penh\n'
            'Please help apply the correct address before delivery handoff.',
        status: 'address_applied',
        createdAt: null,
      );

      expect(request.linkedOrderId, 3);
      expect(request.updatedDeliveryAddress, '56b Saint 143, Phnom Penh');
      expect(request.isDeliveryAddressRecoveryRequest, isTrue);
      expect(request.statusLabel, 'Address applied');
    },
  );

  test('AdminSupportRequest ignores non-recovery delivery requests', () {
    const request = AdminSupportRequest(
      id: 2,
      userId: '',
      email: '',
      requestType: 'delivery',
      message: 'My rider has not arrived yet.',
      createdAt: null,
    );

    expect(request.linkedOrderId, isNull);
    expect(request.updatedDeliveryAddress, isEmpty);
    expect(request.isDeliveryAddressRecoveryRequest, isFalse);
  });

  test('AdminSupportRequest normalizes invalid statuses to pending', () {
    final request = AdminSupportRequest.fromMap({
      'id': 3,
      'request_type': 'general',
      'message': 'Hello',
      'status': 'unknown',
      'support_note': 'We are checking this now.',
    });

    expect(request.status, 'pending');
    expect(request.statusLabel, 'Pending');
    expect(request.supportNote, 'We are checking this now.');
    expect(request.hasSupportNote, isTrue);
  });
}
