import 'package:flutter/material.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';

/// Settings (spec §5.9): section rows (chip · title+sub · tag pill · chevron).
/// Each row opens the existing settings surface. The transmitter row's pill
/// reflects real capabilities.
class CsSettingsScreen extends StatelessWidget {
  const CsSettingsScreen({super.key, required this.gridView, required this.caps, required this.onOpenRow});

  final bool gridView;
  final IrTransmitterCapabilities? caps;
  final ValueChanged<int> onOpenRow;

  @override
  Widget build(BuildContext context) {
    final txValue = csHasTransmitter(caps) ? 'READY' : 'NONE';
    final txError = !csHasTransmitter(caps);
    final rows = <_Row>[
      _Row('Transmitter & hardware', 'USB IR dongle · Tiqiaa / ElkSmart', txValue,
          AppIcons.setTransmitter, AppColors.toneLearning, error: txError),
      _Row('Backup & restore', 'Export / import all data as JSON', 'JSON',
          AppIcons.setBackup, AppColors.toneTv),
      _Row('About', 'Version 3.3.0-TV · Apache 2.0', 'v3.3',
          AppIcons.setAbout, AppColors.toneNeutral),
    ];
    return Padding(
      padding: AppSpacing.screenPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader('CONFIGURATION', 'SETTINGS'),
          const SizedBox(height: 22),
          Expanded(
            child: gridView
                ? GridView.builder(
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 196,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 22,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => RepaintBoundary(
                      child: _SettingCard(row: rows[i], onPressed: () => onOpenRow(i), entry: i == 0),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: ListView.separated(
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, i) => RepaintBoundary(
                          child: _SettingRow(row: rows[i], onPressed: () => onOpenRow(i), entry: i == 0),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(this.title, this.desc, this.value, this.icon, this.tone, {this.error = false});
  final String title;
  final String desc;
  final String value;
  final IconData icon;
  final Color tone;
  final bool error;
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.row, required this.onPressed, this.entry = false});
  final _Row row;
  final VoidCallback onPressed;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          IconChip(row.icon, tone: row.tone, dim: 56, radius: AppRadii.r13, iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(row.desc, style: AppType.meta),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TagPill(
            row.value,
            fill: row.error ? AppColors.error : AppColors.surface,
            textColor: AppColors.ink,
          ),
          const SizedBox(width: 14),
          const Sym(AppIcons.chevron, size: AppIconSizes.headerBtn, color: AppColors.ink),
        ],
      ),
    );
  }
}

/// Grid-card variant of a settings row.
class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.row, required this.onPressed, this.entry = false});
  final _Row row;
  final VoidCallback onPressed;
  final bool entry;
  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleCard,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(row.icon, tone: row.tone, dim: 52, radius: AppRadii.r13, iconSize: AppIconSizes.settingsRow),
              const Spacer(),
              TagPill(row.value,
                  fill: row.error ? AppColors.error : AppColors.surface, textColor: AppColors.ink),
            ],
          ),
          const Spacer(),
          Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.listTitle),
          const SizedBox(height: 4),
          Text(row.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta),
        ],
      ),
    );
  }
}
