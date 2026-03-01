import 'package:marketflow/features/admin/domain/entities/admin_order_model.dart';
import 'package:flutter/material.dart';

class AdminOrdersTab extends StatelessWidget {
  const AdminOrdersTab({
    super.key,
    required this.loadingOrders,
    required this.submitting,
    required this.canConfirmCashPayments,
    required this.canUpdateDeliveryStatus,
    required this.totalOrdersCount,
    required this.filteredOrders,
    required this.filterPanel,
    required this.onConfirmCashPayment,
    required this.onUpdateOrderStatus,
    required this.statusUpdateOptionsForOrder,
    required this.deliveryTypeLabel,
    required this.paymentMethodLabel,
    required this.statusLabel,
    required this.formatDateTimeLocal,
    required this.formatMoney,
    this.canUseDeliveryQr = false,
    this.onShowDeliveryQr,
    this.onScanAndAdvanceWithQr,
  });

  final bool loadingOrders;
  final bool submitting;
  final bool canConfirmCashPayments;
  final bool canUpdateDeliveryStatus;
  final int totalOrdersCount;
  final List<AdminOrder> filteredOrders;
  final Widget filterPanel;
  final Future<void> Function(AdminOrder order) onConfirmCashPayment;
  final Future<void> Function(AdminOrder order, String nextStatus)
  onUpdateOrderStatus;
  final List<String> Function(AdminOrder order) statusUpdateOptionsForOrder;
  final String Function(dynamic) deliveryTypeLabel;
  final String Function(dynamic) paymentMethodLabel;
  final String Function(String) statusLabel;
  final String Function(dynamic) formatDateTimeLocal;
  final String Function(double usd) formatMoney;
  final bool canUseDeliveryQr;
  final Future<void> Function(AdminOrder order)? onShowDeliveryQr;
  final Future<void> Function()? onScanAndAdvanceWithQr;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        filterPanel,
        Expanded(
          child: loadingOrders
              ? const Center(child: CircularProgressIndicator())
              : filteredOrders.isEmpty
              ? Center(
                  child: Text(
                    totalOrdersCount == 0
                        ? 'No orders found'
                        : 'No orders match selected filters',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filteredOrders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = filteredOrders[index];
                    final orderId = order.id.toString();
                    final email = order.email;
                    final status = order.status.trim().toLowerCase();
                    final paymentMethodRaw = order.paymentMethod
                        .trim()
                        .toLowerCase();
                    final isCashOnDelivery =
                        paymentMethodRaw == 'cash_on_delivery';
                    final deliveryType = deliveryTypeLabel(order.deliveryType);
                    final paymentMethod = paymentMethodLabel(
                      order.paymentMethod,
                    );
                    final cashPaidConfirmed = order.cashPaidConfirmed;
                    final cashPaidConfirmedAt = order.cashPaidConfirmedAt;
                    final paymentReference = order.paymentReference.trim();
                    final address = order.address;
                    final addressDetails = order.addressDetails.trim();
                    final total = order.total;
                    final createdAt = formatDateTimeLocal(
                      order.createdAt?.toIso8601String(),
                    );
                    final itemsCount = order.items.length;
                    final canConfirmCash =
                        canConfirmCashPayments &&
                        isCashOnDelivery &&
                        !cashPaidConfirmed &&
                        status != 'cancelled';
                    final statusUpdateOptions = canUpdateDeliveryStatus
                        ? statusUpdateOptionsForOrder(order)
                        : const <String>[];

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 430;
                              final statusChip = Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF2F4F6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  statusLabel(status),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF4C5A66),
                                  ),
                                ),
                              );

                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Order #$orderId',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    statusChip,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Order #$orderId',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  statusChip,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          Text('Customer: ${email.isEmpty ? '-' : email}'),
                          const SizedBox(height: 4),
                          Text('Date: $createdAt'),
                          const SizedBox(height: 4),
                          Text('Delivery: $deliveryType'),
                          const SizedBox(height: 4),
                          Text('Payment: $paymentMethod'),
                          if (isCashOnDelivery) ...[
                            const SizedBox(height: 4),
                            Text(
                              cashPaidConfirmed
                                  ? 'Cash Payment: Confirmed'
                                  : 'Cash Payment: Pending confirmation',
                              style: TextStyle(
                                color: cashPaidConfirmed
                                    ? Colors.green.shade700
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (cashPaidConfirmedAt != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Confirmed At: ${formatDateTimeLocal(cashPaidConfirmedAt.toIso8601String())}',
                              ),
                            ],
                          ],
                          if (paymentReference.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Payment Ref: $paymentReference'),
                          ],
                          const SizedBox(height: 4),
                          Text('Items: $itemsCount'),
                          const SizedBox(height: 4),
                          Text(
                            'Total: ${formatMoney(total)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text('Address: ${address.isEmpty ? '-' : address}'),
                          if (addressDetails.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Details: $addressDetails'),
                          ],
                          if (canConfirmCash) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: submitting
                                    ? null
                                    : () => onConfirmCashPayment(order),
                                icon: submitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.payments_outlined),
                                label: Text(
                                  submitting
                                      ? 'Confirming...'
                                      : 'Confirm Cash Payment',
                                ),
                              ),
                            ),
                          ],
                          if (canUseDeliveryQr &&
                              canUpdateDeliveryStatus &&
                              status != 'cancelled') ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed:
                                      submitting || onShowDeliveryQr == null
                                      ? null
                                      : () => onShowDeliveryQr!(order),
                                  icon: const Icon(Icons.qr_code_2_outlined),
                                  label: const Text('Show Delivery QR'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      submitting ||
                                          onScanAndAdvanceWithQr == null
                                      ? null
                                      : onScanAndAdvanceWithQr,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_outlined,
                                  ),
                                  label: const Text('Scan QR to Advance'),
                                ),
                              ],
                            ),
                          ],
                          if (statusUpdateOptions.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: statusUpdateOptions.map((nextStatus) {
                                final confirmDelivery =
                                    nextStatus.trim().toLowerCase() ==
                                    'delivered';
                                if (confirmDelivery) {
                                  return ElevatedButton.icon(
                                    onPressed: submitting
                                        ? null
                                        : () => onUpdateOrderStatus(
                                            order,
                                            nextStatus,
                                          ),
                                    icon: const Icon(Icons.verified_rounded),
                                    label: const Text('Confirm Delivery'),
                                  );
                                }
                                return OutlinedButton.icon(
                                  onPressed: submitting
                                      ? null
                                      : () => onUpdateOrderStatus(
                                          order,
                                          nextStatus,
                                        ),
                                  icon: const Icon(
                                    Icons.local_shipping_outlined,
                                  ),
                                  label: Text(statusLabel(nextStatus)),
                                );
                              }).toList(),
                            ),
                          ],
                          if (submitting &&
                              (canConfirmCash ||
                                  statusUpdateOptions.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
