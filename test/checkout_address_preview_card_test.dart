import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_flow_screen.dart';

void main() {
  testWidgets('delivery preview shows resolved address and contact details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckoutAddressPreviewCard(
            isPickup: false,
            title: 'Delivery details',
            statusLabel: 'Ready to deliver',
            headline: 'Street 2004, Phnom Penh',
            description:
                'This address and contact will be used for delivery updates and handoff.',
            contactName: 'Market Flow',
            contactPhone: '+855 12345678',
            primaryLabel: 'Change address',
            onPrimaryAction: () {},
            onSecondaryAction: () {},
            secondaryLabel: 'Edit profile',
          ),
        ),
      ),
    );

    expect(find.text('Delivery details'), findsOneWidget);
    expect(find.text('Ready to deliver'), findsOneWidget);
    expect(find.text('Street 2004, Phnom Penh'), findsOneWidget);
    expect(find.text('Market Flow'), findsOneWidget);
    expect(find.text('+855 12345678'), findsOneWidget);
    expect(find.text('Change address'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
  });

  testWidgets('delivery preview shows warning when phone is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckoutAddressPreviewCard(
            isPickup: false,
            title: 'Delivery details',
            statusLabel: 'Address needed',
            headline: 'Choose a delivery address',
            description:
                'Pick a saved address, current location, or map pin before placing your order.',
            contactName: 'Add your name in Profile',
            contactPhone: 'Add a phone number in Profile',
            primaryLabel: 'Choose address',
            onPrimaryAction: () {},
            warningText:
                'Phone number is required before you can place a delivery order.',
          ),
        ),
      ),
    );

    expect(find.text('Address needed'), findsOneWidget);
    expect(find.text('Choose a delivery address'), findsOneWidget);
    expect(
      find.text(
        'Phone number is required before you can place a delivery order.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose address'), findsOneWidget);
  });
}
