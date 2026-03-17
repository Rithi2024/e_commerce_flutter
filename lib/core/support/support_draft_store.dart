import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CustomerSupportDraft {
  const CustomerSupportDraft({
    required this.requestType,
    required this.message,
    this.followUp,
  });

  final String requestType;
  final String message;
  final SupportDraftFollowUp? followUp;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'request_type': requestType,
      'message': message,
      'follow_up': followUp?.toMap(),
    };
  }

  factory CustomerSupportDraft.fromMap(Map<String, dynamic> map) {
    final followUpMap = map['follow_up'];
    return CustomerSupportDraft(
      requestType: (map['request_type'] ?? 'general').toString().trim(),
      message: (map['message'] ?? '').toString(),
      followUp: followUpMap is Map
          ? SupportDraftFollowUp.fromMap(Map<String, dynamic>.from(followUpMap))
          : null,
    );
  }
}

class SupportDraftFollowUp {
  const SupportDraftFollowUp({
    required this.orderId,
    required this.status,
    required this.requestType,
    required this.supportNote,
    required this.sharedAddress,
  });

  final int orderId;
  final String status;
  final String requestType;
  final String supportNote;
  final String sharedAddress;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'order_id': orderId,
      'status': status,
      'request_type': requestType,
      'support_note': supportNote,
      'shared_address': sharedAddress,
    };
  }

  factory SupportDraftFollowUp.fromMap(Map<String, dynamic> map) {
    final orderIdValue = map['order_id'];
    final orderId = orderIdValue is int
        ? orderIdValue
        : int.tryParse((orderIdValue ?? '').toString()) ?? 0;
    return SupportDraftFollowUp(
      orderId: orderId,
      status: (map['status'] ?? '').toString().trim(),
      requestType: (map['request_type'] ?? '').toString().trim(),
      supportNote: (map['support_note'] ?? '').toString(),
      sharedAddress: (map['shared_address'] ?? '').toString(),
    );
  }
}

String supportDraftKey(String scope) {
  final normalizedScope = scope.trim().isEmpty ? 'anonymous' : scope.trim();
  return 'customer_support.draft.$normalizedScope';
}

class SupportDraftStore {
  const SupportDraftStore();

  Future<CustomerSupportDraft?> loadDraft({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(supportDraftKey(scope));
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CustomerSupportDraft.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft({
    required String scope,
    required CustomerSupportDraft draft,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(supportDraftKey(scope), jsonEncode(draft.toMap()));
  }

  Future<void> clearDraft({required String scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(supportDraftKey(scope));
  }
}
