import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/pricing/event_deal_pricing.dart';

void main() {
  test('resolves original price and savings from active event discount', () {
    final pricing = resolveEventDealPricing(
      eventTitle: 'Spring Launch',
      discountPercent: 20,
      discountedUnitUsd: 41.60,
      quantity: 2,
    );

    expect(pricing, isNotNull);
    expect(pricing!.unitOriginalUsd, 52.00);
    expect(pricing.unitSavingsUsd, 10.40);
    expect(pricing.lineSavingsUsd, 20.80);
    expect(pricing.lineOriginalUsd, 104.00);
  });

  test('returns null for blank or zero discount event pricing', () {
    expect(
      resolveEventDealPricing(
        eventTitle: '',
        discountPercent: 20,
        discountedUnitUsd: 41.60,
        quantity: 1,
      ),
      isNull,
    );
    expect(
      resolveEventDealPricing(
        eventTitle: 'Spring Launch',
        discountPercent: 0,
        discountedUnitUsd: 41.60,
        quantity: 1,
      ),
      isNull,
    );
  });

  test('summarizes mixed event deal lines', () {
    final summary = summarizeEventDealPricing(<EventDealPricing>[
      resolveEventDealPricing(
        eventTitle: 'Spring Launch',
        discountPercent: 20,
        discountedUnitUsd: 41.60,
        quantity: 2,
      )!,
      resolveEventDealPricing(
        eventTitle: 'Spring Launch',
        discountPercent: 15,
        discountedUnitUsd: 17.00,
        quantity: 1,
      )!,
    ]);

    expect(summary.hasDeals, isTrue);
    expect(summary.headlineLabel, 'Spring Launch pricing');
    expect(summary.singleEventTitle, 'Spring Launch');
    expect(summary.discountedLineCount, 2);
    expect(summary.discountedItemCount, 3);
    expect(summary.totalSavingsUsd, 23.80);
  });

  test('summary falls back to generic headline for mixed event titles', () {
    final summary = summarizeEventDealPricing(<EventDealPricing>[
      resolveEventDealPricing(
        eventTitle: 'Spring Launch',
        discountPercent: 20,
        discountedUnitUsd: 41.60,
        quantity: 1,
      )!,
      resolveEventDealPricing(
        eventTitle: 'Weekend Flash',
        discountPercent: 10,
        discountedUnitUsd: 18.00,
        quantity: 1,
      )!,
    ]);

    expect(summary.singleEventTitle, isNull);
    expect(summary.headlineLabel, 'Event pricing');
  });
}
