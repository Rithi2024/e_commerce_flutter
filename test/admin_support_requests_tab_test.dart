import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_support_requests_tab.dart';

void main() {
  testWidgets('support tab highlights delivery address recovery context', (
    tester,
  ) async {
    AdminSupportRequest? openedRequest;
    AdminSupportRequest? statusRequest;
    AdminSupportRequest? repliedRequest;
    String? nextStatus;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSupportRequestsTab(
            submitting: false,
            loadingSupportRequests: false,
            supportRequests: const [
              AdminSupportRequest(
                id: 8,
                userId: '',
                email: '',
                requestType: 'delivery',
                status: 'pending',
                message:
                    'Order #3 needs a delivery address update.\n'
                    'My updated delivery address is: 56b Saint 143, Phnom Penh\n'
                    'Please help apply the correct address before delivery handoff.',
                createdAt: null,
              ),
            ],
            formatDateTimeLocal: (_) => '2026-03-17 10:00',
            onOpenLinkedOrder: (request) async {
              openedRequest = request;
            },
            onUpdateStatus: (request, status) async {
              statusRequest = request;
              nextStatus = status;
            },
            onComposeReply: (request) async {
              repliedRequest = request;
            },
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ChoiceChip, 'All (1)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Pending (1)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Recovery (1)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Resolved (0)'), findsOneWidget);
    expect(find.text('Request #8'), findsOneWidget);
    expect(find.text('Order #3'), findsOneWidget);
    expect(find.text('Updated address'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Linked order: #3'), findsOneWidget);
    expect(find.text('Open order #3'), findsOneWidget);
    expect(find.text('Add reply'), findsOneWidget);
    expect(find.text('Mark address applied'), findsOneWidget);
    expect(find.text('Mark resolved'), findsOneWidget);
    expect(
      find.text('Customer included an updated delivery address.'),
      findsOneWidget,
    );
    expect(find.text('56b Saint 143, Phnom Penh'), findsOneWidget);

    await tester.tap(find.text('Open order #3'));
    await tester.pump();
    expect(openedRequest?.linkedOrderId, 3);

    await tester.tap(find.text('Add reply'));
    await tester.pump();
    expect(repliedRequest?.id, 8);

    await tester.tap(find.text('Mark resolved'));
    await tester.pump();
    expect(statusRequest?.id, 8);
    expect(nextStatus, 'resolved');
  });

  testWidgets('support tab still renders plain requests without recovery UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSupportRequestsTab(
            submitting: false,
            loadingSupportRequests: false,
            supportRequests: [
              AdminSupportRequest(
                id: 9,
                userId: 'u1',
                email: 'user@test.com',
                requestType: 'order',
                message: 'Need help with my order total.',
                supportNote: 'We are checking this now.',
                supportNoteUpdatedAt: DateTime.parse('2026-03-17T11:15:00Z'),
                createdAt: null,
                isAnonymous: false,
              ),
            ],
            formatDateTimeLocal: (_) => '2026-03-17 11:00',
            onComposeReply: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Request #9'), findsOneWidget);
    expect(find.text('Order'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Linked order:'), findsNothing);
    expect(
      find.text('Customer included an updated delivery address.'),
      findsNothing,
    );
    expect(find.text('Customer-visible reply'), findsOneWidget);
    expect(find.text('We are checking this now.'), findsOneWidget);
    expect(find.text('Edit reply'), findsOneWidget);
    expect(find.text('Mark address applied'), findsNothing);
    expect(find.text('Mark resolved'), findsNothing);
    expect(find.text('Need help with my order total.'), findsOneWidget);
  });

  testWidgets('support tab filters requests by status and recovery type', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSupportRequestsTab(
            submitting: false,
            loadingSupportRequests: false,
            supportRequests: const [
              AdminSupportRequest(
                id: 10,
                userId: '',
                email: '',
                requestType: 'delivery',
                message:
                    'Order #3 needs a delivery address update.\n'
                    'My updated delivery address is: 56b Saint 143, Phnom Penh',
                createdAt: null,
              ),
              AdminSupportRequest(
                id: 11,
                userId: '',
                email: '',
                requestType: 'order',
                message: 'Thanks, this is resolved now.',
                status: 'resolved',
                createdAt: null,
              ),
            ],
            formatDateTimeLocal: (_) => '2026-03-17 12:00',
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ChoiceChip, 'All (2)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Pending (1)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Recovery (1)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Resolved (1)'), findsOneWidget);
    expect(find.text('Request #10'), findsOneWidget);
    expect(find.text('Request #11'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Recovery (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Request #10'), findsOneWidget);
    expect(find.text('Request #11'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Resolved (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Request #10'), findsNothing);
    expect(find.text('Request #11'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Pending (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Request #10'), findsOneWidget);
    expect(find.text('Request #11'), findsNothing);
  });
}
