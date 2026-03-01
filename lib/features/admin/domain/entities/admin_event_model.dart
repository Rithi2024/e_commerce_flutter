class AdminEvent {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final String theme;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdminEvent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.theme,
    required this.isActive,
    required this.startsAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUpcoming {
    if (!isActive) return false;
    final starts = startsAt;
    if (starts == null) return false;
    return starts.isAfter(DateTime.now().toUtc()) && !isExpired;
  }

  bool get isLive {
    if (!isActive) return false;
    if (isExpired) return false;
    final starts = startsAt;
    if (starts == null) return true;
    return !starts.isAfter(DateTime.now().toUtc());
  }

  bool get isExpired {
    final expires = expiresAt;
    if (expires == null) return false;
    return !expires.isAfter(DateTime.now().toUtc());
  }

  factory AdminEvent.fromMap(Map<String, dynamic> data) {
    return AdminEvent(
      id: (data['id'] ?? '').toString(),
      title: (data['title'] ?? '').toString().trim(),
      subtitle: (data['subtitle'] ?? '').toString().trim(),
      badge: (data['badge'] ?? '').toString().trim(),
      theme: (data['theme'] ?? 'default').toString().trim().toLowerCase(),
      isActive: _asBool(data['is_active']),
      startsAt: DateTime.tryParse(
        (data['starts_at'] ?? '').toString(),
      )?.toUtc(),
      expiresAt: DateTime.tryParse(
        (data['expires_at'] ?? '').toString(),
      )?.toUtc(),
      createdAt: DateTime.tryParse(
        (data['created_at'] ?? '').toString(),
      )?.toUtc(),
      updatedAt: DateTime.tryParse(
        (data['updated_at'] ?? '').toString(),
      )?.toUtc(),
    );
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }
}
