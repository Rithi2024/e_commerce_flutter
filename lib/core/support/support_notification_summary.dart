import 'package:marketflow/core/support/support_request_link.dart';

class SupportNotificationItem {
  const SupportNotificationItem({
    required this.orderId,
    required this.status,
    required this.requestType,
    required this.activityAt,
    required this.summary,
    this.supportNote = '',
    this.sharedAddress = '',
  });

  final int orderId;
  final String status;
  final String requestType;
  final DateTime activityAt;
  final String summary;
  final String supportNote;
  final String sharedAddress;

  bool get isResolved => status == 'resolved';
}

class SupportNotificationSummary {
  const SupportNotificationSummary({
    this.unreadCount = 0,
    this.activeRequestCount = 0,
    this.items = const <SupportNotificationItem>[],
  });

  final int unreadCount;
  final int activeRequestCount;
  final List<SupportNotificationItem> items;

  bool get hasUnread => unreadCount > 0;

  bool get hasActiveRequests => activeRequestCount > 0;

  bool get hasItems => items.isNotEmpty;

  DateTime? get latestActivityAt => hasItems ? items.first.activityAt : null;
}

SupportNotificationSummary summarizeSupportNotifications(
  List<Map<String, dynamic>> orders, {
  DateTime? lastSeenAt,
  int maxItems = 3,
}) {
  final items = <SupportNotificationItem>[];
  var activeRequestCount = 0;

  for (final order in orders) {
    final latestStatus = _normalizeStatus(
      order['support_request_status'],
      fallback: _latestStatusFromHistory(order['support_request_history']),
    );
    if (latestStatus == 'pending' || latestStatus == 'address_applied') {
      activeRequestCount += 1;
    }

    final item = _buildNotificationItem(order);
    if (item != null) {
      items.add(item);
    }
  }

  items.sort((a, b) => b.activityAt.compareTo(a.activityAt));
  final visibleItems = items.take(maxItems).toList(growable: false);
  final unreadCount = items.where((item) {
    if (lastSeenAt == null) return true;
    return item.activityAt.isAfter(lastSeenAt);
  }).length;

  return SupportNotificationSummary(
    unreadCount: unreadCount,
    activeRequestCount: activeRequestCount,
    items: visibleItems,
  );
}

DateTime? latestSupportNotificationActivityAt(
  List<Map<String, dynamic>> orders,
) {
  final summary = summarizeSupportNotifications(
    orders,
    maxItems: orders.length,
  );
  return summary.latestActivityAt;
}

DateTime? latestSupportNotificationActivityAtForOrder(
  List<Map<String, dynamic>> orders,
  int orderId,
) {
  if (orderId <= 0) return null;

  final summary = summarizeSupportNotifications(
    orders,
    maxItems: orders.length,
  );
  for (final item in summary.items) {
    if (item.orderId == orderId) {
      return item.activityAt;
    }
  }
  return null;
}

String supportNotificationSeenKey(String userId) {
  final normalized = userId.trim();
  return 'support_notifications.seen_at.$normalized';
}

SupportNotificationItem? _buildNotificationItem(Map<String, dynamic> order) {
  final orderId = _parseOrderId(order['id']);
  if (orderId <= 0) return null;

  final history = _extractHistory(order['support_request_history']);
  final latestNotifiable =
      history
          .map(_historyToNotificationSnapshot)
          .whereType<_NotificationSnapshot>()
          .toList()
        ..sort((a, b) => b.activityAt.compareTo(a.activityAt));

  if (latestNotifiable.isEmpty) return null;
  final item = latestNotifiable.first;

  return SupportNotificationItem(
    orderId: orderId,
    status: item.status,
    requestType: item.requestType,
    activityAt: item.activityAt,
    summary: item.summary,
    supportNote: item.supportNote,
    sharedAddress: item.sharedAddress,
  );
}

List<Map<String, dynamic>> _extractHistory(dynamic rawHistory) {
  if (rawHistory is! List) return const <Map<String, dynamic>>[];
  return rawHistory
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

_NotificationSnapshot? _historyToNotificationSnapshot(
  Map<String, dynamic> item,
) {
  final status = _normalizeStatus(item['support_request_status']);
  final requestType = (item['request_type'] ?? 'support').toString().trim();
  final supportNote = (item['support_note'] ?? '').toString().trim();
  final sharedAddress = parseUpdatedDeliveryAddressFromSupportMessage(
    (item['support_request_message'] ?? '').toString(),
  );
  final noteUpdatedAt = _parseDateTime(item['support_note_updated_at']);
  final statusUpdatedAt = _parseDateTime(
    item['support_request_status_updated_at'],
  );
  final createdAt = _parseDateTime(item['support_request_created_at']);
  final fallbackActivityAt = noteUpdatedAt ?? statusUpdatedAt ?? createdAt;
  if (fallbackActivityAt == null) return null;

  if (supportNote.isNotEmpty) {
    return _NotificationSnapshot(
      status: status,
      requestType: requestType,
      activityAt: fallbackActivityAt,
      summary: supportNote,
      supportNote: supportNote,
      sharedAddress: sharedAddress,
    );
  }

  if (status == 'address_applied' || status == 'resolved') {
    return _NotificationSnapshot(
      status: status,
      requestType: requestType,
      activityAt: fallbackActivityAt,
      summary: _statusSummary(status),
      supportNote: '',
      sharedAddress: sharedAddress,
    );
  }

  return null;
}

String _latestStatusFromHistory(dynamic rawHistory) {
  final history = _extractHistory(rawHistory);
  if (history.isEmpty) return '';
  return _normalizeStatus(history.first['support_request_status']);
}

String _normalizeStatus(dynamic raw, {String fallback = ''}) {
  final value = (raw ?? '').toString().trim().toLowerCase();
  switch (value) {
    case 'pending':
    case 'address_applied':
    case 'resolved':
      return value;
    default:
      return fallback;
  }
}

String _statusSummary(String status) {
  switch (status) {
    case 'address_applied':
      return 'Support applied your updated address.';
    case 'resolved':
      return 'Support resolved your latest request.';
    default:
      return 'Support updated your request.';
  }
}

int _parseOrderId(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString()) ?? -1;
}

DateTime? _parseDateTime(dynamic raw) {
  final value = (raw ?? '').toString().trim();
  if (value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

class _NotificationSnapshot {
  const _NotificationSnapshot({
    required this.status,
    required this.requestType,
    required this.activityAt,
    required this.summary,
    required this.supportNote,
    required this.sharedAddress,
  });

  final String status;
  final String requestType;
  final DateTime activityAt;
  final String summary;
  final String supportNote;
  final String sharedAddress;
}
