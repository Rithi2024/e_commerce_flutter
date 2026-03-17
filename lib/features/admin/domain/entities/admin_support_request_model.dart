import 'package:marketflow/core/support/support_request_link.dart';

class AdminSupportRequest {
  final int id;
  final String userId;
  final String email;
  final String sessionId;
  final bool isAnonymous;
  final String requestType;
  final String message;
  final String status;
  final DateTime? statusUpdatedAt;
  final String supportNote;
  final DateTime? supportNoteUpdatedAt;
  final DateTime? createdAt;

  const AdminSupportRequest({
    required this.id,
    required this.userId,
    required this.email,
    this.sessionId = '',
    this.isAnonymous = true,
    required this.requestType,
    required this.message,
    this.status = 'pending',
    this.statusUpdatedAt,
    this.supportNote = '',
    this.supportNoteUpdatedAt,
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
      status: _normalizeStatus((data['status'] ?? 'pending').toString()),
      statusUpdatedAt: DateTime.tryParse(
        (data['status_updated_at'] ?? '').toString(),
      ),
      supportNote: (data['support_note'] ?? '').toString().trim(),
      supportNoteUpdatedAt: DateTime.tryParse(
        (data['support_note_updated_at'] ?? '').toString(),
      ),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }

  static String _normalizeStatus(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'address_applied':
      case 'resolved':
        return value;
      default:
        return 'pending';
    }
  }

  int? get linkedOrderId => parseLinkedOrderIdFromSupportMessage(message);

  String get updatedDeliveryAddress =>
      parseUpdatedDeliveryAddressFromSupportMessage(message);

  bool get isDeliveryAddressRecoveryRequest {
    final normalizedType = requestType.trim().toLowerCase();
    final normalizedMessage = message.trim().toLowerCase();
    return normalizedType == 'delivery' &&
        linkedOrderId != null &&
        normalizedMessage.contains('delivery address');
  }

  String get statusLabel {
    switch (status) {
      case 'address_applied':
        return 'Address applied';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Pending';
    }
  }

  bool get isResolved => status == 'resolved';

  bool get hasSupportNote => supportNote.trim().isNotEmpty;
}
