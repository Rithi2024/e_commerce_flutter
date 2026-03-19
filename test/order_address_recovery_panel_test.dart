import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/checkout/presentation/pages/order_history_list_screen.dart';

void main() {
  testWidgets('order support status card shows pending delivery recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderSupportStatusCard(
            status: 'pending',
            needsAddressRecovery: true,
            updatedAtLabel: '2026-03-17 16:20',
            latestSupportNote: 'We are reviewing your request now.',
            latestSupportNoteUpdatedAtLabel: '2026-03-17 16:30',
          ),
        ),
      ),
    );

    expect(find.text('Support request'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.text(
        'The support team is reviewing the delivery address issue for this order.',
      ),
      findsOneWidget,
    );
    expect(find.text('Latest reply'), findsOneWidget);
    expect(find.text('We are reviewing your request now.'), findsOneWidget);
    expect(find.text('Reply updated: 2026-03-17 16:30'), findsOneWidget);
    expect(find.text('Updated: 2026-03-17 16:20'), findsOneWidget);
  });

  testWidgets('order support status card exposes reopen action when resolved', (
    tester,
  ) async {
    var replyTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderSupportStatusCard(
            status: 'resolved',
            needsAddressRecovery: false,
            latestSupportNote:
                'Your address update has been applied and this support request is now resolved.',
            onReplyInSupport: () => replyTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Reopen in Support'), findsOneWidget);
    await tester.tap(find.text('Reopen in Support'));
    await tester.pump();
    expect(replyTapped, isTrue);
  });

  testWidgets('order support status card shows unread badge when needed', (
    tester,
  ) async {
    var markReadTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderSupportStatusCard(
            status: 'address_applied',
            needsAddressRecovery: false,
            isUnread: true,
            latestSupportNote: 'Support applied your updated address.',
            onMarkAsRead: () => markReadTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('New'), findsOneWidget);
    expect(find.text('Address applied'), findsOneWidget);
    expect(find.text('Mark as read'), findsOneWidget);
    await tester.tap(find.text('Mark as read'));
    await tester.pump();
    expect(markReadTapped, isTrue);
  });

  testWidgets('order support history section shows timeline entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderSupportHistorySection(
            history: const [
              {
                'request_type': 'delivery',
                'support_request_status': 'address_applied',
                'support_request_status_updated_at': '2026-03-17T16:20:00Z',
                'support_note': 'We applied your updated delivery address.',
                'support_request_message':
                    'Order #3 needs a delivery address update.\n'
                    'My updated delivery address is: 56b Saint 143, Phnom Penh',
              },
              {
                'request_type': 'delivery',
                'support_request_status': 'pending',
                'support_request_created_at': '2026-03-17T15:00:00Z',
                'support_request_message':
                    'Order #3 needs a delivery address update.',
              },
            ],
            formatDateTimeLabel: _formatLabel,
          ),
        ),
      ),
    );

    expect(find.text('Support activity (2)'), findsOneWidget);
    expect(find.text('Address applied'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.text('Support applied the latest address on file.'),
      findsOneWidget,
    );
    expect(
      find.text('Support reply: We applied your updated delivery address.'),
      findsOneWidget,
    );
    expect(
      find.text('Address shared: 56b Saint 143, Phnom Penh'),
      findsOneWidget,
    );
  });

  testWidgets('order event pricing card shows savings summary', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderEventPricingCard(
            eventTitle: 'Spring Launch',
            headlineLabel: 'Spring Launch pricing',
            savingsLabel: r'$20.80',
            discountedItemCount: 2,
          ),
        ),
      ),
    );

    expect(find.text('Spring Launch deal'), findsOneWidget);
    expect(
      find.text('Spring Launch pricing kept this order lower at checkout.'),
      findsOneWidget,
    );
    expect(
      find.text('You saved \$20.80 across 2 items on this order.'),
      findsOneWidget,
    );
  });

  testWidgets('order address recovery panel exposes both recovery actions', (
    tester,
  ) async {
    var updateTapped = false;
    var supportTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderAddressRecoveryPanel(
            supportStatus: '',
            onUpdateSavedAddress: () => updateTapped = true,
            onContactSupport: () => supportTapped = true,
          ),
        ),
      ),
    );

    expect(
      find.text('Address required before delivery can continue.'),
      findsOneWidget,
    );
    expect(find.text('Update saved address'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);

    await tester.tap(find.text('Update saved address'));
    await tester.pump();
    expect(updateTapped, isTrue);

    await tester.tap(find.text('Contact support'));
    await tester.pump();
    expect(supportTapped, isTrue);
  });

  testWidgets('order address recovery panel adapts copy for pending support', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderAddressRecoveryPanel(
            supportStatus: 'pending',
            onUpdateSavedAddress: _noop,
            onContactSupport: _noop,
          ),
        ),
      ),
    );

    expect(
      find.text('Support is reviewing your address update.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Your request is already with support. If your saved address changed again, update it and send a follow-up message.',
      ),
      findsOneWidget,
    );
    expect(find.text('Send follow-up'), findsOneWidget);
  });

  testWidgets('order address recovery panel adapts copy for resolved support', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderAddressRecoveryPanel(
            supportStatus: 'resolved',
            onUpdateSavedAddress: _noop,
            onContactSupport: _noop,
          ),
        ),
      ),
    );

    expect(
      find.text('Request resolved, but delivery is still blocked.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The last request was marked resolved. Update your saved address and reopen it in support so the team can continue this order.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reopen in Support'), findsOneWidget);
  });
}

void _noop() {}

String _formatLabel(dynamic raw) => (raw ?? '').toString();
