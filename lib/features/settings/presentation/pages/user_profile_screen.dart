import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/core/auth/profile_identity_text.dart';
import 'package:marketflow/core/location/address_text.dart';
import 'package:marketflow/core/support/support_draft_store.dart';
import 'package:marketflow/core/support/support_notification_store.dart';
import 'package:marketflow/core/support/support_notification_summary.dart';
import 'package:marketflow/core/widgets/logout_prompt_dialog.dart';
import 'package:marketflow/features/admin/presentation/pages/admin_dashboard_screen.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/auth/presentation/pages/verification_code_rules.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/checkout/presentation/pages/checkout_address_selection_screen.dart';
import 'package:marketflow/features/checkout/presentation/pages/order_history_list_screen.dart';
import 'package:marketflow/features/support/presentation/pages/customer_support_screen.dart';
import 'package:marketflow/features/wishlist/presentation/pages/wishlist_overview_screen.dart';

class _PasswordChangeRequest {
  final String currentPassword;
  final String newPassword;

  const _PasswordChangeRequest({
    required this.currentPassword,
    required this.newPassword,
  });
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const String _avatarUrlKey = 'avatar_url';
  static const String _notifyOrderUpdatesKey = 'notify_order_updates';
  static const String _notifyRestockKey = 'notify_back_in_stock';
  static const String _notifySecurityKey = 'notify_security_alerts';

  final TextEditingController _name = TextEditingController();
  final SupportDraftStore _supportDraftStore = const SupportDraftStore();
  final SupportNotificationStore _supportNotificationStore =
      const SupportNotificationStore();

  bool loading = true;
  bool _updatingProfile = false;
  bool _changingEmail = false;
  bool _changingPassword = false;
  bool _updatingNotifications = false;
  bool _updatingAvatar = false;
  bool _loadingSupportNotifications = false;
  bool _loadingSupportDraft = false;

  String _phone = '';
  String _address = '';
  String _avatarUrl = '';
  bool _promoEmailOptIn = false;
  bool _orderUpdatesEnabled = true;
  bool _restockAlertsEnabled = false;
  bool _securityAlertsEnabled = true;
  AccountRole accountRole = AccountRole.fromRaw(AccountRole.customerValue);
  CustomerSupportDraft? _supportDraft;
  SupportNotificationSummary _supportNotifications =
      const SupportNotificationSummary();

