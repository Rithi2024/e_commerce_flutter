import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_address_selection_screen.dart';

void main() {
  testWidgets('Address chooser hides coordinate-only saved addresses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutAddressSelectionScreen(
          selectedAddress: '11.56210, 104.88880',
          historyAddresses: const <String>[
            '11.56210, 104.88880',
            'Street 2004, Phnom Penh',
          ],
          contactName: 'Market Flow',
          contactPhone: '+855 12345678',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('11.56210, 104.88880'), findsNothing);
    expect(find.text('Street 2004, Phnom Penh'), findsOneWidget);
    expect(find.text('My address'), findsOneWidget);
    expect(find.text('No saved address'), findsOneWidget);
  });
}
