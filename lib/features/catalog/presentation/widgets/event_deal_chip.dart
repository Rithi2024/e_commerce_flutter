import 'package:flutter/material.dart';

String formatEventDealLabel(String eventTitle) {
  final cleanTitle = eventTitle.trim();
  if (cleanTitle.isEmpty) {
    return 'Event deal';
  }
  return '$cleanTitle deal';
}

class EventDealChip extends StatelessWidget {
  final String eventTitle;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const EventDealChip({
    super.key,
    required this.eventTitle,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = foregroundColor.withValues(alpha: 0.12);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: [
          BoxShadow(
            color: foregroundColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: fontSize + 8,
            height: fontSize + 8,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.bolt_rounded,
              size: fontSize,
              color: foregroundColor,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              formatEventDealLabel(eventTitle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
