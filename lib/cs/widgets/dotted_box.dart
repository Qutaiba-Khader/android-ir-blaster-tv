import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// A dashed rounded-rectangle border (for "ADD REMOTE" / "NEW MACRO" tiles).
/// Painted with a CustomPainter so we avoid pulling in an extra package.
class DottedBox extends StatelessWidget {
  const DottedBox({
    super.key,
    required this.child,
    this.radius = AppRadii.r18,
    this.color = AppColors.dashed,
    this.strokeWidth = AppBorders.width,
    this.dash = 8,
    this.gap = 6,
  });

  final Widget child;
  final double radius;
  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(
        radius: radius, color: color, strokeWidth: strokeWidth, dash: dash, gap: gap),
      child: SizedBox.expand(child: child),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.radius,
    required this.color,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  final double radius;
  final Color color;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset(strokeWidth / 2, strokeWidth / 2) &
          Size(size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = dist + dash;
        canvas.drawPath(
          metric.extractPath(dist, next.clamp(0, metric.length)),
          paint,
        );
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth ||
      old.dash != dash || old.gap != gap || old.radius != radius;
}
