import 'package:flutter/material.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';

enum _SupportDeskFilter { all, pending, recovery, resolved }

class AdminSupportRequestsTab extends StatefulWidget {
  const AdminSupportRequestsTab({
    super.key,
    required this.loadingSupportRequests,
    required this.supportRequests,
    required this.formatDateTimeLocal,
    this.submitting = false,
    this.onOpenLinkedOrder,
    this.onUpdateStatus,
    this.onComposeReply,
  });

  final bool loadingSupportRequests;
  final List<AdminSupportRequest> supportRequests;
  final String Function(dynamic) formatDateTimeLocal;
  final bool submitting;
  final Future<void> Function(AdminSupportRequest request)? onOpenLinkedOrder;
  final Future<void> Function(AdminSupportRequest request, String status)?
  onUpdateStatus;
  final Future<void> Function(AdminSupportRequest request)? onComposeReply;

  @override
  State<AdminSupportRequestsTab> createState() =>
      _AdminSupportRequestsTabState();
}

class _AdminSupportRequestsTabState extends State<AdminSupportRequestsTab> {
  _SupportDeskFilter _selectedFilter = _SupportDeskFilter.all;

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

  String _filterLabel(_SupportDeskFilter filter) {
    switch (filter) {
      case _SupportDeskFilter.pending:
        return 'Pending';
      case _SupportDeskFilter.recovery:
        return 'Recovery';
      case _SupportDeskFilter.resolved:
        return 'Resolved';
      case _SupportDeskFilter.all:
        return 'All';
    }
  }

  int _filterCount(_SupportDeskFilter filter) {
    switch (filter) {
      case _SupportDeskFilter.pending:
        return widget.supportRequests
            .where((request) => request.status == 'pending')
            .length;
      case _SupportDeskFilter.recovery:
        return widget.supportRequests
            .where((request) => request.isDeliveryAddressRecoveryRequest)
            .length;
      case _SupportDeskFilter.resolved:
        return widget.supportRequests
            .where((request) => request.status == 'resolved')
            .length;
      case _SupportDeskFilter.all:
        return widget.supportRequests.length;
    }
  }

  List<AdminSupportRequest> _filteredRequests() {
    switch (_selectedFilter) {
      case _SupportDeskFilter.pending:
        return widget.supportRequests
            .where((request) => request.status == 'pending')
            .toList();
      case _SupportDeskFilter.recovery:
        return widget.supportRequests
            .where((request) => request.isDeliveryAddressRecoveryRequest)
            .toList();
      case _SupportDeskFilter.resolved:
        return widget.supportRequests
            .where((request) => request.status == 'resolved')
            .toList();
      case _SupportDeskFilter.all:
        return widget.supportRequests;
    }
  }

  String _emptyStateLabel() {
    switch (_selectedFilter) {
      case _SupportDeskFilter.pending:
        return 'No pending support requests';
      case _SupportDeskFilter.recovery:
        return 'No recovery requests found';
      case _SupportDeskFilter.resolved:
        return 'No resolved support requests';
      case _SupportDeskFilter.all:
        return 'No support requests found';
    }
  }

