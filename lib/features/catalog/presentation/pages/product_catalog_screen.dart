import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:marketflow/core/widgets/app_brand_logo.dart';
import 'product_details_screen.dart';

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  Map<String, dynamic>? _activeEvent;
  Duration? _remainingEvent;
  Timer? _eventTicker;

  @override
  void initState() {
    super.initState();
    final productProvider = context.read<ProductCatalogProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.wait([productProvider.fetchProducts(), _loadActiveEvent()]);
    });
  }

  @override
  void dispose() {
    _eventTicker?.cancel();
    super.dispose();
  }

  DateTime? _parseEventExpiry(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  DateTime? _parseEventStart(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed?.toUtc();
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 't' || text == 'yes';
  }

  String _eventState(Map<String, dynamic>? event) {
    if (event == null) return 'inactive';
    final providedState = (event['event_state'] ?? '').toString().trim();
    if (providedState.isNotEmpty) return providedState;

    final isEnabled = _asBool(event['is_active']);
    if (!isEnabled) return 'inactive';
    final now = DateTime.now().toUtc();
    final startsAt = _parseEventStart(event['starts_at']) ?? now;
    final expiresAt = _parseEventExpiry(event['expires_at']);
    if (expiresAt == null || !expiresAt.isAfter(now)) return 'expired';
    if (startsAt.isAfter(now)) return 'upcoming';
    return 'active';
  }

  bool _isEventActive(Map<String, dynamic>? event) {
    return _eventState(event) == 'active';
  }

  void _startEventTicker() {
    _eventTicker?.cancel();
    final event = _activeEvent;
    if (event == null) {
      _remainingEvent = null;
      return;
    }

    final startsAt = _parseEventStart(event['starts_at']);
    final expiry = _parseEventExpiry(event['expires_at']);
    if (expiry == null) {
      _remainingEvent = null;
      return;
    }

    void tick() {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      if (!expiry.isAfter(now)) {
        _eventTicker?.cancel();
        context.read<AppSettingsProvider>().setActiveEventId(null);
        setState(() {
          _activeEvent = null;
          _remainingEvent = null;
        });
        return;
      }

      final isUpcoming = startsAt != null && startsAt.isAfter(now);
      final nextState = isUpcoming ? 'upcoming' : 'active';
      final remaining = isUpcoming
          ? startsAt.difference(now)
          : expiry.difference(now);
      context.read<AppSettingsProvider>().setActiveEventId(
        nextState == 'active' ? (event['id'] ?? '').toString() : null,
      );
      setState(() {
        _remainingEvent = remaining;
        _activeEvent = Map<String, dynamic>.from(event)
          ..['event_state'] = nextState;
      });
    }

    tick();
    _eventTicker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _loadActiveEvent() async {
    try {
      final row = await context
          .read<ProductCatalogProvider>()
          .fetchActiveEvent();
      final nextEvent = row == null ? null : Map<String, dynamic>.from(row);
      final isActive = _isEventActive(nextEvent);
      if (!mounted) return;
      setState(() {
        _activeEvent = nextEvent;
      });
      context.read<AppSettingsProvider>().setActiveEventId(
        isActive ? (nextEvent?['id'] ?? '').toString() : null,
      );
      _startEventTicker();
    } catch (_) {
      if (!mounted) return;
      _eventTicker?.cancel();
      context.read<AppSettingsProvider>().setActiveEventId(null);
      setState(() {
        _activeEvent = null;
        _remainingEvent = null;
      });
    }
  }

  int _gridColumns(double width) {
    if (width >= 1700) return 5;
    if (width >= 1320) return 4;
    if (width >= 980) return 3;
    if (width >= 360) return 2;
    return 1;
  }

  double _gridAspectRatio(double width) {
    if (width >= 1320) return 0.73;
    if (width >= 980) return 0.71;
    if (width >= 360) return 0.68;
    return 0.98;
  }

  double _maxContentWidth(double width) {
    if (width >= 1800) return 1520;
    if (width >= 1440) return 1320;
    return 1160;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductCatalogProvider>();
    final settings = context.watch<AppSettingsProvider>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useDesktopLayout = kIsWeb && screenWidth >= 980;
    final showBrandText = screenWidth >= 420;
    final categories = settings.categoriesForProducts(prov.all);
    final columns = _gridColumns(screenWidth);
    final aspectRatio = _gridAspectRatio(screenWidth);
    final contentHorizontalPadding = useDesktopLayout ? 18.0 : 0.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: useDesktopLayout ? 72 : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 34, showWordmark: false),
            if (showBrandText) ...[
              const SizedBox(width: 12),
              Text(
                Brand.name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: useDesktopLayout ? 28 : 24,
                ),
              ),
            ],
          ],
        ),
      ),
      body: prov.loading
          ? const Center(child: CircularProgressIndicator())
          : prov.error != null && prov.visible.isEmpty
          ? _LoadProductsError(
              message: prov.error!,
              onRetry: () =>
                  context.read<ProductCatalogProvider>().fetchProducts(),
            )
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: useDesktopLayout
                      ? _maxContentWidth(screenWidth)
                      : screenWidth,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: contentHorizontalPadding,
                  ),
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FBF9),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _CategoryChips(categories: categories),
                            const SizedBox(height: 4),
                            const _SearchBar(),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: const Color(0xFFF8FBF9),
                          child: ClipRect(
                            child: ScrollConfiguration(
                              behavior: const _NoOverscrollScrollBehavior(),
                              child: CustomScrollView(
                                physics: const ClampingScrollPhysics(),
                                slivers: [
                                  if (_activeEvent != null)
                                    SliverToBoxAdapter(
                                      child: _HeroBanner(
                                        event: _activeEvent!,
                                        remaining: _remainingEvent,
                                      ),
                                    ),
                                  if (prov.visible.isEmpty)
                                    const SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: Text('No products found'),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.all(12),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              childAspectRatio: aspectRatio,
                                              crossAxisSpacing: 12,
                                              mainAxisSpacing: 12,
                                            ),
                                        delegate: SliverChildBuilderDelegate((
                                          context,
                                          i,
                                        ) {
                                          final p = prov.visible[i];
                                          return _ProductCard(
                                            product: p,
                                            onTap: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ProductDetailsScreen(
                                                      product: p,
                                                    ),
                                              ),
                                            ),
                                          );
                                        }, childCount: prov.visible.length),
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
}

