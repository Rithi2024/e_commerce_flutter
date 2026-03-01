import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_flow_screen.dart';

class ShoppingCartScreen extends StatefulWidget {
  const ShoppingCartScreen({super.key});

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  Future<void> _loadCart() async {
    final user = context.read<AuthenticationProvider>().user;
    if (user == null) {
      return;
    }
    await context.read<ShoppingCartProvider>().load();
  }

  Future<void> _runCartAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      final message =
          context.read<ShoppingCartProvider>().error ??
          'Failed to update your cart';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    final cart = context.watch<ShoppingCartProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useWebLayout = kIsWeb && screenWidth >= 980;
    final compactLayout = screenWidth < 420;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final content = cart.loading
        ? const Center(child: CircularProgressIndicator())
        : cart.error != null && cart.items.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cart.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loadCart,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          )
        : cart.items.isEmpty
        ? const Center(child: Text("Your cart is empty"))
        : Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final item = cart.items[i];
                    final qtyControls = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _runCartAction(
                            () => cart.changeQty(
                              cartId: item.id,
                              qty: item.qty - 1,
                            ),
                          ),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          item.qty.toString(),
                          style: const TextStyle(fontSize: 16),
                        ),
                        IconButton(
                          onPressed: () => _runCartAction(
                            () => cart.changeQty(
                              cartId: item.id,
                              qty: item.qty + 1,
                            ),
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    );

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.imageUrl.isEmpty
                                ? Container(
                                    width: 70,
                                    height: 70,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_outlined,
                                      color: Color(0xFF9AA4AE),
                                    ),
                                  )
                                : Container(
                                    width: 70,
                                    height: 70,
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(settings.formatUsd(item.price)),
                                const SizedBox(height: 6),

                                if ((item.size ?? '').isNotEmpty ||
                                    (item.color ?? '').isNotEmpty)
                                  Text(
                                    "${item.size ?? ''} ${item.color ?? ''}"
                                        .trim(),
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),

                                const SizedBox(height: 8),
                                if (compactLayout)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      qtyControls,
                                      IconButton(
                                        onPressed: () => _runCartAction(
                                          () => cart.remove(cartId: item.id),
                                        ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    children: [
                                      qtyControls,
                                      const Spacer(),
                                      IconButton(
                                        onPressed: () => _runCartAction(
                                          () => cart.remove(cartId: item.id),
                                        ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Total",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          settings.formatUsd(cart.total),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CheckoutFlowScreen(),
                          ),
                        ),
                        child: const Text("Checkout"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          "Your Cart",
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
