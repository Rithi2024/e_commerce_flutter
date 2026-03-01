import 'package:marketflow/core/error/failure.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/admin/domain/repository/admin_repository.dart';
import 'package:marketflow/features/admin/domain/usecases/admin_use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdminRepository implements AdminRepository {
  int listProductsCalls = 0;
  int createProductCalls = 0;
  String? lastProductQuery;

  @override
  Future<Result<AdminProfile?>> getProfile() async {
    return Success<AdminProfile?>(
      const AdminProfile(
        id: 'u1',
        email: 'admin@test.com',
        name: 'Admin',
        phone: '',
        address: '',
        accountType: 'admin',
        createdAt: null,
        updatedAt: null,
      ),
    );
  }

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);

  @override
  Future<Result<List<Product>>> listProducts({required String query}) async {
    listProductsCalls++;
    lastProductQuery = query;
    return Success<List<Product>>(<Product>[
      Product(
        id: 'p1',
        name: 'Coffee',
        price: 2.5,
        imageUrl: '',
        description: '',
        category: 'Drink',
      ),
    ]);
  }

  @override
  Future<Result<List<AdminProfile>>> listProfiles() async {
    return const Success<List<AdminProfile>>(<AdminProfile>[]);
  }

  @override
  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<List<AdminOrder>>> listOrders() async {
    return const Success<List<AdminOrder>>(<AdminOrder>[]);
  }

  @override
  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> confirmCashPayment({required int orderId}) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<List<AdminSupportRequest>>> listSupportRequests() async {
    return const Success<List<AdminSupportRequest>>(<AdminSupportRequest>[]);
  }

  @override
  Future<Result<List<AdminEvent>>> listEvents() async {
    return const Success<List<AdminEvent>>(<AdminEvent>[]);
  }

  @override
  Future<Result<void>> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteEvent({required String eventId}) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<Map<String, int>>> getProductVariantStocks({
    required String productId,
  }) async {
    return const Success<Map<String, int>>(<String, int>{});
  }

  @override
  Future<Result<void>> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {
    createProductCalls++;
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<void>> deleteProduct({required String productId}) async {
    return const Success<void>(null);
  }
}

void main() {
  test('AdminUseCases delegates repository operations', () async {
    final repo = _FakeAdminRepository();
    final useCases = AdminUseCases(repo);

    final productsResult = await useCases.listProducts(query: 'coffee');

    expect(productsResult.isSuccess, true);
    expect(productsResult.requireValue.length, 1);
    expect(repo.listProductsCalls, 1);
    expect(repo.lastProductQuery, 'coffee');
  });

  test('AdminUseCases validates product name before repository call', () async {
    final repo = _FakeAdminRepository();
    final useCases = AdminUseCases(repo);

    final result = await useCases.createProduct(
      name: ' ',
      price: 1,
      imageUrl: '',
      description: '',
      category: 'All',
    );

    expect(result.isFailure, true);
    expect(result.requireFailure, isA<ValidationFailure>());
    expect(repo.createProductCalls, 0);
  });

  test('AdminUseCases validates account type before repository call', () async {
    final repo = _FakeAdminRepository();
    final useCases = AdminUseCases(repo);

    final result = await useCases.setAccountType(
      userId: 'u1',
      accountType: 'invalid_role',
    );

    expect(result.isFailure, true);
    expect(result.requireFailure, isA<ValidationFailure>());
  });
}
