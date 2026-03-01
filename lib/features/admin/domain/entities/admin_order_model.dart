import 'dart:convert';

class AdminOrderItem {
  final String productId;
  final String name;
  final double price;
  final String imageUrl;
  final int qty;
  final String size;
  final String color;

  const AdminOrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.qty,
    required this.size,
    required this.color,
  });

  factory AdminOrderItem.fromMap(Map<String, dynamic> data) {
    return AdminOrderItem(
      productId: (data['productId'] ?? data['product_id'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      price: (data['price'] as num?)?.toDouble() ?? 0,
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      qty: (data['qty'] as num?)?.toInt() ?? 0,
      size: (data['size'] ?? '').toString(),
      color: (data['color'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'qty': qty,
      'size': size,
      'color': color,
    };
  }
}

class AdminOrder {
  final int id;
  final String userId;
  final String email;
  final double total;
  final String address;
  final String addressDetails;
  final String deliveryType;
  final String paymentMethod;
  final bool cashPaidConfirmed;
  final DateTime? cashPaidConfirmedAt;
  final String cashPaidConfirmedBy;
  final String paymentReference;
  final String status;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final DateTime? deliveryLocationUpdatedAt;
  final String deliveryLocationUpdatedBy;
  final String deliveryLocationNote;
  final List<AdminOrderItem> items;
  final DateTime? createdAt;

  const AdminOrder({
    required this.id,
    required this.userId,
    required this.email,
    required this.total,
    required this.address,
    required this.addressDetails,
    required this.deliveryType,
    required this.paymentMethod,
    required this.cashPaidConfirmed,
    required this.cashPaidConfirmedAt,
    required this.cashPaidConfirmedBy,
    required this.paymentReference,
    required this.status,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.deliveryLocationUpdatedAt,
    required this.deliveryLocationUpdatedBy,
    required this.deliveryLocationNote,
    required this.items,
    required this.createdAt,
  });

  factory AdminOrder.fromMap(Map<String, dynamic> data) {
    return AdminOrder(
      id: (data['id'] as num?)?.toInt() ?? 0,
      userId: (data['user_id'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
      total: (data['total'] as num?)?.toDouble() ?? 0,
      address: (data['address'] ?? '').toString(),
      addressDetails: (data['address_details'] ?? '').toString(),
      deliveryType: (data['delivery_type'] ?? 'drop_off').toString(),
      paymentMethod: (data['payment_method'] ?? 'cash_on_delivery').toString(),
      cashPaidConfirmed: _toBool(data['cash_paid_confirmed']),
      cashPaidConfirmedAt: DateTime.tryParse(
        (data['cash_paid_confirmed_at'] ?? '').toString(),
      ),
      cashPaidConfirmedBy: (data['cash_paid_confirmed_by'] ?? '').toString(),
      paymentReference: (data['payment_reference'] ?? '').toString(),
      status: _normalizeStatus(data['status']),
      deliveryLatitude: _toNullableDouble(data['delivery_latitude']),
      deliveryLongitude: _toNullableDouble(data['delivery_longitude']),
      deliveryLocationUpdatedAt: DateTime.tryParse(
        (data['delivery_location_updated_at'] ?? '').toString(),
      ),
      deliveryLocationUpdatedBy: (data['delivery_location_updated_by'] ?? '')
          .toString(),
      deliveryLocationNote: (data['delivery_location_note'] ?? '').toString(),
      items: _parseItems(data['items']),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }

  static String _normalizeStatus(dynamic rawStatus) {
    final value = (rawStatus ?? '').toString().trim().toLowerCase();
    if (value == 'paiding' || value == 'paying') return 'order_received';
    if (value == 'pending' || value == 'paid') return 'order_received';
    if (value == 'shipped') return 'out_for_delivery';
    if (value.isEmpty) return 'order_received';
    return value;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed;
  }

  static List<AdminOrderItem> _parseItems(dynamic rawItems) {
    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map((row) => AdminOrderItem.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    }
    if (rawItems is String && rawItems.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawItems);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(
                (row) => AdminOrderItem.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList();
        }
      } catch (_) {}
    }
    return const <AdminOrderItem>[];
  }
}
