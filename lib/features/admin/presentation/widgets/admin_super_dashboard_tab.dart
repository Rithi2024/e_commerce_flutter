import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:marketflow/core/auth/account_role.dart';
import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:marketflow/features/admin/domain/entities/admin_profile_model.dart';
import 'package:marketflow/features/catalog/domain/entities/product_model.dart';

class SuperAdminDashboardTab extends StatelessWidget {
  const SuperAdminDashboardTab({
    super.key,
    required this.orders,
    required this.products,
    required this.profiles,
    required this.loadingOrders,
    required this.loadingProducts,
    required this.loadingUsers,
  });

  final List<AdminOrder> orders;
  final List<Product> products;
  final List<AdminProfile> profiles;
  final bool loadingOrders;
  final bool loadingProducts;
  final bool loadingUsers;

  static const List<_StatusBand> _statusBands = <_StatusBand>[
    _StatusBand(
      key: 'order_received',
      label: 'Order Received',
      color: Color(0xFF3A86FF),
    ),
    _StatusBand(
      key: 'order_packed',
      label: 'Order Packed',
      color: Color(0xFF00A9A5),
    ),
    _StatusBand(
      key: 'ready_for_pickup',
      label: 'Ready for Pickup',
      color: Color(0xFFF39C12),
    ),
    _StatusBand(
      key: 'out_for_delivery',
      label: 'Out for Delivery',
      color: Color(0xFF9B5DE5),
    ),
    _StatusBand(key: 'delivered', label: 'Delivered', color: Color(0xFF2E9F57)),
    _StatusBand(key: 'cancelled', label: 'Cancelled', color: Color(0xFFE53935)),
  ];

  @override
  Widget build(BuildContext context) {
    if (loadingOrders || loadingProducts || loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    final statusCounts = _buildStatusCounts(orders);
    final weeklySeries = _buildLastSevenDaysSeries(orders);
    final totalOrders = orders.length;
    final deliveredOrders = statusCounts['delivered'] ?? 0;
    final completionRate = totalOrders == 0
        ? 0.0
        : deliveredOrders / totalOrders;
    final netRevenue = orders.fold<double>(0, (sum, order) {
      final status = _normalizeStatus(order.status);
      if (status == 'cancelled') return sum;
      return sum + order.total;
    });
    final staffCount = profiles.where((profile) {
      return !AccountRole.fromRaw(profile.accountType).isCustomer;
    }).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingleColumn = constraints.maxWidth < 980;
        final metricCardWidth = isSingleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        final statusPanel = _DashboardPanel(
          title: 'Order Status Graph',
          subtitle: 'Distribution by delivery stage',
          child: _StatusGraph(counts: statusCounts, bands: _statusBands),
        );
        final weeklyPanel = _DashboardPanel(
          title: '7-Day Orders Graph',
          subtitle: 'Order volume over the last week',
          child: _WeeklyOrdersGraph(series: weeklySeries),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: metricCardWidth,
                    child: _MetricCard(
                      title: 'Total Orders',
                      value: '$totalOrders',
                      tone: const Color(0xFF0B7D69),
                      helper: 'Delivered ${_formatPercent(completionRate)}',
                    ),
                  ),
                  SizedBox(
                    width: metricCardWidth,
                    child: _MetricCard(
                      title: 'Net Revenue',
                      value: _formatCurrency(netRevenue),
                      tone: const Color(0xFF1E88E5),
                      helper: 'Excludes cancelled orders',
                    ),
                  ),
                  SizedBox(
                    width: metricCardWidth,
                    child: _MetricCard(
                      title: 'Products',
                      value: '${products.length}',
                      tone: const Color(0xFF7E57C2),
                      helper: 'Current catalog size',
                    ),
                  ),
                  SizedBox(
                    width: metricCardWidth,
                    child: _MetricCard(
                      title: 'Staff Accounts',
                      value: '$staffCount',
                      tone: const Color(0xFFF57C00),
                      helper: 'All non-customer profiles',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isSingleColumn) ...[
                statusPanel,
                const SizedBox(height: 12),
                weeklyPanel,
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: statusPanel),
                    const SizedBox(width: 12),
                    Expanded(child: weeklyPanel),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static Map<String, int> _buildStatusCounts(List<AdminOrder> orders) {
    final counts = <String, int>{for (final band in _statusBands) band.key: 0};

    for (final order in orders) {
      final status = _normalizeStatus(order.status);
      if (!counts.containsKey(status)) continue;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  static List<_DailyOrdersPoint> _buildLastSevenDaysSeries(
    List<AdminOrder> orders,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byDay = <DateTime, int>{};

    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      byDay[day] = 0;
    }

    for (final order in orders) {
      final createdAt = order.createdAt;
      if (createdAt == null) continue;
      final createdDay = DateTime(
        createdAt.year,
        createdAt.month,
        createdAt.day,
      );
      if (!byDay.containsKey(createdDay)) continue;
      byDay[createdDay] = (byDay[createdDay] ?? 0) + 1;
    }

    return byDay.entries
        .map((entry) => _DailyOrdersPoint(day: entry.key, count: entry.value))
        .toList();
  }

  static String _normalizeStatus(String status) {
    final value = status.trim().toLowerCase();
    if (value == 'pending' || value == 'paid') return 'order_received';
    if (value == 'shipped') return 'out_for_delivery';
    return value;
  }

  static String _formatCurrency(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts.first;
    final decimals = parts.last;
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final reverseIndex = whole.length - i;
      buffer.write(whole[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return '\$${buffer.toString()}.$decimals';
  }

  static String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.helper,
    required this.tone,
  });

  final String title;
  final String value;
  final String helper;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF43504B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E4DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF5E6E67)),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatusGraph extends StatelessWidget {
  const _StatusGraph({required this.counts, required this.bands});

  final Map<String, int> counts;
  final List<_StatusBand> bands;

  @override
  Widget build(BuildContext context) {
    final maxCount = bands.fold<int>(0, (value, band) {
      return math.max(value, counts[band.key] ?? 0);
    });
    final safeMax = math.max(1, maxCount);

    return Column(
      children: bands.map((band) {
        final count = counts[band.key] ?? 0;
        final ratio = count / safeMax;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      band.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF3E4D47),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  backgroundColor: band.color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(band.color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _WeeklyOrdersGraph extends StatelessWidget {
  const _WeeklyOrdersGraph({required this.series});

  final List<_DailyOrdersPoint> series;

  @override
  Widget build(BuildContext context) {
    final maxCount = series.fold<int>(0, (value, point) {
      return math.max(value, point.count);
    });
    final safeMax = math.max(1, maxCount);

    return SizedBox(
      height: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: series.map((point) {
          final ratio = point.count / safeMax;
          final barHeight = 22 + (ratio * 112);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${point.count}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF51635B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFF0B7D69,
                      ).withValues(alpha: point.count == 0 ? 0.2 : 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dayLabel(point.day),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF4F5C57),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    switch (day.weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      default:
        return 'Sun';
    }
  }
}

class _StatusBand {
  const _StatusBand({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}

class _DailyOrdersPoint {
  const _DailyOrdersPoint({required this.day, required this.count});

  final DateTime day;
  final int count;
}