  Widget _infoChip(String label, {Color? backgroundColor, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFFEFF3F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: textColor ?? const Color(0xFF23313A),
        ),
      ),
    );
  }

  Widget _buildRecoverySummary(AdminSupportRequest request) {
    final orderId = request.linkedOrderId;
    final updatedAddress = request.updatedDeliveryAddress;
    if (!request.isDeliveryAddressRecoveryRequest || orderId == null) {
      return const SizedBox.shrink();
    }

    final hasUpdatedAddress = updatedAddress.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasUpdatedAddress
            ? const Color(0xFFEFFAF4)
            : const Color(0xFFFFF6EB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUpdatedAddress
              ? const Color(0xFF9BD3AE)
              : const Color(0xFFF3C37A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Linked order: #$orderId',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            hasUpdatedAddress
                ? 'Customer included an updated delivery address.'
                : 'Customer still needs help correcting the delivery address.',
            style: const TextStyle(height: 1.35),
          ),
          if (hasUpdatedAddress) ...[
            const SizedBox(height: 8),
            Text(
              updatedAddress,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F5F3A),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLinkedOrderAction(AdminSupportRequest request) {
    final orderId = request.linkedOrderId;
    if (orderId == null || widget.onOpenLinkedOrder == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: () => widget.onOpenLinkedOrder!(request),
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text('Open order #$orderId'),
      ),
    );
  }

  Color _statusBackgroundColor(String status) {
    switch (status) {
      case 'address_applied':
        return const Color(0xFFEAF4FF);
      case 'resolved':
        return const Color(0xFFEFFAF4);
      default:
        return const Color(0xFFFFF6EB);
    }
  }

  Color _statusTextColor(String status) {
    switch (status) {
      case 'address_applied':
        return const Color(0xFF1E5E9A);
      case 'resolved':
        return const Color(0xFF1F5F3A);
      default:
        return const Color(0xFF9A5400);
    }
  }

  Widget _buildStatusActions(AdminSupportRequest request) {
    if (widget.onUpdateStatus == null && widget.onComposeReply == null) {
      return const SizedBox.shrink();
    }

    final actions = <Widget>[
      if (widget.onComposeReply != null)
        OutlinedButton(
          onPressed: widget.submitting
              ? null
              : () => widget.onComposeReply!(request),
          child: Text(request.hasSupportNote ? 'Edit reply' : 'Add reply'),
        ),
      if (request.status == 'pending' &&
          request.isDeliveryAddressRecoveryRequest &&
          widget.onUpdateStatus != null)
        OutlinedButton(
          onPressed: widget.submitting
              ? null
              : () => widget.onUpdateStatus!(request, 'address_applied'),
          child: const Text('Mark address applied'),
        ),
      if (!request.isResolved && widget.onUpdateStatus != null)
        FilledButton(
          onPressed: widget.submitting
              ? null
              : () => widget.onUpdateStatus!(request, 'resolved'),
          child: const Text('Mark resolved'),
        ),
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: actions),
    );
  }

  Widget _buildSupportReply(AdminSupportRequest request) {
    if (!request.hasSupportNote) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9CC2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer-visible reply',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E5E9A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            request.supportNote,
            style: const TextStyle(height: 1.35, color: Color(0xFF1E5E9A)),
          ),
          if (request.supportNoteUpdatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Updated: ${widget.formatDateTimeLocal(request.supportNoteUpdatedAt?.toIso8601String())}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E5E9A),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loadingSupportRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    final supportRequests = _filteredRequests();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: _SupportDeskFilter.values.map((filter) {
              final selected = filter == _selectedFilter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    '${_filterLabel(filter)} (${_filterCount(filter)})',
                  ),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedFilter = filter);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: supportRequests.isEmpty
              ? Center(child: Text(_emptyStateLabel()))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: supportRequests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final request = supportRequests[index];
                    final email = request.email.trim();
                    final userId = request.userId.trim();
                    final sessionId = request.sessionId.trim();
                    final isAnonymous = request.isAnonymous;
                    final message = request.message.trim();
                    final createdAt = widget.formatDateTimeLocal(
                      request.createdAt?.toIso8601String(),
                    );
                    final linkedOrderId = request.linkedOrderId;
                    final hasUpdatedAddress =
                        request.updatedDeliveryAddress.isNotEmpty;
                    final statusUpdatedAt = widget.formatDateTimeLocal(
                      request.statusUpdatedAt?.toIso8601String(),
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
                              final chips = Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _infoChip(
                                    _requestTypeLabel(request.requestType),
                                  ),
                                  _infoChip(
                                    request.statusLabel,
                                    backgroundColor: _statusBackgroundColor(
                                      request.status,
                                    ),
                                    textColor: _statusTextColor(request.status),
                                  ),
                                  if (linkedOrderId != null)
                                    _infoChip(
                                      'Order #$linkedOrderId',
                                      backgroundColor: const Color(0xFFEAF4FF),
                                      textColor: const Color(0xFF1E5E9A),
                                    ),
                                  if (hasUpdatedAddress)
                                    _infoChip(
                                      'Updated address',
                                      backgroundColor: const Color(0xFFEFFAF4),
                                      textColor: const Color(0xFF1F5F3A),
                                    ),
                                ],
                              );

                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Request #${request.id}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    chips,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Request #${request.id}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(child: chips),
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
                            Text(
                              'Session ID: ${sessionId.isEmpty ? '-' : sessionId}',
                            ),
                          ] else ...[
                            Text('Email: ${email.isEmpty ? '-' : email}'),
                            const SizedBox(height: 4),
                            Text('User ID: ${userId.isEmpty ? '-' : userId}'),
                          ],
                          const SizedBox(height: 4),
                          Text('Status: ${request.statusLabel}'),
                          if (request.statusUpdatedAt != null) ...[
                            const SizedBox(height: 4),
                            Text('Updated: $statusUpdatedAt'),
                          ],
                          _buildRecoverySummary(request),
                          _buildSupportReply(request),
                          _buildLinkedOrderAction(request),
                          _buildStatusActions(request),
                          const SizedBox(height: 8),
                          Text(
                            message.isEmpty ? '-' : message,
                            style: const TextStyle(height: 1.35),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