class _LoadProductsError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _LoadProductsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: TextField(
        onChanged: (v) => context.read<ProductCatalogProvider>().setQuery(v),

        decoration: InputDecoration(
          hintText: "Search shirts, pants, sneakers...",
          prefixIcon: const Icon(Icons.search),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final List<String> categories;

  const _CategoryChips({required this.categories});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductCatalogProvider>();

    final cats = categories.isEmpty ? const ['All'] : categories;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          itemCount: cats.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final c = cats[i];
            final active = prov.category == c;

            return ChoiceChip(
              label: Text(c),
              selected: active,
              onSelected: (_) =>
                  context.read<ProductCatalogProvider>().setCategory(c),
              selectedColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              side: BorderSide(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade800,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final Map<String, dynamic> event;
  final Duration? remaining;

  const _HeroBanner({required this.event, required this.remaining});

  String _formatRemaining(Duration value) {
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  String _themeKey(Map<String, dynamic> value) {
    return (value['theme'] ?? 'default').toString().trim().toLowerCase();
  }

  LinearGradient _themeGradient(String theme) {
    switch (theme) {
      case 'christmas_sale':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7D69), Color(0xFFB71C1C)],
        );
      case 'valentine':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD33F6A), Color(0xFF8E2B8C)],
        );
      case 'new_year':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F4BA2), Color(0xFF1E8A8A)],
        );
      case 'black_friday':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1B), Color(0xFF4A4A4A)],
        );
      case 'summer_sale':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF8D2F), Color(0xFFE45555)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7D69), Color(0xFF0F5D85)],
        );
    }
  }

  IconData _themeIcon(String theme) {
    switch (theme) {
      case 'christmas_sale':
        return Icons.celebration;
      case 'valentine':
        return Icons.favorite;
      case 'new_year':
        return Icons.auto_awesome;
      case 'black_friday':
        return Icons.local_offer;
      case 'summer_sale':
        return Icons.wb_sunny;
      default:
        return Icons.local_fire_department_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventState = (event['event_state'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isActive = eventState == 'active';
    final isUpcoming = eventState == 'upcoming';
    final badge = (event['badge'] ?? '').toString().trim();
    final theme = _themeKey(event);
    final title = (event['title'] ?? (isUpcoming ? 'Coming Soon' : 'New Drop'))
        .toString()
        .trim();
    final subtitle =
        (event['subtitle'] ??
                (isUpcoming
                    ? 'Fresh arrivals are almost here'
                    : 'Streetwear Week\nUp to 35% OFF'))
            .toString();
    final headline = subtitle.trim().isEmpty ? title : '$title\n$subtitle';
    final timerLabel = remaining != null ? _formatRemaining(remaining!) : '';
    final timerPrefix = isUpcoming ? 'Starts in ' : 'Ends in ';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: _themeGradient(theme),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2A0E6E61),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badge.isEmpty ? 'Featured Event' : badge,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isUpcoming) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x40FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'UPCOMING',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                  if (timerLabel.isNotEmpty && (isUpcoming || isActive)) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '$timerPrefix$timerLabel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: 6),
                  Text(
                    title.isEmpty ? 'Featured Event' : headline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(_themeIcon(theme), color: Colors.white, size: 42),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final discount = settings.discountPercentForProduct(productId: product.id);
    final hasDiscount = discount > 0;
    final displayPrice = settings.formatUsd(
      product.price,
      productId: product.id,
      overrideDiscountPercent: discount,
    );
    final originalPrice = settings.formatUsd(
      product.price,
      overrideDiscountPercent: 0,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color.fromARGB(255, 23, 18, 18)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Hero(
                      tag: 'product-image-${product.id}',
                      transitionOnUserGestures: true,
                      child: product.imageUrl.isEmpty
                          ? Container(
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image, size: 40),
                            )
                          : Image.network(
                              product.imageUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                        child: SizedBox(
                          height: 36,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayPrice,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (hasDiscount)
                                Text(
                                  originalPrice,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                )
                              else
                                const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasDiscount)
              Positioned(
                top: 8,
                left: 8,
                child: Transform.rotate(
                  angle: -0.7853981633974483,
                  child: Container(
                    width: 86,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC5A2E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '-${discount.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoOverscrollScrollBehavior extends MaterialScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
