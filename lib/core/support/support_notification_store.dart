import 'package:shared_preferences/shared_preferences.dart';

import 'package:marketflow/core/support/support_notification_summary.dart';

class SupportNotificationStore {
  const SupportNotificationStore();

  static String _dismissedBannerKey(String userId) {
    final normalized = userId.trim();
    return 'support_notifications.banner_dismissed_at.$normalized';
  }

  Future<DateTime?> loadSeenAt({required String userId}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(supportNotificationSeenKey(normalizedUserId));
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveSeenAt({
    required String userId,
    required DateTime seenAt,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      supportNotificationSeenKey(normalizedUserId),
      seenAt.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> loadBannerDismissedAt({required String userId}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dismissedBannerKey(normalizedUserId));
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveBannerDismissedAt({
    required String userId,
    required DateTime dismissedAt,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _dismissedBannerKey(normalizedUserId),
      dismissedAt.toUtc().toIso8601String(),
    );
  }
}
