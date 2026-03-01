import 'dart:async';

import 'package:flutter/material.dart';

import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/checkout/domain/entities/checkout_prefill_model.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:marketflow/features/checkout/domain/usecases/order_use_cases.dart';

class OrderManagementProvider extends ChangeNotifier {
  final OrderUseCases _useCases;
  final LogUseCases? _logUseCases;

  OrderManagementProvider({
    required OrderUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  Future<int> placeOrder({
    required String address,
    required String deliveryType,
    String status = 'order_received',
    String paymentMethod = 'cash_on_delivery',
    String paymentReference = '',
    String addressDetails = '',
    String promoCode = '',
  }) async {
    try {
      final createdOrderId = await _useCases.placeOrder(
        address: address,
        deliveryType: deliveryType,
        status: status,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        addressDetails: addressDetails,
        promoCode: promoCode,
      );
      notifyListeners();
      _logInfo(
        action: 'place_order',
        metadata: {
          'orderId': createdOrderId,
          'deliveryType': deliveryType,
          'paymentMethod': paymentMethod,
          'promoCode': promoCode,
        },
      );
      return createdOrderId;
    } catch (error) {
      _logError(action: 'place_order', message: error.toString());
      rethrow;
    }
  }

  Future<CheckoutPrefill> loadCheckoutPrefill() {
    return _useCases.loadCheckoutPrefill();
  }

  Future<void> saveDefaultAddress({
    required String userId,
    required String address,
  }) {
    return _useCases.saveDefaultAddress(userId: userId, address: address);
  }

  Future<Map<String, dynamic>> validatePromoCode({
    required String promoCode,
  }) async {
    try {
      final response = await _useCases.validatePromoCode(promoCode: promoCode);
      _logInfo(
        action: 'validate_promo_code',
        metadata: {'promoCode': promoCode, 'valid': response['valid'] == true},
      );
      return response;
    } catch (error) {
      _logError(action: 'validate_promo_code', message: error.toString());
      rethrow;
    }
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
  }) async {
    try {
      final response = await _useCases.generatePayWayQr(
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
      _logInfo(
        action: 'generate_payway_qr',
        metadata: {'tranId': tranId, 'amount': amount},
      );
      return response;
    } catch (error) {
      _logError(action: 'generate_payway_qr', message: error.toString());
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkPayWayTransaction({
    required String tranId,
  }) async {
    try {
      final response = await _useCases.checkPayWayTransaction(tranId: tranId);
      _logInfo(
        action: 'check_payway_transaction',
        metadata: {'tranId': tranId},
      );
      return response;
    } catch (error) {
      _logError(action: 'check_payway_transaction', message: error.toString());
      rethrow;
    }
  }

  Future<void> savePayWayTransaction({
    required String tranId,
    int? orderId,
    required double amount,
    required String currency,
    required Map<String, dynamic> checkResponse,
  }) async {
    try {
      await _useCases.savePayWayTransaction(
        tranId: tranId,
        orderId: orderId,
        amount: amount,
        currency: currency,
        checkResponse: checkResponse,
      );
      _logInfo(
        action: 'save_payway_transaction',
        metadata: {
          'tranId': tranId,
          'orderId': orderId,
          'amount': amount,
          'currency': currency,
        },
      );
    } catch (error) {
      _logError(action: 'save_payway_transaction', message: error.toString());
      rethrow;
    }
  }

  bool isPayWayApproved(Map<String, dynamic> checkResponse) {
    return _useCases.isPayWayApproved(checkResponse);
  }

  Future<List<Map<String, dynamic>>> loadOrders() async {
    try {
      final orders = await _useCases.loadOrders();
      _logInfo(action: 'load_orders', metadata: {'count': orders.length});
      return orders;
    } catch (error) {
      _logError(action: 'load_orders', message: error.toString());
      rethrow;
    }
  }

  void _logInfo({
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.info(
        feature: 'order',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logError({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.error(
        feature: 'order',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }
}
