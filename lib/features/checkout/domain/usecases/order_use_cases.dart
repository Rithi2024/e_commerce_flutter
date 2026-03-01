import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';

class OrderUseCases {
  final OrderRepository _repository;

  const OrderUseCases(this._repository);

  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    String status = 'order_received',
    String paymentMethod = 'cash_on_delivery',
    String paymentReference = '',
    String addressDetails = '',
    String promoCode = '',
  }) async {
    final createdOrderId = await _repository.placeOrder(
      address: address,
      deliveryType: deliveryType,
      status: status,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      addressDetails: addressDetails,
      promoCode: promoCode,
    );
    if (createdOrderId <= 0) {
      throw StateError('Could not create order. Please try again.');
    }
    return createdOrderId;
  }

  Future<List<Map<String, dynamic>>> loadOrders() {
    return _repository.loadOrders();
  }

  Future<CheckoutPrefill> loadCheckoutPrefill() {
    return _repository.loadCheckoutPrefill();
  }

  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  }) {
    return _repository.saveDefaultAddress(userId: userId, address: address);
  }

  Future<Map<String, dynamic>> validatePromoCode({required String promoCode}) {
    final cleanCode = promoCode.trim();
    if (cleanCode.isEmpty) {
      return Future.value(const {
        'valid': false,
        'message': 'Promo code is required',
        'code': '',
        'discount_percent': 0,
        'discount_amount': 0,
        'subtotal': 0,
        'total': 0,
      });
    }
    return _repository.validatePromoCode(promoCode: cleanCode);
  }

  Future<Map<String, dynamic>> generatePayWayQr({
    required String tranId,
    required double amount,
    required List<CartItem> items,
    required String callbackUrl,
    String currency = 'USD',
    String firstName = '',
    String lastName = '',
    String email = '',
    String phone = '',
    int lifetimeMinutes = 15,
    String paymentOption = 'abapay_khqr',
    String qrImageTemplate = 'template3_color',
  }) {
    return _repository.generatePayWayQr(
      tranId: tranId,
      amount: amount,
      items: items,
      callbackUrl: callbackUrl,
      currency: currency,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      lifetimeMinutes: lifetimeMinutes,
      paymentOption: paymentOption,
      qrImageTemplate: qrImageTemplate,
    );
  }

  Future<Map<String, dynamic>> checkPayWayTransaction({
    required String tranId,
  }) {
    return _repository.checkPayWayTransaction(tranId: tranId);
  }

  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) {
    return _repository.savePayWayTransaction(
      tranId: tranId,
      orderId: orderId,
      amount: amount,
      currency: currency,
      checkResponse: checkResponse,
    );
  }

  bool isPayWayApproved(Map<String, dynamic> checkResponse) {
    return _repository.isPayWayApproved(checkResponse);
  }
}
