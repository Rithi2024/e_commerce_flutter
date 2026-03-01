import 'package:flutter/foundation.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/core/widgets/app_brand_logo.dart';
import 'package:marketflow/features/catalog/presentation/pages/product_catalog_screen.dart';
import 'package:marketflow/features/wishlist/presentation/pages/wishlist_overview_screen.dart';
import 'package:marketflow/features/cart/presentation/pages/shopping_cart_screen.dart';
import 'package:marketflow/features/settings/presentation/pages/user_profile_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  static const Color _selectedNavIconColor = Color(0xFF121212);
  static const Color _unselectedNavIconColor = Color(0xFF53615B);

  int _index = 0;

  static final List<Widget> _pages = <Widget>[
    ProductCatalogScreen(),
    WishlistOverviewScreen(),
    ShoppingCartScreen(),
    UserProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.read<AuthenticationProvider>().user == null) {
        return;
      }
      context.read<ShoppingCartProvider>().load();
      context.read<UserWishlistProvider>().load();
    });
  }

  Widget _destinationIcon(
    IconData icon, {
    required int cartQty,
    required bool selected,
    required bool isCart,
  }) {
    final base = Icon(
      icon,
      color: selected ? _selectedNavIconColor : _unselectedNavIconColor,
    );
    if (!isCart || cartQty <= 0) return base;
    final String label = cartQty > 99 ? '99+' : cartQty.toString();
    final backgroundColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        base,
        Positioned(
          right: -8,
          top: -7,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
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

  Widget _buildSideNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required int cartQty,
    required bool isCart,
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
          onTap: () => setState(() => _index = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                _destinationIcon(
                  selected ? selectedIcon : icon,
                  cartQty: cartQty,
                  selected: selected,
                  isCart: isCart,
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
  }) {
    final selected = _index == index;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _index = index),
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

  Widget _buildMobileBottomNav({required int cartQty}) {
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cartQty = context.watch<ShoppingCartProvider>().items.fold<int>(
      0,
      (sum, item) => sum + item.qty,
    );
    final useRailLayout = kIsWeb && screenWidth >= 980;

    if (!useRailLayout) {
      return Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: _buildMobileBottomNav(cartQty: cartQty),
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
                    Expanded(child: _buildContentFrame()),
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
