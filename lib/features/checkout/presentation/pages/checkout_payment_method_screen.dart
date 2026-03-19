import 'package:flutter/material.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';
import 'package:provider/provider.dart';

class CheckoutPaymentMethodScreen extends StatefulWidget {
  const CheckoutPaymentMethodScreen({
    super.key,
    required this.total,
    required this.initialMethod,
  });

  final double total;
  final String initialMethod;

  @override
  State<CheckoutPaymentMethodScreen> createState() =>
      _CheckoutPaymentMethodScreenState();
}

class _CheckoutPaymentMethodScreenState
    extends State<CheckoutPaymentMethodScreen> {
  static const Color _accent = Color(0xFFF6234A);
  late String _selectedMethod;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialMethod.trim();
  }

  List<_PaymentMethodOption> _paymentOptions(AppSettingsProvider settings) {
    return <_PaymentMethodOption>[
      _PaymentMethodOption(
        value: AppSettingsProvider.paymentAbaPayWayQr,
        title: 'ABA PAY',
        subtitle: 'Scan and pay with ABA KHQR',
        supportingTitle: 'Instant confirmation',
        supportingText:
            'Best for faster checkout updates and fewer handoff steps.',
        iconAssetPath: 'assets/brand/aba_pay_logo.png',
        iconColor: const Color(0xFF0B7D69),
        enabled: settings.isPaymentMethodEnabled(
          AppSettingsProvider.paymentAbaPayWayQr,
        ),
        availabilityLabel: 'Online payment',
        badges: const <String>['Recommended', 'Fastest'],
      ),
      _PaymentMethodOption(
        value: AppSettingsProvider.paymentCashOnDelivery,
        title: 'Cash On Delivery',
        subtitle: 'Pay when the order arrives',
        supportingTitle: 'Offline handoff',
        supportingText:
            'Useful when you prefer to pay in person at delivery time.',
        icon: Icons.local_shipping_outlined,
        iconColor: const Color(0xFFFF8A00),
        enabled: settings.isPaymentMethodEnabled(
          AppSettingsProvider.paymentCashOnDelivery,
        ),
        availabilityLabel: 'Offline payment',
        badges: const <String>['Flexible'],
      ),
    ];
  }

  List<_PaymentMethodOption> _enabledOptions(List<_PaymentMethodOption> options) {
    return options.where((option) => option.enabled).toList(growable: false);
  }

  _PaymentMethodOption? _recommendedOption(
    List<_PaymentMethodOption> enabledOptions,
  ) {
    if (enabledOptions.isEmpty) {
      return null;
    }
    for (final option in enabledOptions) {
      if (option.value == AppSettingsProvider.paymentAbaPayWayQr) {
        return option;
      }
    }
    return enabledOptions.first;
  }

  String _effectiveSelection(List<_PaymentMethodOption> enabledOptions) {
    final enabledValues = enabledOptions.map((option) => option.value).toSet();
    if (enabledValues.contains(_selectedMethod)) {
      return _selectedMethod;
    }
    return enabledOptions.isNotEmpty ? enabledOptions.first.value : _selectedMethod;
  }

  _PaymentMethodOption? _optionForValue(
    List<_PaymentMethodOption> options,
    String value,
  ) {
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  String _selectionHeadline(_PaymentMethodOption option) {
    if (option.value == AppSettingsProvider.paymentAbaPayWayQr) {
      return 'Pay now and move straight into confirmation.';
    }
    return 'Pay when your order arrives.';
  }

  String _selectionSupportText(_PaymentMethodOption option) {
    if (option.value == AppSettingsProvider.paymentAbaPayWayQr) {
      return 'Choose this when you want the cleanest handoff into the payment flow.';
    }
    return 'Choose this when you prefer an in-person payment handoff on delivery.';
  }

  Widget _statusPill({
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
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  Widget _methodTile({
    required _PaymentMethodOption option,
    required bool selected,
    required bool recommended,
  }) {
    final hasAssetIcon = option.iconAssetPath != null;
    final enabled = option.enabled;
    return AnimatedContainer(
      key: ValueKey<String>('payment-method-${option.value}'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF5F8), Color(0xFFFFFFFF)],
              )
            : null,
        color: selected ? null : Colors.white,
        border: Border.all(
          color: selected ? _accent : const Color(0xFFE4E7EB),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x14F6234A),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0F161B22),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? () => setState(() => _selectedMethod = option.value) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: hasAssetIcon
                            ? Colors.white
                            : option.iconColor.withValues(alpha: 0.12),
                        border: Border.all(
                          color: option.iconColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: hasAssetIcon
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                option.iconAssetPath!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Icon(
                              option.icon,
                              color: option.iconColor,
                              size: 30,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  option.title,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),
                              AnimatedScale(
                                scale: selected ? 1 : 0.94,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  selected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 28,
                                  color: selected ? _accent : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            option.subtitle,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.grey.shade600,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusPill(
                      label: enabled ? 'Available now' : 'Temporarily unavailable',
                      background: enabled
                          ? const Color(0xFFE8F6F0)
                          : const Color(0xFFF3F4F6),
                      foreground: enabled
                          ? const Color(0xFF17624E)
                          : const Color(0xFF6B7280),
                    ),
                    _statusPill(
                      label: option.availabilityLabel,
                      background: const Color(0xFFF5F7FA),
                      foreground: const Color(0xFF485465),
                    ),
                    for (final badge in option.badges)
                      _statusPill(
                        label: badge,
                        background: badge == 'Recommended'
                            ? const Color(0xFFFFE5EC)
                            : const Color(0xFFEEF3FF),
                        foreground: badge == 'Recommended'
                            ? const Color(0xFFB61F49)
                            : const Color(0xFF3557A6),
                      ),
                    if (recommended && enabled)
                      _statusPill(
                        label: 'Recommended right now',
                        background: const Color(0xFFFFF1D7),
                        foreground: const Color(0xFF8C5C12),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE7EBF0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.supportingTitle,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.supportingText,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Color(0xFF5B6572),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final options = _paymentOptions(settings);
    final enabledOptions = _enabledOptions(options);
    final hasEnabledMethod = enabledOptions.isNotEmpty;
    final selectedMethod = _effectiveSelection(enabledOptions);
    final selectedOption = hasEnabledMethod
        ? _optionForValue(options, selectedMethod)
        : null;
    final recommendedOption = _recommendedOption(enabledOptions);
    final selectedIsRecommended =
        selectedOption != null && recommendedOption?.value == selectedOption.value;
    final confirmLabel = selectedOption == null
        ? 'Confirm'
        : 'Continue with ${selectedOption.title}';

    return Scaffold(
      appBar: AppBar(title: const Text('Choose payment method')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFF5F7), Color(0xFFFFFBFC)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFF5CDD6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order total',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          settings.formatUsd(widget.total),
                          style: const TextStyle(
                            fontSize: 40,
                            color: Color(0xFFF14D00),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusPill(
                            label: '${enabledOptions.length} method${enabledOptions.length == 1 ? '' : 's'} ready',
                            background: const Color(0xFFFFFFFF),
                            foreground: const Color(0xFFB61F49),
                          ),
                          if (selectedOption != null)
                            _statusPill(
                              label: 'Selected: ${selectedOption.title}',
                              background: const Color(0xFFFFFFFF),
                              foreground: const Color(0xFF334155),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (selectedOption != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF0D8DE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectionHeadline(selectedOption),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _selectionSupportText(selectedOption),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: Color(0xFF5B6572),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (!selectedIsRecommended &&
                                  recommendedOption != null) ...[
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: () => setState(
                                    () => _selectedMethod = recommendedOption.value,
                                  ),
                                  icon: const Icon(Icons.auto_fix_high_rounded),
                                  label: Text(
                                    'Use recommended: ${recommendedOption.title}',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF0D8DE)),
                          ),
                          child: Text(
                            'No payment method is currently available. Contact admin.',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Available methods',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasEnabledMethod
                      ? 'Choose the payment handoff that fits this order best.'
                      : 'Admin controls are currently preventing checkout payments.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                for (final option in options)
                  _methodTile(
                    option: option,
                    selected: selectedMethod == option.value,
                    recommended:
                        recommendedOption != null &&
                        recommendedOption.value == option.value,
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE4E7EB)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need help deciding?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'ABA PAY is usually the fastest path for instant payment confirmation. Cash On Delivery stays useful when you want to pay in person.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Color(0xFF5B6572),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 62,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: hasEnabledMethod
                    ? () => Navigator.pop(context, selectedMethod)
                    : null,
                child: Text(confirmLabel, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodOption {
  const _PaymentMethodOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.supportingTitle,
    required this.supportingText,
    required this.iconColor,
    required this.enabled,
    required this.availabilityLabel,
    required this.badges,
    this.icon,
    this.iconAssetPath,
  }) : assert(icon != null || iconAssetPath != null);

  final String value;
  final String title;
  final String subtitle;
  final String supportingTitle;
  final String supportingText;
  final IconData? icon;
  final String? iconAssetPath;
  final Color iconColor;
  final bool enabled;
  final String availabilityLabel;
  final List<String> badges;
}
