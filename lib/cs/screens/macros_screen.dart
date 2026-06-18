import 'package:flutter/material.dart';
import 'package:irblaster_controller/models/timed_macro.dart';
import 'package:irblaster_controller/state/macros_state.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/dotted_box.dart';
import '../widgets/focusable_surface.dart';

/// Macros (spec §5.3): list of automations, each with a RUN button + a dashed
/// NEW MACRO tile. Reads the real `macros` list; opening/running/creating is
/// delegated to the existing macro screens.
class MacrosScreen extends StatelessWidget {
  const MacrosScreen({
    super.key,
    required this.gridView,
    required this.onEdit,
    required this.onRun,
    required this.onNew,
  });

  final bool gridView;
  final ValueChanged<TimedMacro> onEdit;
  final ValueChanged<TimedMacro> onRun;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screenPad;
    return ValueListenableBuilder<int>(
      valueListenable: macrosRevision,
      builder: (context, _, __) {
        final items = macros;
        return CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 22),
              sliver: const SliverToBoxAdapter(child: ScreenHeader('AUTOMATIONS', 'MACROS')),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
              sliver: gridView
                  ? SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 150,
                        crossAxisSpacing: 22,
                        mainAxisSpacing: 22,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i == items.length) return _NewMacroTile(onNew: onNew, entry: items.isEmpty);
                          return RepaintBoundary(
                            child: _MacroCard(
                              macro: items[i], index: i,
                              onRun: () => onRun(items[i]),
                              entry: i == 0,
                            ),
                          );
                        },
                        childCount: items.length + 1,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final child = (i == items.length)
                              ? SizedBox(height: 70, child: _NewMacroTile(onNew: onNew, entry: items.isEmpty))
                              : RepaintBoundary(
                                  child: _MacroRow(
                                    macro: items[i], index: i,
                                    onEdit: () => onEdit(items[i]),
                                    onRun: () => onRun(items[i]),
                                    entry: i == 0,
                                  ),
                                );
                          return Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
                        },
                        childCount: items.length + 1,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.macro,
    required this.index,
    required this.onEdit,
    required this.onRun,
    this.entry = false,
  });

  final TimedMacro macro;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    final scope = macro.remoteName.isEmpty ? 'MULTIPLE DEVICES' : macro.remoteName.toUpperCase();
    return Row(
      children: [
        Expanded(
          child: FocusableSurface(
            onPressed: onEdit,
            entry: entry,
            borderRadius: AppRadii.r16,
            scale: AppFocus.scaleList,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
            child: Row(
              children: [
                IconChip(AppIcons.macMovie, tone: csTone(index), dim: 48, iconSize: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(macro.name.isEmpty ? 'MACRO' : macro.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowTitle),
                      const SizedBox(height: 4),
                      Text('$scope · ${macro.steps.length} STEPS', style: AppType.meta),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: 360,
          child: FocusableSurface(
            onPressed: onRun,
            borderRadius: AppRadii.r16,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Sym(AppIcons.run, size: 20, color: AppColors.ink),
                const SizedBox(width: 10),
                Text('RUN', style: AppType.buttonLabel),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewMacroTile extends StatelessWidget {
  const _NewMacroTile({required this.onNew, this.entry = false});
  final VoidCallback onNew;
  final bool entry;
  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onNew,
      entry: entry,
      borderRadius: AppRadii.r16,
      border: false,
      fill: Colors.transparent,
      fillFocused: AppColors.focusFillDashed,
      restShadow: const <BoxShadow>[],
      child: DottedBox(
        radius: AppRadii.r16,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Sym(AppIcons.add, size: 28, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Text('NEW MACRO', style: AppType.buttonLabel.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid cell for a macro — tap RUNS it (grid is the quick-launch view).
class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.macro, required this.index, required this.onRun, this.entry = false});
  final TimedMacro macro;
  final int index;
  final VoidCallback onRun;
  final bool entry;
  @override
  Widget build(BuildContext context) {
    final scope = macro.remoteName.isEmpty ? 'MULTIPLE DEVICES' : macro.remoteName.toUpperCase();
    return FocusableSurface(
      onPressed: onRun,
      entry: entry,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleCard,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconChip(AppIcons.macMovie, tone: csTone(index), dim: 48, iconSize: 24),
            const Spacer(),
            const Sym(AppIcons.run, size: 24, color: AppColors.ink),
          ]),
          const Spacer(),
          Text(macro.name.isEmpty ? 'MACRO' : macro.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowTitle),
          const SizedBox(height: 4),
          Text('$scope · ${macro.steps.length} STEPS', style: AppType.meta),
        ],
      ),
    );
  }
}