  bool get _busy =>
      _updatingProfile ||
      _changingEmail ||
      _changingPassword ||
      _updatingNotifications ||
      _updatingAvatar;

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
      _address = AddressText.deliveryAddressOrEmpty(data?.address ?? '');
      _promoEmailOptIn = data?.promoEmailOptIn ?? false;
      accountRole = AccountRole.fromRaw(data?.accountType);
      _applyUserMetadata(auth.user);
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') {
        await auth.logout();
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }

    if (mounted) {
      await _refreshSupportNotifications(auth);
      await _refreshSupportDraft(auth);
    }
  }

  OrderManagementProvider? _orderManagementProviderOrNull() {
    try {
      return context.read<OrderManagementProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _refreshSupportNotifications(AuthenticationProvider auth) async {
    final user = auth.user;
    final orderProvider = _orderManagementProviderOrNull();
    if (user == null || !accountRole.isCustomer || orderProvider == null) {
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
      final orders = await orderProvider.loadOrders();
      final seenAt = await _supportNotificationStore.loadSeenAt(
        userId: user.id,
      );
      final summary = summarizeSupportNotifications(
        orders,
        lastSeenAt: seenAt,
        maxItems: 2,
      );
      if (!mounted) return;
      setState(() => _supportNotifications = summary);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _supportNotifications = const SupportNotificationSummary(),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingSupportNotifications = false);
      }
    }
  }

  Future<void> _refreshSupportDraft(AuthenticationProvider auth) async {
    final user = auth.user;
    if (user == null || !accountRole.isCustomer) {
      if (!mounted) return;
      setState(() {
        _loadingSupportDraft = false;
        _supportDraft = null;
      });
      return;
    }

    if (mounted) {
      setState(() => _loadingSupportDraft = true);
    }

    try {
      final draft = await _supportDraftStore.loadDraft(scope: user.id);
      if (!mounted) return;
      setState(() {
        _supportDraft = draft == null || draft.message.trim().isEmpty
            ? null
            : draft;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _supportDraft = null);
    } finally {
      if (mounted) {
        setState(() => _loadingSupportDraft = false);
      }
    }
  }

  bool get _hasSupportDraft =>
      _supportDraft != null && _supportDraft!.message.trim().isNotEmpty;

  String _supportRequestTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'order':
        return 'Order issue';
      case 'payment':
        return 'Payment issue';
      case 'delivery':
        return 'Delivery issue';
      case 'refund':
        return 'Refund request';
      case 'account':
        return 'Account issue';
      default:
        return 'General question';
    }
  }

  String _supportDraftTitle() {
    final draft = _supportDraft;
    if (draft == null) return 'Draft saved';
    final followUp = draft.followUp;
    if (followUp != null && followUp.orderId > 0) {
      return 'Resume Order #${followUp.orderId} follow-up';
    }
    return 'Draft saved';
  }

  String _supportDraftDescription() {
    final draft = _supportDraft;
    if (draft == null) return '';
    final followUp = draft.followUp;
    final requestLabel = _supportRequestTypeLabel(draft.requestType);
    if (followUp != null && followUp.orderId > 0) {
      return '$requestLabel draft is saved on this device and ready to send.';
    }
    return '$requestLabel draft is saved on this device and ready to send.';
  }

  void _applyUserMetadata(User? user) {
    final metadata = Map<String, dynamic>.from(
      user?.userMetadata ?? const <String, dynamic>{},
    );
    _avatarUrl = (metadata[_avatarUrlKey] ?? '').toString().trim();
    _orderUpdatesEnabled = _readMetadataBool(
      metadata[_notifyOrderUpdatesKey],
      fallback: true,
    );
    _restockAlertsEnabled = _readMetadataBool(
      metadata[_notifyRestockKey],
      fallback: false,
    );
    _securityAlertsEnabled = _readMetadataBool(
      metadata[_notifySecurityKey],
      fallback: true,
    );
  }

  bool _readMetadataBool(Object? raw, {required bool fallback}) {
    if (raw is bool) return raw;
    final normalized = raw?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  Future<bool> _updateProfile({
    required AuthenticationProvider auth,
    required String name,
    required String phone,
    String? address,
    bool? promoEmailOptIn,
  }) async {
    if (_updatingProfile) return false;
    final nextAddress = AddressText.deliveryAddressOrEmpty(address ?? _address);
    setState(() => _updatingProfile = true);
    try {
      final refreshed = await auth.saveProfile(
        name: name.trim(),
        phone: phone.trim(),
        address: nextAddress,
        promoEmailOptIn: promoEmailOptIn,
      );

      if (!mounted) return false;
      setState(() {
        _name.text = (refreshed?.name ?? name).trim();
        _phone = (refreshed?.phone ?? phone).trim();
        _address = AddressText.deliveryAddressOrEmpty(
          refreshed?.address ?? nextAddress,
        );
        _promoEmailOptIn =
            refreshed?.promoEmailOptIn ?? promoEmailOptIn ?? _promoEmailOptIn;
        accountRole = AccountRole.fromRaw(
          refreshed?.accountType ?? accountRole.normalized,
        );
      });
      return true;
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') {
        await auth.logout();
      } else {
        _showMessage('Failed to update profile');
      }
      return false;
    } catch (_) {
      _showMessage('Failed to update profile');
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
                    'If email changes, a confirmation code is required.',
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

    _showMessage('Contact info updated');

    if (!emailChanged) return;
    await _changeEmailWithCode(auth: auth, newEmail: nextEmail);
  }

  Future<void> _manageAddress(AuthenticationProvider auth) async {
    final savedAddress = AddressText.deliveryAddressOrEmpty(_address);
    final selected = await Navigator.push<CheckoutAddressSelectionResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutAddressSelectionScreen(
          selectedAddress: savedAddress,
          historyAddresses: savedAddress.isEmpty
              ? const <String>[]
              : <String>[savedAddress],
          contactName: _name.text.trim(),
          contactPhone: _phone.trim(),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final nextAddress = AddressText.deliveryAddressOrEmpty(selected.address);
    if (nextAddress.isEmpty) {
      _showMessage('Please choose a more specific address');
      return;
    }

    final ok = await _updateProfile(
      auth: auth,
      name: _name.text.trim(),
      phone: _phone.trim(),
      address: nextAddress,
    );
    if (!mounted || !ok) return;
    _showMessage('Saved address updated');
  }

  Future<void> _updateNotificationMetadata(
    AuthenticationProvider auth, {
    required Map<String, dynamic> data,
    required void Function() onLocalSuccess,
    required String successMessage,
  }) async {
    if (_updatingNotifications) return;
    setState(() => _updatingNotifications = true);
    try {
      final updatedUser = await auth.updateUserMetadata(data: data);
      if (!mounted) return;
      setState(() {
        if (updatedUser != null) {
          _applyUserMetadata(updatedUser);
        } else {
          onLocalSuccess();
        }
      });
      _showMessage(successMessage);
    } catch (error) {
      _showMessage(_friendlyActionError(error));
    } finally {
      if (mounted) {
        setState(() => _updatingNotifications = false);
      }
    }
  }

  Future<void> _togglePromoEmail(
    AuthenticationProvider auth,
    bool nextValue,
  ) async {
    final ok = await _updateProfile(
      auth: auth,
      name: _name.text.trim(),
      phone: _phone.trim(),
      promoEmailOptIn: nextValue,
    );
    if (!mounted || !ok) return;
    _showMessage(
      nextValue ? 'Promotional emails enabled' : 'Promotional emails disabled',
    );
  }

  Future<void> _changePassword(AuthenticationProvider auth) async {
    final request = await _promptForPasswordChange();
    if (!mounted || request == null) return;

    setState(() => _changingPassword = true);
    try {
      await auth.updatePassword(
        currentPassword: request.currentPassword,
        newPassword: request.newPassword,
      );
      if (!mounted) return;
      _showMessage('Password updated');
    } catch (error) {
      _showMessage(_friendlyActionError(error));
    } finally {
      if (mounted) {
        setState(() => _changingPassword = false);
      }
    }
  }

  Future<_PasswordChangeRequest?> _promptForPasswordChange() async {
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String dialogError = '';
    bool showPasswords = false;
    final result = await showDialog<_PasswordChangeRequest>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentPasswordController,
                    obscureText: !showPasswords,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setDialogState(() => showPasswords = !showPasswords);
                        },
                        icon: Icon(
                          showPasswords
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: !showPasswords,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmController,
                    obscureText: !showPasswords,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Use at least 8 characters.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF5B6570)),
                    ),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dialogError,
                        style: const TextStyle(
                          color: Color(0xFFA7192E),
                          fontWeight: FontWeight.w600,
                        ),
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
                    final currentPassword = currentPasswordController.text
                        .trim();
                    final password = passwordController.text.trim();
                    final confirm = confirmController.text.trim();
                    if (currentPassword.isEmpty) {
                      setDialogState(
                        () => dialogError = 'Current password is required',
                      );
                      return;
                    }
                    if (password.length < 8) {
                      setDialogState(
                        () => dialogError =
                            'Password must be at least 8 characters',
                      );
                      return;
                    }
                    if (password != confirm) {
                      setDialogState(
                        () => dialogError = 'Passwords do not match',
                      );
                      return;
                    }
                    if (currentPassword == password) {
                      setDialogState(
                        () => dialogError =
                            'Choose a new password different from the current one',
                      );
                      return;
                    }
                    Navigator.pop(
                      dialogContext,
                      _PasswordChangeRequest(
                        currentPassword: currentPassword,
                        newPassword: password,
                      ),
                    );
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
    currentPasswordController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    return result;
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
                    'Enter the confirmation code sent to $email',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B6570),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: verificationCodeMaxLength,
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
                    if (!isValidVerificationCode(code)) {
                      setDialogState(
                        () => dialogError = 'Enter a valid confirmation code',
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
      _showMessage(_friendlyActionError(error));
      return;
    } finally {
      if (mounted) {
        setState(() => _changingEmail = false);
      }
    }

    if (!mounted) return;
    _showMessage('Verification code sent to $targetEmail');

    final code = await _promptForVerificationCode(email: targetEmail);
    if (!mounted || code == null) return;

    setState(() => _changingEmail = true);
    try {
      await auth.confirmEmailChange(newEmail: targetEmail, code: code);
      if (!mounted) return;
      _showMessage('Email updated');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_friendlyActionError(error));
    } finally {
      if (mounted) {
        setState(() => _changingEmail = false);
      }
    }
  }

  Future<void> _showAvatarActions(AuthenticationProvider auth) async {
    if (_updatingAvatar) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_back_outlined),
                title: Text(
                  _avatarUrl.isEmpty ? 'Upload profile photo' : 'Change photo',
                ),
                onTap: () => Navigator.pop(sheetContext, 'upload'),
              ),
              if (_avatarUrl.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove photo'),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'upload') {
      await _pickAndUploadProfilePhoto(auth);
    } else if (action == 'remove') {
      await _removeProfilePhoto(auth);
    }
  }

  Future<void> _pickAndUploadProfilePhoto(AuthenticationProvider auth) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showMessage('Could not read selected image');
      return;
    }
    if (bytes.length > 8 * 1024 * 1024) {
      _showMessage('Image must be 8MB or smaller');
      return;
    }

    setState(() => _updatingAvatar = true);
    try {
      final imageUrl = await auth.uploadProfileAvatar(
        bytes: bytes,
        fileName: file.name,
      );
      final updatedUser = await auth.updateUserMetadata(
        data: <String, dynamic>{_avatarUrlKey: imageUrl},
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = imageUrl;
        _applyUserMetadata(updatedUser ?? auth.user);
      });
      _showMessage('Profile photo updated');
    } catch (error) {
      _showMessage(_friendlyActionError(error));
    } finally {
      if (mounted) {
        setState(() => _updatingAvatar = false);
      }
    }
  }

  Future<void> _removeProfilePhoto(AuthenticationProvider auth) async {
    setState(() => _updatingAvatar = true);
    try {
      final updatedUser = await auth.updateUserMetadata(
        data: const <String, dynamic>{_avatarUrlKey: null},
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = '';
        _applyUserMetadata(updatedUser ?? auth.user);
      });
      _showMessage('Profile photo removed');
    } catch (error) {
      _showMessage(_friendlyActionError(error));
    } finally {
      if (mounted) {
        setState(() => _updatingAvatar = false);
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
      _showMessage('Logout failed: $error');
    }
  }

  String _friendlyActionError(Object error) {
    final raw = error.toString().trim();
    final normalized = raw.replaceFirst('Exception: ', '').trim();
    final lower = normalized.toLowerCase();
    if (lower.contains('already') && lower.contains('registered')) {
      return 'This email is already in use.';
    }
    if (lower.contains('same') && lower.contains('email')) {
      return 'Use a different email address.';
    }
    if (lower.contains('invalid login credentials')) {
      return 'Current password is incorrect.';
    }
    if (lower.contains('reauthentication') && lower.contains('valid')) {
      return 'Please confirm your current password and try again.';
    }
    if (lower.contains('token') &&
        (lower.contains('invalid') || lower.contains('otp'))) {
      return 'Invalid confirmation code.';
    }
    if (lower.contains('expired')) {
      return 'Confirmation code expired. Please request a new one.';
    }
    if (normalized.isNotEmpty && normalized.length <= 160) {
      return normalized;
    }
    return 'Something went wrong. Please try again.';
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  String _displayName(User user) {
    return ProfileIdentityText.displayName(
      explicitName: _name.text,
      userMetadata: Map<String, dynamic>.from(
        user.userMetadata ?? const <String, dynamic>{},
      ),
      email: user.email ?? '',
    );
  }

  String _profileEyebrow() {
    if (!accountRole.isCustomer) {
      return '${accountRole.displayLabel} account';
    }
    return 'Personal profile';
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

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14211C),
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF5B6570),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildIdentityCard(User user, AuthenticationProvider auth) {
    final avatar = _avatarLabel(user);
    final emailVerified = user.emailConfirmedAt != null;
    final displayName = _displayName(user);

    return _buildCard(
      padding: EdgeInsets.zero,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: () => _showAvatarActions(auth),
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: const Color(0x33FFFFFF),
                        backgroundImage: _avatarUrl.isNotEmpty
                            ? NetworkImage(_avatarUrl)
                            : null,
                        child: _avatarUrl.isEmpty
                            ? Text(
                                avatar,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: GestureDetector(
                        onTap: () => _showAvatarActions(auth),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE4ECE8)),
                          ),
                          child: _updatingAvatar
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: Color(0xFF0B6F58),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _profileEyebrow(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _updatingAvatar
                            ? null
                            : () => _showAvatarActions(auth),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.photo_camera_outlined, size: 16),
                        label: Text(
                          _avatarUrl.isEmpty
                              ? 'Add profile photo'
                              : 'Update profile photo',
                        ),
                      ),
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
                _buildStatusChip(
                  icon: emailVerified
                      ? Icons.verified_user_outlined
                      : Icons.report_gmailerrorred_outlined,
                  label: emailVerified
                      ? 'Email verified'
                      : 'Email needs attention',
                  background: emailVerified
                      ? const Color(0xFFE8F4EF)
                      : const Color(0xFFFFF0E8),
                  foreground: emailVerified
                      ? const Color(0xFF0B6F58)
                      : const Color(0xFFB85A00),
                ),
                if (!accountRole.isCustomer)
                  _buildStatusChip(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Role: ${accountRole.displayLabel}',
                    background: const Color(0xFFE8F4EF),
                    foreground: const Color(0xFF0B6F58),
                  ),
                _buildStatusChip(
                  icon: Icons.loyalty_outlined,
                  label: 'Member',
                  background: const Color(0xFFF0F3F1),
                  foreground: const Color(0xFF4F5D57),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSnapshotCard(User user, AuthenticationProvider auth) {
    final completionPercent = _profileCompletionPercent(user);
    final completionFraction = completionPercent / 100;
    final checklist = _profileCompletionChecklist(user);
    final hasAddress = AddressText.deliveryAddressOrEmpty(_address).isNotEmpty;
    final emailVerified = user.emailConfirmedAt != null;
    final unreadSupport = _supportNotifications.unreadCount;
    final supportLabel = _hasSupportDraft
        ? 'Draft saved'
        : unreadSupport > 0
        ? '$unreadSupport update${unreadSupport == 1 ? '' : 's'}'
        : _supportNotifications.hasActiveRequests
        ? '${_supportNotifications.activeRequestCount} open'
        : 'Caught up';

    return _buildSectionCard(
      title: 'Account Snapshot',
      subtitle:
          'See what is ready for checkout and what still needs attention.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEAF6F2), Color(0xFFF1F6FB)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD7E6DF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profile completion',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF597069),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$completionPercent%',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF12352E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildInlineBadge(
                      label: completionPercent >= 100
                          ? 'Ready'
                          : checklist.length == 1
                          ? '1 step left'
                          : '${checklist.length} steps left',
                      background: completionPercent >= 100
                          ? const Color(0xFFE8F4EF)
                          : const Color(0xFFFFF0E8),
                      foreground: completionPercent >= 100
                          ? const Color(0xFF0B6F58)
                          : const Color(0xFFB85A00),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: completionFraction.clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: const Color(0xFFD9E8E2),
                    color: const Color(0xFF0D8B6F),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  completionPercent >= 100
                      ? 'Your account is ready for smoother checkout, support, and order tracking.'
                      : 'Finish the remaining details so checkout, delivery, and support stay friction-free.',
                  style: const TextStyle(
                    color: Color(0xFF4D5F59),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SnapshotMetricTile(
                label: 'Address',
                value: hasAddress ? 'Ready' : 'Needed',
                icon: hasAddress
                    ? Icons.location_on_outlined
                    : Icons.location_off_outlined,
              ),
              _SnapshotMetricTile(
                label: 'Email',
                value: emailVerified ? 'Verified' : 'Pending',
                icon: emailVerified
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              _SnapshotMetricTile(
                label: 'Support',
                value: supportLabel,
                icon: _hasSupportDraft
                    ? Icons.edit_note_outlined
                    : Icons.support_agent_outlined,
              ),
              _SnapshotMetricTile(
                label: 'Membership',
                value: _memberSinceLabel(user),
                icon: Icons.workspace_premium_outlined,
              ),
            ],
          ),
          if (checklist.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Next best steps',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5D6E67),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: checklist.map((item) {
                return _buildInlineBadge(
                  label: item,
                  background: const Color(0xFFF7F4EA),
                  foreground: const Color(0xFF7A5A1C),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _handleSnapshotPrimaryAction(auth, user),
                icon: Icon(_snapshotPrimaryActionIcon(user)),
                label: Text(_snapshotPrimaryActionLabel(user)),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _openOrders(auth, initialOrderId: _primarySupportOrderId()),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Review orders'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(AuthenticationProvider auth) {
    final savedAddress = AddressText.deliveryAddressOrEmpty(_address);
    final hasAddress = savedAddress.isNotEmpty;
    return _buildSectionCard(
      title: 'Saved Address',
      subtitle: 'Keep one primary delivery address ready for checkout.',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAF9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD8E4DD)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4EF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    color: Color(0xFF0B6F58),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasAddress
                            ? 'Default delivery address'
                            : 'No delivery address yet',
                        style: const TextStyle(
                          color: Color(0xFF14211C),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasAddress
                            ? savedAddress
                            : 'No delivery address saved yet.',
                        style: TextStyle(
                          color: hasAddress
                              ? const Color(0xFF1F2A24)
                              : const Color(0xFF5B6570),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Use the map, current location, or recent addresses to update it.',
                        style: TextStyle(
                          color: Color(0xFF5B6570),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _manageAddress(auth),
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(hasAddress ? 'Manage Address' : 'Add Address'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(AuthenticationProvider auth, User user) {
    final emailVerified = user.emailConfirmedAt != null;
    return _buildSectionCard(
      title: 'Security',
      subtitle: 'Review the essentials that keep your account secure.',
      child: Column(
        children: [
          _buildInfoRow(
            icon: emailVerified
                ? Icons.mark_email_read_outlined
                : Icons.mark_email_unread_outlined,
            title: 'Email verification',
            description: emailVerified
                ? 'Your email is confirmed and ready for secure sign-in.'
                : 'This account still needs email confirmation.',
            trailing: _buildInlineBadge(
              label: emailVerified ? 'Verified' : 'Pending',
              background: emailVerified
                  ? const Color(0xFFE8F4EF)
                  : const Color(0xFFFFF0E8),
              foreground: emailVerified
                  ? const Color(0xFF0B6F58)
                  : const Color(0xFFB85A00),
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.password_outlined,
            title: 'Password',
            description:
                'Change your password any time to keep sign-in protected.',
            trailingBelow: true,
            trailing: OutlinedButton.icon(
              onPressed: _changingPassword ? null : () => _changePassword(auth),
              icon: _changingPassword
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_reset_outlined),
              label: Text(
                _changingPassword ? 'Updating...' : 'Change Password',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard(AuthenticationProvider auth) {
    return _buildSectionCard(
      title: 'Notifications',
      subtitle: 'Control store, order, and security updates in one place.',
      child: Column(
        children: [
          if (_updatingNotifications)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          _buildSwitchTile(
            title: 'Promotional emails',
            subtitle: 'Receive offers, drops, and seasonal campaigns.',
            value: _promoEmailOptIn,
            enabled: !_busy,
            onChanged: (value) => _togglePromoEmail(auth, value),
          ),
          const Divider(height: 22),
          _buildSwitchTile(
            title: 'Order updates',
            subtitle: 'Get delivery, payment, and order status updates.',
            value: _orderUpdatesEnabled,
            enabled: !_busy,
            onChanged: (value) {
              _updateNotificationMetadata(
                auth,
                data: <String, dynamic>{_notifyOrderUpdatesKey: value},
                onLocalSuccess: () => _orderUpdatesEnabled = value,
                successMessage: value
                    ? 'Order updates enabled'
                    : 'Order updates disabled',
              );
            },
          ),
          const Divider(height: 22),
          _buildSwitchTile(
            title: 'Restock alerts',
            subtitle: 'Know when wishlist items come back in stock.',
            value: _restockAlertsEnabled,
            enabled: !_busy,
            onChanged: (value) {
              _updateNotificationMetadata(
                auth,
                data: <String, dynamic>{_notifyRestockKey: value},
                onLocalSuccess: () => _restockAlertsEnabled = value,
                successMessage: value
                    ? 'Restock alerts enabled'
                    : 'Restock alerts disabled',
              );
            },
          ),
          const Divider(height: 22),
          _buildSwitchTile(
            title: 'Security alerts',
            subtitle: 'Receive important account and verification notices.',
            value: _securityAlertsEnabled,
            enabled: !_busy,
            onChanged: (value) {
              _updateNotificationMetadata(
                auth,
                data: <String, dynamic>{_notifySecurityKey: value},
                onLocalSuccess: () => _securityAlertsEnabled = value,
                successMessage: value
                    ? 'Security alerts enabled'
                    : 'Security alerts disabled',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String description,
    required Widget trailing,
    bool trailingBelow = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E4DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0B6F58)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2A24),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF5B6570),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (!trailingBelow) ...[const SizedBox(width: 12), trailing],
            ],
          ),
          if (trailingBelow) ...[
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.only(left: 50), child: trailing),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineBadge({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  int _profileCompletionPercent(User user) {
    final checkpoints = <bool>[
      _displayName(user).trim().isNotEmpty,
      _phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 8,
      AddressText.deliveryAddressOrEmpty(_address).isNotEmpty,
      user.emailConfirmedAt != null,
      _avatarUrl.trim().isNotEmpty,
    ];
    final completed = checkpoints.where((value) => value).length;
    return ((completed / checkpoints.length) * 100).round();
  }

  List<String> _profileCompletionChecklist(User user) {
    final items = <String>[];
    if (_displayName(user).trim().isEmpty) {
      items.add('Add your full name');
    }
    if (_phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      items.add('Add a valid phone number');
    }
    if (AddressText.deliveryAddressOrEmpty(_address).isEmpty) {
      items.add('Save a delivery address');
    }
    if (user.emailConfirmedAt == null) {
      items.add('Verify your email');
    }
    if (_avatarUrl.trim().isEmpty) {
      items.add('Upload a profile photo');
    }
    return items;
  }

  String _memberSinceLabel(User user) {
    final parsed = DateTime.tryParse(user.createdAt);
    if (parsed == null) {
      return 'Active';
    }
    const monthLabels = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthLabels[parsed.month - 1]} ${parsed.year}';
  }

  String _snapshotPrimaryActionLabel(User user) {
    if (AddressText.deliveryAddressOrEmpty(_address).isEmpty) {
      return 'Add address';
    }
    if (_displayName(user).trim().isEmpty ||
        _phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      return 'Update details';
    }
    if (user.emailConfirmedAt == null) {
      return 'Review security';
    }
    if (_avatarUrl.trim().isEmpty) {
      return 'Add photo';
    }
    if (_hasSupportDraft || _supportNotifications.hasUnread) {
      return 'Review support';
    }
    return 'Manage profile';
  }

  IconData _snapshotPrimaryActionIcon(User user) {
    if (AddressText.deliveryAddressOrEmpty(_address).isEmpty) {
      return Icons.add_location_alt_outlined;
    }
    if (_displayName(user).trim().isEmpty ||
        _phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      return Icons.edit_outlined;
    }
    if (user.emailConfirmedAt == null) {
      return Icons.security_outlined;
    }
    if (_avatarUrl.trim().isEmpty) {
      return Icons.photo_camera_outlined;
    }
    if (_hasSupportDraft || _supportNotifications.hasUnread) {
      return Icons.support_agent_outlined;
    }
    return Icons.person_outline;
  }

  Future<void> _handleSnapshotPrimaryAction(
    AuthenticationProvider auth,
    User user,
  ) async {
    if (AddressText.deliveryAddressOrEmpty(_address).isEmpty) {
      await _manageAddress(auth);
      return;
    }
    if (_displayName(user).trim().isEmpty ||
        _phone.replaceAll(RegExp(r'[^0-9]'), '').length < 8) {
      await _editContactInfo(auth);
      return;
    }
    if (user.emailConfirmedAt == null) {
      await _changePassword(auth);
      return;
    }
    if (_avatarUrl.trim().isEmpty) {
      await _showAvatarActions(auth);
      return;
    }
    if (_hasSupportDraft || _supportNotifications.hasUnread) {
      await _openCustomerSupport(auth);
      return;
    }
    await _editContactInfo(auth);
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF5B6570), height: 1.4),
      ),
    );
  }

  Future<void> _openOrders(
    AuthenticationProvider auth, {
    int? initialOrderId,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderHistoryListScreen(initialOrderId: initialOrderId),
      ),
    );
    if (!mounted) return;
    await _refreshSupportNotifications(auth);
  }

  Future<void> _openCustomerSupport(AuthenticationProvider auth) async {
    final latestSupportItem =
        !_hasSupportDraft && _supportNotifications.items.isNotEmpty
        ? _supportNotifications.items.first
        : null;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSupportScreen(
          initialFollowUpOrderId: latestSupportItem?.orderId,
          initialFollowUpStatus: latestSupportItem?.status,
          initialFollowUpRequestType: latestSupportItem?.requestType,
          initialFollowUpSupportNote: latestSupportItem?.supportNote,
          initialFollowUpActivityAt: latestSupportItem?.activityAt
              .toUtc()
              .toIso8601String(),
          initialFollowUpSharedAddress: latestSupportItem?.sharedAddress,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshSupportNotifications(auth);
    await _refreshSupportDraft(auth);
  }

  Future<void> _clearSupportDraft(AuthenticationProvider auth) async {
    final user = auth.user;
    if (user == null || !_hasSupportDraft) return;

    try {
      await _supportDraftStore.clearDraft(scope: user.id);
      if (!mounted) return;
      setState(() => _supportDraft = null);
      _showMessage('Saved support draft cleared');
    } catch (_) {
      _showMessage('Could not clear saved draft');
    }
  }

  String _supportStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'address_applied':
        return 'Address applied';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Pending';
    }
  }

  String _supportStatusSummary(String status) {
    switch (status.trim().toLowerCase()) {
      case 'address_applied':
        return 'Support updated the delivery address and left a fresh note.';
      case 'resolved':
        return 'Support finished the latest request and shared a final reply.';
      default:
        return 'Support still has an open request tied to one of your orders.';
    }
  }

  String _supportActivityDateLabel(DateTime activityAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = activityAt.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  int? _primarySupportOrderId() {
    final summary = _supportNotifications;
    if (summary.items.isNotEmpty) {
      return summary.items.first.orderId;
    }
    final followUpOrderId = _supportDraft?.followUp?.orderId ?? 0;
    if (followUpOrderId > 0) {
      return followUpOrderId;
    }
    return null;
  }

  String _primarySupportStatus() {
    final summary = _supportNotifications;
    if (summary.items.isNotEmpty) {
      return summary.items.first.status.trim().toLowerCase();
    }
    return (_supportDraft?.followUp?.status ?? '').trim().toLowerCase();
  }

  String _supportActionLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'resolved':
        return 'Reopen in Support';
      case 'address_applied':
        return 'Send another update';
      default:
        return 'Reply in Support';
    }
  }

  String _supportActionDescription(String status, int orderId) {
    switch (status.trim().toLowerCase()) {
      case 'resolved':
        return 'Reopen Order #$orderId in Support';
      case 'address_applied':
        return 'Update Order #$orderId in Support';
      default:
        return 'Reply about Order #$orderId';
    }
  }

  Widget _buildSupportUpdatesCard(AuthenticationProvider auth) {
    final summary = _supportNotifications;
    final primarySupportOrderId = _primarySupportOrderId();
    final primarySupportStatus = _primarySupportStatus();
    final shouldShowCard =
        summary.hasItems ||
        summary.hasActiveRequests ||
        _hasSupportDraft ||
        _loadingSupportNotifications ||
        _loadingSupportDraft;
    if (!accountRole.isCustomer || !shouldShowCard) {
      return const SizedBox.shrink();
    }

    return _buildSectionCard(
      title: 'Support Updates',
      subtitle:
          'Keep up with replies and recovery steps on your latest orders.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingSupportNotifications)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_loadingSupportDraft)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInlineBadge(
                label: summary.hasUnread
                    ? '${summary.unreadCount} unread'
                    : 'Caught up',
                background: summary.hasUnread
                    ? const Color(0xFFFFF0E8)
                    : const Color(0xFFE8F4EF),
                foreground: summary.hasUnread
                    ? const Color(0xFFB85A00)
                    : const Color(0xFF0B6F58),
              ),
              if (summary.hasActiveRequests)
                _buildInlineBadge(
                  label:
                      '${summary.activeRequestCount} open request${summary.activeRequestCount == 1 ? '' : 's'}',
                  background: const Color(0xFFEAF4FF),
                  foreground: const Color(0xFF1E5E9A),
                ),
              if (_hasSupportDraft)
                _buildInlineBadge(
                  label: 'Draft saved',
                  background: const Color(0xFFFFF5E8),
                  foreground: const Color(0xFFB85A00),
                ),
            ],
          ),
          if (_hasSupportDraft) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8D9B0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _supportDraftTitle(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2A2417),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _supportDraftDescription(),
                    style: const TextStyle(
                      color: Color(0xFF5B6570),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openCustomerSupport(auth),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Resume draft'),
                      ),
                      TextButton(
                        key: const ValueKey<String>(
                          'clear_profile_support_draft',
                        ),
                        onPressed: () => _clearSupportDraft(auth),
                        child: const Text('Clear draft'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (summary.items.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _hasSupportDraft
                  ? 'You still have a saved support draft on this device. Open support to finish or clear it.'
                  : 'Your latest support request is still open. We will surface fresh replies here as soon as support responds.',
              style: const TextStyle(color: Color(0xFF5B6570), height: 1.45),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...summary.items.map((item) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: item.isResolved
                      ? const Color(0xFFF4FBF7)
                      : const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: item.isResolved
                        ? const Color(0xFFCEE8D6)
                        : const Color(0xFFD8E4DD),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Order #${item.orderId}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF14211C),
                          ),
                        ),
                        _buildInlineBadge(
                          label: _supportStatusLabel(item.status),
                          background: item.isResolved
                              ? const Color(0xFFE8F4EF)
                              : const Color(0xFFEAF4FF),
                          foreground: item.isResolved
                              ? const Color(0xFF0B6F58)
                              : const Color(0xFF1E5E9A),
                        ),
                        Text(
                          _supportActivityDateLabel(item.activityAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5B6570),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.supportNote.isNotEmpty
                          ? item.supportNote
                          : _supportStatusSummary(item.status),
                      style: const TextStyle(
                        color: Color(0xFF1F2A24),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    _openOrders(auth, initialOrderId: primarySupportOrderId),
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(
                  primarySupportOrderId == null
                      ? 'Review in My Orders'
                      : 'View Order #$primarySupportOrderId',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openCustomerSupport(auth),
                icon: const Icon(Icons.support_agent_outlined),
                label: Text(
                  _hasSupportDraft
                      ? 'Resume draft'
                      : summary.items.isNotEmpty
                      ? _supportActionLabel(primarySupportStatus)
                      : 'Open Support',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? description,
    String? badgeLabel,
    Color? badgeBackground,
    Color? badgeForeground,
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
        label: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (description != null && description.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B6570),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badgeLabel != null && badgeLabel.trim().isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBackground ?? const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: badgeForeground ?? const Color(0xFF1E5E9A),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(AuthenticationProvider auth) {
    final unreadSupportCount = _supportNotifications.unreadCount;
    final activeSupportRequestCount = _supportNotifications.activeRequestCount;
    final primarySupportOrderId = _primarySupportOrderId();
    final primarySupportStatus = _primarySupportStatus();
    final highlightedOrderId = unreadSupportCount > 0
        ? primarySupportOrderId
        : null;
    final supportDescriptionPieces = <String>[
      if (_hasSupportDraft) _supportDraftTitle(),
      if (!_hasSupportDraft && primarySupportOrderId != null)
        _supportActionDescription(primarySupportStatus, primarySupportOrderId),
      if (!_hasSupportDraft && unreadSupportCount > 0)
        '$unreadSupportCount unread update${unreadSupportCount == 1 ? '' : 's'}',
      if (activeSupportRequestCount > 0)
        '$activeSupportRequestCount active request${activeSupportRequestCount == 1 ? '' : 's'}',
    ];
    final supportDescriptionParts = supportDescriptionPieces.isEmpty
        ? const <String>[]
        : <String>[supportDescriptionPieces.join(' - ')];

    return _buildSectionCard(
      title: 'Quick Actions',
      subtitle: 'Manage your details, favorites, and order history quickly.',
      child: Column(
        children: [
          _buildActionButton(
            onPressed: _busy ? null : () => _editContactInfo(auth),
            icon: Icons.edit_outlined,
            label: _changingEmail
                ? 'Verifying Email...'
                : (_updatingProfile ? 'Saving...' : 'Edit Contact Info'),
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WishlistOverviewScreen(),
                ),
              );
            },
            icon: Icons.favorite_border,
            label: 'My Wishlist',
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () {
              _openOrders(auth, initialOrderId: highlightedOrderId);
            },
            icon: Icons.receipt_long,
            label: 'My Orders',
            description: unreadSupportCount > 0
                ? primarySupportOrderId != null && unreadSupportCount == 1
                      ? '1 new support update on Order #$primarySupportOrderId'
                      : '$unreadSupportCount new support update${unreadSupportCount == 1 ? '' : 's'}'
                : null,
            badgeLabel: unreadSupportCount > 0 ? '$unreadSupportCount' : null,
            badgeBackground: const Color(0xFFFFF0E8),
            badgeForeground: const Color(0xFFB85A00),
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            onPressed: () {
              _openCustomerSupport(auth);
            },
            icon: Icons.support_agent_outlined,
            label: _hasSupportDraft
                ? 'Resume Support Draft'
                : primarySupportOrderId != null
                ? _supportActionLabel(primarySupportStatus)
                : 'Customer Support',
            description: supportDescriptionParts.isEmpty
                ? null
                : supportDescriptionParts.join(' • '),
            badgeLabel: _hasSupportDraft
                ? 'Draft'
                : unreadSupportCount > 0
                ? '$unreadSupportCount'
                : activeSupportRequestCount > 0
                ? '$activeSupportRequestCount'
                : null,
            badgeBackground: _hasSupportDraft
                ? const Color(0xFFFFF5E8)
                : unreadSupportCount > 0
                ? const Color(0xFFFFF0E8)
                : const Color(0xFFEAF4FF),
            badgeForeground: _hasSupportDraft
                ? const Color(0xFFB85A00)
                : unreadSupportCount > 0
                ? const Color(0xFFB85A00)
                : const Color(0xFF1E5E9A),
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
    final showSupportSection =
        accountRole.isCustomer &&
        (_supportNotifications.hasItems ||
            _supportNotifications.hasActiveRequests ||
            _loadingSupportNotifications ||
            _hasSupportDraft ||
            _loadingSupportDraft);

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
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
                constraints: BoxConstraints(
                  maxWidth: useWebLayout ? 1180 : 560,
                ),
                child: useWebLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              children: [
                                _buildIdentityCard(user, auth),
                                const SizedBox(height: 14),
                                _buildAccountSnapshotCard(user, auth),
                                const SizedBox(height: 14),
                                _buildAddressCard(auth),
                                if (showSupportSection) ...[
                                  const SizedBox(height: 14),
                                  _buildSupportUpdatesCard(auth),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _buildSecurityCard(auth, user),
                                const SizedBox(height: 14),
                                _buildNotificationsCard(auth),
                                const SizedBox(height: 14),
                                _buildActionsCard(auth),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildIdentityCard(user, auth),
                          const SizedBox(height: 14),
                          _buildAccountSnapshotCard(user, auth),
                          const SizedBox(height: 14),
                          _buildAddressCard(auth),
                          const SizedBox(height: 14),
                          _buildSecurityCard(auth, user),
                          const SizedBox(height: 14),
                          _buildNotificationsCard(auth),
                          if (showSupportSection) ...[
                            const SizedBox(height: 14),
                            _buildSupportUpdatesCard(auth),
                          ],
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

class _SnapshotMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SnapshotMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 132),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAF9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8E4DD)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F4EF),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF0B6F58)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5D6E67),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15211D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
