import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/core/pricing/event_deal_pricing.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/cart/domain/entities/cart_line_item.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/catalog/presentation/widgets/event_deal_chip.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_flow_screen.dart';

class ShoppingCartScreen extends StatefulWidget {
  const ShoppingCartScreen({super.key});

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  static const Color _panelBorderColor = Color(0xFFD8E4DD);
  static const Color _panelBackgroundColor = Color(0xFFFFFFFF);

  EventDealPricing? _eventPricingForItem(
    CartItem item,
    AppSettingsProvider settings,
  ) {
    final eventDiscount = settings.activeDiscountForProduct(
      productId: item.productId,
    );
    if (eventDiscount == null) {
      return null;
    }
    return resolveEventDealPricing(
      eventTitle: eventDiscount.eventTitle,
      discountPercent: eventDiscount.discountPercent,
      discountedUnitUsd: item.price,
      quantity: item.qty,
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    Color valueColor = Colors.black,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: const Color(0xFF3D4652),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 18 : 15,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    Color color = _panelBackgroundColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _panelBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14173E33),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

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

  Widget _buildCartItemCard({
    required CartItem item,
    required ShoppingCartProvider cart,
    required AppSettingsProvider settings,
    required bool compactLayout,
  }) {
    final eventPricing = _eventPricingForItem(item, settings);
    final discountedUnitPrice = settings.formatUsd(
      item.price,
      overrideDiscountPercent: 0,
    );
    final regularUnitPrice = eventPricing == null
        ? null
        : settings.formatUsd(
            eventPricing.unitOriginalUsd,
            overrideDiscountPercent: 0,
          );
    final lineTotal = settings.formatUsd(
      item.subTotal,
      overrideDiscountPercent: 0,
    );
    final regularLineTotal = eventPricing == null
        ? null
        : settings.formatUsd(
            eventPricing.lineOriginalUsd,
            overrideDiscountPercent: 0,
          );
    final savingsLabel = eventPricing == null
        ? null
        : settings.formatUsd(
            eventPricing.lineSavingsUsd,
            overrideDiscountPercent: 0,
          );
    final qtyControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _runCartAction(
            () => cart.changeQty(cartId: item.id, qty: item.qty - 1),
          ),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(item.qty.toString(), style: const TextStyle(fontSize: 16)),
        IconButton(
          onPressed: () => _runCartAction(
            () => cart.changeQty(cartId: item.id, qty: item.qty + 1),
          ),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE7E2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: item.imageUrl.isEmpty
                ? Container(
                    width: 84,
                    height: 84,
                    color: const Color(0xFFF3F5F7),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF9AA4AE),
                    ),
                  )
                : Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(color: Color(0xFFF3F5F7)),
                    padding: const EdgeInsets.all(8),
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (eventPricing != null) ...[
                  EventDealChip(
                    eventTitle: eventPricing.eventTitle,
                    backgroundColor: const Color(0xFFE9F5F0),
                    foregroundColor: const Color(0xFF173D36),
                    borderColor: const Color(0xFFD6E6DF),
                    fontSize: 10.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      discountedUnitPrice,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (regularUnitPrice != null)
                      Text(
                        regularUnitPrice,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (savingsLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE8EE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Save $savingsLabel',
                          style: const TextStyle(
                            color: Color(0xFFB62B53),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if ((item.size ?? '').isNotEmpty ||
                    (item.color ?? '').isNotEmpty)
                  Text(
                    '${item.size ?? ''} ${item.color ?? ''}'.trim(),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Qty ${item.qty}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      'Line total $lineTotal',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFF6234A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (regularLineTotal != null)
                      Text(
                        regularLineTotal,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (compactLayout)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      qtyControls,
                      IconButton(
                        onPressed: () =>
                            _runCartAction(() => cart.remove(cartId: item.id)),
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
                        onPressed: () =>
                            _runCartAction(() => cart.remove(cartId: item.id)),
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
  }

  Widget _buildCartSummaryCard({
    required AppSettingsProvider settings,
    required ShoppingCartProvider cart,
    required EventDealPricingSummary eventSummary,
    required double regularCartTotal,
    bool framed = true,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Summary',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF18231F),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Review your bag before you head to checkout.',
          style: TextStyle(
            color: Color(0xFF5B6570),
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        if (eventSummary.hasDeals) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD2E8DF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${eventSummary.headlineLabel} in your bag',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF173D36),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You are already saving ${settings.formatUsd(eventSummary.totalSavingsUsd, overrideDiscountPercent: 0)} across ${eventSummary.discountedItemCount} items before checkout.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF557168),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _summaryRow(
            'Regular price',
            settings.formatUsd(regularCartTotal, overrideDiscountPercent: 0),
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Event savings',
            '-${settings.formatUsd(eventSummary.totalSavingsUsd, overrideDiscountPercent: 0)}',
            valueColor: const Color(0xFF0B7D69),
          ),
          const SizedBox(height: 8),
        ],
        _summaryRow(
          'Cart total',
          settings.formatUsd(cart.total, overrideDiscountPercent: 0),
          bold: true,
        ),
        const SizedBox(height: 10),
        const Text(
          'Delivery options, address details, and VAT are confirmed during checkout.',
          style: TextStyle(
            fontSize: 12.5,
            color: Color(0xFF6B766F),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckoutFlowScreen()),
            ),
            child: const Text('Checkout'),
          ),
        ),
      ],
    );
    if (!framed) {
      return content;
    }
    return _buildSurfaceCard(child: content);
  }

  Widget _buildDesktopCartLayout({
    required ShoppingCartProvider cart,
    required AppSettingsProvider settings,
    required EventDealPricingSummary eventSummary,
    required double regularCartTotal,
  }) {
    final itemCount = cart.items.fold<int>(0, (sum, item) => sum + item.qty);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F7F4), Color(0xFFF8F4EB)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSurfaceCard(
                          color: const Color(0xFFF9FCFB),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F4EF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Color(0xFF0B6F58),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Bag Overview',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF15211D),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$itemCount item${itemCount == 1 ? '' : 's'} ready for checkout.',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        color: Color(0xFF5B6570),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (eventSummary.hasDeals)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF5F0),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Saved ${settings.formatUsd(eventSummary.totalSavingsUsd, overrideDiscountPercent: 0)}',
                                    style: const TextStyle(
                                      color: Color(0xFF0B6F58),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: _buildSurfaceCard(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Items',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF18231F),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView.separated(
                                    padding: EdgeInsets.zero,
                                    itemCount: cart.items.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) =>
                                        _buildCartItemCard(
                                          item: cart.items[index],
                                          cart: cart,
                                          settings: settings,
                                          compactLayout: false,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  SizedBox(
                    width: 340,
                    child: _buildCartSummaryCard(
                      settings: settings,
                      cart: cart,
                      eventSummary: eventSummary,
                      regularCartTotal: regularCartTotal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenteredStateCard({
    required Widget child,
    bool useWebLayout = false,
  }) {
    final inner = Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: useWebLayout ? 420 : 320),
          child: _buildSurfaceCard(child: child),
        ),
      ),
    );
    if (!useWebLayout) {
      return inner;
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F7F4), Color(0xFFF8F4EB)],
        ),
      ),
      child: inner,
    );
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
    final eventDealLines = cart.items
        .map((item) => _eventPricingForItem(item, settings))
        .whereType<EventDealPricing>()
        .toList();
    final eventSummary = summarizeEventDealPricing(eventDealLines);
    final regularCartTotal = cart.total + eventSummary.totalSavingsUsd;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    final content = cart.loading
        ? _buildCenteredStateCard(
            useWebLayout: useWebLayout,
            child: const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        : cart.error != null && cart.items.isEmpty
        ? _buildCenteredStateCard(
            useWebLayout: useWebLayout,
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
          )
        : cart.items.isEmpty
        ? _buildCenteredStateCard(
            useWebLayout: useWebLayout,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 44,
                  color: Color(0xFF8B9A93),
                ),
                SizedBox(height: 10),
                Text(
                  'Your cart is empty',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18231F),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Add a few products to start building your next order.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF5B6570), height: 1.45),
                ),
              ],
            ),
          )
        : useWebLayout
        ? _buildDesktopCartLayout(
            cart: cart,
            settings: settings,
            eventSummary: eventSummary,
            regularCartTotal: regularCartTotal,
          )
        : Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) => _buildCartItemCard(
                    item: cart.items[i],
                    cart: cart,
                    settings: settings,
                    compactLayout: compactLayout,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: _buildCartSummaryCard(
                  settings: settings,
                  cart: cart,
                  eventSummary: eventSummary,
                  regularCartTotal: regularCartTotal,
                  framed: false,
                ),
              ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          "Your Cart",
          style: TextStyle(fontSize: compactLayout ? 22 : 28),
        ),
      ),
      body: content,
    );
  }
}
