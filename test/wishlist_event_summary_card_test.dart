import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/features/wishlist/presentation/pages/wishlist_overview_screen.dart';

void main() {
  testWidgets('wishlist event summary shows savings and discount context', (
    WidgetTester tester,
  ) async {
    var shopTapped = false;
    var addTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WishlistEventSummaryCard(
            eventTitle: 'Spring Launch',
            matchingItemCount: 2,
            totalSavingsLabel: '\$12.40',
            maxDiscountLabel: 'Up to 20% off',
            timingLabel: 'Ends in 2d 4h',
            onShopEvent: () {
              shopTapped = true;
            },
            onAddMatches: () {
              addTapped = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Spring Launch deal'), findsOneWidget);
    expect(
      find.text('2 saved favorites match this live event.'),
      findsOneWidget,
    );
    expect(find.textContaining('Ends in 2d 4h'), findsOneWidget);
    expect(find.text('Save \$12.40'), findsOneWidget);
    expect(find.text('Up to 20% off'), findsOneWidget);
    expect(find.text('Add matches'), findsOneWidget);

    await tester.tap(find.text('Shop event deals'));
    await tester.pump();

    expect(shopTapped, isTrue);

    await tester.tap(find.text('Add matches'));
    await tester.pump();

    expect(addTapped, isTrue);
  });
}
