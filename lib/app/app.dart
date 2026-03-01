import 'package:marketflow/features/auth/data/repository/supabase_auth_repository.dart';
import 'package:marketflow/features/admin/data/repository/supabase_admin_repository.dart';
import 'package:marketflow/features/cart/data/repository/supabase_cart_repository.dart';
import 'package:marketflow/features/logging/data/repository/supabase_log_repository.dart';
import 'package:marketflow/features/checkout/data/repository/supabase_order_repository.dart';
import 'package:marketflow/features/catalog/data/repository/supabase_product_repository.dart';
import 'package:marketflow/features/wishlist/data/repository/supabase_wishlist_repository.dart';
import 'package:marketflow/features/admin/data/data_sources/admin_service.dart';
import 'package:marketflow/features/admin/domain/repository/admin_repository.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/cart/domain/repository/cart_repository.dart';
import 'package:marketflow/features/logging/domain/repository/log_repository.dart';
import 'package:marketflow/features/admin/presentation/pages/admin_dashboard_screen.dart';
import 'package:marketflow/features/auth/presentation/pages/authentication_screen.dart';
import 'package:marketflow/features/shell/presentation/pages/main_navigation_shell.dart';
import 'package:marketflow/features/admin/presentation/pages/support_dashboard_screen.dart';
import 'package:marketflow/config/routes/app_routes.dart';
import 'package:marketflow/config/theme/app_scroll_behavior.dart';
import 'package:marketflow/config/theme/ecommerce_app_theme.dart';
import 'package:marketflow/features/checkout/domain/repository/order_repository.dart';
import 'package:marketflow/features/catalog/domain/repository/product_repository.dart';
import 'package:marketflow/features/wishlist/domain/repository/wishlist_repository.dart';
import 'package:marketflow/features/admin/domain/usecases/admin_use_cases.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/cart/domain/usecases/cart_use_cases.dart';
import 'package:marketflow/features/logging/domain/usecases/log_use_cases.dart';
import 'package:marketflow/features/checkout/domain/usecases/order_use_cases.dart';
import 'package:marketflow/features/catalog/domain/usecases/product_use_cases.dart';
import 'package:marketflow/features/wishlist/domain/usecases/wishlist_use_cases.dart';
import 'package:marketflow/features/admin/presentation/bloc/admin_dashboard_provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/catalog/presentation/bloc/product_catalog_provider.dart';
import 'package:marketflow/features/cart/presentation/bloc/shopping_cart_provider.dart';
import 'package:marketflow/features/wishlist/presentation/bloc/user_wishlist_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EcommerceApp extends StatelessWidget {
  final bool hasSupabaseConfig;

  const EcommerceApp({super.key, this.hasSupabaseConfig = true});

  @override
  Widget build(BuildContext context) {
    if (!hasSupabaseConfig) {
      return MaterialApp(
        theme: AppTheme.light(),
        scrollBehavior: const AppScrollBehavior(),
        debugShowCheckedModeBanner: false,
        home: const _MissingSupabaseConfigScreen(),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettingsProvider>(
          create: (_) => AppSettingsProvider(),
        ),
        Provider<AuthRepository>(
          create: (_) => SupabaseAuthRepository(db: Supabase.instance.client),
        ),
        Provider<CartRepository>(
          create: (_) => SupabaseCartRepository(db: Supabase.instance.client),
        ),
        Provider<ProductRepository>(
          create: (_) =>
              SupabaseProductRepository(db: Supabase.instance.client),
        ),
        Provider<WishlistRepository>(
          create: (_) =>
              SupabaseWishlistRepository(db: Supabase.instance.client),
        ),
        Provider<AdminService>(
          create: (_) => AdminService(db: Supabase.instance.client),
        ),
        Provider<AdminRepository>(
          create: (context) =>
              SupabaseAdminRepository(service: context.read<AdminService>()),
        ),
        Provider<LogRepository>(
          create: (_) => SupabaseLogRepository(db: Supabase.instance.client),
        ),
        Provider<OrderRepository>(
          create: (_) => SupabaseOrderRepository(db: Supabase.instance.client),
        ),
        ProxyProvider<AuthRepository, AuthUseCases>(
          update: (context, repository, previous) => AuthUseCases(repository),
        ),
        ProxyProvider<CartRepository, CartUseCases>(
          update: (context, repository, previous) => CartUseCases(repository),
        ),
        ProxyProvider<ProductRepository, ProductUseCases>(
          update: (context, repository, previous) =>
              ProductUseCases(repository),
        ),
        ProxyProvider<WishlistRepository, WishlistUseCases>(
          update: (context, repository, previous) =>
              WishlistUseCases(repository),
        ),
        ProxyProvider<OrderRepository, OrderUseCases>(
          update: (context, repository, previous) => OrderUseCases(repository),
        ),
        ProxyProvider<AdminRepository, AdminUseCases>(
          update: (context, repository, previous) => AdminUseCases(repository),
        ),
        ProxyProvider<LogRepository, LogUseCases>(
          update: (context, repository, previous) => LogUseCases(repository),
        ),
        ChangeNotifierProvider<AuthenticationProvider>(
          create: (context) => AuthenticationProvider(
            useCases: context.read<AuthUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
        ChangeNotifierProvider<ProductCatalogProvider>(
          create: (context) => ProductCatalogProvider(
            useCases: context.read<ProductUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
        ChangeNotifierProvider<ShoppingCartProvider>(
          create: (context) => ShoppingCartProvider(
            useCases: context.read<CartUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
        ChangeNotifierProvider<OrderManagementProvider>(
          create: (context) => OrderManagementProvider(
            useCases: context.read<OrderUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
        ChangeNotifierProvider<UserWishlistProvider>(
          create: (context) => UserWishlistProvider(
            useCases: context.read<WishlistUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
        ChangeNotifierProvider<AdminDashboardProvider>(
          create: (context) => AdminDashboardProvider(
            useCases: context.read<AdminUseCases>(),
            logUseCases: context.read<LogUseCases>(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        scrollBehavior: const AppScrollBehavior(),
        debugShowCheckedModeBanner: false,
        onGenerateRoute: (settings) {
          final requestedPath = settings.name ?? AppRoutes.home;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => _AppEntry(requestedPath: requestedPath),
          );
        },
      ),
    );
  }
}

class _MissingSupabaseConfigScreen extends StatelessWidget {
  const _MissingSupabaseConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Missing Supabase configuration.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                SizedBox(height: 10),
                Text('Set build-time env values (--dart-define):'),
                SizedBox(height: 8),
                SelectableText(
                  'SUPABASE_URL=https://YOUR_PROJECT.supabase.co\n'
                  'SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppEntry extends StatelessWidget {
  _AppEntry({required String requestedPath})
    : routeRequest = _AppRouteRequest(requestedPath);

  final _AppRouteRequest routeRequest;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthenticationProvider>(
      builder: (context, auth, _) {
        if (auth.user == null) {
          return const AuthenticationScreen();
        }

        if (routeRequest.isSupport && !auth.accountRole.isSupportAgent) {
          return const _SupportAccessDeniedScreen();
        }

        if (routeRequest.isSupport) {
          return const SupportDashboardScreen();
        }

        if (routeRequest.isStaff && !auth.isStaff) {
          return const _AdminAccessDeniedScreen();
        }

        if (routeRequest.isStaff && auth.accountRole.isSupportAgent) {
          return const SupportDashboardScreen();
        }

        if (routeRequest.isStaff) {
          return const AdminDashboardScreen();
        }

        if (auth.accountRole.isSupportAgent) {
          return const SupportDashboardScreen();
        }

        if (auth.isStaff) {
          return const AdminDashboardScreen();
        }

        return const MainNavigationShell();
      },
    );
  }
}

class _AdminAccessDeniedScreen extends StatelessWidget {
  const _AdminAccessDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Access Required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 52,
                  color: Color(0xFF7A2E2E),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This page is only available for staff accounts.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                  },
                  child: const Text('Back to Store'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportAccessDeniedScreen extends StatelessWidget {
  const _SupportAccessDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support Access Required')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.support_agent_outlined,
                  size: 52,
                  color: Color(0xFF7A2E2E),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This page is available only for support-agent accounts.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                  },
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppRouteRequest {
  _AppRouteRequest(String requestedPath)
    : _normalizedPath = requestedPath.trim().toLowerCase();

  final String _normalizedPath;

  bool get isSupport =>
      _normalizedPath == AppRoutes.support ||
      _normalizedPath.startsWith('${AppRoutes.support}/');

  bool get isStaff =>
      _normalizedPath == AppRoutes.staff ||
      _normalizedPath.startsWith('${AppRoutes.staff}/') ||
      _normalizedPath == AppRoutes.admin ||
      _normalizedPath.startsWith('${AppRoutes.admin}/');
}
