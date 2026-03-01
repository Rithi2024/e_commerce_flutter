import 'package:marketflow/features/admin/domain/entities/admin_event_model.dart';
import 'package:flutter/material.dart';

class AdminEventsTab extends StatelessWidget {
  const AdminEventsTab({
    super.key,
    required this.loadingEvents,
    required this.events,
    required this.submitting,
    required this.formatCountdown,
    required this.onTapEvent,
    required this.onEditEvent,
    required this.onDeleteEvent,
  });

  final bool loadingEvents;
  final List<AdminEvent> events;
  final bool submitting;
  final String Function(Duration value) formatCountdown;
  final void Function(AdminEvent event) onTapEvent;
  final void Function(AdminEvent event) onEditEvent;
  final void Function(AdminEvent event) onDeleteEvent;

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

  @override
  Widget build(BuildContext context) {
    if (loadingEvents) {
      return const Center(child: CircularProgressIndicator());
    }
    if (events.isEmpty) {
      return const Center(child: Text('No events found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        final title = event.title;
        final subtitle = event.subtitle;
        final badge = event.badge;
        final isActive = event.isActive;
        final isLive = event.isLive;
        final isUpcoming = event.isUpcoming;
        final expiresAt = event.expiresAt;
        final startsAt = event.startsAt;
        final remaining = expiresAt?.difference(DateTime.now().toUtc());
        final timerText = isLive && remaining != null && remaining.inSeconds > 0
            ? 'Ends in ${formatCountdown(remaining)}'
            : (event.isExpired
                  ? 'Expired'
                  : (isUpcoming ? 'Upcoming' : 'Inactive'));
        final subtitleText = subtitle.isEmpty
            ? 'Badge: ${badge.isEmpty ? '-' : badge}\nTheme: ${_themeLabel(event.theme)}\nStart: ${_formatDateTime(startsAt)}\nEnd: ${_formatDateTime(expiresAt)}\n$timerText'
            : '$subtitle\nBadge: ${badge.isEmpty ? '-' : badge}\nTheme: ${_themeLabel(event.theme)}\nStart: ${_formatDateTime(startsAt)}\nEnd: ${_formatDateTime(expiresAt)}\n$timerText';

        final actions = Wrap(
          spacing: 2,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (event.isExpired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFECEC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Expired',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB33030),
                  ),
                ),
              ),
            if (!isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF49525A),
                  ),
                ),
              ),
            if (isActive && isUpcoming && !event.isExpired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Upcoming',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2F5EA8),
                  ),
                ),
              ),
            if (isActive && isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5F2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B7D69),
                  ),
                ),
              ),
            IconButton(
              onPressed: submitting ? null : () => onEditEvent(event),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              onPressed: submitting ? null : () => onDeleteEvent(event),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTapEvent(event),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 620;
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty ? 'Untitled Event' : title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(subtitleText),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title.isEmpty ? 'Untitled Event' : title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(subtitleText),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        actions,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
