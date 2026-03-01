class UserProfile {
  final String name;
  final String phone;
  final String address;
  final String accountType;
  final bool promoEmailOptIn;

  const UserProfile({
    required this.name,
    required this.phone,
    required this.address,
    required this.accountType,
    required this.promoEmailOptIn,
  });

  factory UserProfile.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final rawPromo = map['promo_email_opt_in'];
    final promoEmailOptIn = rawPromo is bool
        ? rawPromo
        : (rawPromo?.toString().toLowerCase() == 'true' ||
              rawPromo?.toString() == '1');
    return UserProfile(
      name: (map['name'] ?? '').toString().trim(),
      phone: (map['phone'] ?? '').toString().trim(),
      address: (map['address'] ?? '').toString().trim(),
      accountType: (map['account_type'] ?? 'customer').toString().trim(),
      promoEmailOptIn: promoEmailOptIn,
    );
  }
}
