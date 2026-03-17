import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/core/support/support_notification_store.dart';
import 'package:marketflow/core/support/support_notification_summary.dart';
import 'package:marketflow/core/widgets/app_brand_logo.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/cart/presentation/pages/shopping_cart_screen.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/presentation/pages/product_catalog_screen.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/checkout/presentation/pages/order_history_list_screen.dart';
import 'package:marketflow/features/settings/presentation/pages/user_profile_screen.dart';
import 'package:marketflow/features/support/presentation/pages/customer_support_screen.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:marketflow/features/wishlist/presentation/pages/wishlist_overview_screen.dart';

class MainNavigationShell extends StatefulWidget {
  final CatalogCollectionFilter? initialCollectionFilter;

  const MainNavigationShell({super.key, this.initialCollectionFilter});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with WidgetsBindingObserver {
  static const Color _selectedNavIconColor = Color(0xFF121212);
  static const Color _unselectedNavIconColor = Color(0xFF53615B);
  static const Color _supportBadgeBackground = Color(0xFFD96D2A);
  static const Color _supportBadgeForeground = Colors.white;

  final SupportNotificationStore _supportNotificationStore =
      const SupportNotificationStore();

  int _index = 0;
  late final List<Widget> _pages;
  SupportNotificationSummary _supportNotifications =
      const SupportNotificationSummary();
  bool _loadingSupportNotifications = false;
  bool _hasLoadedSupportNotifications = false;
  DateTime? _dismissedSupportBannerAt;
  DateTime? _lastAnnouncedSupportActivityAt;
  String _supportContextKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages = <Widget>[
      ProductCatalogScreen(
        initialCollectionFilter: widget.initialCollectionFilter,
      ),
      const WishlistOverviewScreen(),
      const ShoppingCartScreen(),
      const UserProfileScreen(),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.read<AuthenticationProvider>().user == null) {
        return;
      }
      context.read<ShoppingCartProvider>().load();
      context.read<UserWishlistProvider>().load();
      unawaited(_refreshSupportNotifications());
    });
  }

  void _syncSupportContext(AuthenticationProvider auth) {
    final nextKey = '${auth.user?.id ?? ''}:${auth.normalizedAccountType}';
    if (_supportContextKey == nextKey) {
      return;
    }
    final hadSupportContext = _supportContextKey.isNotEmpty;
    _supportContextKey = nextKey;
    _dismissedSupportBannerAt = null;
    _hasLoadedSupportNotifications = false;
    _lastAnnouncedSupportActivityAt = null;
    if (!hadSupportContext) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshSupportNotifications());
    });
  }

  OrderManagementProvider? _orderManagementProviderOrNull() {
    try {
      return context.read<OrderManagementProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _refreshSupportNotifications() async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    final orderProvider = _orderManagementProviderOrNull();
    if (user == null || !auth.accountRole.isCustomer || orderProvider == null) {
      if (!mounted) return;
      setState(() {
        _loadingSupportNotifications = false;
        _supportNotifications = const SupportNotificationSummary();
      });
      return;
    }

    if (mounted) {
      setState(() => _loadingSupportNotifications = true);
    }

    try {
      final previousSummary = _supportNotifications;
      final orders = await orderProvider.loadOrders();
      final seenAt = await _supportNotificationStore.loadSeenAt(
        userId: user.id,
      );
      final dismissedBannerAt = await _supportNotificationStore
          .loadBannerDismissedAt(userId: user.id);
      final summary = summarizeSupportNotifications(
        orders,
        lastSeenAt: seenAt,
        maxItems: 1,
      );
      final shouldShowSnackBar = _shouldAnnounceSupportUpdate(
        previousSummary: previousSummary,
        nextSummary: summary,
      );
      if (!mounted) return;
      setState(() {
        _supportNotifications = summary;
        _hasLoadedSupportNotifications = true;
        _dismissedSupportBannerAt = dismissedBannerAt;
      });
      if (shouldShowSnackBar) {
        _showSupportUpdateSnackBar(summary);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _supportNotifications = const SupportNotificationSummary();
        _hasLoadedSupportNotifications = true;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingSupportNotifications = false);
      }
    }
  }

  void _handleNavSelection(int index) {
    if (_index != index) {
      setState(() => _index = index);
    }
    unawaited(_refreshSupportNotifications());
  }

  bool _shouldAnnounceSupportUpdate({
    required SupportNotificationSummary previousSummary,
    required SupportNotificationSummary nextSummary,
  }) {
    if (!_hasLoadedSupportNotifications || !nextSummary.hasUnread) {
      return false;
    }
    final latestActivityAt = nextSummary.latestActivityAt;
    if (latestActivityAt == null) {
      return false;
    }
    final previousLatestActivityAt = previousSummary.latestActivityAt;
    if (previousLatestActivityAt != null &&
        !latestActivityAt.isAfter(previousLatestActivityAt)) {
      return false;
    }
    final lastAnnouncedActivityAt = _lastAnnouncedSupportActivityAt;
    if (lastAnnouncedActivityAt != null &&
        !latestActivityAt.isAfter(lastAnnouncedActivityAt)) {
      return false;
    }
    return _index != 3;
  }

  void _showSupportUpdateSnackBar(SupportNotificationSummary summary) {
    final item = summary.items.isEmpty ? null : summary.items.first;
    if (item == null) {
      return;
    }
    _lastAnnouncedSupportActivityAt = item.activityAt;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      final content = _supportSnackBarMessage(summary);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(content),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: _supportPrimaryActionLabel(summary),
              onPressed: _handlePrimarySupportAction,
            ),
          ),
        );
    });
  }

  String? get _profileSupportBadgeLabel {
    if (_supportNotifications.unreadCount > 0) {
      final count = _supportNotifications.unreadCount;
      return count > 99 ? '99+' : '$count';
    }
    if (_supportNotifications.activeRequestCount > 0) {
      return '!';
    }
    return null;
  }

  String _supportStatusSummary(String status) {
    switch (status.trim().toLowerCase()) {
      case 'address_applied':
        return 'Support updated the delivery address and left a fresh note.';
      case 'resolved':
        return 'Support finished the latest request and shared a final reply.';
      default:
        return 'Support is still reviewing your latest request.';
    }
  }

  String _supportBannerTitle(SupportNotificationSummary summary) {
    final item = summary.items.isEmpty ? null : summary.items.first;
    if (item == null) {
      return 'Support update available';
    }
    if (summary.unreadCount > 1) {
      return '${summary.unreadCount} new support updates';
    }
    switch (item.status) {
      case 'address_applied':
        return 'Address updated for Order #${item.orderId}';
      case 'resolved':
        return 'Support resolved Order #${item.orderId}';
      default:
        return 'Support replied about Order #${item.orderId}';
    }
  }

  String _supportSnackBarMessage(SupportNotificationSummary summary) {
    final item = summary.items.isEmpty ? null : summary.items.first;
    if (item == null) {
      return 'A new support update is ready in My Orders.';
    }
    if (summary.unreadCount > 1) {
      return '${summary.unreadCount} new support updates are ready in My Orders.';
    }
    switch (item.status) {
      case 'address_applied':
        return 'Support applied an address update for Order #${item.orderId}.';
      case 'resolved':
        return 'Support resolved Order #${item.orderId}.';
      default:
        return 'New support update for Order #${item.orderId}.';
    }
  }

  String _supportPrimaryActionLabel(SupportNotificationSummary summary) {
    final item = summary.items.isEmpty ? null : summary.items.first;
    if (item == null || summary.unreadCount > 1) {
      return 'Review now';
    }
    switch (item.status) {
      case 'address_applied':
        return 'Send update';
      case 'resolved':
        return 'Reopen';
      default:
        return 'Reply';
    }
  }

  IconData _supportPrimaryActionIcon(SupportNotificationSummary summary) {
    final item = summary.items.isEmpty ? null : summary.items.first;
    if (item == null || summary.unreadCount > 1) {
      return Icons.receipt_long_outlined;
    }
    switch (item.status) {
      case 'address_applied':
        return Icons.edit_note_outlined;
      case 'resolved':
        return Icons.refresh_rounded;
      default:
        return Icons.reply_outlined;
    }
  }

  IconData _supportBannerIcon(String status) {
    switch (status.trim().toLowerCase()) {
      case 'address_applied':
        return Icons.edit_location_alt_outlined;
      case 'resolved':
        return Icons.task_alt_rounded;
      default:
        return Icons.mark_chat_unread_rounded;
    }
  }

  Color _supportBannerAccent(String status) {
    switch (status.trim().toLowerCase()) {
      case 'address_applied':
        return const Color(0xFF1E5E9A);
      case 'resolved':
        return const Color(0xFF0B6F58);
      default:
        return const Color(0xFFB85A00);
    }
  }

  bool get _showSupportBanner {
    if (_index == 3 ||
        _loadingSupportNotifications ||
        !_supportNotifications.hasUnread ||
        _supportNotifications.items.isEmpty) {
      return false;
    }
    final latestActivityAt = _supportNotifications.items.first.activityAt;
    final dismissedAt = _dismissedSupportBannerAt;
    return dismissedAt == null || latestActivityAt.isAfter(dismissedAt);
  }

  Future<void> _openOrdersFromSupportBanner() async {
    final orderId = _supportNotifications.items.isEmpty
        ? null
        : _supportNotifications.items.first.orderId;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderHistoryListScreen(initialOrderId: orderId),
      ),
    );
    if (!mounted) return;
    await _refreshSupportNotifications();
  }

  Future<void> _openSupportFromBanner() async {
    final item = _supportNotifications.items.isEmpty
        ? null
        : _supportNotifications.items.first;
    if (item == null) {
      await _openOrdersFromSupportBanner();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSupportScreen(
          initialFollowUpOrderId: item.orderId,
          initialFollowUpStatus: item.status,
          initialFollowUpRequestType: item.requestType,
          initialFollowUpSupportNote: item.supportNote,
          initialFollowUpActivityAt: item.activityAt.toUtc().toIso8601String(),
          initialFollowUpSharedAddress: item.sharedAddress,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshSupportNotifications();
  }

  Future<void> _handlePrimarySupportAction() async {
    if (_supportNotifications.items.isEmpty ||
        _supportNotifications.unreadCount > 1) {
      await _openOrdersFromSupportBanner();
      return;
    }
    await _openSupportFromBanner();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }
    unawaited(_refreshSupportNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _dismissSupportBanner() {
    final latestActivityAt = _supportNotifications.items.isEmpty
        ? DateTime.now()
        : _supportNotifications.items.first.activityAt;
    setState(() => _dismissedSupportBannerAt = latestActivityAt);
    final userId = context.read<AuthenticationProvider>().user?.id.trim() ?? '';
    if (userId.isEmpty) {
      return;
    }
    unawaited(
      _supportNotificationStore.saveBannerDismissedAt(
        userId: userId,
        dismissedAt: latestActivityAt,
      ),
    );
  }

  Widget _destinationIcon(
    IconData icon, {
    required int cartQty,
    required bool selected,
    required bool isCart,
    String? badgeLabel,
    Color? badgeBackground,
    Color? badgeForeground,
    Key? badgeKey,
  }) {
    final base = Icon(
      icon,
      color: selected ? _selectedNavIconColor : _unselectedNavIconColor,
    );

    final String? label;
    final Color backgroundColor;
    final Color foregroundColor;

    if (isCart) {
      if (cartQty <= 0) {
        return base;
      }
      label = cartQty > 99 ? '99+' : cartQty.toString();
      backgroundColor = selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.secondary;
      foregroundColor = Colors.white;
    } else {
      final normalizedBadge = badgeLabel?.trim() ?? '';
      if (normalizedBadge.isEmpty) {
        return base;
      }
      label = normalizedBadge;
      backgroundColor = badgeBackground ?? _supportBadgeBackground;
      foregroundColor = badgeForeground ?? _supportBadgeForeground;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -8,
          top: -7,
          child: Container(
            key: badgeKey,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: foregroundColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContentFrame() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBF9),
          border: Border.all(color: const Color(0xFFD8E4DD)),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A184739),
              blurRadius: 26,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: IndexedStack(index: _index, children: _pages),
      ),
    );
  }

  Widget _buildSupportAlertBanner({required bool mobile}) {
    final item = _supportNotifications.items.first;
    final accentColor = _supportBannerAccent(item.status);
    final unreadLabel = _supportNotifications.unreadCount == 1
        ? '1 new support update'
        : '${_supportNotifications.unreadCount} new support updates';
    final title = _supportBannerTitle(_supportNotifications);
    final message = item.supportNote.isNotEmpty
        ? item.supportNote
        : _supportStatusSummary(item.status);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? 12 : 0,
        mobile ? 10 : 0,
        mobile ? 12 : 0,
        12,
      ),
      child: Container(
        key: const ValueKey('support-alert-banner'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF4EA), Color(0xFFF7FBFF)],
          ),
          border: Border.all(color: const Color(0xFFE5D1B9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14183E33),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _supportBannerIcon(item.status),
                color: accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF14211C),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE6D7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          unreadLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB85A00),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    maxLines: mobile ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF495953),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _handlePrimarySupportAction,
                        icon: Icon(
                          _supportPrimaryActionIcon(_supportNotifications),
                        ),
                        label: Text(
                          _supportPrimaryActionLabel(_supportNotifications),
                        ),
                      ),
                      TextButton(
                        onPressed: _dismissSupportBanner,
                        child: const Text('Later'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _dismissSupportBanner,
              tooltip: 'Dismiss support alert',
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required int cartQty,
    required bool isCart,
    String? badgeLabel,
    Key? badgeKey,
  }) {
    final selected = _index == index;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.14) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.42)
              : const Color(0xFFDCE7E2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleNavSelection(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                _destinationIcon(
                  selected ? selectedIcon : icon,
                  cartQty: cartQty,
                  selected: selected,
                  isCart: isCart,
                  badgeLabel: badgeLabel,
                  badgeBackground: _supportBadgeBackground,
                  badgeForeground: _supportBadgeForeground,
                  badgeKey: badgeKey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected
                          ? scheme.primary
                          : const Color(0xFF53615B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required int cartQty,
    required bool isCart,
    String? badgeLabel,
    Key? badgeKey,
  }) {
    final selected = _index == index;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleNavSelection(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _destinationIcon(
                  selected ? selectedIcon : icon,
                  cartQty: cartQty,
                  selected: selected,
                  isCart: isCart,
                  badgeLabel: badgeLabel,
                  badgeBackground: _supportBadgeBackground,
                  badgeForeground: _supportBadgeForeground,
                  badgeKey: badgeKey,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : const Color(0xFF53615B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBottomNav({
    required int cartQty,
    required String? profileBadgeLabel,
  }) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE7E2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14173E33),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scheme = Theme.of(context).colorScheme;
                const indicatorInset = 4.0;
                final slotWidth = constraints.maxWidth / 4;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      left: (_index * slotWidth) + indicatorInset,
                      top: 2,
                      bottom: 2,
                      width: slotWidth - (indicatorInset * 2),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.34),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _buildBottomNavItem(
                          index: 0,
                          label: 'Shop',
                          icon: Icons.storefront_outlined,
                          selectedIcon: Icons.storefront,
                          cartQty: cartQty,
                          isCart: false,
                        ),
                        _buildBottomNavItem(
                          index: 1,
                          label: 'Favorite',
                          icon: Icons.favorite_border,
                          selectedIcon: Icons.favorite,
                          cartQty: cartQty,
                          isCart: false,
                        ),
                        _buildBottomNavItem(
                          index: 2,
                          label: 'Cart',
                          icon: Icons.shopping_bag_outlined,
                          selectedIcon: Icons.shopping_bag,
                          cartQty: cartQty,
                          isCart: true,
                        ),
                        _buildBottomNavItem(
                          index: 3,
                          label: 'Profile',
                          icon: Icons.person_outline,
                          selectedIcon: Icons.person,
                          cartQty: cartQty,
                          isCart: false,
                          badgeLabel: profileBadgeLabel,
                          badgeKey: const ValueKey('profile-support-badge'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthenticationProvider>();
    _syncSupportContext(auth);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cartQty = context.watch<ShoppingCartProvider>().items.fold<int>(
      0,
      (sum, item) => sum + item.qty,
    );
    final profileBadgeLabel = _profileSupportBadgeLabel;
    final useRailLayout = kIsWeb && screenWidth >= 980;

    if (!useRailLayout) {
      final content = _showSupportBanner
          ? Column(
              children: [
                SafeArea(top: true, bottom: false, child: const SizedBox()),
                _buildSupportAlertBanner(mobile: true),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: IndexedStack(index: _index, children: _pages),
                  ),
                ),
              ],
            )
          : IndexedStack(index: _index, children: _pages);
      return Scaffold(
        body: content,
        bottomNavigationBar: _buildMobileBottomNav(
          cartQty: cartQty,
          profileBadgeLabel: profileBadgeLabel,
        ),
      );
    }

    final compactSideNav = screenWidth < 980;
    final navigationPanelWidth = screenWidth >= 1320 ? 176.0 : 152.0;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9F5F1), Color(0xFFF8F3E9)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1560),
              child: Padding(
                padding: EdgeInsets.all(compactSideNav ? 8 : 16),
                child: Row(
                  children: [
                    Container(
                      width: navigationPanelWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE7E2)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14173E33),
                            blurRadius: 14,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 14, bottom: 8),
                            child: BrandLogo(size: 40, showWordmark: false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                              child: Column(
                                children: [
                                  _buildSideNavItem(
                                    index: 0,
                                    label: 'Shop',
                                    icon: Icons.storefront_outlined,
                                    selectedIcon: Icons.storefront,
                                    cartQty: cartQty,
                                    isCart: false,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSideNavItem(
                                    index: 1,
                                    label: 'Favorite',
                                    icon: Icons.favorite_border,
                                    selectedIcon: Icons.favorite,
                                    cartQty: cartQty,
                                    isCart: false,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSideNavItem(
                                    index: 2,
                                    label: 'Cart',
                                    icon: Icons.shopping_bag_outlined,
                                    selectedIcon: Icons.shopping_bag,
                                    cartQty: cartQty,
                                    isCart: true,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSideNavItem(
                                    index: 3,
                                    label: 'Profile',
                                    icon: Icons.person_outline,
                                    selectedIcon: Icons.person,
                                    cartQty: cartQty,
                                    isCart: false,
                                    badgeLabel: profileBadgeLabel,
                                    badgeKey: const ValueKey(
                                      'profile-support-badge',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: 12,
                            ),
                            child: Text(
                              'MarketFlow',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF61716A),
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: compactSideNav ? 8 : 16),
                    Expanded(
                      child: Column(
                        children: [
                          if (_showSupportBanner)
                            _buildSupportAlertBanner(mobile: false),
                          Expanded(child: _buildContentFrame()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
