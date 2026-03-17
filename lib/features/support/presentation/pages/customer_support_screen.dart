import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:marketflow/config/support_config.dart';
import 'package:marketflow/core/network/supabase_data_proxy.dart';
import 'package:marketflow/core/support/support_draft_store.dart';
import 'package:marketflow/core/support/support_notification_store.dart';
import 'package:marketflow/core/support/support_request_link.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
import 'package:marketflow/features/checkout/presentation/bloc/order_management_provider.dart';
import 'package:marketflow/features/checkout/presentation/pages/order_history_list_screen.dart';

class CustomerSupportScreen extends StatefulWidget {
  const CustomerSupportScreen({
    super.key,
    this.initialRequestType,
    this.initialMessage,
    this.initialFollowUpOrderId,
    this.initialFollowUpStatus,
    this.initialFollowUpRequestType,
    this.initialFollowUpSupportNote,
    this.initialFollowUpActivityAt,
    this.initialFollowUpSharedAddress,
  });

  final String? initialRequestType;
  final String? initialMessage;
  final int? initialFollowUpOrderId;
  final String? initialFollowUpStatus;
  final String? initialFollowUpRequestType;
  final String? initialFollowUpSupportNote;
  final String? initialFollowUpActivityAt;
  final String? initialFollowUpSharedAddress;

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
  final ScrollController _scrollController = ScrollController();
  final FocusNode _requestFocusNode = FocusNode();
  final GlobalKey _requestFormKey = GlobalKey();
  final SupportDraftStore _draftStore = const SupportDraftStore();
  final SupportNotificationStore _supportNotificationStore =
      const SupportNotificationStore();

  String _selectedRequestType = _requestTypes.first;
  String _anonymousSessionId = '';
  List<_CustomerSupportUpdate> _recentUpdates =
      const <_CustomerSupportUpdate>[];
  _CustomerSupportUpdate? _activeFollowUpUpdate;
  _SupportUpdateFilter _selectedUpdateFilter = _SupportUpdateFilter.all;
  bool _opening = false;
  bool _loadingRecentUpdates = false;
  bool _submitting = false;
  bool _markedInitialFollowUpSeen = false;
  late final bool _hasExplicitInitialContext;

  @override
  void initState() {
    super.initState();
    final initialRequestType = widget.initialRequestType?.trim().toLowerCase();
    final initialMessage = widget.initialMessage?.trim() ?? '';
    final initialFollowUp = _buildInitialFollowUpUpdate();
    _hasExplicitInitialContext =
        initialFollowUp != null ||
        (initialRequestType != null && initialRequestType.isNotEmpty) ||
        initialMessage.isNotEmpty;
    if (initialFollowUp != null) {
      _applyFollowUpDraft(initialFollowUp);
    } else {
      if (initialRequestType != null &&
          _requestTypes.contains(initialRequestType)) {
        _selectedRequestType = initialRequestType;
      }

      if (initialMessage.isNotEmpty) {
        _requestController.text = initialMessage;
      }
    }
    _requestController.addListener(_handleRequestChanged);
    _getOrCreateAnonymousSessionId();
    Future.microtask(() async {
      await _restoreDraftIfNeeded();
      await _loadRecentUpdates();
      await _markInitialFollowUpSeenIfNeeded();
    });
  }

