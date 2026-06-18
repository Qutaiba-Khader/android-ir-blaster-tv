import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import 'atoms.dart';
import 'focusable_surface.dart';

/// Home "No IR transmitter" banner (spec §8). Shown only when no transmitter is
/// available. HOW IT WORKS + SETTINGS actions + dismiss.
class HardwareBanner extends StatelessWidget {
  const HardwareBanner({
    super.key,
    required this.onHowItWorks,
    required this.onSettings,
    required this.onDismiss,
  });

  final VoidCallback onHowItWorks;
  final VoidCallback onSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        border: Border.all(color: AppColors.ink, width: AppBorders.inner),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        boxShadow: AppShadows.md,
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.warning,
              border: Border.all(color: AppColors.ink, width: 3),
              borderRadius: BorderRadius.circular(AppRadii.r13),
            ),
            alignment: Alignment.center,
            child: const Sym(AppIcons.warning, size: AppIconSizes.bannerChip, color: AppColors.ink),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No IR transmitter', style: AppType.rowTitle),
                const SizedBox(height: 4),
                Text('PLUG IN A USB IR DONGLE TO START BLASTING CODES',
                    style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BannerButton(label: 'HOW IT WORKS', onPressed: onHowItWorks, filled: true),
          const SizedBox(width: 10),
          _BannerButton(label: 'SETTINGS', onPressed: onSettings),
          const SizedBox(width: 10),
          FocusableSurface(
            onPressed: onDismiss,
            borderRadius: AppRadii.r12,
            padding: const EdgeInsets.all(11),
            restShadow: AppShadows.sm,
            child: const Sym(AppIcons.close, size: AppIconSizes.status, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({required this.label, required this.onPressed, this.filled = false});
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      borderRadius: AppRadii.r12,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      fill: filled ? AppColors.ink : AppColors.warningSurface,
      restShadow: AppShadows.sm,
      child: Text(label, style: AppType.buttonLabel.copyWith(
        color: filled ? AppColors.warningSurface : AppColors.ink)),
    );
  }
}
