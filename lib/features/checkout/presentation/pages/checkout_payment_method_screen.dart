import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marketflow/features/settings/presentation/bloc/app_settings_provider.dart';

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
    _selectedMethod = widget.initialMethod;
  }

  Widget _methodTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String subtitle = '',
    required String value,
    required bool enabled,
    required bool selected,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? () => setState(() => _selectedMethod = value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: iconColor, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 32,
                color: selected ? _accent : Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final abaEnabled = settings.isPaymentMethodEnabled(
      AppSettingsProvider.paymentAbaPayWayQr,
    );
    final cashOnDeliveryEnabled = settings.isPaymentMethodEnabled(
      AppSettingsProvider.paymentCashOnDelivery,
    );
    final enabledSelection = <String>[
      if (abaEnabled) AppSettingsProvider.paymentAbaPayWayQr,
      if (cashOnDeliveryEnabled) AppSettingsProvider.paymentCashOnDelivery,
    ];
    final selectedMethod = enabledSelection.contains(_selectedMethod)
        ? _selectedMethod
        : (enabledSelection.isNotEmpty
              ? enabledSelection.first
              : _selectedMethod);
    final hasEnabledMethod = enabledSelection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose payment method')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      settings.formatUsd(widget.total),
                      style: const TextStyle(
                        fontSize: 42,
                        color: Color(0xFFF14D00),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE8E8EC)),
                  ),
                  child: Column(
                    children: [
                      _methodTile(
                        icon: Icons.qr_code_2_rounded,
                        iconColor: const Color(0xFF0B7D69),
                        title: 'ABA PAY',
                        subtitle: 'Tap to pay with ABA KHQR',
                        value: 'aba_payway_qr',
                        enabled: abaEnabled,
                        selected: selectedMethod == 'aba_payway_qr',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.chat_bubble_rounded,
                        iconColor: const Color(0xFF22C55E),
                        title: 'Wechat Pay',
                        value: 'wechat',
                        enabled: false,
                        selected: selectedMethod == 'wechat',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: const Color(0xFF0E7490),
                        title: 'Wallet',
                        subtitle: 'Tap to enable wallet',
                        value: 'wallet',
                        enabled: false,
                        selected: selectedMethod == 'wallet',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.account_balance_rounded,
                        iconColor: const Color(0xFF84CC16),
                        title: 'Wing Bank',
                        value: 'wing',
                        enabled: false,
                        selected: selectedMethod == 'wing',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.payments_outlined,
                        iconColor: const Color(0xFF14B8A6),
                        title: 'Lanton Pay',
                        value: 'lanton',
                        enabled: false,
                        selected: selectedMethod == 'lanton',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.currency_exchange,
                        iconColor: const Color(0xFFE11D48),
                        title: 'CoolCash',
                        value: 'coolcash',
                        enabled: false,
                        selected: selectedMethod == 'coolcash',
                      ),
                      const Divider(height: 1),
                      _methodTile(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: const Color(0xFF1E3A8A),
                        title: 'ACLEDA PAY',
                        subtitle: 'Tap to pay with ACLEDA Mobile',
                        value: 'acleda',
                        enabled: false,
                        selected: selectedMethod == 'acleda',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE8E8EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        child: Text(
                          'Support offline payment',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      _methodTile(
                        icon: Icons.local_shipping_outlined,
                        iconColor: const Color(0xFFFF8A00),
                        title: 'Cash On Delivery',
                        value: 'cash_on_delivery',
                        enabled: cashOnDeliveryEnabled,
                        selected: selectedMethod == 'cash_on_delivery',
                      ),
                    ],
                  ),
                ),
                if (!hasEnabledMethod) ...[
                  const SizedBox(height: 10),
                  Text(
                    'No payment method is currently available. Contact admin.',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                child: const Text('Confirm', style: TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
