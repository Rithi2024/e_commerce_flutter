import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/core/support/support_notification_summary.dart';

void main() {
  test('support summary counts unread updates and active requests', () {
    final summary = summarizeSupportNotifications(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 3,
          'support_request_status': 'resolved',
          'support_request_history': <Map<String, dynamic>>[
            <String, dynamic>{
              'request_type': 'delivery',
              'support_request_status': 'resolved',
              'support_request_status_updated_at': '2026-03-17T10:31:59Z',
              'support_note':
                  'Your address update has been applied and this support request is now resolved.',
              'support_note_updated_at': '2026-03-17T10:31:59Z',
            },
          ],
        },
        <String, dynamic>{
          'id': 4,
          'support_request_status': 'pending',
          'support_request_history': <Map<String, dynamic>>[
            <String, dynamic>{
              'request_type': 'delivery',
              'support_request_status': 'pending',
              'support_request_created_at': '2026-03-17T10:45:00Z',
            },
          ],
        },
        <String, dynamic>{
          'id': 5,
          'support_request_status': 'address_applied',
          'support_request_history': <Map<String, dynamic>>[
            <String, dynamic>{
              'request_type': 'delivery',
              'support_request_status': 'address_applied',
              'support_request_status_updated_at': '2026-03-17T11:30:00Z',
            },
          ],
        },
      ],
      lastSeenAt: DateTime.parse('2026-03-17T10:45:30Z'),
      maxItems: 5,
    );

    expect(summary.unreadCount, 1);
    expect(summary.activeRequestCount, 2);
    expect(summary.items, hasLength(2));
    expect(summary.items.first.orderId, 5);
    expect(summary.items.first.status, 'address_applied');
    expect(summary.items.last.orderId, 3);
    expect(
      summary.items.last.supportNote,
      'Your address update has been applied and this support request is now resolved.',
    );
  });

  test(
    'pending requests without a support reply do not create unread items',
    () {
      final summary = summarizeSupportNotifications(<Map<String, dynamic>>[
        <String, dynamic>{
          'id': 3,
          'support_request_status': 'pending',
          'support_request_history': <Map<String, dynamic>>[
            <String, dynamic>{
              'request_type': 'delivery',
              'support_request_status': 'pending',
              'support_request_created_at': '2026-03-17T10:31:59Z',
            },
          ],
        },
      ]);

      expect(summary.unreadCount, 0);
      expect(summary.activeRequestCount, 1);
      expect(summary.items, isEmpty);
      expect(
        latestSupportNotificationActivityAt(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 3,
            'support_request_status': 'pending',
            'support_request_history': <Map<String, dynamic>>[
              <String, dynamic>{
                'request_type': 'delivery',
                'support_request_status': 'pending',
                'support_request_created_at': '2026-03-17T10:31:59Z',
              },
            ],
          },
        ]),
        isNull,
      );
    },
  );

  test('support summary can return the latest activity for a single order', () {
    final orders = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 3,
        'support_request_status': 'resolved',
        'support_request_history': <Map<String, dynamic>>[
          <String, dynamic>{
            'request_type': 'delivery',
            'support_request_status': 'resolved',
            'support_note':
                'Your address update has been applied and this support request is now resolved.',
            'support_note_updated_at': '2026-03-17T10:31:59Z',
          },
        ],
      },
      <String, dynamic>{
        'id': 5,
        'support_request_status': 'address_applied',
        'support_request_history': <Map<String, dynamic>>[
          <String, dynamic>{
            'request_type': 'delivery',
            'support_request_status': 'address_applied',
            'support_request_status_updated_at': '2026-03-17T11:30:00Z',
          },
        ],
      },
    ];

    expect(
      latestSupportNotificationActivityAtForOrder(orders, 3),
      DateTime.parse('2026-03-17T10:31:59Z').toUtc(),
    );
    expect(
      latestSupportNotificationActivityAtForOrder(orders, 5),
      DateTime.parse('2026-03-17T11:30:00Z').toUtc(),
    );
    expect(latestSupportNotificationActivityAtForOrder(orders, 99), isNull);
  });
}
