import 'package:flutter/foundation.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:marketflow/core/widgets/favorite_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/features/catalog/presentation/pages/product_details_screen.dart';

class WishlistOverviewScreen extends StatefulWidget {
  const WishlistOverviewScreen({super.key});

  @override
  State<WishlistOverviewScreen> createState() => _WishlistOverviewScreenState();
}

class _WishlistOverviewScreenState extends State<WishlistOverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final auth = context.read<AuthenticationProvider>();
    final products = context.read<ProductCatalogProvider>();
    final wishlist = context.read<UserWishlistProvider>();
    final user = auth.user;

    if (user == null) {
      wishlist.clear();
      return;
    }

    final tasks = <Future<void>>[wishlist.load()];
    if (products.all.isEmpty && !products.loading) {
      tasks.add(products.fetchProducts());
    }
    try {
      await Future.wait(tasks);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to refresh favorites')),
      );
    }
  }

  Future<void> _toggleFavorite(Product product) async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    if (user == null) return;

    try {
      await context.read<UserWishlistProvider>().toggle(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${product.name}" updated in favorites')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update favorites')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthenticationProvider>();
    final products = context.watch<ProductCatalogProvider>();
    final wishlist = context.watch<UserWishlistProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useWebLayout = kIsWeb && screenWidth >= 980;
    final compactLayout = screenWidth < 420;
    final user = auth.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to use favorites')),
      );
    }

    final items = products.all
        .where((p) => wishlist.ids.contains(p.id))
        .toList();
    final initialLoading =
        (wishlist.loading && wishlist.ids.isEmpty) ||
        (products.loading && products.all.isEmpty);

    final content = initialLoading
        ? const Center(child: CircularProgressIndicator())
        : wishlist.error != null && items.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wishlist.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refreshData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: _refreshData,
            child: items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      FavoriteIcon(isFavorite: false, size: 64),
                      SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Your favorites are empty',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        tileColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: item.imageUrl.isEmpty
                                ? Container(
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_outlined,
                                      color: Color(0xFF9AA4AE),
                                    ),
                                  )
                                : Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF3F5F7),
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: Image.network(
                                      item.imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.medium,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Color(0xFF9AA4AE),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          settings.formatUsd(item.price, productId: item.id),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: FavoriteIconButton(
                          tooltip: 'Remove from favorites',
                          onPressed: () => _toggleFavorite(item),
                          isFavorite: true,
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailsScreen(product: item),
                          ),
                        ),
                      );
                    },
                  ),
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          'Favorites',
          style: TextStyle(fontSize: compactLayout ? 22 : 28),
        ),
      ),
      body: useWebLayout
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: content,
              ),
            )
          : content,
    );
  }
}
