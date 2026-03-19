class EventDealPricing {
  const EventDealPricing({
    required this.eventTitle,
    required this.discountPercent,
    required this.unitDiscountedUsd,
    required this.unitOriginalUsd,
    required this.quantity,
  });

  final String eventTitle;
  final double discountPercent;
  final double unitDiscountedUsd;
  final double unitOriginalUsd;
  final int quantity;

  double get unitSavingsUsd => _roundUsd(unitOriginalUsd - unitDiscountedUsd);
  double get lineDiscountedUsd => _roundUsd(unitDiscountedUsd * quantity);
  double get lineOriginalUsd => _roundUsd(unitOriginalUsd * quantity);
  double get lineSavingsUsd => _roundUsd(unitSavingsUsd * quantity);
  bool get hasSavings => unitSavingsUsd > 0;
}

class EventDealPricingSummary {
  const EventDealPricingSummary(this.lines);

  final List<EventDealPricing> lines;

  bool get hasDeals => lines.isNotEmpty;
  int get discountedLineCount => lines.length;
  int get discountedItemCount =>
      lines.fold<int>(0, (sum, line) => sum + line.quantity);
  String? get singleEventTitle {
    final titles = lines
        .map((line) => line.eventTitle.trim())
        .where((title) => title.isNotEmpty)
        .toSet();
    if (titles.length != 1) {
      return null;
    }
    return titles.first;
  }

  double get totalSavingsUsd => _roundUsd(
    lines.fold<double>(0, (sum, line) => sum + line.lineSavingsUsd),
  );

  String get headlineLabel {
    final title = singleEventTitle;
    if (title != null) {
      return '$title pricing';
    }
    return 'Event pricing';
  }
}

EventDealPricing? resolveEventDealPricing({
  required String eventTitle,
  required double discountPercent,
  required double discountedUnitUsd,
  required int quantity,
}) {
  final cleanTitle = eventTitle.trim();
  final normalizedPercent = discountPercent.clamp(0, 95).toDouble();
  if (cleanTitle.isEmpty ||
      normalizedPercent <= 0 ||
      discountedUnitUsd <= 0 ||
      quantity <= 0) {
    return null;
  }

  final multiplier = 1 - (normalizedPercent / 100);
  if (multiplier <= 0) {
    return null;
  }

  final originalUnitUsd = _roundUsd(discountedUnitUsd / multiplier);
  if (originalUnitUsd <= discountedUnitUsd) {
    return null;
  }

  final pricing = EventDealPricing(
    eventTitle: cleanTitle,
    discountPercent: normalizedPercent,
    unitDiscountedUsd: _roundUsd(discountedUnitUsd),
    unitOriginalUsd: originalUnitUsd,
    quantity: quantity,
  );
  if (!pricing.hasSavings) {
    return null;
  }
  return pricing;
}

EventDealPricingSummary summarizeEventDealPricing(
  Iterable<EventDealPricing> source,
) {
  return EventDealPricingSummary(List<EventDealPricing>.unmodifiable(source));
}

double _roundUsd(double value) => double.parse(value.toStringAsFixed(2));
