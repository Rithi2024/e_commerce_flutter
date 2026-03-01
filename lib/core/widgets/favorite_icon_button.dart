import 'package:flutter/material.dart';

class FavoriteIcon extends StatelessWidget {
  final bool isFavorite;
  final double? size;
  final Color activeColor;
  final Color? inactiveColor;

  const FavoriteIcon({
    super.key,
    required this.isFavorite,
    this.size,
    this.activeColor = const Color(0xFFD13D3D),
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      isFavorite ? Icons.favorite : Icons.favorite_border,
      size: size,
      color: isFavorite ? activeColor : inactiveColor,
    );
  }
}

class FavoriteIconButton extends StatefulWidget {
  final bool isFavorite;
  final VoidCallback? onPressed;
  final double? size;
  final Color activeColor;
  final Color? inactiveColor;
  final String? tooltip;
  final double pressScale;
  final Duration animationDuration;

  const FavoriteIconButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
    this.size,
    this.activeColor = const Color(0xFFD13D3D),
    this.inactiveColor,
    this.tooltip,
    this.pressScale = 0.88,
    this.animationDuration = const Duration(milliseconds: 110),
  });

  @override
  State<FavoriteIconButton> createState() => _FavoriteIconButtonState();
}

class _FavoriteIconButtonState extends State<FavoriteIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return Listener(
      onPointerDown: enabled ? (_) => _setPressed(true) : null,
      onPointerUp: enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: enabled ? (_) => _setPressed(false) : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: _pressed ? widget.pressScale : 1),
        duration: widget.animationDuration,
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: IconButton(
          onPressed: widget.onPressed,
          tooltip: widget.tooltip,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: FavoriteIcon(
              key: ValueKey<bool>(widget.isFavorite),
              isFavorite: widget.isFavorite,
              size: widget.size,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}
