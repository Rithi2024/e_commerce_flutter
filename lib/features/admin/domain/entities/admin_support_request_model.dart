class AdminSupportRequest {
  final int id;
  final String userId;
  final String email;
  final String sessionId;
  final bool isAnonymous;
  final String requestType;
  final String message;
  final DateTime? createdAt;

  const AdminSupportRequest({
    required this.id,
    required this.userId,
    required this.email,
    this.sessionId = '',
    this.isAnonymous = true,
    required this.requestType,
    required this.message,
    required this.createdAt,
  });

  factory AdminSupportRequest.fromMap(Map<String, dynamic> data) {
    final userId = (data['user_id'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final sessionId = (data['session_id'] ?? '').toString().trim();
    final rawAnonymous = (data['is_anonymous'] ?? '').toString().trim();
    final normalizedAnonymous = rawAnonymous.toLowerCase();
    final isAnonymous = normalizedAnonymous.isEmpty
        ? true
        : normalizedAnonymous == 'true' ||
              normalizedAnonymous == 't' ||
              normalizedAnonymous == '1' ||
              normalizedAnonymous == 'yes';
    return AdminSupportRequest(
      id: (data['id'] as num?)?.toInt() ?? 0,
      userId: userId,
      email: email,
      sessionId: sessionId,
      isAnonymous: isAnonymous,
      requestType: (data['request_type'] ?? 'general').toString().trim(),
      message: (data['message'] ?? '').toString().trim(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }
}
