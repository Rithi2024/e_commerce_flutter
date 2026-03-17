final RegExp _supportOrderIdPattern = RegExp(
  r'Order\s*#\s*(\d+)',
  caseSensitive: false,
);

final RegExp _supportUpdatedAddressPattern = RegExp(
  r'My updated delivery address is:\s*(.+)',
  caseSensitive: false,
  multiLine: true,
);

int? parseLinkedOrderIdFromSupportMessage(String message) {
  final match = _supportOrderIdPattern.firstMatch(message);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

String parseUpdatedDeliveryAddressFromSupportMessage(String message) {
  final match = _supportUpdatedAddressPattern.firstMatch(message);
  return (match?.group(1) ?? '').trim();
}
