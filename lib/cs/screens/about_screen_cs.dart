import 'package:flutter/material.dart';
import 'package:irblaster_controller/ir_finder/irblaster_db.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// About (Control Surface): app identity + version + license + info rows.
class AboutScreenCs extends StatelessWidget {
  const AboutScreenCs({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final rows = <_Info>[
      _Info('Version', '3.3.0-TV', AppIcons.setAbout, AppColors.toneNeutral),
      _Info('License', 'Apache 2.0', AppIcons.setKeyBinding, AppColors.toneAudio),
      _Info('Transmitter', 'USB IR dongle · Tiqiaa / ElkSmart', AppIcons.setTransmitter, AppColors.toneLearning),
      _Info('Protocols', '33 IR protocol encoders', AppIcons.tester, AppColors.toneAppearance),
      _Info('Design', 'Control Surface · Neo-brutalist TV', AppIcons.setAppearance, AppColors.toneTv),
    ];
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PrimaryFocus(
                builder: (n) => FocusableSurface(
                  onPressed: onBack,
                  focusNode: n,
                  borderRadius: AppRadii.r14,
                  padding: const EdgeInsets.all(15),
                  restShadow: AppShadows.sm,
                  child: const Sym(AppIcons.back, size: AppIconSizes.headerBtn, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eyebrow removed per design — title only.
                    Text('ABOUT', style: AppType.drillHeader),
                  ],
                ),
              ),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  border: Border.all(color: AppColors.ink, width: 3),
                  borderRadius: BorderRadius.circular(AppRadii.r16),
                ),
                alignment: Alignment.center,
                child: const Text('IR', style: TextStyle(
                  fontFamily: AppType.fontDisplay, fontSize: 26, fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: FutureBuilder<String?>(
                  future: IrBlasterDb.instance.dbDate(),
                  builder: (context, snap) => _InfoRow(
                    info: _Info('Code Database',
                        '4,912 brands · updated ${snap.data ?? '…'}',
                        AppIcons.tester, AppColors.toneTv),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView.separated(clipBehavior: Clip.none,
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => RepaintBoundary(child: _InfoRow(info: rows[i])),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const HintStrip('◀ BACK'),
        ],
      ),
    );
  }
}

class _Info {
  const _Info(this.label, this.value, this.icon, this.tone);
  final String label;
  final String value;
  final IconData icon;
  final Color tone;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.info});
  final _Info info;

  @override
  Widget build(BuildContext context) {
    // Focusable so the d-pad can move through the rows (each shows the focus
    // ring); the rows are informational so pressing is a no-op.
    return FocusableSurface(
      onPressed: () {},
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      restShadow: AppShadows.md,
      child: Row(
        children: [
          IconChip(info.icon, tone: info.tone, dim: 56, radius: AppRadii.r13, iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(child: Text(info.label, style: AppType.listTitle)),
          Text(info.value, style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
        ],
      ),
    );
  }
}
