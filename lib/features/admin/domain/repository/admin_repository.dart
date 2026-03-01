import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';

abstract class AdminRepository {
  Future<Result<AdminProfile?>> getProfile();

  Future<Result<void>> signOut();

  Future<Result<List<Product>>> listProducts({required String query});

  Future<Result<List<AdminProfile>>> listProfiles();

  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  });

  Future<Result<List<AdminOrder>>> listOrders();

  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  });

  Future<Result<void>> confirmCashPayment({required int orderId});

  Future<Result<List<AdminSupportRequest>>> listSupportRequests();

  Future<Result<List<AdminEvent>>> listEvents();

  Future<Result<void>> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  });

  Future<Result<void>> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  });

  Future<Result<void>> deleteEvent({required String eventId});

  Future<Result<Map<String, int>>> getProductVariantStocks({
    required String productId,
  });

  Future<Result<void>> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  });

  Future<Result<void>> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  });

  Future<Result<void>> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  });

  Future<Result<void>> deleteProduct({required String productId});
}
