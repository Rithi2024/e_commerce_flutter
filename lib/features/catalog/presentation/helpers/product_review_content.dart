class ProductReviewEntry {
  const ProductReviewEntry({
    required this.rating,
    required this.review,
    required this.updatedAt,
    required this.isCurrentUser,
  });

  final int rating;
  final String review;
  final DateTime? updatedAt;
  final bool isCurrentUser;
}

class ProductRatingBreakdown {
  const ProductRatingBreakdown({
    this.countsByStar = const <int, int>{},
    this.totalRatings = 0,
    this.writtenReviewCount = 0,
  });

  final Map<int, int> countsByStar;
  final int totalRatings;
  final int writtenReviewCount;

  int countFor(int stars) => countsByStar[stars] ?? 0;

  double fractionFor(int stars) {
    if (totalRatings <= 0) {
      return 0;
    }
    return countFor(stars) / totalRatings;
  }
}

enum ProductReviewSortOption { recent, highestRated, lowestRated }

extension ProductReviewSortOptionX on ProductReviewSortOption {
  String get label {
    switch (this) {
      case ProductReviewSortOption.recent:
        return 'Most recent';
      case ProductReviewSortOption.highestRated:
        return 'Highest rated';
      case ProductReviewSortOption.lowestRated:
        return 'Lowest rated';
    }
  }
}

List<ProductReviewEntry> buildProductReviewEntries({
  required Iterable<Map<String, dynamic>> rows,
  String? currentUserId,
  int? maxEntries,
}) {
  final normalizedCurrentUserId = (currentUserId ?? '').trim();
  final reviews = <ProductReviewEntry>[];

  for (final row in rows) {
    final review = (row['review'] ?? '').toString().trim();
    final rating = _toInt(row['rating']);
    if (review.isEmpty || rating < 1 || rating > 5) {
      continue;
    }

    final updatedAt = DateTime.tryParse(
      (row['updated_at'] ?? '').toString().trim(),
    )?.toLocal();
    final reviewUserId = (row['user_id'] ?? '').toString().trim();
    reviews.add(
      ProductReviewEntry(
        rating: rating,
        review: review,
        updatedAt: updatedAt,
        isCurrentUser:
            normalizedCurrentUserId.isNotEmpty &&
            reviewUserId == normalizedCurrentUserId,
      ),
    );
  }

  reviews.sort((a, b) {
    if (a.isCurrentUser != b.isCurrentUser) {
      return a.isCurrentUser ? -1 : 1;
    }
    final aTimestamp = a.updatedAt?.millisecondsSinceEpoch ?? -1;
    final bTimestamp = b.updatedAt?.millisecondsSinceEpoch ?? -1;
    final timestampCompare = bTimestamp.compareTo(aTimestamp);
    if (timestampCompare != 0) {
      return timestampCompare;
    }
    return b.rating.compareTo(a.rating);
  });

  if (maxEntries == null || reviews.length <= maxEntries) {
    return List<ProductReviewEntry>.unmodifiable(reviews);
  }
  return List<ProductReviewEntry>.unmodifiable(reviews.take(maxEntries));
}

ProductRatingBreakdown buildProductRatingBreakdown(
  Iterable<Map<String, dynamic>> rows,
) {
  final countsByStar = <int, int>{};
  var totalRatings = 0;
  var writtenReviewCount = 0;

  for (final row in rows) {
    final rating = _toInt(row['rating']);
    final review = (row['review'] ?? '').toString().trim();
    final hasValidRating = rating >= 1 && rating <= 5;
    if (hasValidRating) {
      countsByStar[rating] = (countsByStar[rating] ?? 0) + 1;
      totalRatings += 1;
    }
    if (hasValidRating && review.isNotEmpty) {
      writtenReviewCount += 1;
    }
  }

  return ProductRatingBreakdown(
    countsByStar: Map<int, int>.unmodifiable(countsByStar),
    totalRatings: totalRatings,
    writtenReviewCount: writtenReviewCount,
  );
}

List<ProductReviewEntry> filterAndSortProductReviews({
  required Iterable<ProductReviewEntry> reviews,
  ProductReviewSortOption sortOption = ProductReviewSortOption.recent,
  int? exactRating,
  bool currentUserOnly = false,
  int? maxEntries,
}) {
  final filtered = reviews.where((entry) {
    final ratingOk = exactRating == null || entry.rating == exactRating;
    final currentUserOk = !currentUserOnly || entry.isCurrentUser;
    return ratingOk && currentUserOk;
  }).toList();

  filtered.sort((a, b) {
    switch (sortOption) {
      case ProductReviewSortOption.recent:
        final aTimestamp = a.updatedAt?.millisecondsSinceEpoch ?? -1;
        final bTimestamp = b.updatedAt?.millisecondsSinceEpoch ?? -1;
        final timestampCompare = bTimestamp.compareTo(aTimestamp);
        if (timestampCompare != 0) {
          return timestampCompare;
        }
        return b.rating.compareTo(a.rating);
      case ProductReviewSortOption.highestRated:
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) {
          return ratingCompare;
        }
        final aTimestamp = a.updatedAt?.millisecondsSinceEpoch ?? -1;
        final bTimestamp = b.updatedAt?.millisecondsSinceEpoch ?? -1;
        return bTimestamp.compareTo(aTimestamp);
      case ProductReviewSortOption.lowestRated:
        final ratingCompare = a.rating.compareTo(b.rating);
        if (ratingCompare != 0) {
          return ratingCompare;
        }
        final aTimestamp = a.updatedAt?.millisecondsSinceEpoch ?? -1;
        final bTimestamp = b.updatedAt?.millisecondsSinceEpoch ?? -1;
        return bTimestamp.compareTo(aTimestamp);
    }
  });

  if (maxEntries == null || filtered.length <= maxEntries) {
    return List<ProductReviewEntry>.unmodifiable(filtered);
  }
  return List<ProductReviewEntry>.unmodifiable(filtered.take(maxEntries));
}

String formatProductReviewTimestamp(DateTime? updatedAt, {DateTime? now}) {
  if (updatedAt == null) {
    return 'Recently';
  }

  final reference = now ?? DateTime.now();
  final localReference = reference.isUtc ? reference.toLocal() : reference;
  final diff = localReference.difference(updatedAt);

  if (diff.isNegative) {
    return _formatAbsoluteDate(updatedAt);
  }
  if (diff.inMinutes < 1) {
    return 'Just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return _formatAbsoluteDate(updatedAt);
}

int _toInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

String _formatAbsoluteDate(DateTime value) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[value.month - 1];
  return '$month ${value.day}, ${value.year}';
}