  @override
  void dispose() {
    _requestController.removeListener(_handleRequestChanged);
    _requestController.dispose();
    _scrollController.dispose();
    _requestFocusNode.dispose();
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

  AuthenticationProvider? _authenticationProviderOrNull() {
    try {
      return context.read<AuthenticationProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  OrderManagementProvider? _orderManagementProviderOrNull() {
    try {
      return context.read<OrderManagementProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  String _draftScope() {
    final userId = _authenticationProviderOrNull()?.user?.id.trim() ?? '';
    return userId.isEmpty ? 'anonymous' : userId;
  }

  SupportDraftFollowUp? _serializeActiveFollowUp() {
    final update = _activeFollowUpUpdate;
    if (update == null) return null;

    return SupportDraftFollowUp(
      orderId: update.orderId,
      status: update.status,
      requestType: update.requestType,
      supportNote: update.supportNote,
      sharedAddress: update.sharedAddress,
    );
  }

  _CustomerSupportUpdate _draftFollowUpToUpdate(SupportDraftFollowUp followUp) {
    return _CustomerSupportUpdate(
      orderId: followUp.orderId,
      requestType: followUp.requestType,
      status: followUp.status,
      activityAt: DateTime.now().toUtc(),
      supportNote: followUp.supportNote,
      sharedAddress: followUp.sharedAddress,
    );
  }

  _CustomerSupportUpdate? _buildInitialFollowUpUpdate() {
    final orderId = widget.initialFollowUpOrderId ?? 0;
    if (orderId <= 0) return null;

    final rawRequestType = (widget.initialFollowUpRequestType ??
            widget.initialRequestType ??
            'general')
        .trim()
        .toLowerCase();
    final requestType = _requestTypes.contains(rawRequestType)
        ? rawRequestType
        : 'general';

    return _CustomerSupportUpdate(
      orderId: orderId,
      requestType: requestType,
      status: _normalizeSupportStatus(widget.initialFollowUpStatus),
      activityAt:
          _parseUtcDateTime(widget.initialFollowUpActivityAt) ??
          DateTime.now().toUtc(),
      supportNote: (widget.initialFollowUpSupportNote ?? '').trim(),
      sharedAddress: (widget.initialFollowUpSharedAddress ?? '').trim(),
    );
  }

  void _applyFollowUpDraft(_CustomerSupportUpdate update) {
    _activeFollowUpUpdate = update;
    if (_requestTypes.contains(update.requestType)) {
      _selectedRequestType = update.requestType;
    } else {
      _selectedRequestType = 'general';
    }
    _requestController
      ..text = _buildFollowUpDraft(update)
      ..selection = TextSelection.collapsed(
        offset: _requestController.text.length,
      );
  }

  Future<void> _persistDraft() async {
    final scope = _draftScope();
    final message = _requestController.text;
    final shouldClear = message.trim().isEmpty && _activeFollowUpUpdate == null;
    if (shouldClear) {
      await _draftStore.clearDraft(scope: scope);
      return;
    }

    await _draftStore.saveDraft(
      scope: scope,
      draft: CustomerSupportDraft(
        requestType: _selectedRequestType,
        message: message,
        followUp: _serializeActiveFollowUp(),
      ),
    );
  }

  void _scheduleDraftPersist() {
    unawaited(_persistDraft());
  }

  void _handleRequestChanged() {
    if (mounted) {
      setState(() {});
    }
    _scheduleDraftPersist();
  }

  bool get _hasGeneralDraftContext =>
      _activeFollowUpUpdate == null &&
      _requestController.text.trim().isNotEmpty;

  void _clearComposerDraft() {
    if (_submitting) return;
    setState(() {
      _activeFollowUpUpdate = null;
      _selectedRequestType = _requestTypes.first;
      _requestController.clear();
    });
    _requestFocusNode.unfocus();
    _scheduleDraftPersist();
  }

  Future<void> _restoreDraftIfNeeded() async {
    if (_hasExplicitInitialContext) return;

    final draft = await _draftStore.loadDraft(scope: _draftScope());
    if (!mounted || draft == null) return;

    setState(() {
      final requestType = draft.requestType.trim().toLowerCase();
      _selectedRequestType = _requestTypes.contains(requestType)
          ? requestType
          : _requestTypes.first;
      _requestController.text = draft.message;
      _activeFollowUpUpdate = draft.followUp == null
          ? null
          : _draftFollowUpToUpdate(draft.followUp!);
    });
  }

  int _parseOrderId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse((raw ?? '').toString()) ?? -1;
  }

  String _normalizeSupportStatus(dynamic raw) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    switch (value) {
      case 'address_applied':
      case 'resolved':
        return value;
      default:
        return 'pending';
    }
  }

  DateTime? _parseUtcDateTime(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  String _supportStatusLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'address_applied':
        return 'Address applied';
      case 'resolved':
        return 'Resolved';
      default:
        return 'Pending';
    }
  }

  String _supportStatusSummary(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'address_applied':
        return 'Support applied the latest address update to your order.';
      case 'resolved':
        return 'Support marked this request resolved.';
      default:
        return 'Support has your request and is reviewing it now.';
    }
  }

  Color _supportStatusColor(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'address_applied':
        return const Color(0xFF1E5E9A);
      case 'resolved':
        return const Color(0xFF1F5F3A);
      default:
        return const Color(0xFF9A5400);
    }
  }

