class AdminProfile {
  final String id;
  final String email;
  final String name;
  final String phone;
  final String address;
  final String accountType;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdminProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.address,
    required this.accountType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AdminProfile.fromMap(Map<String, dynamic> data) {
    return AdminProfile(
      id: (data['id'] ?? '').toString(),
      email: (data['email'] ?? '').toString().trim(),
      name: (data['name'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      address: (data['address'] ?? '').toString().trim(),
      accountType: (data['account_type'] ?? 'customer').toString().trim(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((data['updated_at'] ?? '').toString()),
    );
  }
}
