import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:flutter/material.dart';

class AdminEventsTab extends StatefulWidget {
  const AdminEventsTab({
    super.key,
    required this.loadingEvents,
    required this.events,
    required this.submitting,
    required this.formatCountdown,
    required this.onTapEvent,
    required this.onEditEvent,
    required this.onDuplicateEvent,
    required this.onDeleteEvent,
    required this.onToggleActive,
  });

  final bool loadingEvents;
  final List<AdminEvent> events;
  final bool submitting;
  final String Function(Duration value) formatCountdown;
  final void Function(AdminEvent event) onTapEvent;
  final void Function(AdminEvent event) onEditEvent;
  final void Function(AdminEvent event) onDuplicateEvent;
  final void Function(AdminEvent event) onDeleteEvent;
  final void Function(AdminEvent event, bool nextActive) onToggleActive;

  @override
  State<AdminEventsTab> createState() => _AdminEventsTabState();
}

class _AdminEventsTabState extends State<AdminEventsTab> {
  String _selectedFilter = 'all';

  static const List<String> _filters = <String>[
    'all',
    'active',
    'upcoming',
    'inactive',
    'expired',
  ];

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _themeLabel(String theme) {
    switch (theme) {
      case 'christmas_sale':
        return 'Christmas Sale';
      case 'valentine':
        return 'Valentine';
      case 'new_year':
        return 'New Year';
      case 'black_friday':
        return 'Black Friday';
      case 'summer_sale':
        return 'Summer Sale';
      default:
        return 'Default';
    }
  }

  String _filterLabel(String value) {
    switch (value) {
      case 'active':
        return 'Active';
      case 'upcoming':
        return 'Upcoming';
      case 'inactive':
        return 'Inactive';
      case 'expired':
        return 'Expired';
      default:
        return 'All';
    }
  }

  int _filterCount(String filter) {
    if (filter == 'all') return widget.events.length;
    return widget.events.where((event) => event.statusKey == filter).length;
  }

  List<AdminEvent> _filteredEvents() {
    final filtered = _selectedFilter == 'all'
        ? widget.events.toList()
        : widget.events
              .where((event) => event.statusKey == _selectedFilter)
              .toList();
    filtered.sort(_compareEvents);
    return filtered;
  }

