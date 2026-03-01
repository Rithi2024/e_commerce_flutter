import 'package:flutter/material.dart';

class AdminOrdersFilterPanel extends StatelessWidget {
  const AdminOrdersFilterPanel({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.orderStatusFilter,
    required this.orderDeliveryFilter,
    required this.orderSearchFilter,
    required this.orderFilterController,
    required this.orderStatuses,
    required this.orderDeliveryTypes,
    required this.filteredOrdersCount,
    required this.totalOrdersCount,
    this.canExportOrders = true,
    required this.exportingOrders,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onStatusChanged,
    required this.onDeliveryChanged,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onResetFilters,
    required this.onExportOrders,
    required this.formatDateShort,
    required this.statusLabel,
    required this.deliveryTypeLabel,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final String orderStatusFilter;
  final String orderDeliveryFilter;
  final String orderSearchFilter;
  final TextEditingController orderFilterController;
  final List<String> orderStatuses;
  final List<String> orderDeliveryTypes;
  final int filteredOrdersCount;
  final int totalOrdersCount;
  final bool canExportOrders;
  final bool exportingOrders;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onDeliveryChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onResetFilters;
  final VoidCallback onExportOrders;
  final String Function(DateTime?) formatDateShort;
  final String Function(String) statusLabel;
  final String Function(dynamic) deliveryTypeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary Export',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              if (compact) {
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onPickFromDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text('From: ${formatDateShort(fromDate)}'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onPickToDate,
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('To: ${formatDateShort(toDate)}'),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickFromDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text('From: ${formatDateShort(fromDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickToDate,
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text('To: ${formatDateShort(toDate)}'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              if (compact) {
                return Column(
                  children: [
                    _statusDropdown(),
                    const SizedBox(height: 8),
                    _deliveryDropdown(),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _statusDropdown()),
                  const SizedBox(width: 8),
                  Expanded(child: _deliveryDropdown()),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: orderFilterController,
            decoration: InputDecoration(
              labelText: 'Search all fields',
              hintText: 'Order ID, email, status, address...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: orderSearchFilter.isEmpty
                  ? null
                  : IconButton(
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Showing $filteredOrdersCount of $totalOrdersCount orders',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              OutlinedButton(
                onPressed: onResetFilters,
                child: const Text('Reset Filters'),
              ),
              if (canExportOrders)
                ElevatedButton.icon(
                  onPressed: exportingOrders ? null : onExportOrders,
                  icon: exportingOrders
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    exportingOrders ? 'Exporting...' : 'Download Excel',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('status_filter_$orderStatusFilter'),
      isExpanded: true,
      isDense: true,
      initialValue: orderStatusFilter,
      decoration: const InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(),
      ),
      items: orderStatuses
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(
                statusLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) => orderStatuses
          .map(
            (value) => Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value == 'all' ? 'All' : statusLabel(value)),
              ),
            ),
          )
          .toList(),
      onChanged: onStatusChanged,
    );
  }

  Widget _deliveryDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey<String>('delivery_filter_$orderDeliveryFilter'),
      isExpanded: true,
      isDense: true,
      initialValue: orderDeliveryFilter,
      decoration: const InputDecoration(
        labelText: 'Delivery',
        border: OutlineInputBorder(),
      ),
      items: orderDeliveryTypes
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(
                value == 'all' ? 'All' : deliveryTypeLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) => orderDeliveryTypes
          .map(
            (value) => Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value == 'all' ? 'All' : deliveryTypeLabel(value)),
              ),
            ),
          )
          .toList(),
      onChanged: onDeliveryChanged,
    );
  }
}
