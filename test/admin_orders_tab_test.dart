import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_orders_tab.dart';

void main() {
  AdminOrder buildOrder({required String status}) {
    return AdminOrder(
      id: 4,
      userId: 'u1',
      email: 'rithybhi@gmail.com',
      total: 229.33,
      address: '56b Saint 143, Phnom Penh',
      addressDetails: 'Delivery time: ASAP',
      deliveryType: 'drop_off',
      paymentMethod: 'cash_on_delivery',
      cashPaidConfirmed: true,
      cashPaidConfirmedAt: DateTime.parse('2026-03-16T15:54:00Z'),
      cashPaidConfirmedBy: 'cashier@gmail.com',
      paymentReference: '',
      status: status,
      deliveryLatitude: null,
      deliveryLongitude: null,
      deliveryLocationUpdatedAt: null,
      deliveryLocationUpdatedBy: '',
      deliveryLocationNote: '',
      items: const <AdminOrderItem>[],
      createdAt: DateTime.parse('2026-03-16T15:20:00Z'),
    );
  }

  Widget buildSubject({
    required AdminOrder order,
    required List<String> statusOptions,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AdminOrdersTab(
          loadingOrders: false,
          submitting: false,
          canConfirmCashPayments: false,
          canUpdateDeliveryStatus: true,
          totalOrdersCount: 1,
          filteredOrders: <AdminOrder>[order],
          filterPanel: const SizedBox.shrink(),
          onConfirmCashPayment: (_) async {},
          onUpdateOrderStatus: (order, nextStatus) async {},
          statusUpdateOptionsForOrder: (_) => statusOptions,
          deliveryTypeLabel: (_) => 'Drop-off',
          paymentMethodLabel: (_) => 'Cash on delivery',
          statusLabel: (status) => status,
          formatDateTimeLocal: (_) => '2026-03-16 22:20',
          formatMoney: (usd) => '\$${usd.toStringAsFixed(2)}',
          canUseDeliveryQr: true,
          onShowDeliveryQr: (_) async {},
          onScanAndAdvanceWithQr: () async {},
        ),
      ),
    );
  }

  testWidgets('shows delivery qr actions while order is still active', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        order: buildOrder(status: 'out_for_delivery'),
        statusOptions: const <String>['delivered'],
      ),
    );

    expect(find.text('Show Delivery QR'), findsOneWidget);
    expect(find.text('Scan QR to Advance'), findsOneWidget);
    expect(find.text('Confirm Delivery'), findsOneWidget);
  });

  testWidgets('hides delivery qr actions after delivery is completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        order: buildOrder(status: 'delivered'),
        statusOptions: const <String>[],
      ),
    );

    expect(find.text('Show Delivery QR'), findsNothing);
    expect(find.text('Scan QR to Advance'), findsNothing);
    expect(find.text('Confirm Delivery'), findsNothing);
  });

  testWidgets(
    'hides rider actions when a drop-off order has no valid address',
    (tester) async {
      final order = AdminOrder(
        id: 5,
        userId: 'u1',
        email: 'rithybhi@gmail.com',
        total: 24.50,
        address: '',
        addressDetails: '',
        deliveryType: 'drop_off',
        paymentMethod: 'aba_payway_qr',
        cashPaidConfirmed: false,
        cashPaidConfirmedAt: null,
        cashPaidConfirmedBy: '',
        paymentReference: 'PW1771932632998606',
        status: 'order_received',
        deliveryLatitude: null,
        deliveryLongitude: null,
        deliveryLocationUpdatedAt: null,
        deliveryLocationUpdatedBy: '',
        deliveryLocationNote: '',
        items: const <AdminOrderItem>[],
        createdAt: DateTime.parse('2026-02-24T11:30:00Z'),
      );

      await tester.pumpWidget(
        buildSubject(
          order: order,
          statusOptions: const <String>['out_for_delivery'],
        ),
      );

      expect(find.text('Address required before delivery handoff.'), findsOne);
      expect(find.text('Copy customer email'), findsOneWidget);
      expect(find.text('Show Delivery QR'), findsNothing);
      expect(find.text('Scan QR to Advance'), findsNothing);
      expect(find.text('Out for Delivery'), findsNothing);
    },
  );
}
