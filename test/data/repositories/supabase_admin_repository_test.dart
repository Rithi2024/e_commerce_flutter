import 'package:marketflow/features/admin/data/repository/supabase_admin_repository.dart';
import 'package:marketflow/features/admin/data/data_sources/admin_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdminDataSource implements AdminDataSource {
  bool throwOnListProfiles = false;

  @override
  Future<Map<String, dynamic>?> getProfile() async {
    return {
      'id': 'u1',
      'name': 'Admin',
      'phone': '',
      'address': '',
      'account_type': 'admin',
    };
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<List<dynamic>> listProducts({required String query}) async {
    return [
      {
        'id': 'p1',
        'name': 'Latte',
        'price': 2.5,
        'image_url': '',
        'description': '',
        'category': 'Drink',
      },
    ];
  }

  @override
  Future<List<dynamic>> listProfiles() async {
    if (throwOnListProfiles) {
      throw Exception('boom');
    }
    return [
      {
        'id': 'u1',
        'email': 'admin@test.com',
        'name': 'Admin',
        'phone': '',
        'address': '',
        'account_type': 'admin',
      },
    ];
  }

  @override
  Future<void> setAccountType({
    required String userId,
    required String accountType,
  }) async {}

  @override
  Future<List<dynamic>> listOrders() async {
    return [
      {
        'id': 1,
        'user_id': 'u1',
        'email': 'user@test.com',
        'total': 5.0,
        'address': 'A',
        'address_details': '',
        'delivery_type': 'drop_off',
        'payment_method': 'cash_on_delivery',
        'payment_reference': '',
        'status': 'pending',
        'items': [
          {
            'productId': 'p1',
            'name': 'Latte',
            'price': 2.5,
            'qty': 2,
            'size': 'M',
            'color': 'Black',
          },
        ],
        'created_at': '2025-01-01T00:00:00Z',
      },
    ];
  }

  @override
  Future<void> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {}

  @override
  Future<void> confirmCashPayment({required int orderId}) async {}

  @override
  Future<List<dynamic>> listSupportRequests() async {
    return [
      {
        'id': 9,
        'request_type': 'delivery',
        'message': 'Where is my package?',
        'session_id': 'chat-test-session',
        'is_anonymous': true,
        'created_at': '2025-01-01T00:00:00Z',
      },
    ];
  }

  @override
  Future<List<dynamic>> listEvents() async => const <dynamic>[];

  @override
  Future<void> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) async {}

  @override
  Future<void> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) async {}

  @override
  Future<void> deleteEvent({required String eventId}) async {}

  @override
  Future<List<dynamic>> getProductVariantStocks({
    required String productId,
  }) async {
    return [
      {'size': 'M', 'color': 'Black', 'stock': 12},
      {'size': 'L', 'color': 'Red', 'stock': 3},
    ];
  }

  @override
  Future<void> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) async {}

  @override
  Future<void> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {}

  @override
  Future<void> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {}

  @override
  Future<void> deleteProduct({required String productId}) async {}
}

void main() {
  test('SupabaseAdminRepository maps order and stock rows', () async {
    final repository = SupabaseAdminRepository(service: _FakeAdminDataSource());

    final ordersResult = await repository.listOrders();
    final stocksResult = await repository.getProductVariantStocks(
      productId: 'p1',
    );
    final supportResult = await repository.listSupportRequests();

    expect(ordersResult.isSuccess, true);
    expect(ordersResult.requireValue.first.items.length, 1);
    expect(ordersResult.requireValue.first.items.first.name, 'Latte');
    expect(stocksResult.isSuccess, true);
    expect(stocksResult.requireValue['M::Black'], 12);
    expect(stocksResult.requireValue['L::Red'], 3);
    expect(supportResult.isSuccess, true);
    expect(supportResult.requireValue.first.requestType, 'delivery');
    expect(supportResult.requireValue.first.isAnonymous, true);
    expect(supportResult.requireValue.first.sessionId, 'chat-test-session');
  });

  test(
    'SupabaseAdminRepository maps datasource exceptions to failures',
    () async {
      final dataSource = _FakeAdminDataSource()..throwOnListProfiles = true;
      final repository = SupabaseAdminRepository(service: dataSource);

      final result = await repository.listProfiles();

      expect(result.isFailure, true);
      expect(result.requireFailure.message.isNotEmpty, true);
    },
  );
}