  String _formatUpdateDate(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  List<_CustomerSupportUpdate> _extractRecentUpdates(
    List<Map<String, dynamic>> orders,
  ) {
    final updates = <_CustomerSupportUpdate>[];
    for (final order in orders) {
      final orderId = _parseOrderId(order['id']);
      if (orderId <= 0) continue;
      final history = order['support_request_history'];
      if (history is! List) continue;
      for (final row in history.whereType<Map>()) {
        final item = Map<String, dynamic>.from(row);
        final status = _normalizeSupportStatus(item['support_request_status']);
        final activityAt =
            _parseUtcDateTime(item['support_note_updated_at']) ??
            _parseUtcDateTime(item['support_request_status_updated_at']) ??
            _parseUtcDateTime(item['support_request_created_at']);
        if (activityAt == null) continue;
        updates.add(
          _CustomerSupportUpdate(
            orderId: orderId,
            requestType: (item['request_type'] ?? 'general').toString().trim(),
            status: status,
            activityAt: activityAt,
            supportNote: (item['support_note'] ?? '').toString().trim(),
            sharedAddress: parseUpdatedDeliveryAddressFromSupportMessage(
              (item['support_request_message'] ?? '').toString(),
            ),
          ),
        );
      }
    }

    updates.sort((a, b) => b.activityAt.compareTo(a.activityAt));
    return updates.take(4).toList(growable: false);
  }

  Future<void> _loadRecentUpdates() async {
    final auth = _authenticationProviderOrNull();
    final user = auth?.user;
    final orderProvider = _orderManagementProviderOrNull();
    if (user == null || orderProvider == null) {
      if (!mounted) return;
      setState(() {
        _loadingRecentUpdates = false;
        _recentUpdates = const <_CustomerSupportUpdate>[];
      });
      return;
    }

    if (mounted) {
      setState(() => _loadingRecentUpdates = true);
    }

    try {
      final orders = await orderProvider.loadOrders();
      final updates = _extractRecentUpdates(orders);
      if (!mounted) return;
      setState(() => _recentUpdates = updates);
    } catch (_) {
      if (!mounted) return;
      setState(() => _recentUpdates = const <_CustomerSupportUpdate>[]);
    } finally {
      if (mounted) {
        setState(() => _loadingRecentUpdates = false);
      }
    }
  }

  Future<void> _markInitialFollowUpSeenIfNeeded() async {
    if (_markedInitialFollowUpSeen) return;

    final activeFollowUp = _activeFollowUpUpdate;
    if (activeFollowUp == null) return;

    final userId = _authenticationProviderOrNull()?.user?.id.trim() ?? '';
    if (userId.isEmpty) return;

    var seenActivityAt = activeFollowUp.activityAt;
    for (final update in _recentUpdates) {
      if (update.orderId == activeFollowUp.orderId) {
        seenActivityAt = update.activityAt;
        break;
      }
    }

    final seenAt = await _supportNotificationStore.loadSeenAt(userId: userId);
    if (seenAt != null && !seenActivityAt.isAfter(seenAt)) {
      _markedInitialFollowUpSeen = true;
      return;
    }

    await _supportNotificationStore.saveSeenAt(
      userId: userId,
      seenAt: seenActivityAt,
    );
    _markedInitialFollowUpSeen = true;
  }

  Future<void> _handleRefresh() async {
    await Future.wait<void>([
      _getOrCreateAnonymousSessionId(),
      _loadRecentUpdates(),
    ]);
  }

  Future<void> _openOrderHistory({int? orderId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderHistoryListScreen(initialOrderId: orderId),
      ),
    );
    if (!mounted) return;
    await _loadRecentUpdates();
  }

  String _buildFollowUpDraft(_CustomerSupportUpdate update) {
    final requestTypeLabel = _requestTypeLabel(
      update.requestType,
    ).toLowerCase();
    final lines = switch (update.status) {
      'resolved' => <String>[
        'Reopening support request for Order #${update.orderId}.',
        'I still need help with this $requestTypeLabel request.',
      ],
      'address_applied' => <String>[
        'Sending another update for Order #${update.orderId}.',
        'I have more information for this $requestTypeLabel request.',
      ],
      _ => <String>[
        'Following up on Order #${update.orderId}.',
        'I need more help with this $requestTypeLabel request.',
      ],
    };

    if (update.supportNote.isNotEmpty) {
      lines.add('Latest support reply: ${update.supportNote}');
    }
    if (update.sharedAddress.isNotEmpty) {
      lines.add('Address shared: ${update.sharedAddress}');
    }
    lines.add('');
    return lines.join('\n');
  }

