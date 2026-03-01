import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:marketflow/config/support_config.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';

class CustomerSupportScreen extends StatefulWidget {
  const CustomerSupportScreen({super.key});

  @override
  State<CustomerSupportScreen> createState() => _CustomerSupportScreenState();
}

class _CustomerSupportScreenState extends State<CustomerSupportScreen> {
  static const String _anonymousSessionIdKey =
      'customer_support_anonymous_session_id';
  static const List<String> _requestTypes = <String>[
    'general',
    'order',
    'payment',
    'delivery',
    'refund',
    'account',
  ];

  final _requestController = TextEditingController();

  String _selectedRequestType = _requestTypes.first;
  String _anonymousSessionId = '';
  bool _opening = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _getOrCreateAnonymousSessionId();
  }

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _openExternal({
    required Uri uri,
    required String failureMessage,
  }) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<void> _openEmail() async {
    final email = SupportConfig.email.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support email not configured')),
      );
      return;
    }

    final userEmail =
        context.read<AuthenticationProvider>().user?.email?.trim() ?? '';
    final subject = Uri.encodeComponent('Customer support request');
    final body = Uri.encodeComponent(
      'Hello support,\n\nI need help with:\n\n---\n\nAccount: $userEmail',
    );
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    await _openExternal(uri: uri, failureMessage: 'Unable to open email app');
  }

  Future<void> _openPhone() async {
    final phone = SupportConfig.phone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support phone not configured')),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    await _openExternal(uri: uri, failureMessage: 'Unable to start phone call');
  }

  Future<void> _openUrl(String url, String failureMessage) async {
    final value = url.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Support channel not configured')),
      );
      return;
    }
    final uri = _parseExternalUri(value);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid support URL')));
      return;
    }
    await _openExternal(uri: uri, failureMessage: failureMessage);
  }

  Uri? _parseExternalUri(String value) {
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value);
    if (hasScheme) return Uri.tryParse(value);

    // If the user supplied a plain host/path, default to HTTPS.
    if (value.contains(' ') || !value.contains('.')) {
      return null;
    }
    return Uri.tryParse('https://$value');
  }

  Future<void> _openStoreLocation() async {
    final value = SupportConfig.storeLocationUrl.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Store location not configured')),
      );
      return;
    }

    final uri = _buildStoreLocationUri(value);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid store location link')),
      );
      return;
    }

    await _openExternal(uri: uri, failureMessage: 'Unable to open map');
  }

  Uri? _buildStoreLocationUri(String value) {
    final direct = _parseExternalUri(value);
    if (direct != null) return direct;

    // Fallback: treat raw value as map search query (address or coordinates).
    return Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': value,
    });
  }

  String _requestTypeLabel(String value) {
    switch (value) {
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

  Future<String> _getOrCreateAnonymousSessionId() async {
    if (_anonymousSessionId.trim().isNotEmpty) {
      return _anonymousSessionId;
    }
    final prefs = await SharedPreferences.getInstance();
    var value = (prefs.getString(_anonymousSessionIdKey) ?? '').trim();
    if (value.isEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final randomPart = Random()
          .nextInt(0x7fffffff)
          .toRadixString(36)
          .padLeft(6, '0');
      value = 'chat-$timestamp$randomPart';
      await prefs.setString(_anonymousSessionIdKey, value);
    }
    if (mounted) {
      setState(() => _anonymousSessionId = value);
    } else {
      _anonymousSessionId = value;
    }
    return value;
  }

  Future<void> _submitInAppRequest() async {
    if (_submitting) return;

    final requestText = _requestController.text.trim();
    if (requestText.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your issue in detail')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final anonymousSessionId = await _getOrCreateAnonymousSessionId();
      final dataProxy = SupabaseDataProxy(db: Supabase.instance.client);
      await dataProxy.rpc(
        'rpc_app_log',
        params: {
          'p_level': 'info',
          'p_feature': 'customer_support',
          'p_action': 'request_submitted',
          'p_message': requestText,
          'p_metadata': {
            'request_type': _selectedRequestType,
            'request_type_label': _requestTypeLabel(_selectedRequestType),
            'source': 'in_app_support_screen',
            'anonymous': true,
            'session_id': anonymousSessionId,
          },
          'p_user_id': null,
        },
      );

      if (!mounted) return;
      _requestController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Support request sent')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send request. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Widget _buildSupportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      onTap: _opening ? null : onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final supportHours = SupportConfig.supportHours.trim();
    final email = SupportConfig.email.trim();
    final phone = SupportConfig.phone.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need help?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  supportHours.isEmpty
                      ? 'Our support team is here to help.'
                      : 'Support hours: $supportHours',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'In-App Anonymous Chat',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _anonymousSessionId.isEmpty
                      ? 'Your identity is hidden from support staff.'
                      : 'Anonymous chat ID: $_anonymousSessionId',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey<String>('support_type_$_selectedRequestType'),
                  initialValue: _selectedRequestType,
                  decoration: const InputDecoration(
                    labelText: 'Issue Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _requestTypes
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(_requestTypeLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedRequestType = value);
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _requestController,
                  minLines: 4,
                  maxLines: 6,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'How can we help you?',
                    hintText: 'Describe your issue here...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submitInAppRequest,
                    icon: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _submitting ? 'Sending...' : 'Send Anonymous Message',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildSupportTile(
            icon: Icons.email_outlined,
            title: 'Email Support',
            subtitle: email.isEmpty ? 'Not configured' : email,
            onTap: _openEmail,
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.phone_outlined,
            title: 'Call Support',
            subtitle: phone.isEmpty ? 'Not configured' : phone,
            onTap: _openPhone,
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.chat_bubble_outline,
            title: 'WhatsApp',
            subtitle: SupportConfig.whatsAppUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open chat',
            onTap: () {
              _openUrl(
                SupportConfig.whatsAppUrl,
                'Unable to open WhatsApp support',
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.send_outlined,
            title: 'Telegram',
            subtitle: SupportConfig.telegramUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open chat',
            onTap: () {
              _openUrl(
                SupportConfig.telegramUrl,
                'Unable to open Telegram support',
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.facebook_outlined,
            title: 'Facebook',
            subtitle: SupportConfig.facebookUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open page',
            onTap: () {
              _openUrl(
                SupportConfig.facebookUrl,
                'Unable to open Facebook page',
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.message_outlined,
            title: 'Messenger',
            subtitle: SupportConfig.messengerUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open chat',
            onTap: () {
              _openUrl(SupportConfig.messengerUrl, 'Unable to open Messenger');
            },
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.location_on_outlined,
            title: 'Store Location',
            subtitle: SupportConfig.storeLocationUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open in maps',
            onTap: _openStoreLocation,
          ),
          const SizedBox(height: 8),
          _buildSupportTile(
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: SupportConfig.faqUrl.trim().isEmpty
                ? 'Not configured'
                : 'Open FAQ',
            onTap: () {
              _openUrl(SupportConfig.faqUrl, 'Unable to open help center');
            },
          ),
        ],
      ),
    );
  }
}
