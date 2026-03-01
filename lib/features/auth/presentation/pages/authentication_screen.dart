import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/support/presentation/pages/legal_documents_screen.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/core/widgets/app_brand_logo.dart';

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key});

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();

  bool isLogin = true;
  bool loading = false;
  bool resendingVerification = false;
  bool verifyingCode = false;
  bool obscure = true;
  bool promoEmailOptIn = false;
  String error = '';

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  String? _validateInput() {
    final emailText = email.text.trim();
    final passText = pass.text.trim();

    if (emailText.isEmpty) return 'Email is required';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(emailText)) return 'Enter a valid email';

    if (passText.isEmpty) return 'Password is required';
    if (passText.length < 6) return 'Password must be at least 6 characters';

    if (!isLogin) {
      final nameText = fullName.text.trim();
      final phoneText = phone.text.trim();
      final phoneDigits = phoneText.replaceAll(RegExp(r'[^0-9]'), '');

      if (nameText.isEmpty) return 'Full name is required';
      if (phoneText.isEmpty) return 'Phone number is required';
      if (phoneDigits.length < 8) return 'Enter a valid phone number';
    }

    return null;
  }

  String _friendlyAuthError(Object error) {
    final raw = error.toString().trim();
    final normalized = raw.replaceFirst('Exception: ', '').trim();
    final lower = normalized.toLowerCase();

    if (lower.contains('invalid login credentials')) {
      return 'Invalid email or password.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please verify using the 6-digit code sent to your email.';
    }
    if (lower.contains('already registered') ||
        lower.contains('user already exists')) {
      return 'This email is already registered. Please sign in.';
    }
    if (lower.contains('too many requests') || lower.contains('rate limit')) {
      return 'Too many attempts. Please wait and try again.';
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup')) {
      return 'Network error. Check your internet connection and try again.';
    }
    if (lower.contains('password') && lower.contains('at least')) {
      return 'Password must be at least 6 characters.';
    }
    if ((lower.contains('invalid') || lower.contains('expired')) &&
        (lower.contains('otp') ||
            lower.contains('code') ||
            lower.contains('token'))) {
      return 'Invalid or expired 6-digit verification code.';
    }
    if (normalized.isNotEmpty && normalized.length <= 120) {
      return normalized;
    }
    return 'Something went wrong. Please try again.';
  }

  String? _validateEmailOnly() {
    final emailText = email.text.trim();
    if (emailText.isEmpty) return 'Email is required';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(emailText)) return 'Enter a valid email';
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validateInput();
    if (validationError != null) {
      setState(() => error = validationError);
      return;
    }

    setState(() {
      loading = true;
      error = '';
    });

    final auth = context.read<AuthenticationProvider>();
    try {
      if (isLogin) {
        await auth.login(email.text.trim(), pass.text.trim());
      } else {
        await auth.register(
          email: email.text.trim(),
          password: pass.text.trim(),
          name: fullName.text.trim(),
          phone: phone.text.trim(),
          promoEmailOptIn: promoEmailOptIn,
        );
        if (!mounted) return;
        if (auth.user == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A 6-digit verification code was sent to your email.',
              ),
            ),
          );
          setState(() => isLogin = true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _friendlyAuthError(e));
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _resendVerification() async {
    final emailError = _validateEmailOnly();
    if (emailError != null) {
      setState(() => error = emailError);
      return;
    }

    setState(() {
      resendingVerification = true;
      error = '';
    });

    final auth = context.read<AuthenticationProvider>();
    try {
      await auth.resendSignupVerification(email: email.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '6-digit verification code sent. Check inbox and spam folder.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyAuthError(e);
      setState(() => error = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => resendingVerification = false);
      }
    }
  }

  Future<String?> _promptForVerificationCode() async {
    final controller = TextEditingController();
    String dialogError = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter the 6-digit code sent to your email.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  if (dialogError.isNotEmpty) ...[
                    const SizedBox(height: 8),
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
                    final code = controller.text.trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                      setDialogState(
                        () => dialogError = 'Enter a valid 6-digit code',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, code);
                  },
                  child: const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _verifySignupCode() async {
    final emailError = _validateEmailOnly();
    if (emailError != null) {
      setState(() => error = emailError);
      return;
    }
    final code = await _promptForVerificationCode();
    if (!mounted || code == null) return;

    setState(() {
      verifyingCode = true;
      error = '';
    });

    final auth = context.read<AuthenticationProvider>();
    try {
      await auth.verifySignupCode(email: email.text.trim(), code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = _friendlyAuthError(e);
      setState(() => error = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => verifyingCode = false);
      }
    }
  }

  Future<void> _openLegal(LegalDocumentType type) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LegalDocumentsScreen(type: type)));
  }

  Widget _buildAuthCard(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0E5E5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandLogo(size: 46),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F5F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    text: 'Sign In',
                    active: isLogin,
                    onTap: () => setState(() => isLogin = true),
                  ),
                ),
                Expanded(
                  child: _ModeChip(
                    text: 'Create Account',
                    active: !isLogin,
                    onTap: () => setState(() => isLogin = false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!isLogin) ...[
            TextField(
              controller: fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => obscure = !obscure);
                },
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          if (!isLogin) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: promoEmailOptIn,
              onChanged: (value) {
                setState(() => promoEmailOptIn = value == true);
              },
              title: const Text(
                'Send me promotional emails',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
          if (error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDEBEC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFA7192E)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: colors.primary),
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isLogin ? 'Sign In' : 'Create Account'),
            ),
          ),
          if (isLogin) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 0,
              children: [
                TextButton(
                  onPressed: verifyingCode ? null : _verifySignupCode,
                  child: verifyingCode
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify 6-digit code'),
                ),
                TextButton(
                  onPressed: resendingVerification ? null : _resendVerification,
                  child: resendingVerification
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Resend code'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'By continuing you agree to our ',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                InkWell(
                  onTap: () => _openLegal(LegalDocumentType.terms),
                  child: const Text(
                    'Terms',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  ' and ',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                InkWell(
                  onTap: () => _openLegal(LegalDocumentType.privacy),
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                Text(
                  '.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebIntroPanel() {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A7E68), Color(0xFF0C6178)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0C4A44),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MarketFlow',
            style: TextStyle(
              fontSize: 36,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Web storefront and staff operations in one place.',
            style: TextStyle(
              fontSize: 17,
              height: 1.35,
              color: Color(0xFFD8F4EC),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          const _WebFeatureTile(
            icon: Icons.inventory_2_outlined,
            title: 'Catalog and stock ready',
            subtitle:
                'Manage products, categories, and variants with live sync.',
          ),
          const SizedBox(height: 12),
          const _WebFeatureTile(
            icon: Icons.payments_outlined,
            title: 'Payments and cashier flow',
            subtitle: 'Track COD confirmations, ABA PayWay, and promo codes.',
          ),
          const SizedBox(height: 12),
          const _WebFeatureTile(
            icon: Icons.local_shipping_outlined,
            title: 'Delivery tracking',
            subtitle: 'Rider updates and real-time customer order visibility.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final useDesktopLayout = kIsWeb && size.width >= 980;

    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundDecor(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(useDesktopLayout ? 24 : 18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: useDesktopLayout ? 1120 : 430,
                  ),
                  child: useDesktopLayout
                      ? SizedBox(
                          height: 660,
                          child: Row(
                            children: [
                              Expanded(child: _buildWebIntroPanel()),
                              const SizedBox(width: 22),
                              SizedBox(
                                width: 440,
                                child: _buildAuthCard(colors),
                              ),
                            ],
                          ),
                        )
                      : _buildAuthCard(colors),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _WebFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFE4FCF4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xCBE9F8F4), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;

  const _ModeChip({
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF0B7D69) : const Color(0xFF56636D),
          ),
        ),
      ),
    );
  }
}

class _BackgroundDecor extends StatelessWidget {
  const _BackgroundDecor();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF6F4), Color(0xFFF6F4EE)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -40,
            child: _Blob(color: const Color(0xFF8AD8C2), size: 240),
          ),
          Positioned(
            bottom: -120,
            left: -70,
            child: _Blob(color: const Color(0xFFF0CBA9), size: 280),
          ),
          Positioned(
            top: 140,
            left: -80,
            child: _Blob(color: const Color(0xFFDBECFF), size: 200),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(size * 0.45),
      ),
    );
  }
}
