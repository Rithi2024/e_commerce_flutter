import 'dart:async';

import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/cart/domain/usecases/cart_use_cases.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShoppingCartProvider extends ChangeNotifier {
  final CartUseCases _useCases;
  final LogUseCases? _logUseCases;

  ShoppingCartProvider({
    required CartUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  final List<CartItem> _items = <CartItem>[];
  List<CartItem> get items => List<CartItem>.unmodifiable(_items);
  bool loading = false;
  String? error;
  double _serverTotal = 0;

  double get total => _serverTotal;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final snapshot = await _useCases.loadCart();
      _items
        ..clear()
        ..addAll(snapshot.items);
      _serverTotal = snapshot.total;
      _logInfo(
        action: 'load_cart',
        metadata: {'itemCount': _items.length, 'total': _serverTotal},
      );
    } on PostgrestException catch (e) {
      _items.clear();
      _serverTotal = 0;
      error = e.message.isEmpty ? 'Failed to load cart' : e.message;
      _logError(action: 'load_cart', message: error ?? 'Unknown error');
    } catch (_) {
      _items.clear();
      _serverTotal = 0;
      error = 'Failed to load cart';
      _logError(action: 'load_cart', message: error ?? 'Unknown error');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> addToCart({
    required Product product,
    String? size,
    String? color,
    int quantity = 1,
  }) async {
    error = null;
    notifyListeners();
    try {
      await _useCases.addToCart(
        product: product,
        size: size,
        color: color,
        quantity: quantity,
      );
      await load();
      _logInfo(
        action: 'add_to_cart',
        metadata: {
          'productId': product.id,
          'size': size ?? '',
          'color': color ?? '',
          'quantity': quantity,
        },
      );
    } on PostgrestException catch (e) {
      error = e.message.isEmpty ? 'Failed to add item to cart' : e.message;
      notifyListeners();
      _logError(action: 'add_to_cart', message: error ?? 'Unknown error');
      rethrow;
    } catch (_) {
      error = 'Failed to add item to cart';
      notifyListeners();
      _logError(action: 'add_to_cart', message: error ?? 'Unknown error');
      rethrow;
    }
  }

  Future<void> changeQty({required String cartId, required int qty}) async {
    error = null;
    notifyListeners();
    try {
      await _useCases.setCartQuantity(cartId: cartId, qty: qty);
      await load();
      _logInfo(
        action: 'set_cart_qty',
        metadata: {'cartId': cartId, 'qty': qty},
      );
    } on PostgrestException catch (e) {
      error = e.message.isEmpty ? 'Failed to update cart quantity' : e.message;
      notifyListeners();
      _logError(action: 'set_cart_qty', message: error ?? 'Unknown error');
      rethrow;
    } catch (_) {
      error = 'Failed to update cart quantity';
      notifyListeners();
      _logError(action: 'set_cart_qty', message: error ?? 'Unknown error');
      rethrow;
    }
  }

  Future<void> remove({required String cartId}) async {
    error = null;
    notifyListeners();
    try {
      await _useCases.setCartQuantity(cartId: cartId, qty: 0);
      await load();
      _logInfo(action: 'remove_cart_item', metadata: {'cartId': cartId});
    } on PostgrestException catch (e) {
      error = e.message.isEmpty ? 'Failed to remove item from cart' : e.message;
      notifyListeners();
      _logError(action: 'remove_cart_item', message: error ?? 'Unknown error');
      rethrow;
    } catch (_) {
      error = 'Failed to remove item from cart';
      notifyListeners();
      _logError(action: 'remove_cart_item', message: error ?? 'Unknown error');
      rethrow;
    }
  }

  Future<void> clear() async {
    error = null;
    notifyListeners();
    try {
      await _useCases.clearCart();
      await load();
      _logInfo(action: 'clear_cart');
    } on PostgrestException catch (e) {
      error = e.message.isEmpty ? 'Failed to clear cart' : e.message;
      notifyListeners();
      _logError(action: 'clear_cart', message: error ?? 'Unknown error');
      rethrow;
    } catch (_) {
      error = 'Failed to clear cart';
      notifyListeners();
      _logError(action: 'clear_cart', message: error ?? 'Unknown error');
      rethrow;
    }
  }

  void _logInfo({
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.info(
        feature: 'cart',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }

  void _logError({
    required String action,
    required String message,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.error(
        feature: 'cart',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }
}
