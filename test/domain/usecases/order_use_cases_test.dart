import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';
import 'package:marketflow/features/checkout/domain/usecases/order_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrderRepository implements OrderRepository {
  String? placedAddress;
  String? savedAddressUserId;
  int createdOrderId = 7;

  @override
  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    required String status,
    required String paymentMethod,
    required String paymentReference,
    required String addressDetails,
    required String promoCode,
  }) async {
    placedAddress = address;
    return createdOrderId;
  }

  @override
  Future<List<Map<String, dynamic>>> loadOrders() async {
    return [
      {'id': 1, 'status': 'pending'},
    ];
  }

  @override
  Future<CheckoutPrefill> loadCheckoutPrefill() async {
    return const CheckoutPrefill(
      defaultAddress: 'A',
      contactName: 'N',
      contactPhone: 'P',
      savedAddresses: ['A'],
    );
  }

  @override
  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  }) async {
    savedAddressUserId = userId;
  }

  @override
  Future<Map<String, dynamic>> validatePromoCode({
    required String promoCode,
  }) async {
    return const {
      'valid': true,
      'message': 'ok',
      'code': 'SAVE10',
      'discount_percent': 10,
      'discount_amount': 1,
      'subtotal': 10,
      'total': 9,
    };
  }

  @override
  Future<Map<String, dynamic>> generatePayWayQr({
    required String tranId,
    required double amount,
    required List<CartItem> items,
    required String callbackUrl,
    required String currency,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required int lifetimeMinutes,
    required String paymentOption,
    required String qrImageTemplate,
  }) async {
    return {
      'status': {'code': '0'},
    };
  }

  @override
  Future<Map<String, dynamic>> checkPayWayTransaction({
    required String tranId,
  }) async {
    return {
      'data': {'payment_status': 'APPROVED', 'payment_status_code': 0},
    };
  }

  @override
  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) async {}

  @override
  bool isPayWayApproved(Map<String, dynamic> checkResponse) => true;
}

void main() {
  test('OrderUseCases delegates order and payment operations', () async {
    final repo = _FakeOrderRepository();
    final useCases = OrderUseCases(repo);

    final id = await useCases.placeOrder(
      address: 'A',
      deliveryType: 'drop_off',
    );
    final prefill = await useCases.loadCheckoutPrefill();
    await useCases.saveDefaultAddress(userId: 'u1', address: 'A');
    final orders = await useCases.loadOrders();

    expect(id, 7);
    expect(prefill.defaultAddress, 'A');
    expect(repo.savedAddressUserId, 'u1');
    expect(orders.length, 1);
  });

  test('OrderUseCases rejects invalid order id', () async {
    final repo = _FakeOrderRepository()..createdOrderId = 0;
    final useCases = OrderUseCases(repo);

    expect(
      () => useCases.placeOrder(address: 'A', deliveryType: 'drop_off'),
      throwsA(isA<StateError>()),
    );
  });
}
