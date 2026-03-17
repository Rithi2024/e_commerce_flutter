class SupportReplyTemplate {
  final String id;
  final String label;
  final String message;

  const SupportReplyTemplate({
    required this.id,
    required this.label,
    required this.message,
  });
}

const SupportReplyTemplate supportReplyTemplateAddressApplied =
    SupportReplyTemplate(
      id: 'address_applied',
      label: 'Address applied',
      message: 'We applied your updated delivery address.',
    );

const SupportReplyTemplate supportReplyTemplateNeedMoreDetail =
    SupportReplyTemplate(
      id: 'need_more_detail',
      label: 'Need more detail',
      message: 'Please send a more specific delivery address.',
    );

const SupportReplyTemplate supportReplyTemplateReviewing = SupportReplyTemplate(
  id: 'reviewing',
  label: 'Reviewing',
  message: 'We are reviewing your request now.',
);

const SupportReplyTemplate supportReplyTemplateResolved = SupportReplyTemplate(
  id: 'resolved',
  label: 'Resolved',
  message: 'Your request has been resolved.',
);

List<SupportReplyTemplate> supportReplyTemplatesForContext({
  required bool isDeliveryAddressRecoveryRequest,
  required String targetStatus,
}) {
  final normalizedStatus = targetStatus.trim().toLowerCase();
  if (isDeliveryAddressRecoveryRequest) {
    switch (normalizedStatus) {
      case 'address_applied':
        return const <SupportReplyTemplate>[
          supportReplyTemplateAddressApplied,
          supportReplyTemplateNeedMoreDetail,
          supportReplyTemplateReviewing,
          supportReplyTemplateResolved,
        ];
      case 'resolved':
        return const <SupportReplyTemplate>[
          supportReplyTemplateResolved,
          supportReplyTemplateAddressApplied,
          supportReplyTemplateNeedMoreDetail,
          supportReplyTemplateReviewing,
        ];
      default:
        return const <SupportReplyTemplate>[
          supportReplyTemplateReviewing,
          supportReplyTemplateNeedMoreDetail,
          supportReplyTemplateAddressApplied,
          supportReplyTemplateResolved,
        ];
    }
  }

  switch (normalizedStatus) {
    case 'resolved':
      return const <SupportReplyTemplate>[
        supportReplyTemplateResolved,
        supportReplyTemplateReviewing,
      ];
    default:
      return const <SupportReplyTemplate>[
        supportReplyTemplateReviewing,
        supportReplyTemplateResolved,
      ];
  }
}

String supportReplyDefaultMessageForContext({
  required bool isDeliveryAddressRecoveryRequest,
  required String targetStatus,
}) {
  return supportReplyTemplatesForContext(
    isDeliveryAddressRecoveryRequest: isDeliveryAddressRecoveryRequest,
    targetStatus: targetStatus,
  ).first.message;
}
