import 'package:marketflow/core/error/failure.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/admin/domain/repository/admin_repository.dart';
import 'package:marketflow/features/admin/domain/usecases/admin_use_cases.dart';
import 'package:marketflow/features/admin/presentation/bloc/admin_dashboard_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdminRepository implements AdminRepository {
  Result<AdminProfile?> profileResult = Success<AdminProfile?>(
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

  Result<List<Product>> productsResult = Success<List<Product>>(<Product>[
    Product(
      id: 'p1',
      name: 'Latte',
      price: 2.0,
      imageUrl: '',
      description: '',
      category: 'Drink',
    ),
  ]);
  Result<List<AdminProfile>> profilesResult = const Success<List<AdminProfile>>(
    <AdminProfile>[],
  );
  Result<List<AdminOrder>> ordersResult = const Success<List<AdminOrder>>(
    <AdminOrder>[],
  );
  Result<List<AdminEvent>> eventsResult = const Success<List<AdminEvent>>(
    <AdminEvent>[],
  );
  Result<List<AdminSupportRequest>> supportRequestsResult =
      const Success<List<AdminSupportRequest>>(<AdminSupportRequest>[]);
  Result<void> createProductResult = const Success<void>(null);
  Result<void> confirmCashPaymentResult = const Success<void>(null);
  Result<void> updateOrderStatusResult = const Success<void>(null);

  @override
  Future<Result<AdminProfile?>> getProfile() async => profileResult;

  @override
  Future<Result<void>> signOut() async => const Success<void>(null);

  @override
  Future<Result<List<Product>>> listProducts({required String query}) async {
    return productsResult;
  }

  @override
  Future<Result<List<AdminProfile>>> listProfiles() async => profilesResult;

  @override
  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  }) async {
    return const Success<void>(null);
  }

  @override
  Future<Result<List<AdminOrder>>> listOrders() async => ordersResult;

  @override
  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    return updateOrderStatusResult;
  }

  @override
  Future<Result<void>> confirmCashPayment({required int orderId}) async {
    return confirmCashPaymentResult;
  }

  @override
  Future<Result<List<AdminSupportRequest>>> listSupportRequests() async {
    return supportRequestsResult;
  }

  @override
  Future<Result<List<AdminEvent>>> listEvents() async => eventsResult;

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
    return createProductResult;
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
  test('initialize loads admin data successfully', () async {
    final repository = _FakeAdminRepository();
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );

    final result = await provider.initialize();

    expect(result.isSuccess, true);
    expect(provider.checkingAccess, false);
    expect(provider.hasAdminAccess, true);
    expect(provider.products.length, 1);
  });

  test('initialize denies non-admin profile', () async {
    final repository = _FakeAdminRepository();
    repository.profileResult = Success<AdminProfile?>(
      const AdminProfile(
        id: 'u2',
        email: 'customer@test.com',
        name: 'Customer',
        phone: '',
        address: '',
        accountType: 'customer',
        createdAt: null,
        updatedAt: null,
      ),
    );
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );

    final result = await provider.initialize();

    expect(result.isFailure, true);
    expect(result.requireFailure, isA<PermissionDeniedFailure>());
    expect(provider.hasAdminAccess, false);
    expect(provider.checkingAccess, false);
  });

  test('initialize allows cashier profile', () async {
    final repository = _FakeAdminRepository();
    repository.profileResult = Success<AdminProfile?>(
      const AdminProfile(
        id: 'u3',
        email: 'cashier@test.com',
        name: 'Cashier',
        phone: '',
        address: '',
        accountType: 'cashier',
        createdAt: null,
        updatedAt: null,
      ),
    );
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );

    final result = await provider.initialize();

    expect(result.isSuccess, true);
    expect(provider.checkingAccess, false);
    expect(provider.hasAdminAccess, false);
    expect(provider.hasCashierAccess, true);
    expect(provider.hasDashboardAccess, true);
  });

  test('saveProduct exposes failure and clears submitting state', () async {
    final repository = _FakeAdminRepository();
    repository.createProductResult = FailureResult<void>(
      ValidationFailure('Product name is required'),
    );
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );
    await provider.initialize();

    final result = await provider.saveProduct(
      name: '  ',
      price: 1,
      imageUrl: '',
      description: '',
      category: 'All',
    );

    expect(result.isFailure, true);
    expect(provider.submitting, false);
    expect(provider.error, 'Product name is required');
  });

  test('initialize allows support agent and loads support requests', () async {
    final repository = _FakeAdminRepository();
    repository.profileResult = Success<AdminProfile?>(
      const AdminProfile(
        id: 'u4',
        email: 'support@test.com',
        name: 'Support',
        phone: '',
        address: '',
        accountType: 'support_agent',
        createdAt: null,
        updatedAt: null,
      ),
    );
    repository.supportRequestsResult =
        const Success<List<AdminSupportRequest>>(<AdminSupportRequest>[
          AdminSupportRequest(
            id: 1,
            userId: 'u1',
            email: 'user@test.com',
            requestType: 'order',
            message: 'Need help',
            createdAt: null,
          ),
        ]);
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );

    final result = await provider.initialize();

    expect(result.isSuccess, true);
    expect(provider.hasSupportAgentAccess, true);
    expect(provider.hasAdminAccess, false);
    expect(provider.supportRequests.length, 1);
  });

  test('rider can update only shipped or delivered statuses', () async {
    final repository = _FakeAdminRepository();
    repository.profileResult = Success<AdminProfile?>(
      const AdminProfile(
        id: 'u5',
        email: 'rider@test.com',
        name: 'Rider',
        phone: '',
        address: '',
        accountType: 'rider',
        createdAt: null,
        updatedAt: null,
      ),
    );
    final provider = AdminDashboardProvider(
      useCases: AdminUseCases(repository),
    );
    await provider.initialize();

    final result = await provider.updateOrderStatus(
      orderId: 1,
      status: 'cancelled',
    );

    expect(result.isFailure, true);
    expect(result.requireFailure, isA<PermissionDeniedFailure>());
  });
}
