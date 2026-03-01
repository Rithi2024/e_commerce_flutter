enum AccountType {
  customer,
  supportAgent,
  delivery,
  cashier,
  superAdmin,
  staff,
}

class AccountRole {
  static const String customerValue = 'customer';
  static const String supportAgentValue = 'support_agent';
  static const String deliveryValue = 'delivery';
  static const String cashierValue = 'cashier';
  static const String superAdminValue = 'super_admin';
  static const String staffValue = 'staff';

  static const List<String> orderedAssignableValues = <String>[
    customerValue,
    supportAgentValue,
    deliveryValue,
    cashierValue,
    staffValue,
    superAdminValue,
  ];

  static const Set<String> assignableValues = <String>{
    customerValue,
    supportAgentValue,
    deliveryValue,
    cashierValue,
    staffValue,
    superAdminValue,
  };

  const AccountRole._(this.normalized);

  factory AccountRole.fromRaw(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return const AccountRole._(customerValue);
    if (value == 'rider') return const AccountRole._(deliveryValue);
    if (value == 'admin') return const AccountRole._(staffValue);
    if (!assignableValues.contains(value)) {
      return const AccountRole._(customerValue);
    }
    return AccountRole._(value);
  }

  final String normalized;

  AccountType get type {
    switch (normalized) {
      case customerValue:
        return AccountType.customer;
      case supportAgentValue:
        return AccountType.supportAgent;
      case deliveryValue:
        return AccountType.delivery;
      case cashierValue:
        return AccountType.cashier;
      case staffValue:
        return AccountType.staff;
      case superAdminValue:
        return AccountType.superAdmin;
      default:
        return AccountType.customer;
    }
  }

  bool get isCustomer => type == AccountType.customer;
  bool get isSupportAgent => type == AccountType.supportAgent;
  bool get isRider => type == AccountType.delivery;
  bool get isCashier => type == AccountType.cashier;
  bool get isSuperAdmin => type == AccountType.superAdmin;
  bool get isAdmin => type == AccountType.staff || isSuperAdmin;
  bool get isStaff => isAdmin || isCashier || isSupportAgent || isRider;

  String get displayLabel {
    switch (type) {
      case AccountType.superAdmin:
        return 'Super Admin';
      case AccountType.supportAgent:
        return 'Support Agent';
      case AccountType.delivery:
        return 'Delivery';
      case AccountType.cashier:
        return 'Cashier';
      case AccountType.staff:
        return 'Staff';
      case AccountType.customer:
        return 'Customer';
    }
  }

  String get managementValue {
    return normalized;
  }

  static bool isAssignableValue(String raw) {
    final value = raw.trim().toLowerCase();
    return assignableValues.contains(value);
  }
}
