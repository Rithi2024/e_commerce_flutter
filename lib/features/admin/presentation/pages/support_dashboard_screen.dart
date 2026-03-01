import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/core/widgets/logout_prompt_dialog.dart';

import 'package:marketflow/features/admin/presentation/widgets/admin_support_requests_tab.dart';
import 'package:marketflow/features/admin/presentation/bloc/admin_dashboard_provider.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';

class SupportDashboardScreen extends StatefulWidget {
  const SupportDashboardScreen({super.key});

  @override
  State<SupportDashboardScreen> createState() => _SupportDashboardScreenState();
}

class _SupportDashboardScreenState extends State<SupportDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_initialize);
  }

  Future<void> _initialize() async {
    final provider = context.read<AdminDashboardProvider>();
    final result = await provider.initialize();
    if (!mounted || result.isSuccess) return;
    final failure = result.requireFailure;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failure.message)));
  }

  Future<void> _refreshSupport() async {
    final result = await context
        .read<AdminDashboardProvider>()
        .loadSupportRequests();
    if (!mounted || result.isSuccess) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.requireFailure.message)));
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutPrompt(context);
    if (!confirmed || !mounted) return;
    try {
      await context.read<AuthenticationProvider>().logout();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $error')));
    }
  }

  String _formatDateTimeLocal(dynamic raw) {
    final source = (raw ?? '').toString();
    final dt = DateTime.tryParse(source)?.toLocal();
    if (dt == null) return source.isEmpty ? '-' : source;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final support = context.watch<AdminDashboardProvider>();

    if (support.checkingAccess) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!support.hasSupportAgentAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support Access Required')),
        body: const Center(
          child: Text('Only support-agent accounts can access this screen'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Support Desk'),
        actions: [
          IconButton(
            onPressed: support.submitting ? null : _refreshSupport,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: AdminSupportRequestsTab(
        loadingSupportRequests: support.loadingSupportRequests,
        supportRequests: support.supportRequests,
        formatDateTimeLocal: _formatDateTimeLocal,
      ),
    );
  }
}
