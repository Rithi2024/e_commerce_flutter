import 'dart:async';

import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserWishlistProvider extends ChangeNotifier {
  final WishlistUseCases _useCases;
  final LogUseCases? _logUseCases;

  UserWishlistProvider({
    required WishlistUseCases useCases,
    LogUseCases? logUseCases,
  }) : _useCases = useCases,
       _logUseCases = logUseCases;

  final Set<String> _ids = <String>{};
  Set<String> get ids => Set<String>.unmodifiable(_ids);
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      final ids = await _useCases.loadWishlistIds();
      _ids
        ..clear()
        ..addAll(ids);
      _logInfo(action: 'load_wishlist', metadata: {'count': _ids.length});
    } on PostgrestException catch (e) {
      _ids.clear();
      error = e.message.isEmpty ? 'Failed to load favorites' : e.message;
      _logError(action: 'load_wishlist', message: error ?? 'Unknown error');
    } catch (_) {
      _ids.clear();
      error = 'Failed to load favorites';
      _logError(action: 'load_wishlist', message: error ?? 'Unknown error');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> toggle(String productId) async {
    error = null;
    notifyListeners();

    try {
      final isFav = await _useCases.toggleWishlist(productId);
      if (isFav) {
        _ids.add(productId);
      } else {
        _ids.remove(productId);
      }
      notifyListeners();
      _logInfo(
        action: 'toggle_wishlist',
        metadata: {'productId': productId, 'isFavorite': isFav},
      );
    } on PostgrestException catch (e) {
      error = e.message.isEmpty ? 'Failed to update favorites' : e.message;
      notifyListeners();
      _logError(action: 'toggle_wishlist', message: error ?? 'Unknown error');
      rethrow;
    } catch (_) {
      error = 'Failed to update favorites';
      notifyListeners();
      _logError(action: 'toggle_wishlist', message: error ?? 'Unknown error');
      rethrow;
    }
  }

  void clear() {
    _ids.clear();
    error = null;
    loading = false;
    notifyListeners();
  }

  bool isFav(String productId) => _ids.contains(productId);

  void _logInfo({
    required String action,
    String message = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final logger = _logUseCases;
    if (logger == null) return;
    unawaited(
      logger.info(
        feature: 'wishlist',
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
        feature: 'wishlist',
        action: action,
        message: message,
        metadata: metadata,
      ),
    );
  }
}
