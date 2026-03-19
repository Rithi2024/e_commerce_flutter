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
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('0 methods ready'), findsOneWidget);
    final confirmButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirm'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('confirm returns selected payment method', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    final codCard = find.byKey(
      const ValueKey<String>(
        'payment-method-${AppSettingsProvider.paymentCashOnDelivery}',
      ),
    );
    await tester.ensureVisible(codCard);
    await tester.pumpAndSettle();
    await tester.tap(codCard);
    await tester.pumpAndSettle();
    expect(find.text('Continue with Cash On Delivery'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Continue with Cash On Delivery'),
    );
    await tester.pumpAndSettle();

    expect(selectedResult, AppSettingsProvider.paymentCashOnDelivery);
  });

  testWidgets('disabled initial selection falls back to the recommended method', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_settings.payment_methods': jsonEncode(<String, bool>{
        AppSettingsProvider.paymentAbaPayWayQr: false,
        AppSettingsProvider.paymentCashOnDelivery: true,
      }),
    });
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
              total: 42,
              initialMethod: AppSettingsProvider.paymentAbaPayWayQr,
            ),
          ),
        )
        .then((value) => selectedResult = value);
    await tester.pumpAndSettle();

    final codCard = find.byKey(
      const ValueKey<String>(
        'payment-method-${AppSettingsProvider.paymentCashOnDelivery}',
      ),
    );
    await tester.ensureVisible(codCard);
    await tester.pumpAndSettle();
    expect(find.text('Continue with Cash On Delivery'), findsOneWidget);
    expect(find.text('Recommended right now'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Continue with Cash On Delivery'),
    );
    await tester.pumpAndSettle();

    expect(selectedResult, AppSettingsProvider.paymentCashOnDelivery);
  });

  testWidgets('selection summary can reset back to the recommended method', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
              total: 56,
              initialMethod: AppSettingsProvider.paymentAbaPayWayQr,
            ),
          ),
        )
        .then((value) => selectedResult = value);
    await tester.pumpAndSettle();

    final codCard = find.byKey(
      const ValueKey<String>(
        'payment-method-${AppSettingsProvider.paymentCashOnDelivery}',
      ),
    );
    await tester.ensureVisible(codCard);
    await tester.pumpAndSettle();
    await tester.tap(codCard);
    await tester.pumpAndSettle();

    expect(find.text('Use recommended: ABA PAY'), findsOneWidget);
    final useRecommendedButton = find.widgetWithText(
      TextButton,
      'Use recommended: ABA PAY',
    );
    await tester.ensureVisible(useRecommendedButton);
    await tester.pumpAndSettle();
    await tester.tap(useRecommendedButton);
    await tester.pumpAndSettle();

    expect(find.text('Continue with ABA PAY'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue with ABA PAY'));
    await tester.pumpAndSettle();

    expect(selectedResult, AppSettingsProvider.paymentAbaPayWayQr);
  });
}
