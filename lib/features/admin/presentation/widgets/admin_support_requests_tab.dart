import 'package:flutter/material.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';

class AdminSupportRequestsTab extends StatelessWidget {
  const AdminSupportRequestsTab({
    super.key,
    required this.loadingSupportRequests,
    required this.supportRequests,
    required this.formatDateTimeLocal,
  });

  final bool loadingSupportRequests;
  final List<AdminSupportRequest> supportRequests;
  final String Function(dynamic) formatDateTimeLocal;

  String _requestTypeLabel(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'order':
        return 'Order';
      case 'payment':
        return 'Payment';
      case 'delivery':
        return 'Delivery';
      case 'refund':
        return 'Refund';
      case 'account':
        return 'Account';
      default:
        return 'General';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadingSupportRequests) {
      return const Center(child: CircularProgressIndicator());
    }
    if (supportRequests.isEmpty) {
      return const Center(child: Text('No support requests found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: supportRequests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final request = supportRequests[index];
        final email = request.email.trim();
        final userId = request.userId.trim();
        final sessionId = request.sessionId.trim();
        final isAnonymous = request.isAnonymous;
        final message = request.message.trim();
        final createdAt = formatDateTimeLocal(
          request.createdAt?.toIso8601String(),
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 430;
                  final typeChip = Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF3F7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _requestTypeLabel(request.requestType),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request #${request.id}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        typeChip,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Request #${request.id}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      typeChip,
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('Date: $createdAt'),
              const SizedBox(height: 4),
              if (isAnonymous) ...[
                const Text('Sender: Anonymous chat'),
                const SizedBox(height: 4),
                Text('Session ID: ${sessionId.isEmpty ? '-' : sessionId}'),
              ] else ...[
                Text('Email: ${email.isEmpty ? '-' : email}'),
                const SizedBox(height: 4),
                Text('User ID: ${userId.isEmpty ? '-' : userId}'),
              ],
              const SizedBox(height: 8),
              Text(
                message.isEmpty ? '-' : message,
                style: const TextStyle(height: 1.35),
              ),
            ],
          ),
        );
      },
    );
  }
}
