import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A small Material Symbols Rounded icon with the design's axes baked in
/// (FILL 0, wght 700, opsz 48). Use everywhere instead of a bare Icon().
class Sym extends StatelessWidget {
  const Sym(this.icon, {super.key, this.size = 24, this.color = AppColors.ink, this.fill = 0});
  final IconData icon;
  final double size;
  final Color color;
  final double fill;

  @override
  Widget build(BuildContext context) => Icon(
        icon,
        size: size,
        color: color,
        weight: 700,
        opticalSize: 48,
        fill: fill,
      );
}

/// "// KICKER" section label (Space Mono, accent).
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text('// $text'.toUpperCase(), style: AppType.kicker);
}

/// Screen header: kicker + big Sora title.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.kicker, this.title, {super.key});
  final String kicker;
  final String title;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow/kicker removed per design — title only.
          Text(title.toUpperCase(), style: AppType.screenTitle),
        ],
      );
}

/// Small ink-bordered pill (e.g. "42 KEYS", "DARK", "JSON").
class TagPill extends StatelessWidget {
  const TagPill(this.text, {super.key, this.fill = AppColors.surface, this.textColor = AppColors.ink});
  final String text;
  final Color fill;
  final Color textColor;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: AppColors.ink, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text.toUpperCase(), style: AppType.tagPill.copyWith(color: textColor)),
      );
}

/// Rounded square category chip with an icon (used in cards, rows, tester tools).
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.tone = AppColors.toneNeutral, this.dim = 48, this.radius = 12, this.iconSize = 24});
  final IconData icon;
  final Color tone;
  final double dim;
  final double radius;
  final double iconSize;
  @override
  Widget build(BuildContext context) => Container(
        width: dim,
        height: dim,
        decoration: BoxDecoration(
          color: tone,
          border: Border.all(color: AppColors.ink, width: 3),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Center(child: Sym(icon, size: iconSize, color: AppColors.ink)),
      );
}

/// Bottom hint strip ("◀ NAV · ENTER OPENS · 4PX FOCUS RING").
class HintStrip extends StatelessWidget {
  const HintStrip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(); // hint footer removed app-wide (user request)
}
