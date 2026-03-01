import 'package:flutter/material.dart';

class Brand {
  static const name = 'MarketFlow';
  static const tagline = 'Sell smart, move fast';
}

class BrandLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const BrandLogo({super.key, this.size = 38, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/brand/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              Brand.name,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              Brand.tagline,
              style: TextStyle(fontSize: 11, color: Color(0xFF586063)),
            ),
          ],
        ),
      ],
    );
  }
}
