import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/support/support_reply_template.dart';
import 'package:marketflow/features/admin/presentation/pages/support_dashboard_screen.dart';

void main() {
  testWidgets('support reply composer uses quick reply templates', (
    tester,
  ) async {
    String? savedReply;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                savedReply = await showDialog<String>(
                  context: context,
                  builder: (_) => const SupportReplyComposerDialog(
                    title: 'Add customer reply',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Quick replies'), findsOneWidget);
    expect(find.text('Reviewing'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Reviewing'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'We are reviewing your request now.');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(savedReply, 'We are reviewing your request now.');
  });

  test(
    'support reply template helper prioritizes delivery recovery templates',
    () {
      final templates = supportReplyTemplatesForContext(
        isDeliveryAddressRecoveryRequest: true,
        targetStatus: 'address_applied',
      );

      expect(templates.first.id, 'address_applied');
      expect(
        supportReplyDefaultMessageForContext(
          isDeliveryAddressRecoveryRequest: true,
          targetStatus: 'resolved',
        ),
        'Your request has been resolved.',
      );
    },
  );
}
