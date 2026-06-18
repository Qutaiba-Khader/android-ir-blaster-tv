import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';

/// Signal Tester (spec §5.6): 3 tool cards. Each opens the existing diagnostic
/// screen (IR Finder / Learning / Universal power-off).
class TesterScreen extends StatelessWidget {
  const TesterScreen({
    super.key,
    required this.gridView,
    required this.onFindCode,
    required this.onLearning,
    required this.onUniversalPower,
  });

  final bool gridView;
  final VoidCallback onFindCode;
  final VoidCallback onLearning;
  final VoidCallback onUniversalPower;

  @override
  Widget build(BuildContext context) {
    final tools = <_Tool>[
      _Tool('Find a code', 'PICK BRAND + TYPE, STEP THROUGH CANDIDATES WITH A DID-IT-WORK LOOP.',
          AppIcons.findCode, AppColors.toneAudio, onFindCode),
      _Tool('Learning mode', 'CAPTURE IR CODES FROM A REAL PHYSICAL REMOTE.',
          AppIcons.learning, AppColors.toneLearning, onLearning),
      _Tool('Universal power-off', "BLAST EVERY BRAND'S OFF CODE IN SEQUENCE.",
          AppIcons.powerOff, AppColors.error, onUniversalPower),
    ];
    return Padding(
      padding: AppSpacing.screenPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenHeader('DIAGNOSTICS', 'SIGNAL TESTER'),
          const SizedBox(height: 22),
          Expanded(
            child: gridView
                ? Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 580),
                      child: GridView.count(
                        clipBehavior: Clip.none,
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        crossAxisCount: 3,
                        crossAxisSpacing: 22,
                        mainAxisSpacing: 22,
                        childAspectRatio: 1.0,
                        children: [
                          for (var i = 0; i < tools.length; i++)
                            RepaintBoundary(child: _ToolCard(tool: tools[i], entry: i == 0)),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.all(16),
                    itemCount: tools.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) =>
                        RepaintBoundary(child: _ToolRow(tool: tools[i], entry: i == 0)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tool {
  const _Tool(this.name, this.desc, this.icon, this.tone, this.onPressed);
  final String name;
  final String desc;
  final IconData icon;
  final Color tone;
  final VoidCallback onPressed;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, this.entry = false});
  final _Tool tool;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: tool.onPressed,
      entry: entry,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleList,
      fill: tool.tone,
      fillFocused: tool.tone,
      restShadow: AppShadows.lg,
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.ink, width: 3),
              borderRadius: BorderRadius.circular(AppRadii.r16),
            ),
            alignment: Alignment.center,
            child: Sym(tool.icon, size: AppIconSizes.toolCard, color: AppColors.ink),
          ),
          const Spacer(),
          Text(tool.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.drillHeader.copyWith(fontSize: 30, color: AppColors.ink)),
          const SizedBox(height: 10),
          Text(tool.desc, style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
        ],
      ),
    );
  }
}

/// List-row variant of a tester tool.
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, this.entry = false});
  final _Tool tool;
  final bool entry;
  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: tool.onPressed,
      entry: entry,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleList,
      fill: tool.tone,
      fillFocused: tool.tone,
      restShadow: AppShadows.md,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.ink, width: 3),
              borderRadius: BorderRadius.circular(AppRadii.r13),
            ),
            alignment: Alignment.center,
            child: Sym(tool.icon, size: AppIconSizes.settingsRow, color: AppColors.ink),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.name, style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(tool.desc, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Sym(AppIcons.chevron, size: AppIconSizes.headerBtn, color: AppColors.ink),
        ],
      ),
    );
  }
}
