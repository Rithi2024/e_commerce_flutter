import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketflow/features/checkout/presentation/pages/checkout_payment_method_screen.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('confirm disabled when all payment methods are disabled', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings.payment_methods': jsonEncode(<String, bool>{
        AppSettingsProvider.paymentAbaPayWayQr: false,
        AppSettingsProvider.paymentCashOnDelivery: false,
      }),
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>(
        create: (_) => AppSettingsProvider(),
        child: const MaterialApp(
          home: CheckoutPaymentMethodScreen(
            total: 24,
            initialMethod: AppSettingsProvider.paymentAbaPayWayQr,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No payment method is currently available. Contact admin.'),
      findsOneWidget,
    );
    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('confirm returns selected payment method', (
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    String? selectedResult;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!
        .push<String>(
          MaterialPageRoute<String>(
            builder: (_) => const CheckoutPaymentMethodScreen(
              total: 100,
              initialMethod: AppSettingsProvider.paymentAbaPayWayQr,
            ),
          ),
        )
        .then((value) => selectedResult = value);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash On Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
    await tester.pumpAndSettle();

    expect(selectedResult, AppSettingsProvider.paymentCashOnDelivery);
  });
}
