import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/presentation/widgets/admin_events_tab.dart';

void main() {
  testWidgets('events tab filters events by status', (tester) async {
    final now = DateTime.now().toUtc();
    final events = <AdminEvent>[
      AdminEvent(
        id: '1',
        title: 'Spring Launch',
        subtitle: 'New arrivals',
        badge: 'Launch',
        theme: 'default',
        isActive: true,
        startsAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 5)),
        createdAt: now,
        updatedAt: now,
      ),
      AdminEvent(
        id: '2',
        title: 'Summer Drop',
        subtitle: '',
        badge: 'Soon',
        theme: 'summer_sale',
        isActive: true,
        startsAt: now.add(const Duration(hours: 6)),
        expiresAt: now.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
      ),
      AdminEvent(
        id: '3',
        title: 'Archive Sale',
        subtitle: '',
        badge: '',
        theme: 'black_friday',
        isActive: false,
        startsAt: now.subtract(const Duration(days: 4)),
        expiresAt: now.subtract(const Duration(days: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminEventsTab(
            loadingEvents: false,
            events: events,
            submitting: false,
            formatCountdown: (value) => '${value.inHours}h',
            onTapEvent: (_) {},
            onEditEvent: (_) {},
            onDuplicateEvent: (_) {},
            onDeleteEvent: (_) {},
            onToggleActive: (event, nextActive) {},
          ),
        ),
      ),
    );

    expect(find.text('Event overview'), findsOneWidget);
    expect(find.text('All (3)'), findsOneWidget);
    expect(find.text('Spring Launch'), findsOneWidget);
    expect(find.text('Summer Drop'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Upcoming (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Summer Drop'), findsOneWidget);
    expect(find.text('Spring Launch'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Expired (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Archive Sale'), findsOneWidget);
    expect(find.text('Summer Drop'), findsNothing);
  });

  testWidgets('events tab shows filtered empty state', (tester) async {
    final now = DateTime.now().toUtc();
    final events = <AdminEvent>[
      AdminEvent(
        id: '1',
        title: 'Launch',
        subtitle: '',
        badge: '',
        theme: 'default',
        isActive: true,
        startsAt: now.subtract(const Duration(hours: 1)),
        expiresAt: now.add(const Duration(hours: 2)),
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminEventsTab(
            loadingEvents: false,
            events: events,
            submitting: false,
            formatCountdown: (value) => '${value.inHours}h',
            onTapEvent: (_) {},
            onEditEvent: (_) {},
            onDuplicateEvent: (_) {},
            onDeleteEvent: (_) {},
            onToggleActive: (event, nextActive) {},
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Expired (0)'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(
      find.text('No expired events match this filter right now.'),
      findsOneWidget,
    );
  });

  testWidgets('events tab exposes quick pause action', (tester) async {
    final now = DateTime.now().toUtc();
    AdminEvent? toggledEvent;
    bool? toggledValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminEventsTab(
            loadingEvents: false,
            events: <AdminEvent>[
              AdminEvent(
                id: '1',
                title: 'Live Event',
                subtitle: '',
                badge: '',
                theme: 'default',
                isActive: true,
                startsAt: now.subtract(const Duration(hours: 1)),
                expiresAt: now.add(const Duration(hours: 2)),
                createdAt: now,
                updatedAt: now,
              ),
            ],
            submitting: false,
            formatCountdown: (value) => '${value.inHours}h',
            onTapEvent: (_) {},
            onEditEvent: (_) {},
            onDuplicateEvent: (_) {},
            onDeleteEvent: (_) {},
            onToggleActive: (event, nextActive) {
              toggledEvent = event;
              toggledValue = nextActive;
            },
          ),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pumpAndSettle();

    expect(toggledEvent?.title, 'Live Event');
    expect(toggledValue, isFalse);
  });

  testWidgets('events tab exposes duplicate action', (tester) async {
    final now = DateTime.now().toUtc();
    AdminEvent? duplicatedEvent;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminEventsTab(
            loadingEvents: false,
            events: <AdminEvent>[
              AdminEvent(
                id: '1',
                title: 'Weekend Drop',
                subtitle: '',
                badge: '',
                theme: 'default',
                isActive: false,
                startsAt: now.add(const Duration(hours: 3)),
                expiresAt: now.add(const Duration(days: 1)),
                createdAt: now,
                updatedAt: now,
              ),
            ],
            submitting: false,
            formatCountdown: (value) => '${value.inHours}h',
            onTapEvent: (_) {},
            onEditEvent: (_) {},
            onDuplicateEvent: (event) {
              duplicatedEvent = event;
            },
            onDeleteEvent: (_) {},
            onToggleActive: (event, nextActive) {},
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Duplicate'));
    await tester.pumpAndSettle();

    expect(duplicatedEvent?.title, 'Weekend Drop');
  });
}
