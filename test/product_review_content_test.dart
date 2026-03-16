import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/features/catalog/presentation/helpers/product_review_content.dart';

void main() {
  test(
    'review helper keeps recent written reviews and prioritizes current user',
    () {
      final reviews = buildProductReviewEntries(
        rows: const <Map<String, dynamic>>[
          <String, dynamic>{
            'user_id': 'user-2',
            'rating': 4,
            'review': 'Comfortable enough for daily wear.',
            'updated_at': '2026-03-12T09:00:00Z',
          },
          <String, dynamic>{
            'user_id': 'user-1',
            'rating': 5,
            'review': 'Perfect fit and better cushioning than expected.',
            'updated_at': '2026-03-10T09:00:00Z',
          },
          <String, dynamic>{
            'user_id': 'user-3',
            'rating': 5,
            'review': '   ',
            'updated_at': '2026-03-14T09:00:00Z',
          },
        ],
        currentUserId: 'user-1',
      );

      expect(reviews.length, 2);
      expect(reviews.first.isCurrentUser, isTrue);
      expect(reviews.first.review, contains('Perfect fit'));
      expect(reviews.last.review, contains('Comfortable'));
    },
  );

  test('review helper keeps all reviews unless a max is requested', () {
    final reviews = buildProductReviewEntries(
      rows: List<Map<String, dynamic>>.generate(8, (index) {
        return <String, dynamic>{
          'user_id': 'user-$index',
          'rating': 5,
          'review': 'Review $index',
          'updated_at': '2026-03-10T0${index % 9}:00:00Z',
        };
      }),
    );

    final limited = buildProductReviewEntries(
      rows: List<Map<String, dynamic>>.generate(8, (index) {
        return <String, dynamic>{
          'user_id': 'user-$index',
          'rating': 5,
          'review': 'Review $index',
          'updated_at': '2026-03-10T0${index % 9}:00:00Z',
        };
      }),
      maxEntries: 3,
    );

    expect(reviews.length, 8);
    expect(limited.length, 3);
  });

  test('rating breakdown counts stars and written reviews', () {
    final breakdown = buildProductRatingBreakdown(const <Map<String, dynamic>>[
      <String, dynamic>{'rating': 5, 'review': 'Excellent'},
      <String, dynamic>{'rating': 5, 'review': ''},
      <String, dynamic>{'rating': 4, 'review': 'Very good'},
      <String, dynamic>{'rating': 2, 'review': 'Not for me'},
      <String, dynamic>{'rating': 0, 'review': 'Ignored'},
    ]);

    expect(breakdown.totalRatings, 4);
    expect(breakdown.writtenReviewCount, 3);
    expect(breakdown.countFor(5), 2);
    expect(breakdown.countFor(4), 1);
    expect(breakdown.countFor(2), 1);
    expect(breakdown.fractionFor(5), 0.5);
  });

  test('review filter and sort helper supports star and owner filters', () {
    final reviews = <ProductReviewEntry>[
      ProductReviewEntry(
        rating: 4,
        review: 'Solid everyday pair.',
        updatedAt: DateTime.utc(2026, 3, 10),
        isCurrentUser: false,
      ),
      ProductReviewEntry(
        rating: 5,
        review: 'Best purchase this month.',
        updatedAt: DateTime.utc(2026, 3, 12),
        isCurrentUser: true,
      ),
      ProductReviewEntry(
        rating: 2,
        review: 'Sizing felt off.',
        updatedAt: DateTime.utc(2026, 3, 11),
        isCurrentUser: false,
      ),
    ];

    final highest = filterAndSortProductReviews(
      reviews: reviews,
      sortOption: ProductReviewSortOption.highestRated,
    );
    final currentUserOnly = filterAndSortProductReviews(
      reviews: reviews,
      currentUserOnly: true,
    );
    final fourStarOnly = filterAndSortProductReviews(
      reviews: reviews,
      exactRating: 4,
    );

    expect(highest.map((entry) => entry.rating), <int>[5, 4, 2]);
    expect(currentUserOnly.length, 1);
    expect(currentUserOnly.first.isCurrentUser, isTrue);
    expect(fourStarOnly.length, 1);
    expect(fourStarOnly.first.review, contains('Solid'));
  });

  test('review timestamp formatter supports relative and absolute labels', () {
    final now = DateTime.utc(2026, 3, 16, 12);

    expect(
      formatProductReviewTimestamp(DateTime.utc(2026, 3, 16, 11, 30), now: now),
      '30m ago',
    );
    expect(
      formatProductReviewTimestamp(DateTime.utc(2026, 3, 15, 12), now: now),
      '1d ago',
    );
    expect(
      formatProductReviewTimestamp(DateTime.utc(2026, 3, 1, 12), now: now),
      'Mar 1, 2026',
    );
  });
}
