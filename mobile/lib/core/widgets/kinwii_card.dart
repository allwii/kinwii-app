import 'package:flutter/material.dart';

class KinwiiCard extends StatelessWidget {
  const KinwiiCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);
    final decoration = BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: borderRadius,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: Ink(
          width: double.infinity,
          decoration: decoration,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: decoration,
      child: child,
    );
  }
}
