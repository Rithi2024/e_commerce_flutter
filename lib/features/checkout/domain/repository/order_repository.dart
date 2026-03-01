import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';

abstract class OrderRepository {
  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    required String status,
    required String paymentMethod,
    required String paymentReference,
    required String addressDetails,
    required String promoCode,
  });

  Future<List<Map<String, dynamic>>> loadOrders();

  Future<CheckoutPrefill> loadCheckoutPrefill();

  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  });

  Future<Map<String, dynamic>> validatePromoCode({required String promoCode});

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
  });

  Future<Map<String, dynamic>> checkPayWayTransaction({required String tranId});

  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  });

  bool isPayWayApproved(Map<String, dynamic> checkResponse);
}
