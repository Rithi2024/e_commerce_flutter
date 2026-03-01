import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/core/widgets/logout_prompt_dialog.dart';

import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/admin/presentation/pages/admin_dashboard_screen.dart';
import 'package:marketflow/features/support/presentation/pages/customer_support_screen.dart';
import 'package:marketflow/features/checkout/presentation/pages/order_history_list_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _name = TextEditingController();
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool loading = true;
  bool _updatingProfile = false;
  bool _changingEmail = false;
  String _phone = '';
  String _address = '';
  bool _promoEmailOptIn = false;
  AccountRole accountRole = AccountRole.fromRaw(AccountRole.customerValue);

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadProfile);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final auth = context.read<AuthenticationProvider>();
    final user = auth.user;
    if (user == null) {
      if (mounted) {
        setState(() => loading = false);
      }
      return;
    }

    try {
      final data = await auth.loadProfile();

      if (!mounted) return;

      _name.text = data?.name ?? '';
      _phone = data?.phone ?? '';
      _address = data?.address ?? '';
      _promoEmailOptIn = data?.promoEmailOptIn ?? false;
      accountRole = AccountRole.fromRaw(data?.accountType);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        await auth.logout();
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<bool> _updateProfile({
    required AuthenticationProvider auth,
    required String name,
    required String phone,
    bool? promoEmailOptIn,
  }) async {
    if (_updatingProfile) return false;
    setState(() => _updatingProfile = true);
    try {
      final refreshed = await auth.saveProfile(
        name: name.trim(),
        phone: phone.trim(),
        address: _address,
        promoEmailOptIn: promoEmailOptIn,
      );

      if (!mounted) return false;
      setState(() {
        _name.text = (refreshed?.name ?? name).trim();
        _phone = (refreshed?.phone ?? phone).trim();
        _address = (refreshed?.address ?? _address).trim();
        _promoEmailOptIn =
            refreshed?.promoEmailOptIn ?? promoEmailOptIn ?? _promoEmailOptIn;
        accountRole = AccountRole.fromRaw(
          refreshed?.accountType ?? accountRole.normalized,
        );
      });
      return true;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        await auth.logout();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile')),
        );
      }
      return false;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile')),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _updatingProfile = false);
      }
    }
  }

  Future<void> _editContactInfo(AuthenticationProvider auth) async {
    final nameController = TextEditingController(text: _name.text.trim());
    final phoneController = TextEditingController(text: _phone);
    final currentEmail = (auth.user?.email ?? '').trim();
    final emailController = TextEditingController(text: currentEmail);
    String dialogError = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Contact Info'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'If email changes, a 6-digit confirmation code is required.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF5B6570)),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError,
                      style: const TextStyle(
                        color: Color(0xFFA7192E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final phone = phoneController.text.trim();
                    final email = emailController.text.trim().toLowerCase();
                    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
                    if (name.isEmpty) {
                      setDialogState(
                        () => dialogError = 'Full name is required',
                      );
                      return;
                    }
                    if (phone.isEmpty || digits.length < 8) {
                      setDialogState(
                        () => dialogError = 'Enter a valid phone number',
                      );
                      return;
                    }
                    if (email.isEmpty) {
                      setDialogState(() => dialogError = 'Email is required');
                      return;
                    }
                    if (!_emailPattern.hasMatch(email)) {
                      setDialogState(
                        () => dialogError = 'Enter a valid email address',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, <String, String>{
                      'name': name,
                      'phone': phone,
                      'email': email,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();

    if (result == null) return;
    final name = (result['name'] ?? '').trim();
    final phone = (result['phone'] ?? '').trim();
    final nextEmail = (result['email'] ?? '').trim().toLowerCase();
    final ok = await _updateProfile(auth: auth, name: name, phone: phone);
    if (!mounted || !ok) return;
    final oldEmail = currentEmail.toLowerCase();
    final emailChanged = nextEmail.isNotEmpty && nextEmail != oldEmail;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Contact info updated')));

    if (!emailChanged) return;
    await _changeEmailWithCode(auth: auth, newEmail: nextEmail);
  }

  Future<void> _editEmailPreference(AuthenticationProvider auth) async {
    bool localOptIn = _promoEmailOptIn;
    final nextValue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Email Preferences'),
              content: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Receive promotional emails'),
                value: localOptIn,
                onChanged: (value) => setDialogState(() => localOptIn = value),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, localOptIn),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (nextValue == null || nextValue == _promoEmailOptIn) return;

    final ok = await _updateProfile(
      auth: auth,
      name: _name.text.trim(),
      phone: _phone.trim(),
      promoEmailOptIn: nextValue,
    );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextValue
              ? 'Promotional emails enabled'
              : 'Promotional emails disabled',
        ),
      ),
    );
  }

  String _friendlyAuthError(Object error) {
    final raw = error.toString().trim();
    final normalized = raw.replaceFirst('Exception: ', '').trim();
    final lower = normalized.toLowerCase();
    if (lower.contains('already') && lower.contains('registered')) {
      return 'This email is already in use.';
    }
    if (lower.contains('same') && lower.contains('email')) {
      return 'Use a different email address.';
    }
    if (lower.contains('token') &&
        (lower.contains('invalid') || lower.contains('otp'))) {
      return 'Invalid confirmation code.';
    }
    if (lower.contains('expired')) {
      return 'Confirmation code expired. Please request a new one.';
    }
    if (normalized.isNotEmpty && normalized.length <= 140) {
      return normalized;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<String?> _promptForVerificationCode({required String email}) async {
    final codeController = TextEditingController();
    String dialogError = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Email Change'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter the 6-digit confirmation code sent to $email',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B6570),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Confirmation code',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      dialogError,
                      style: const TextStyle(
                        color: Color(0xFFA7192E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final code = codeController.text.trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                      setDialogState(
                        () => dialogError = 'Enter a valid 6-digit code',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, code);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();
    return result;
  }

  Future<void> _changeEmailWithCode({
    required AuthenticationProvider auth,
    required String newEmail,
  }) async {
    if (_changingEmail) return;
    final targetEmail = newEmail.trim().toLowerCase();
    if (targetEmail.isEmpty) return;

    setState(() => _changingEmail = true);
    try {
      await auth.requestEmailChange(newEmail: targetEmail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
      return;
    } finally {
      if (mounted) {
        setState(() => _changingEmail = false);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Verification code sent to $targetEmail')),
    );

    final code = await _promptForVerificationCode(email: targetEmail);
    if (!mounted || code == null) return;

    setState(() => _changingEmail = true);
    try {
      await auth.confirmEmailChange(newEmail: targetEmail, code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email updated')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
    } finally {
      if (mounted) {
        setState(() => _changingEmail = false);
      }
    }
  }

  Future<void> _handleLogout(AuthenticationProvider auth) async {
    final confirmed = await showLogoutPrompt(context);
    if (!confirmed || !mounted) return;
    try {
      await auth.logout();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $error')));
    }
  }

  String _avatarLabel(User user) {
    final fromName = _name.text.trim();
    if (fromName.isNotEmpty) {
      final parts = fromName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
      final initials = parts.take(2).map((part) => part[0]).join();
      if (initials.isNotEmpty) return initials.toUpperCase();
    }
    final email = (user.email ?? '').trim();
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return 'U';
  }

  Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E4DD)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F2D24),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildIdentityCard(User user) {
    final avatar = _avatarLabel(user);
    return _buildCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0E7B64), Color(0xFF2F5E8A)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0x33FFFFFF),
                  child: Text(
                    avatar,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name.text.trim().isEmpty
                            ? 'My Account'
                            : _name.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 13,
                        ),
                      ),
                      if (_phone.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _phone.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!accountRole.isCustomer)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4EF),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Role: ${accountRole.displayLabel}',
                      style: const TextStyle(
                        color: Color(0xFF0B6F58),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F1),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    'Member',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          foregroundColor: destructive ? const Color(0xFF8D2D2D) : null,
          side: destructive ? const BorderSide(color: Color(0xFFD7A5A5)) : null,
        ),
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildActionsCard(AuthenticationProvider auth) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: (_updatingProfile || _changingEmail)
                ? null
                : () => _editContactInfo(auth),
            icon: Icons.edit_outlined,
            label: _changingEmail
                ? 'Verifying Email...'
                : (_updatingProfile ? 'Saving...' : 'Edit Contact Info'),
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: (_updatingProfile || _changingEmail)
                ? null
                : () => _editEmailPreference(auth),
            icon: Icons.mark_email_read_outlined,
            label: 'Email Preferences (${_promoEmailOptIn ? 'On' : 'Off'})',
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrderHistoryListScreen(),
                ),
              );
            },
            icon: Icons.receipt_long,
            label: 'My Orders',
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CustomerSupportScreen(),
                ),
              );
            },
            icon: Icons.support_agent_outlined,
            label: 'Customer Support',
          ),
          if (accountRole.isAdmin || accountRole.isCashier) ...[
            const SizedBox(height: 10),
            _buildActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminDashboardScreen(),
                  ),
                );
              },
              icon: Icons.admin_panel_settings_outlined,
              label: accountRole.isCashier ? 'Cashier Panel' : 'Staff Panel',
            ),
          ],
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () => _handleLogout(auth),
            icon: Icons.logout,
            label: 'Logout',
            destructive: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthenticationProvider>();
    final user = auth.user;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useWebLayout = kIsWeb && screenWidth >= 980;
    final compactLayout = screenWidth < 420;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          'Profile',
          style: TextStyle(fontSize: compactLayout ? 22 : 28),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF1F6F4), Color(0xFFF8FBFA)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: useWebLayout ? 760 : 560),
                child: Column(
                  children: [
                    _buildIdentityCard(user),
                    const SizedBox(height: 14),
                    _buildActionsCard(auth),
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