  String _followUpBannerTitle(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'Reopening Order #${update.orderId}';
      case 'address_applied':
        return 'Updating Order #${update.orderId}';
      default:
        return 'Following up on Order #${update.orderId}';
    }
  }

  String _followUpActionLabel(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'Reopen request';
      case 'address_applied':
        return 'Send another update';
      default:
        return 'Send follow-up';
    }
  }

  String _followUpReadyLabel(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'Reopen draft ready for Order #${update.orderId}';
      case 'address_applied':
        return 'Update draft ready for Order #${update.orderId}';
      default:
        return 'Reply draft ready for Order #${update.orderId}';
    }
  }

  String _followUpSuccessLabel(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'Reopen request sent for Order #${update.orderId}';
      case 'address_applied':
        return 'Address update sent for Order #${update.orderId}';
      default:
        return 'Follow-up sent for Order #${update.orderId}';
    }
  }

  String _followUpSubmittingLabel(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'Reopening...';
      case 'address_applied':
        return 'Sending update...';
      default:
        return 'Sending follow-up...';
    }
  }

  String _followUpMode(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return 'reopen';
      case 'address_applied':
        return 'update';
      default:
        return 'reply';
    }
  }

  IconData _followUpBannerIcon(_CustomerSupportUpdate update) {
    switch (update.status) {
      case 'resolved':
        return Icons.refresh_rounded;
      case 'address_applied':
        return Icons.edit_note_outlined;
      default:
        return Icons.reply_outlined;
    }
  }

  Future<void> _startFollowUp(_CustomerSupportUpdate update) async {
    if (_submitting) return;

    setState(() {
      _applyFollowUpDraft(update);
    });

    final formContext = _requestFormKey.currentContext;
    if (formContext != null) {
      await Scrollable.ensureVisible(
        formContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.04,
      );
    } else if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    _requestFocusNode.requestFocus();
    _scheduleDraftPersist();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_followUpReadyLabel(update))),
    );
  }

  void _discardFollowUpDraft() {
    _clearComposerDraft();
  }

  bool _matchesUpdateFilter(
    _CustomerSupportUpdate update,
    _SupportUpdateFilter filter,
  ) {
    switch (filter) {
      case _SupportUpdateFilter.open:
        return update.status != 'resolved';
      case _SupportUpdateFilter.resolved:
        return update.status == 'resolved';
      case _SupportUpdateFilter.all:
        return true;
    }
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
      final activeFollowUp = _activeFollowUpUpdate;
      final linkedOrderId = parseLinkedOrderIdFromSupportMessage(requestText);
      final currentUser = Supabase.instance.client.auth.currentUser;
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
            'support_status': 'pending',
            'source': 'in_app_support_screen',
            'anonymous': true,
            'session_id': anonymousSessionId,
            'is_follow_up': activeFollowUp != null,
            ...?activeFollowUp == null
                ? null
                : <String, dynamic>{
                    'follow_up_order_id': activeFollowUp.orderId,
                    'follow_up_status': activeFollowUp.status,
                    'follow_up_request_type': activeFollowUp.requestType,
                    'follow_up_mode': _followUpMode(activeFollowUp),
                  },
            ...?linkedOrderId == null
                ? null
                : <String, dynamic>{'linked_order_id': linkedOrderId},
          },
          'p_user_id': currentUser?.id,
        },
      );

      if (!mounted) return;
      setState(() {
        _activeFollowUpUpdate = null;
        _selectedRequestType = _requestTypes.first;
        _requestController.clear();
      });
      await _draftStore.clearDraft(scope: _draftScope());
      await _loadRecentUpdates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activeFollowUp == null
                ? 'Support request sent'
                : _followUpSuccessLabel(activeFollowUp),
          ),
        ),
      );
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

  Widget _buildRecentUpdatesSection() {
    final orderProvider = _orderManagementProviderOrNull();
    if (orderProvider == null) {
      return const SizedBox.shrink();
    }

    final openCount = _recentUpdates
        .where(
          (update) => _matchesUpdateFilter(update, _SupportUpdateFilter.open),
        )
        .length;
    final resolvedCount = _recentUpdates
        .where(
          (update) =>
              _matchesUpdateFilter(update, _SupportUpdateFilter.resolved),
        )
        .length;
    final filteredUpdates = _recentUpdates
        .where((update) => _matchesUpdateFilter(update, _selectedUpdateFilter))
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent support updates',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: _loadingRecentUpdates ? null : _loadRecentUpdates,
                tooltip: 'Refresh support updates',
                icon: const Icon(Icons.refresh_rounded),
              ),
              TextButton.icon(
                onPressed: _loadingRecentUpdates ? null : _openOrderHistory,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('My Orders'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Track the latest replies and delivery recovery progress without leaving support.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('All (${_recentUpdates.length})'),
                selected: _selectedUpdateFilter == _SupportUpdateFilter.all,
                onSelected: (_) {
                  setState(
                    () => _selectedUpdateFilter = _SupportUpdateFilter.all,
                  );
                },
              ),
              ChoiceChip(
                label: Text('Open ($openCount)'),
                selected: _selectedUpdateFilter == _SupportUpdateFilter.open,
                onSelected: (_) {
                  setState(
                    () => _selectedUpdateFilter = _SupportUpdateFilter.open,
                  );
                },
              ),
              ChoiceChip(
                label: Text('Resolved ($resolvedCount)'),
                selected:
                    _selectedUpdateFilter == _SupportUpdateFilter.resolved,
                onSelected: (_) {
                  setState(
                    () => _selectedUpdateFilter = _SupportUpdateFilter.resolved,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingRecentUpdates)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_recentUpdates.isEmpty && !_loadingRecentUpdates)
            Text(
              'No support updates yet. New replies and status changes will show up here.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            )
          else if (filteredUpdates.isEmpty && !_loadingRecentUpdates)
            Text(
              _selectedUpdateFilter == _SupportUpdateFilter.resolved
                  ? 'No resolved updates yet.'
                  : 'No open support updates right now.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            )
          else
            ...filteredUpdates.map((update) {
              final statusColor = _supportStatusColor(update.status);
              final supportMessage = update.supportNote.isNotEmpty
                  ? update.supportNote
                  : _supportStatusSummary(update.status);
              final requestTypeLabel = update.requestType.isEmpty
                  ? 'Support'
                  : _requestTypeLabel(update.requestType);

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD9E0E5)),
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
                          'Order #${update.orderId}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2A24),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _supportStatusLabel(update.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          requestTypeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF56636D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatUpdateDate(update.activityAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF56636D),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(supportMessage, style: const TextStyle(height: 1.4)),
                    if (update.sharedAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Address shared: ${update.sharedAddress}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF56636D),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          key: ValueKey<String>('follow_up_${update.orderId}'),
                          onPressed: _loadingRecentUpdates
                              ? null
                              : () => _startFollowUp(update),
                          icon: Icon(
                            _followUpBannerIcon(update),
                            size: 18,
                          ),
                          label: Text(_followUpActionLabel(update)),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: ValueKey<String>('view_order_${update.orderId}'),
                          onPressed: _loadingRecentUpdates
                              ? null
                              : () =>
                                    _openOrderHistory(orderId: update.orderId),
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                          ),
                          label: const Text('View order'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supportHours = SupportConfig.supportHours.trim();
    final email = SupportConfig.email.trim();
    final phone = SupportConfig.phone.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Customer Support')),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          controller: _scrollController,
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
              key: _requestFormKey,
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
                  if (_hasGeneralDraftContext) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F7F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE6D9B5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.save_outlined,
                            size: 18,
                            color: Color(0xFF8A6500),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Draft saved locally',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2A2417),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_requestTypeLabel(_selectedRequestType)} draft will stay on this device until you send or clear it.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6A5A33),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: const ValueKey<String>('clear_general_draft'),
                            onPressed: _submitting ? null : _clearComposerDraft,
                            child: const Text('Clear draft'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_activeFollowUpUpdate != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3FAF7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB8E3D6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _followUpBannerIcon(_activeFollowUpUpdate!),
                                size: 18,
                                color: const Color(0xFF0B7D69),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _followUpBannerTitle(
                                    _activeFollowUpUpdate!,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2A24),
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey<String>(
                                  'discard_follow_up',
                                ),
                                onPressed: _submitting
                                    ? null
                                    : _discardFollowUpDraft,
                                child: const Text('Discard draft'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _activeFollowUpUpdate!.supportNote.isNotEmpty
                                ? _activeFollowUpUpdate!.supportNote
                                : _supportStatusSummary(
                                    _activeFollowUpUpdate!.status,
                                  ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF56636D),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Saved automatically on this device until you send or discard it.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF56636D),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                            _scheduleDraftPersist();
                          },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _requestController,
                    focusNode: _requestFocusNode,
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
                        _submitting
                            ? _activeFollowUpUpdate == null
                                  ? 'Sending...'
                                  : _followUpSubmittingLabel(
                                      _activeFollowUpUpdate!,
                                    )
                            : _activeFollowUpUpdate == null
                            ? 'Send Anonymous Message'
                            : _followUpActionLabel(_activeFollowUpUpdate!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentUpdatesSection(),
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
                _openUrl(
                  SupportConfig.messengerUrl,
                  'Unable to open Messenger',
                );
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
      ),
    );
  }
}

class _CustomerSupportUpdate {
  const _CustomerSupportUpdate({
    required this.orderId,
    required this.requestType,
    required this.status,
    required this.activityAt,
    required this.supportNote,
    required this.sharedAddress,
  });

  final int orderId;
  final String requestType;
  final String status;
  final DateTime activityAt;
  final String supportNote;
  final String sharedAddress;
}

enum _SupportUpdateFilter { all, open, resolved }
