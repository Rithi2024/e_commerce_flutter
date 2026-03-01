import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/core/error/failure.dart';
import 'package:marketflow/core/error/result.dart';
import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_support_request_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/admin/domain/repository/admin_repository.dart';

class AdminUseCases {
  final AdminRepository _repository;
  static const Set<String> _allowedEventThemes = <String>{
    'default',
    'christmas_sale',
    'valentine',
    'new_year',
    'black_friday',
    'summer_sale',
  };

  const AdminUseCases(this._repository);

  Future<Result<AdminProfile?>> getProfile() => _repository.getProfile();

  Future<Result<void>> signOut() => _repository.signOut();

  Future<Result<List<Product>>> listProducts({required String query}) {
    return _repository.listProducts(query: query);
  }

  Future<Result<List<AdminProfile>>> listProfiles() {
    return _repository.listProfiles();
  }

  Future<Result<void>> setAccountType({
    required String userId,
    required String accountType,
  }) {
    final normalizedUserId = userId.trim();
    final rawRole = accountType.trim().toLowerCase();

    if (normalizedUserId.isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('User id is required')),
      );
    }
    if (!AccountRole.isAssignableValue(rawRole)) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Invalid account type')),
      );
    }
    final normalizedRole = AccountRole.fromRaw(rawRole).normalized;
    return _repository.setAccountType(
      userId: normalizedUserId,
      accountType: normalizedRole,
    );
  }

  Future<Result<List<AdminOrder>>> listOrders() {
    return _repository.listOrders();
  }

  Future<Result<void>> updateOrderStatus({
    required int orderId,
    required String status,
  }) {
    if (orderId <= 0) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Order id is required')),
      );
    }
    final nextStatus = status.trim().toLowerCase();
    const allowedStatuses = <String>{
      'order_received',
      'order_packed',
      'ready_for_pickup',
      'out_for_delivery',
      'delivered',
      'cancelled',
      // Backward-compatible legacy states
      'pending',
      'paid',
      'shipped',
    };
    if (!allowedStatuses.contains(nextStatus)) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Invalid order status')),
      );
    }
    return _repository.updateOrderStatus(orderId: orderId, status: nextStatus);
  }

  Future<Result<void>> confirmCashPayment({required int orderId}) {
    if (orderId <= 0) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Order id is required')),
      );
    }
    return _repository.confirmCashPayment(orderId: orderId);
  }

  Future<Result<List<AdminEvent>>> listEvents() {
    return _repository.listEvents();
  }

  Future<Result<List<AdminSupportRequest>>> listSupportRequests() {
    return _repository.listSupportRequests();
  }

  Future<Result<void>> createEvent({
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) {
    if (title.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Event title is required')),
      );
    }
    final startsAt = DateTime.tryParse(startsAtIsoUtc)?.toUtc();
    if (startsAt == null) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event start date/time is invalid'),
        ),
      );
    }
    final expiresAt = DateTime.tryParse(expiresAtIsoUtc)?.toUtc();
    if (expiresAt == null) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event end date/time is invalid'),
        ),
      );
    }
    if (!expiresAt.isAfter(startsAt)) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event end date/time must be after start'),
        ),
      );
    }
    final normalizedTheme = theme.trim().toLowerCase();
    if (!_allowedEventThemes.contains(normalizedTheme)) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Invalid event theme')),
      );
    }
    return _repository.createEvent(
      title: title.trim(),
      subtitle: subtitle.trim(),
      badge: badge.trim(),
      theme: normalizedTheme,
      isActive: isActive,
      startsAtIsoUtc: startsAt.toIso8601String(),
      expiresAtIsoUtc: expiresAt.toIso8601String(),
    );
  }

  Future<Result<void>> updateEvent({
    required String eventId,
    required String title,
    required String subtitle,
    required String badge,
    required String theme,
    required bool isActive,
    required String startsAtIsoUtc,
    required String expiresAtIsoUtc,
  }) {
    if (eventId.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Event id is required')),
      );
    }
    if (title.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Event title is required')),
      );
    }
    final startsAt = DateTime.tryParse(startsAtIsoUtc)?.toUtc();
    if (startsAt == null) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event start date/time is invalid'),
        ),
      );
    }
    final expiresAt = DateTime.tryParse(expiresAtIsoUtc)?.toUtc();
    if (expiresAt == null) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event end date/time is invalid'),
        ),
      );
    }
    if (!expiresAt.isAfter(startsAt)) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Event end date/time must be after start'),
        ),
      );
    }
    final normalizedTheme = theme.trim().toLowerCase();
    if (!_allowedEventThemes.contains(normalizedTheme)) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Invalid event theme')),
      );
    }
    return _repository.updateEvent(
      eventId: eventId.trim(),
      title: title.trim(),
      subtitle: subtitle.trim(),
      badge: badge.trim(),
      theme: normalizedTheme,
      isActive: isActive,
      startsAtIsoUtc: startsAt.toIso8601String(),
      expiresAtIsoUtc: expiresAt.toIso8601String(),
    );
  }

  Future<Result<void>> deleteEvent({required String eventId}) {
    if (eventId.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Event id is required')),
      );
    }
    return _repository.deleteEvent(eventId: eventId.trim());
  }

  Future<Result<Map<String, int>>> getProductVariantStocks({
    required String productId,
  }) {
    if (productId.trim().isEmpty) {
      return Future.value(
        FailureResult<Map<String, int>>(
          ValidationFailure('Product id is required'),
        ),
      );
    }
    return _repository.getProductVariantStocks(productId: productId.trim());
  }

  Future<Result<void>> setProductVariantStocks({
    required String productId,
    required List<Map<String, dynamic>> items,
  }) {
    if (productId.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Product id is required')),
      );
    }
    return _repository.setProductVariantStocks(
      productId: productId.trim(),
      items: items,
    );
  }

  Future<Result<void>> createProduct({
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) {
    if (name.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Product name is required')),
      );
    }
    if (price < 0) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Product price must be non-negative'),
        ),
      );
    }
    return _repository.createProduct(
      name: name.trim(),
      price: price,
      imageUrl: imageUrl.trim(),
      description: description.trim(),
      category: category.trim(),
    );
  }

  Future<Result<void>> updateProduct({
    required String productId,
    required String name,
    required double price,
    required String imageUrl,
    required String description,
    required String category,
  }) {
    if (productId.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Product id is required')),
      );
    }
    if (name.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Product name is required')),
      );
    }
    if (price < 0) {
      return Future.value(
        FailureResult<void>(
          ValidationFailure('Product price must be non-negative'),
        ),
      );
    }
    return _repository.updateProduct(
      productId: productId.trim(),
      name: name.trim(),
      price: price,
      imageUrl: imageUrl.trim(),
      description: description.trim(),
      category: category.trim(),
    );
  }

  Future<Result<void>> deleteProduct({required String productId}) {
    if (productId.trim().isEmpty) {
      return Future.value(
        FailureResult<void>(ValidationFailure('Product id is required')),
      );
    }
    return _repository.deleteProduct(productId: productId.trim());
  }
}