  int _compareEvents(AdminEvent a, AdminEvent b) {
    int priority(AdminEvent event) {
      switch (event.statusKey) {
        case 'active':
          return 0;
        case 'upcoming':
          return 1;
        case 'inactive':
          return 2;
        case 'expired':
          return 3;
        default:
          return 4;
      }
    }

    final priorityDiff = priority(a).compareTo(priority(b));
    if (priorityDiff != 0) return priorityDiff;

    final aStart = a.startsAt;
    final bStart = b.startsAt;
    if (a.statusKey == 'active' || a.statusKey == 'upcoming') {
      if (aStart != null && bStart != null) {
        return aStart.compareTo(bStart);
      }
    } else {
      final aUpdated = a.updatedAt ?? a.createdAt;
      final bUpdated = b.updatedAt ?? b.createdAt;
      if (aUpdated != null && bUpdated != null) {
        return bUpdated.compareTo(aUpdated);
      }
    }

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  Color _statusBackgroundColor(AdminEvent event) {
    switch (event.statusKey) {
      case 'active':
        return const Color(0xFFE8F5F2);
      case 'upcoming':
        return const Color(0xFFEAF2FF);
      case 'expired':
        return const Color(0xFFFFECEC);
      default:
        return const Color(0xFFF2F3F5);
    }
  }

  Color _statusForegroundColor(AdminEvent event) {
    switch (event.statusKey) {
      case 'active':
        return const Color(0xFF0B7D69);
      case 'upcoming':
        return const Color(0xFF2F5EA8);
      case 'expired':
        return const Color(0xFFB33030);
      default:
        return const Color(0xFF49525A);
    }
  }

  String _scheduleSummary(AdminEvent event) {
    if (event.isLive) {
      final remaining = event.timeUntilEnd;
      if (remaining != null && remaining.inSeconds > 0) {
        return 'Ends in ${widget.formatCountdown(remaining)}';
      }
      return 'Live now';
    }
    if (event.isUpcoming) {
      final startsIn = event.timeUntilStart;
      if (startsIn != null && startsIn.inSeconds > 0) {
        return 'Starts in ${widget.formatCountdown(startsIn)}';
      }
      return 'Scheduled';
    }
    if (event.isExpired) return 'Finished';
    return 'Draft event';
  }

  Widget _buildSummaryStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E4DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Event overview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filters.map((filter) {
              final selected = filter == _selectedFilter;
              return ChoiceChip(
                selected: selected,
                label: Text(
                  '${_filterLabel(filter)} (${_filterCount(filter)})',
                ),
                onSelected: (_) {
                  setState(() => _selectedFilter = filter);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final label = _filterLabel(_selectedFilter).toLowerCase();
    final message = _selectedFilter == 'all'
        ? 'Create your first event to start scheduling campaigns.'
        : 'No $label events match this filter right now.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.campaign_outlined,
              size: 44,
              color: Color(0xFF80918A),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedFilter == 'all' ? 'No events found' : 'Nothing here yet',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5E6A65)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }
    final visibleEvents = _filteredEvents();

    return Column(
      children: [
        _buildSummaryStrip(),
        Expanded(
          child: visibleEvents.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: visibleEvents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = visibleEvents[index];
                    final title = event.title;
                    final subtitle = event.subtitle;
                    final badge = event.badge;
                    final expiresAt = event.expiresAt;
                    final startsAt = event.startsAt;
                    final summary = _scheduleSummary(event);
                    final infoPillStyle = TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    );

                    final actions = Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (!event.isExpired)
                          FilledButton.tonalIcon(
                            onPressed: widget.submitting
                                ? null
                                : () => widget.onToggleActive(
                                    event,
                                    !event.isActive,
                                  ),
                            icon: Icon(
                              event.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 18,
                            ),
                            label: Text(event.isActive ? 'Pause' : 'Activate'),
                          ),
                        OutlinedButton.icon(
                          onPressed: widget.submitting
                              ? null
                              : () => widget.onEditEvent(event),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.submitting
                              ? null
                              : () => widget.onDuplicateEvent(event),
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: const Text('Duplicate'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.submitting
                              ? null
                              : () => widget.onDeleteEvent(event),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete'),
                        ),
                      ],
                    );

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD8E4DD)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => widget.onTapEvent(event),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      title.isEmpty ? 'Untitled Event' : title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (badge.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4EFE2),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF7B5E14),
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusBackgroundColor(event),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        event.statusLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _statusForegroundColor(event),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: Color(0xFF44524D),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _EventInfoPill(
                                      icon: Icons.palette_outlined,
                                      label: _themeLabel(event.theme),
                                      textStyle: infoPillStyle,
                                    ),
                                    _EventInfoPill(
                                      icon: Icons.play_circle_outline,
                                      label: _formatDateTime(startsAt),
                                      textStyle: infoPillStyle,
                                    ),
                                    _EventInfoPill(
                                      icon: Icons.stop_circle_outlined,
                                      label: _formatDateTime(expiresAt),
                                      textStyle: infoPillStyle,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F8F7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule_outlined,
                                        size: 18,
                                        color: Color(0xFF35544A),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          summary,
                                          style: const TextStyle(
                                            color: Color(0xFF35544A),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        'View event items',
                                        style: TextStyle(
                                          color: Color(0xFF0B7D69),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EventInfoPill extends StatelessWidget {
  const _EventInfoPill({
    required this.icon,
    required this.label,
    required this.textStyle,
  });

  final IconData icon;
  final String label;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF576560)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: textStyle)),
        ],
      ),
    );
  }
}
