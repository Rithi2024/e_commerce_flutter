import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:marketflow/config/payway_config.dart';
import 'package:marketflow/config/support_config.dart';
import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/settings/presentation/pages/user_profile_screen.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'checkout_address_selection_screen.dart';
import 'checkout_payment_method_screen.dart';

class CheckoutFlowScreen extends StatefulWidget {
  const CheckoutFlowScreen({super.key});

  @override
  State<CheckoutFlowScreen> createState() => _CheckoutFlowScreenState();
}

Future<Map<String, dynamic>> _emptyPayWayCheckTransaction() async {
  return const <String, dynamic>{};
}

bool _neverApprovedPayWayResponse(Map<String, dynamic> _) => false;

class _CheckoutFlowScreenState extends State<CheckoutFlowScreen> {
  static const String _deliveryDropOff = 'drop_off';
  static const String _deliveryPickup = 'real_meeting';
  static const String _pickupAddressLabel = 'Store Pickup';
  static const String _paymentCashOnDelivery = 'cash_on_delivery';
  static const String _paymentAbaPayWayQr = 'aba_payway_qr';
  static const double _vatRate = 0.10;
  static const Color _accent = Color(0xFFF6234A);

  bool _loading = true;
  bool _placing = false;
  bool _applyingPromo = false;
  String _selectedDeliveryType = _deliveryDropOff;
  String _selectedAddress = '';
  String _selectedPaymentMethod = _paymentCashOnDelivery;
  String _appliedPromoCode = '';
  double _promoDiscountUsd = 0;
  double _promoDiscountPercent = 0;
  String _contactName = '';
  String _contactPhone = '';
  bool _deliveryAsap = true;
  DateTime? _scheduledDeliveryAt;
  final List<String> _savedAddresses = [];
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _promoCodeController = TextEditingController();
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadCheckoutData);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCheckoutData() async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    if (user == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final prefill = await context
          .read<OrderManagementProvider>()
          .loadCheckoutPrefill();

      if (!mounted) return;
      setState(() {
        _savedAddresses.clear();
        _savedAddresses.addAll(prefill.savedAddresses);
        _selectedAddress = _savedAddresses.isNotEmpty
            ? _savedAddresses.first
            : '';
        _contactName = prefill.contactName;
        _contactPhone = prefill.contactPhone;
      });
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        await auth.logout();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load checkout info')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load checkout info')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _buildPayWayTranId() {
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = (100 + _random.nextInt(900)).toString();
    return 'PW$millis$suffix';
  }

  double _toDouble(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _roundUsd(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  double _effectivePromoDiscount(double subtotalUsd) {
    if (_appliedPromoCode.trim().isEmpty || _promoDiscountUsd <= 0) {
      return 0;
    }
    return _roundUsd(_promoDiscountUsd.clamp(0, subtotalUsd).toDouble());
  }

  double _discountedSubtotal(double subtotalUsd) {
    final discounted = subtotalUsd - _effectivePromoDiscount(subtotalUsd);
    return _roundUsd(discounted < 0 ? 0 : discounted);
  }

  double _vatAmount(double subtotalUsd) {
    final discounted = _discountedSubtotal(subtotalUsd);
    return _roundUsd(discounted * _vatRate);
  }

  double _payableTotal(double subtotalUsd) {
    final discounted = _discountedSubtotal(subtotalUsd);
    final vatAmount = _vatAmount(subtotalUsd);
    return _roundUsd(discounted + vatAmount);
  }

  bool get _hasRequiredPhone {
    final normalizedPhone = _contactPhone.trim();
    final digits = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return normalizedPhone.isNotEmpty && digits.length >= 8;
  }

  bool _isPickupAddressLabel(String value) {
    return value.trim().toLowerCase() == _pickupAddressLabel.toLowerCase();
  }

  bool _isDropOffAddressValid(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    return !_isPickupAddressLabel(normalized);
  }

  void _clearPromo({bool clearInput = false}) {
    _appliedPromoCode = '';
    _promoDiscountUsd = 0;
    _promoDiscountPercent = 0;
    if (clearInput) {
      _promoCodeController.clear();
    }
  }

  Future<bool> _revalidateAppliedPromo({
    required OrderManagementProvider orders,
    required double subtotalUsd,
  }) async {
    final code = _appliedPromoCode.trim();
    if (code.isEmpty) return true;

    try {
      final response = await orders.validatePromoCode(promoCode: code);
      final valid = response['valid'] == true;
      if (!valid) {
        if (!mounted) return false;
        final message = (response['message'] ?? 'Promo code is no longer valid')
            .toString()
            .trim();
        setState(() => _clearPromo());
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return false;
      }

      final discountAmount = _toDouble(response['discount_amount']);
      final discountPercent = _toDouble(response['discount_percent']);
      final normalizedCode = (response['code'] ?? code)
          .toString()
          .trim()
          .toUpperCase();

      if (mounted) {
        setState(() {
          _appliedPromoCode = normalizedCode;
          _promoDiscountUsd = discountAmount;
          _promoDiscountPercent = discountPercent;
          _promoCodeController.value = TextEditingValue(
            text: normalizedCode,
            selection: TextSelection.collapsed(offset: normalizedCode.length),
          );
        });
      }
      return _payableTotal(subtotalUsd) > 0;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to validate promo code')),
      );
      return false;
    }
  }

  Future<void> _applyPromoCode(double subtotalUsd) async {
    final orders = context.read<OrderManagementProvider>();
    final code = _promoCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a promo code')));
      return;
    }

    setState(() => _applyingPromo = true);
    try {
      final response = await orders.validatePromoCode(promoCode: code);
      if (!mounted) return;

      final valid = response['valid'] == true;
      final message = (response['message'] ?? '').toString().trim();
      if (!valid) {
        setState(() => _clearPromo());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.isEmpty ? 'Promo code is invalid or expired' : message,
            ),
          ),
        );
        return;
      }

      final normalizedCode = (response['code'] ?? code)
          .toString()
          .trim()
          .toUpperCase();
      final discountAmount = _toDouble(response['discount_amount']);
      final discountPercent = _toDouble(response['discount_percent']);

      setState(() {
        _appliedPromoCode = normalizedCode;
        _promoDiscountUsd = discountAmount;
        _promoDiscountPercent = discountPercent;
        _promoCodeController.value = TextEditingValue(
          text: normalizedCode,
          selection: TextSelection.collapsed(offset: normalizedCode.length),
        );
      });

      final discountedTotal = _payableTotal(subtotalUsd);
      final summary =
          'Promo $normalizedCode applied (${discountPercent.toStringAsFixed(0)}% off). New total: ${context.read<AppSettingsProvider>().formatUsd(discountedTotal)}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(summary)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to apply promo code')),
      );
    } finally {
      if (mounted) {
        setState(() => _applyingPromo = false);
      }
    }
  }

  Future<String?> _preparePayWayPayment({
    required AuthenticationProvider auth,
    required OrderManagementProvider orders,
    required ShoppingCartProvider cart,
    required double payableTotal,
  }) async {
    if (payableTotal <= 0) {
      throw Exception('Order total must be greater than 0 for ABA PayWay.');
    }

    final contactNameParts = _contactName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final firstName = contactNameParts.isNotEmpty ? contactNameParts.first : '';
    final lastName = contactNameParts.length > 1
        ? contactNameParts.sublist(1).join(' ')
        : '';
    final phone = _contactPhone.trim();
    final email = auth.user?.email?.trim() ?? '';

    final promoDiscountUsd = _effectivePromoDiscount(cart.total);
    final vatAmountUsd = _vatAmount(cart.total);
    final payWayItems = promoDiscountUsd > 0
        ? <CartItem>[
            CartItem(
              id: 'promo_total',
              productId: 'promo_total',
              name: _appliedPromoCode.trim().isEmpty
                  ? 'Order Total (incl. 10% VAT)'
                  : 'Order Total (${_appliedPromoCode.trim().toUpperCase()}, incl. 10% VAT)',
              price: payableTotal,
              imageUrl: '',
              qty: 1,
            ),
          ]
        : <CartItem>[
            ...cart.items,
            if (vatAmountUsd > 0)
              CartItem(
                id: 'vat_10',
                productId: 'vat_10',
                name: 'VAT 10%',
                price: vatAmountUsd,
                imageUrl: '',
                qty: 1,
              ),
          ];

    final tranId = _buildPayWayTranId();
    final response = await orders.generatePayWayQr(
      tranId: tranId,
      amount: payableTotal,
      items: payWayItems,
      callbackUrl: PayWayConfig.callbackUrl,
      currency: PayWayConfig.currency,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      lifetimeMinutes: PayWayConfig.qrLifetimeMinutes,
      qrImageTemplate: PayWayConfig.qrTemplate,
    );

    final status = response['status'] is Map
        ? Map<String, dynamic>.from(response['status'] as Map)
        : const <String, dynamic>{};
    final responseTranId =
        (response['tran_id'] ?? response['tranId'] ?? status['tran_id'] ?? '')
            .toString()
            .trim();
    final payWayTranId = responseTranId.isEmpty ? tranId : responseTranId;
    final qrImageData = (response['qrImage'] ?? response['qr_image'] ?? '')
        .toString();
    final qrString = (response['qrString'] ?? response['qr_string'] ?? '')
        .toString();
    final abaDeeplink = (response['abapay_deeplink'] ?? '').toString();
    final appStoreUrl = (response['app_store'] ?? '').toString();
    final playStoreUrl = (response['play_store'] ?? '').toString();

    if (!mounted) return null;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayWayQrDialog(
        tranId: payWayTranId,
        amount: payableTotal,
        currency: PayWayConfig.currency.toUpperCase(),
        qrImageData: qrImageData,
        qrString: qrString,
        abaDeeplink: abaDeeplink,
        appStoreUrl: appStoreUrl,
        playStoreUrl: playStoreUrl,
        onCheckTransaction: () =>
            orders.checkPayWayTransaction(tranId: payWayTranId),
        isApprovedResponse: orders.isPayWayApproved,
      ),
    );

    if (approved == true) return payWayTranId;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ABA PayWay payment was not completed')),
      );
    }
    return null;
  }

  Future<void> _persistPayWayTransaction({
    required OrderManagementProvider orders,
    required String tranId,
    required int orderId,
    required double amount,
    required String currency,
  }) async {
    final normalizedTranId = tranId.trim();
    if (normalizedTranId.isEmpty) return;

    try {
      final checkResponse = await orders.checkPayWayTransaction(
        tranId: normalizedTranId,
      );
      await orders.savePayWayTransaction(
        tranId: normalizedTranId,
        orderId: orderId > 0 ? orderId : null,
        amount: amount,
        currency: currency,
        checkResponse: checkResponse,
      );
    } catch (_) {
      // Best-effort persistence: order placement should not fail if transaction
      // logging is unavailable.
    }
  }

  Future<void> _selectAddress() async {
    final result = await Navigator.push<CheckoutAddressSelectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutAddressSelectionScreen(
          selectedAddress: _selectedAddress,
          historyAddresses: _savedAddresses,
          contactName: _contactName,
          contactPhone: _contactPhone,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedAddress = result.address;
      if (!_savedAddresses.contains(result.address)) {
        _savedAddresses.insert(0, result.address);
      }
    });
  }

  Future<void> _selectPaymentMethod(double total) async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutPaymentMethodScreen(
          total: total,
          initialMethod: _selectedPaymentMethod,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedPaymentMethod = selected;
    });
  }

  String _deliveryTypeLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _deliveryPickup || normalized == 'pickup') {
      return 'Store Pickup';
    }
    return 'Drop-off';
  }

  Future<void> _selectDeliveryType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delivery Method',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('Drop-off'),
                  subtitle: const Text('Deliver to your selected address'),
                  trailing: Icon(
                    _selectedDeliveryType == _deliveryDropOff
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => Navigator.pop(context, _deliveryDropOff),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: const Text('Store Pickup'),
                  subtitle: const Text('Pick up your order at our store'),
                  trailing: Icon(
                    _selectedDeliveryType == _deliveryPickup
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => Navigator.pop(context, _deliveryPickup),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDeliveryType = selected;
      if (selected == _deliveryDropOff &&
          _isPickupAddressLabel(_selectedAddress)) {
        _selectedAddress = '';
      }
    });
  }

  String _formatDateTimeLocal(DateTime value) {
    final local = value.toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = hour24 >= 12 ? 'PM' : 'AM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour12:$minute $suffix';
  }

  String _deliveryTimeLabel({required bool isPickup}) {
    final prefix = isPickup ? 'Pickup' : 'Delivery';
    if (_deliveryAsap || _scheduledDeliveryAt == null) {
      return '$prefix ASAP';
    }
    return _formatDateTimeLocal(_scheduledDeliveryAt!);
  }

  Future<void> _selectDeliveryTime() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flash_on_outlined),
                  title: const Text('ASAP'),
                  trailing: Icon(
                    _deliveryAsap
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => Navigator.pop(context, 'asap'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Schedule date and time'),
                  subtitle: _scheduledDeliveryAt == null
                      ? null
                      : Text(_formatDateTimeLocal(_scheduledDeliveryAt!)),
                  trailing: Icon(
                    !_deliveryAsap && _scheduledDeliveryAt != null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  onTap: () => Navigator.pop(context, 'schedule'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selection == null || !mounted) return;
    if (selection == 'asap') {
      setState(() {
        _deliveryAsap = true;
        _scheduledDeliveryAt = null;
      });
      return;
    }

    final now = DateTime.now();
    final initial =
        (_scheduledDeliveryAt != null && _scheduledDeliveryAt!.isAfter(now))
        ? _scheduledDeliveryAt!
        : now.add(const Duration(hours: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;

    final scheduled = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (!scheduled.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a future date and time')),
      );
      return;
    }

    setState(() {
      _deliveryAsap = false;
      _scheduledDeliveryAt = scheduled;
    });
  }

  String _buildAddressDetails({required bool isPickup, required String note}) {
    final lines = <String>[];
    final timeLabel = isPickup ? 'Pickup time' : 'Delivery time';
    lines.add(
      _deliveryAsap || _scheduledDeliveryAt == null
          ? '$timeLabel: ASAP'
          : '$timeLabel: ${_formatDateTimeLocal(_scheduledDeliveryAt!)}',
    );
    final trimmedNote = note.trim();
    if (trimmedNote.isNotEmpty) {
      lines.add('Note: $trimmedNote');
    }
    return lines.join('\n');
  }

  Uri? _parseExternalUri(String value) {
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value);
    if (hasScheme) return Uri.tryParse(value);
    if (value.contains(' ') || !value.contains('.')) return null;
    return Uri.tryParse('https://$value');
  }

  Uri? _buildStoreLocationUri(String value) {
    final direct = _parseExternalUri(value);
    if (direct != null) return direct;
    return Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': value,
    });
  }

  Future<void> _openPickupStoreLocation() async {
    final value = SupportConfig.storeLocationUrl.trim();
    if (value.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store location is not configured yet')),
      );
      return;
    }

    final uri = _buildStoreLocationUri(value);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid store location link')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open map')));
    }
  }

  String _paymentMethodLabel(String value) {
    if (value == _paymentAbaPayWayQr) return 'ABA PAY';
    return 'Cash On Delivery';
  }

  Future<bool> _confirmCashOnDeliveryDialog(
    double totalUsd, {
    required bool isPickup,
  }) async {
    final settings = context.read<AppSettingsProvider>();
    final totalLabel = settings.formatUsd(totalUsd);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Cash on Delivery'),
        content: Text(
          'You selected Cash on Delivery.\n'
          'Please confirm you will pay $totalLabel ${isPickup ? 'when you pick up your order.' : 'when your order arrives.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _placeOrder() async {
    final auth = context.read<AuthenticationProvider>();
    final cart = context.read<ShoppingCartProvider>();
    final orders = context.read<OrderManagementProvider>();
    final settings = context.read<AppSettingsProvider>();
    final user = auth.user;
    final isPickup = _selectedDeliveryType == _deliveryPickup;
    final address = isPickup ? _pickupAddressLabel : _selectedAddress.trim();
    final note = _noteController.text.trim();
    if (user == null || cart.items.isEmpty) return;
    if (!isPickup && !_isDropOffAddressValid(address)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid delivery address')),
      );
      return;
    }
    if (!_hasRequiredPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Phone number is required before ordering. Please update your profile phone number.',
          ),
          action: SnackBarAction(
            label: 'Update',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserProfileScreen()),
              );
              if (!mounted) return;
              await _loadCheckoutData();
            },
          ),
        ),
      );
      return;
    }
    if (!settings.isPaymentMethodEnabled(_selectedPaymentMethod)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selected payment method is currently unavailable. Please choose another method.',
          ),
        ),
      );
      return;
    }

    final promoStillValid = await _revalidateAppliedPromo(
      orders: orders,
      subtotalUsd: cart.total,
    );
    if (!mounted) return;
    if (!promoStillValid) {
      return;
    }
    final promoCode = _appliedPromoCode.trim().toUpperCase();
    final payableTotal = _payableTotal(cart.total);
    if (payableTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order total must be greater than 0')),
      );
      return;
    }

    if (_selectedPaymentMethod == _paymentCashOnDelivery) {
      final confirmed = await _confirmCashOnDeliveryDialog(
        payableTotal,
        isPickup: isPickup,
      );
      if (!confirmed) {
        return;
      }
    }

    setState(() => _placing = true);
    try {
      var orderStatus = 'order_received';
      var paymentReference = '';

      if (_selectedPaymentMethod == _paymentAbaPayWayQr) {
        final paidTranId = await _preparePayWayPayment(
          auth: auth,
          orders: orders,
          cart: cart,
          payableTotal: payableTotal,
        );
        if (paidTranId == null) return;
        orderStatus = 'order_received';
        paymentReference = paidTranId;
      }

      final createdOrderId = await orders.placeOrder(
        address: address,
        deliveryType: _selectedDeliveryType,
        addressDetails: _buildAddressDetails(isPickup: isPickup, note: note),
        status: orderStatus,
        paymentMethod: _selectedPaymentMethod,
        paymentReference: paymentReference,
        promoCode: promoCode,
      );

      if (_selectedPaymentMethod == _paymentAbaPayWayQr &&
          paymentReference.trim().isNotEmpty) {
        await _persistPayWayTransaction(
          orders: orders,
          tranId: paymentReference,
          orderId: createdOrderId,
          amount: payableTotal,
          currency: PayWayConfig.currency,
        );
      }

      if (!isPickup) {
        await orders.saveDefaultAddress(userId: user.id, address: address);
      }
      await cart.load();

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.popUntil(context, (route) => route.isFirst);
      messenger.showSnackBar(const SnackBar(content: Text('Order placed!')));
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        await auth.logout();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not place order')));
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Could not process payment' : message,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _placing = false);
      }
    }
  }

  Widget _addressSection({
    required ShoppingCartProvider cart,
    required AppSettingsProvider settings,
  }) {
    final address = _selectedAddress.trim();
    final hasValidDropOffAddress = _isDropOffAddressValid(address);
    final isPickup = _selectedDeliveryType == _deliveryPickup;
    final paymentMethodEnabled = settings.isPaymentMethodEnabled(
      _selectedPaymentMethod,
    );
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _lineItem(
            label: 'Delivery method',
            value: _deliveryTypeLabel(_selectedDeliveryType),
            onTap: _selectDeliveryType,
          ),
          const Divider(height: 1),
          if (isPickup)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: _accent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pick up at store',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You will collect this order from our store.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                        if (!_hasRequiredPhone) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Phone number is required to place an order.',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (SupportConfig.storeLocationUrl.trim().isNotEmpty)
                          TextButton.icon(
                            onPressed: _openPickupStoreLocation,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.only(top: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Open store location'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: _selectAddress,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.location_on_outlined,
                        color: _accent,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasValidDropOffAddress
                                ? address
                                : 'Select your address',
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_contactName.isNotEmpty ||
                              _contactPhone.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${_contactName.isEmpty ? 'Contact' : _contactName}, ${_contactPhone.isEmpty ? '-' : _contactPhone}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                          if (!_hasRequiredPhone) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Phone number is required to place an order.',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 30),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          _lineItem(
            label: isPickup ? 'Pickup time' : 'Delivery time',
            value: _deliveryTimeLabel(isPickup: isPickup),
            onTap: _selectDeliveryTime,
          ),
          const Divider(height: 1),
          _lineItem(
            label: 'Payment method',
            value: _paymentMethodLabel(_selectedPaymentMethod),
            onTap: () {
              _selectPaymentMethod(_payableTotal(cart.total));
            },
          ),
          if (!paymentMethodEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                'This payment method was disabled by admin. Please choose another method.',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineItem({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final compactLayout = MediaQuery.sizeOf(context).width < 380;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: compactLayout ? 15 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: compactLayout ? 14 : 15,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _promoSection(
    AppSettingsProvider settings,
    ShoppingCartProvider cart,
  ) {
    final hasPromo = _appliedPromoCode.trim().isNotEmpty;
    final discountUsd = _effectivePromoDiscount(cart.total);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Promo Code',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promoCodeController,
            textCapitalization: TextCapitalization.characters,
            enabled: !_applyingPromo && !_placing,
            decoration: InputDecoration(
              hintText: 'Enter promo code',
              border: const OutlineInputBorder(),
              suffixIcon: hasPromo
                  ? IconButton(
                      onPressed: _applyingPromo || _placing
                          ? null
                          : () {
                              setState(() => _clearPromo(clearInput: true));
                            },
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            onChanged: (value) {
              if (_appliedPromoCode.trim().isEmpty) return;
              if (value.trim().toUpperCase() == _appliedPromoCode.trim()) {
                return;
              }
              setState(() => _clearPromo());
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _applyingPromo || _placing
                      ? null
                      : () => _applyPromoCode(cart.total),
                  icon: _applyingPromo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_offer_outlined),
                  label: Text(_applyingPromo ? 'Applying...' : 'Apply Code'),
                ),
              ),
            ],
          ),
          if (hasPromo && discountUsd > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Applied $_appliedPromoCode (${_promoDiscountPercent.toStringAsFixed(0)}%): -${settings.formatUsd(discountUsd)}',
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemsSection(
    ShoppingCartProvider cart,
    AppSettingsProvider settings,
  ) {
    final compactLayout = MediaQuery.sizeOf(context).width < 420;
    final promoDiscount = _effectivePromoDiscount(cart.total);
    final vatAmount = _vatAmount(cart.total);
    final payableTotal = _payableTotal(cart.total);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order items',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ...cart.items.map((item) {
            final variant = [
              item.size ?? '',
              item.color ?? '',
            ].where((e) => e.trim().isNotEmpty).join(', ');
            final lineTotal = settings.formatUsd(item.price * item.qty);
            final itemInfo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (variant.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    variant,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'x${item.qty}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              ],
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: compactLayout
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: item.imageUrl.isEmpty
                                  ? Container(
                                      width: 70,
                                      height: 70,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_outlined),
                                    )
                                  : Image.network(
                                      item.imageUrl,
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 70,
                                        height: 70,
                                        color: Colors.grey.shade200,
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: itemInfo),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            lineTotal,
                            style: const TextStyle(
                              fontSize: 18,
                              color: _accent,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: item.imageUrl.isEmpty
                              ? Container(
                                  width: 70,
                                  height: 70,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_outlined),
                                )
                              : Image.network(
                                  item.imageUrl,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 70,
                                    height: 70,
                                    color: Colors.grey.shade200,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: itemInfo),
                        const SizedBox(width: 8),
                        Text(
                          lineTotal,
                          style: const TextStyle(fontSize: 18, color: _accent),
                        ),
                      ],
                    ),
            );
          }),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _moneyRow('Subtotal', cart.total, settings: settings),
          const SizedBox(height: 8),
          _moneyRow('Delivery Fee', 0, settings: settings),
          const SizedBox(height: 8),
          _moneyRow(
            'Discount',
            promoDiscount,
            settings: settings,
            negative: true,
          ),
          const SizedBox(height: 8),
          _moneyRow('VAT (10%)', vatAmount, settings: settings),
          const SizedBox(height: 12),
          _moneyRow('Total', payableTotal, settings: settings, bold: true),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    double amount, {
    required AppSettingsProvider settings,
    bool bold = false,
    bool negative = false,
  }) {
    final priceText = settings.formatUsd(amount);
    final value = negative ? '-$priceText' : priceText;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: negative ? _accent : Colors.black,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _noteSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: TextField(
        controller: _noteController,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Note',
          hintText: 'Your requirements (Taste, like)',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<ShoppingCartProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactBottomBar = screenWidth < 420;
    final payableTotal = _payableTotal(cart.total);
    final hasAddressForOrder =
        _selectedDeliveryType == _deliveryPickup ||
        _isDropOffAddressValid(_selectedAddress);
    final paymentMethodEnabled = settings.isPaymentMethodEnabled(
      _selectedPaymentMethod,
    );
    final canSubmit =
        !_placing &&
        !_applyingPromo &&
        !_loading &&
        hasAddressForOrder &&
        _hasRequiredPhone &&
        cart.items.isNotEmpty &&
        paymentMethodEnabled &&
        payableTotal > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit order')),
      backgroundColor: const Color(0xFFF3F4F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : cart.items.isEmpty
          ? const Center(child: Text('Your bag is empty'))
          : ListView(
              children: [
                const SizedBox(height: 10),
                _addressSection(cart: cart, settings: settings),
                const SizedBox(height: 10),
                _promoSection(settings, cart),
                const SizedBox(height: 10),
                _itemsSection(cart, settings),
                const SizedBox(height: 10),
                _noteSection(),
                const SizedBox(height: 96),
              ],
            ),
      bottomNavigationBar: cart.items.isEmpty
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1F24),
                  borderRadius: BorderRadius.circular(
                    compactBottomBar ? 24 : 999,
                  ),
                ),
                child: compactBottomBar
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Text(
                                'Total: ${settings.formatUsd(payableTotal)}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 46,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: canSubmit ? _placeOrder : null,
                                child: _placing
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Order',
                                        style: TextStyle(fontSize: 18),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : SizedBox(
                        height: 70,
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Text(
                                  'Total: ${settings.formatUsd(payableTotal)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              height: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: canSubmit ? _placeOrder : null,
                                child: _placing
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Order',
                                        style: TextStyle(fontSize: 18),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
    );
  }
}

class _PayWayQrDialog extends StatefulWidget {
  const _PayWayQrDialog({
    this.tranId = '',
    this.amount = 0,
    this.currency = 'USD',
    this.qrImageData = '',
    this.qrString = '',
    this.abaDeeplink = '',
    this.appStoreUrl = '',
    this.playStoreUrl = '',
    this.onCheckTransaction = _emptyPayWayCheckTransaction,
    this.isApprovedResponse = _neverApprovedPayWayResponse,
  });

  final String tranId;
  final double amount;
  final String currency;
  final String qrImageData;
  final String qrString;
  final String abaDeeplink;
  final String appStoreUrl;
  final String playStoreUrl;
  final Future<Map<String, dynamic>> Function() onCheckTransaction;
  final bool Function(Map<String, dynamic>) isApprovedResponse;

  @override
  State<_PayWayQrDialog> createState() => _PayWayQrDialogState();
}

class _PayWayQrDialogState extends State<_PayWayQrDialog> {
  bool _checking = false;
  bool _autoChecking = false;
  String _statusMessage = '';
  Timer? _autoCheckTimer;
  DateTime _openedAt = DateTime.now();
  bool _attemptedAutoOpenAba = false;

  static const Duration _autoCheckInterval = Duration(seconds: 4);
  static const Duration _autoCheckTimeout = Duration(minutes: 10);

  bool get _canOpenAbaApp {
    return widget.abaDeeplink.trim().isNotEmpty ||
        widget.appStoreUrl.trim().isNotEmpty ||
        widget.playStoreUrl.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _startAutoCheck();
    _scheduleAutoOpenAbaIfInstalled();
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _startAutoCheck() {
    _autoCheckTimer?.cancel();
    _autoCheckTimer = Timer.periodic(_autoCheckInterval, (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_openedAt);
      if (elapsed >= _autoCheckTimeout) {
        _autoCheckTimer?.cancel();
        return;
      }
      _checkPayment(silent: true);
    });
    unawaited(_checkPayment(silent: true));
  }

  void _scheduleAutoOpenAbaIfInstalled() {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final deeplinkRaw = widget.abaDeeplink.trim();
    if (deeplinkRaw.isEmpty) return;

    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted || _attemptedAutoOpenAba) return;
      _attemptedAutoOpenAba = true;

      final deeplink = Uri.tryParse(deeplinkRaw);
      if (deeplink == null) return;

      try {
        await launchUrl(deeplink, mode: LaunchMode.externalApplication);
      } catch (_) {}
    });
  }

  Uint8List? _decodeQrImage(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final base64Part = value.contains(',') ? value.split(',').last : value;
    try {
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkPayment({bool silent = false}) async {
    if (silent) {
      if (_autoChecking || _checking) return;
      _autoChecking = true;
    } else {
      if (_checking) return;
      setState(() {
        _checking = true;
        _statusMessage = '';
      });
    }

    try {
      final result = await widget.onCheckTransaction();
      if (!mounted) return;
      if (widget.isApprovedResponse(result)) {
        _autoCheckTimer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }

      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : const <String, dynamic>{};
      final status =
          (data['payment_status'] ?? result['payment_status'] ?? 'PENDING')
              .toString()
              .toUpperCase();
      if (!silent) {
        setState(() {
          _statusMessage =
              'Current status: $status. Complete payment and check again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        final message = e.toString().replaceFirst('Exception: ', '').trim();
        setState(() {
          _statusMessage = message.isEmpty
              ? 'Failed to verify payment status'
              : message;
        });
      }
    } finally {
      if (silent) {
        _autoChecking = false;
      } else if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  String _fallbackStoreUrl() {
    final android = widget.playStoreUrl.trim();
    final ios = widget.appStoreUrl.trim();
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android) {
      return android.isNotEmpty ? android : ios;
    }
    if (platform == TargetPlatform.iOS) {
      return ios.isNotEmpty ? ios : android;
    }
    return android.isNotEmpty ? android : ios;
  }

  Future<void> _openAbaApp() async {
    final deeplinkRaw = widget.abaDeeplink.trim();
    if (deeplinkRaw.isNotEmpty) {
      final deeplink = Uri.tryParse(deeplinkRaw);
      if (deeplink != null) {
        try {
          final opened = await launchUrl(
            deeplink,
            mode: LaunchMode.externalApplication,
          );
          if (opened) return;
        } catch (_) {}
      }
    }

    final storeRaw = _fallbackStoreUrl();
    if (storeRaw.isNotEmpty) {
      final storeUrl = Uri.tryParse(storeRaw);
      if (storeUrl != null) {
        try {
          final opened = await launchUrl(
            storeUrl,
            mode: LaunchMode.externalApplication,
          );
          if (opened) return;
        } catch (_) {}
      }
    }

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Unable to open ABA app. Please scan the QR to pay.';
    });
  }

  double _qrSize() {
    final screen = MediaQuery.sizeOf(context);
    final shortestSide = min(screen.width, screen.height);
    final estimatedDialogWidth = max(190.0, screen.width - 72.0);
    final target = shortestSide <= 390
        ? min(estimatedDialogWidth, 280.0)
        : min(estimatedDialogWidth, 260.0);
    return target.clamp(190.0, 300.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeQrImage(widget.qrImageData);
    final qrSize = _qrSize();

    return AlertDialog(
      title: const Text('Scan ABA QR to Pay'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount: ${widget.currency} ${widget.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText('Transaction: ${widget.tranId}'),
            const SizedBox(height: 12),
            if (imageBytes != null)
              Center(
                child: Image.memory(
                  imageBytes,
                  width: qrSize,
                  height: qrSize,
                  fit: BoxFit.contain,
                ),
              )
            else if (widget.qrString.trim().isNotEmpty)
              SelectableText(widget.qrString)
            else
              const Text('QR image is unavailable. Please try again.'),
            const SizedBox(height: 10),
            if (_canOpenAbaApp) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _openAbaApp,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open ABA App'),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'After payment, tap "Check Payment" to continue.',
              style: TextStyle(fontSize: 12),
            ),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _checking ? null : _checkPayment,
          icon: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(_checking ? 'Checking...' : 'Check Payment'),
        ),
      ],
    );
  }
}
