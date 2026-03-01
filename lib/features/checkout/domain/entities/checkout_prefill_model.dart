class CheckoutPrefill {
  final String defaultAddress;
  final String contactName;
  final String contactPhone;
  final List<String> savedAddresses;

  const CheckoutPrefill({
    required this.defaultAddress,
    required this.contactName,
    required this.contactPhone,
    required this.savedAddresses,
  });

  factory CheckoutPrefill.empty() {
    return const CheckoutPrefill(
      defaultAddress: '',
      contactName: '',
      contactPhone: '',
      savedAddresses: <String>[],
    );
  }
}
