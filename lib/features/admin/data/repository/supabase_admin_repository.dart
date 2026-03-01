import 'package:marketflow/core/error/failure_mapper.dart';
import 'package:marketflow/features/admin/data/data_sources/admin_service.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/admin/domain/repository/admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  final AdminDataSource _service;

  SupabaseAdminRepository({required AdminDataSource service})
    : _service = service;

  @override
  Future<Result<AdminProfile?>> getProfile() async {
    try {
      final row = await _service.getProfile();
      if (row == null) {
        return const Success<AdminProfile?>(null);
      }
      return Success<AdminProfile?>(AdminProfile.fromMap(row));
    } catch (error, stackTrace) {
      return FailureResult<AdminProfile?>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load admin profile',
        ),
      );
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _service.signOut();
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to sign out',
        ),
      );
    }
  }

  @override
  Future<Result<List<Product>>> listProducts({required String query}) async {
    try {
      final rows = await _service.listProducts(query: query);
      final products = rows.whereType<Map>().map((raw) {
        final data = Map<String, dynamic>.from(raw);
        return Product.fromMap((data['id'] ?? '').toString(), data);
      }).toList();
      return Success<List<Product>>(products);
    } catch (error, stackTrace) {
      return FailureResult<List<Product>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load products',
        ),
      );
    }
  }

  @override
  Future<Result<List<AdminProfile>>> listProfiles() async {
    try {
      final rows = await _service.listProfiles();
      final profiles = rows
          .whereType<Map>()
          .map((raw) => AdminProfile.fromMap(Map<String, dynamic>.from(raw)))
          .toList();
      return Success<List<AdminProfile>>(profiles);
    } catch (error, stackTrace) {
      return FailureResult<List<AdminProfile>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load user profiles',
        ),
      );
    }
  }

  @override
  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  }) async {
    try {
      await _service.setAccountType(userId: userId, accountType: accountType);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to update account type',
        ),
      );
    }
  }

  @override
  Future<Result<List<AdminOrder>>> listOrders() async {
    try {
      final rows = await _service.listOrders();
      final orders = rows
          .whereType<Map>()
          .map((raw) => AdminOrder.fromMap(Map<String, dynamic>.from(raw)))
          .toList();
      return Success<List<AdminOrder>>(orders);
    } catch (error, stackTrace) {
      return FailureResult<List<AdminOrder>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load orders',
        ),
      );
    }
  }

  @override
  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    try {
      await _service.updateOrderStatus(orderId: orderId, status: status);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to update order status',
        ),
      );
    }
  }

  @override
  Future<Result<void>> confirmCashPayment({required int orderId}) async {
    try {
      await _service.confirmCashPayment(orderId: orderId);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to confirm cash payment',
        ),
      );
    }
  }

  @override
  Future<Result<List<AdminSupportRequest>>> listSupportRequests() async {
    try {
      final rows = await _service.listSupportRequests();
      final requests = rows
          .whereType<Map>()
          .map(
            (raw) =>
                AdminSupportRequest.fromMap(Map<String, dynamic>.from(raw)),
          )
          .toList();
      return Success<List<AdminSupportRequest>>(requests);
    } catch (error, stackTrace) {
      return FailureResult<List<AdminSupportRequest>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load support requests',
        ),
      );
    }
  }

  @override
  Future<Result<List<AdminEvent>>> listEvents() async {
    try {
      final rows = await _service.listEvents();
      final events = rows
          .whereType<Map>()
          .map((raw) => AdminEvent.fromMap(Map<String, dynamic>.from(raw)))
          .toList();
      return Success<List<AdminEvent>>(events);
    } catch (error, stackTrace) {
      return FailureResult<List<AdminEvent>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load events',
        ),
      );
    }
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
    try {
      await _service.createEvent(
        title: title,
        subtitle: subtitle,
        badge: badge,
        theme: theme,
        isActive: isActive,
        startsAtIsoUtc: startsAtIsoUtc,
        expiresAtIsoUtc: expiresAtIsoUtc,
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to create event',
        ),
      );
    }
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
    try {
      await _service.updateEvent(
        eventId: eventId,
        title: title,
        subtitle: subtitle,
        badge: badge,
        theme: theme,
        isActive: isActive,
        startsAtIsoUtc: startsAtIsoUtc,
        expiresAtIsoUtc: expiresAtIsoUtc,
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to update event',
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteEvent({required String eventId}) async {
    try {
      await _service.deleteEvent(eventId: eventId);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to delete event',
        ),
      );
    }
  }

  @override
  Future<Result<Map<String, int>>> getProductVariantStocks({
    required String productId,
  }) async {
    try {
      final rows = await _service.getProductVariantStocks(productId: productId);
      final stockMap = <String, int>{};
      for (final raw in rows.whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final size = (row['size'] ?? '').toString();
        final color = (row['color'] ?? '').toString();
        final stock = (row['stock'] as num?)?.toInt() ?? 0;
        if (size.isEmpty || color.isEmpty) continue;
        stockMap['$size::$color'] = stock;
      }
      return Success<Map<String, int>>(stockMap);
    } catch (error, stackTrace) {
      return FailureResult<Map<String, int>>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to load product stock',
        ),
      );
    }
  }

  @override
  Future<Result<void>> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _service.setProductVariantStocks(
        productId: productId,
        items: items,
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to update product stock',
        ),
      );
    }
  }

  @override
  Future<Result<void>> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) async {
    try {
      await _service.createProduct(
        name: name,
        price: price,
        imageUrl: imageUrl,
        description: description,
        category: category,
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to create product',
        ),
      );
    }
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
    try {
      await _service.updateProduct(
        productId: productId,
        name: name,
        price: price,
        imageUrl: imageUrl,
        description: description,
        category: category,
      );
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to update product',
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteProduct({required String productId}) async {
    try {
      await _service.deleteProduct(productId: productId);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return FailureResult<void>(
        mapDataExceptionToFailure(
          error,
          stackTrace,
          fallbackMessage: 'Failed to delete product',
        ),
      );
    }
  }
}
