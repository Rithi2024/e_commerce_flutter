class ProductRatingSummary {
  final int ratingCount;
  final double averageRating;
  final int reviewCount;

  const ProductRatingSummary({
    required this.ratingCount,
    required this.averageRating,
    this.reviewCount = 0,
  });

  bool get hasRatings => ratingCount > 0;
  bool get hasWrittenReviews => reviewCount > 0;
}
