import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:marketflow/core/widgets/app_brand_logo.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/auth/presentation/pages/auth_error_message.dart';

class SignupVerificationScreen extends StatefulWidget {
  final String initialEmail;
  final String? introMessage;

  const SignupVerificationScreen({
    super.key,
    required this.initialEmail,
    this.introMessage,
  });

  @override
  State<SignupVerificationScreen> createState() =>
      _SignupVerificationScreenState();
}

class _SignupVerificationScreenState extends State<SignupVerificationScreen> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();

  bool _verifying = false;
  bool _resending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    final focus = FocusScope.of(context);
    if (!focus.hasPrimaryFocus) {
      focus.unfocus();
    }
  }

  String? _validateEmail() {
    final emailText = _emailController.text.trim();
    if (emailText.isEmpty) return 'Email is required';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(emailText)) return 'Enter a valid email';
    return null;
  }

  String? _validateCode() {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return 'Enter a valid 6-digit code';
    }
    return null;
  }

  Future<void> _verify() async {
    final emailError = _validateEmail();
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }

    final codeError = _validateCode();
    if (codeError != null) {
      setState(() => _error = codeError);
      return;
    }

    setState(() {
      _verifying = true;
      _error = '';
    });

    try {
      await context.read<AuthenticationProvider>().verifySignupCode(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified successfully.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  Future<void> _resendCode() async {
    final emailError = _validateEmail();
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }

    setState(() {
      _resending = true;
      _error = '';
    });

    try {
      await context.read<AuthenticationProvider>().resendSignupVerification(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '6-digit verification code sent. Check inbox and spam folder.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyAuthErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF244A42),
      ),
    );
  }

  InputDecoration _decoration({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
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

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final introMessage = widget.introMessage?.trim();
    final hasIntroMessage = introMessage != null && introMessage.isNotEmpty;

    return Scaffold(
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAF6F4), Color(0xFFF6F4EE)],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(18, 22, 18, 22 + viewInsets.bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const BrandLogo(size: 46, showWordmark: false),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Back'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Verify your email',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: Color(0xFF143C35),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Enter the 6-digit code from your email to finish signing in.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Color(0xFF60706A),
                          ),
                        ),
                        if (hasIntroMessage) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF7F3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFCFE7DD),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.mark_email_read_outlined,
                                  color: Color(0xFF0B7D69),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    introMessage,
                                    style: const TextStyle(
                                      color: Color(0xFF255148),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _buildFieldLabel('Email'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: _decoration(
                            hint: 'you@example.com',
                            icon: Icons.alternate_email_rounded,
                          ),
                          onTapOutside: (_) => _dismissKeyboard(),
                        ),
                        const SizedBox(height: 16),
                        _buildFieldLabel('6-digit code'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 8,
                          ),
                          maxLength: 6,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: _decoration(
                            hint: '123456',
                            icon: Icons.password_rounded,
                          ).copyWith(counterText: ''),
                          onTapOutside: (_) => _dismissKeyboard(),
                          onSubmitted: (_) => _verify(),
                        ),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDEBEC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFF1C6CD),
                              ),
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
                                    _error,
                                    style: const TextStyle(
                                      color: Color(0xFFA7192E),
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _verifying ? null : _verify,
                            icon: _verifying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.verified_user_outlined),
                            label: const Text('Verify email'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: colors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _resending ? null : _resendCode,
                            icon: _resending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.primary,
                                    ),
                                  )
                                : const Icon(Icons.mark_email_unread_outlined),
                            label: const Text('Resend code'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Back to sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
