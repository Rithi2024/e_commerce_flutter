import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/features/support/presentation/pages/legal_documents_screen.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/auth/presentation/pages/auth_error_message.dart';
import 'package:marketflow/features/auth/presentation/pages/signup_verification_screen.dart';
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
  bool obscure = true;
  bool promoEmailOptIn = false;
  String error = '';

  void _setAuthMode(bool loginMode) {
    if (isLogin == loginMode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      isLogin = loginMode;
      error = '';
    });
  }

  void _dismissKeyboard() {
    final focus = FocusScope.of(context);
    if (!focus.hasPrimaryFocus) {
      focus.unfocus();
    }
  }

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  String _localPhoneDigits() {
    return phone.text.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _normalizedPhone() {
    final digits = _localPhoneDigits();
    return digits.isEmpty ? '' : '+855$digits';
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
      final phoneDigits = _localPhoneDigits();

      if (nameText.isEmpty) return 'Full name is required';
      if (phoneDigits.isEmpty) return 'Phone number is required';
      if (phoneDigits.length < 8) return 'Enter a valid phone number';
    }

    return null;
  }

  String? _validateEmailOnly() {
    final emailText = email.text.trim();
    if (emailText.isEmpty) return 'Email is required';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(emailText)) return 'Enter a valid email';
    return null;
  }

  Future<void> _openVerificationScreen({String? introMessage}) async {
    final emailError = _validateEmailOnly();
    if (emailError != null) {
      setState(() => error = emailError);
      return;
    }

    _dismissKeyboard();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SignupVerificationScreen(
          initialEmail: email.text.trim(),
          introMessage: introMessage,
        ),
      ),
    );
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
          phone: _normalizedPhone(),
          promoEmailOptIn: promoEmailOptIn,
        );
        if (!mounted) return;
        if (auth.user == null) {
          setState(() {
            isLogin = true;
            loading = false;
          });
          await _openVerificationScreen(
            introMessage:
                'We sent a verification code to your email. Check inbox and spam if you do not see it right away.',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (isLogin && requiresEmailVerification(e)) {
        setState(() {
          loading = false;
          error = '';
        });
        await _openVerificationScreen(
          introMessage:
              'Your account still needs email verification. Enter your verification code below, or resend a new one.',
        );
      } else {
        setState(() => error = friendlyAuthErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _openLegal(LegalDocumentType type) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LegalDocumentsScreen(type: type)));
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      prefixText: prefixText,
      fillColor: const Color(0xFFF7FBF9),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7E3DE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD7E3DE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF0B7D69), width: 1.5),
      ),
    );
  }

  Widget _buildInputLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF244A42),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<String>? autofillHints,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
    bool obscureText = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    VoidCallback? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
          decoration: _fieldDecoration(
            hint: hint,
            icon: icon,
            suffixIcon: suffixIcon,
            prefixText: prefixText,
          ),
          onTapOutside: (_) => _dismissKeyboard(),
          onSubmitted: (_) => onSubmitted?.call(),
        ),
      ],
    );
  }

  Widget _buildHeaderBlock() {
    final title = isLogin ? 'Welcome back' : 'Create your account';
    final subtitle = isLogin
        ? 'Sign in to continue shopping, manage orders, and pick up where you left off.'
        : 'Set up your MarketFlow account to save addresses, track orders, and get support faster.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeader = constraints.maxWidth < 390;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BrandLogo(size: 48, showWordmark: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        Brand.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF143C35),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        Brand.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF60706A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compactHeader ? 9 : 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isLogin ? 'Secure sign in' : 'New customer',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B6C5C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Column(
                key: ValueKey(isLogin),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: compactHeader ? 24 : 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: const Color(0xFF143C35),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Color(0xFF60706A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEBEC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1C6CD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFA7192E),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFA7192E),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFEFFFE),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE0E8E4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 36,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: AutofillGroup(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBlock(),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ModeChip(
                        text: 'Sign In',
                        active: isLogin,
                        onTap: () => _setAuthMode(true),
                      ),
                    ),
                    Expanded(
                      child: _ModeChip(
                        text: 'Create Account',
                        active: !isLogin,
                        onTap: () => _setAuthMode(false),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!isLogin) ...[
                _buildTextField(
                  controller: fullName,
                  label: 'Full name',
                  hint: 'Your full name',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: phone,
                  label: 'Phone number',
                  hint: '12 345 678',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  prefixText: '+855 ',
                  inputFormatters: const [_CambodiaPhoneNumberFormatter()],
                ),
                const SizedBox(height: 14),
              ],
              _buildTextField(
                controller: email,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: pass,
                label: 'Password',
                hint: isLogin ? 'Enter your password' : 'At least 6 characters',
                icon: Icons.lock_outline_rounded,
                obscureText: obscure,
                textInputAction: TextInputAction.done,
                autofillHints: isLogin
                    ? const [AutofillHints.password]
                    : const [AutofillHints.newPassword],
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
                onSubmitted: _submit,
              ),
              if (!isLogin) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: promoEmailOptIn,
                    onChanged: (value) {
                      setState(() => promoEmailOptIn = value == true);
                    },
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    title: const Text(
                      'Send me promotional emails',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Get product drops, offers, and updates occasionally.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
              if (error.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildErrorBanner(),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
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
              const SizedBox(height: 12),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'By continuing you agree to our ',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                      ),
                    ),
                    InkWell(
                      onTap: () => _openLegal(LegalDocumentType.terms),
                      child: const Text(
                        'Terms',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      ' and ',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                      ),
                    ),
                    InkWell(
                      onTap: () => _openLegal(LegalDocumentType.privacy),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Text(
                      '.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final useDesktopLayout = kIsWeb && size.width >= 980;

    return Scaffold(
      body: Stack(
        children: [
          const _BackgroundDecor(),
          SafeArea(
            child: GestureDetector(
              onTap: _dismissKeyboard,
              behavior: HitTestBehavior.translucent,
              child: Align(
                alignment: useDesktopLayout
                    ? Alignment.center
                    : Alignment.topCenter,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    useDesktopLayout ? 24 : 18,
                    useDesktopLayout ? 24 : 22,
                    useDesktopLayout ? 24 : 18,
                    (useDesktopLayout ? 24 : 22) + viewInsets.bottom,
                  ),
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
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildAuthCard(colors),
                          ),
                  ),
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

class _CambodiaPhoneNumberFormatter extends TextInputFormatter {
  const _CambodiaPhoneNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('855')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 9) {
      digits = digits.substring(0, 9);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
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
