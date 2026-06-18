import 'package:flutter/material.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/remote.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/dotted_box.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/hardware_banner.dart';

/// Remotes (home) — spec §5.1. The WHOLE page scrolls as one: the header (title +
/// search/toggle/count) is the first sliver, so it scrolls away with the grid
/// rather than staying pinned. dpad auto-scrolls focus into view, and UP from the
/// top row reaches the header controls. Reads the real `remotes` list.
class RemotesScreen extends StatelessWidget {
  const RemotesScreen({
    super.key,
    required this.showBanner,
    required this.gridView,
    required this.onToggleView,
    required this.onOpenRemote,
    required this.onAddRemote,
    required this.onSearch,
    required this.onHowItWorks,
    required this.onOpenSettings,
    required this.onDismissBanner,
  });

  final bool showBanner;
  final bool gridView;
  final VoidCallback onToggleView;
  final ValueChanged<Remote> onOpenRemote;
  final VoidCallback onAddRemote;
  final VoidCallback onSearch;
  final VoidCallback onHowItWorks;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismissBanner;

  @override
  Widget build(BuildContext context) {
    final grid = gridView;
    final pad = AppSpacing.screenPad;
    return ValueListenableBuilder<int>(
      valueListenable: remotesRevision,
      builder: (context, _, __) {
        final items = remotes;
        return CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            // Header scrolls WITH the content (not pinned).
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 22),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBanner) ...[
                      HardwareBanner(
                        onHowItWorks: onHowItWorks,
                        onSettings: onOpenSettings,
                        onDismiss: onDismissBanner,
                      ),
                      const SizedBox(height: 24),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Expanded(child: ScreenHeader('CONTROL SURFACE — TV', 'REMOTES')),
                        _SearchPill(onPressed: onSearch),
                        const SizedBox(width: 14),
                        _SegToggle(grid: grid, onChanged: (_) => onToggleView()),
                        const SizedBox(width: 14),
                        _CountPill(count: items.length),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
              sliver: grid
                  ? _RemoteSliverGrid(items: items, onOpen: onOpenRemote, onAdd: onAddRemote)
                  : _RemoteSliverList(items: items, onOpen: onOpenRemote, onAdd: onAddRemote),
            ),
          ],
        );
      },
    );
  }
}

class _RemoteSliverGrid extends StatelessWidget {
  const _RemoteSliverGrid({required this.items, required this.onOpen, required this.onAdd});
  final List<Remote> items;
  final ValueChanged<Remote> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: AppSizes.remoteCardH,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i == items.length) {
            return _AddTile(onPressed: onAdd, entry: items.isEmpty);
          }
          return RepaintBoundary(
            child: _RemoteCard(
              remote: items[i], index: i,
              onPressed: () => onOpen(items[i]),
              entry: i == 0,
            ),
          );
        },
        childCount: items.length + 1,
      ),
    );
  }
}

class _RemoteSliverList extends StatelessWidget {
  const _RemoteSliverList({required this.items, required this.onOpen, required this.onAdd});
  final List<Remote> items;
  final ValueChanged<Remote> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final child = (i == items.length)
              ? _AddTile(onPressed: onAdd, short: true, entry: items.isEmpty)
              : RepaintBoundary(
                  child: _RemoteRow(
                      remote: items[i], index: i, onPressed: () => onOpen(items[i]), entry: i == 0),
                );
          return Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
        },
        childCount: items.length + 1,
      ),
    );
  }
}

class _RemoteCard extends StatelessWidget {
  const _RemoteCard({required this.remote, required this.index, required this.onPressed, this.entry = false});
  final Remote remote;
  final int index;
  final VoidCallback onPressed;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleCard,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(csRemoteGlyph(index), tone: csTone(index), dim: 60, radius: AppRadii.r14, iconSize: AppIconSizes.cardChip),
          const Spacer(),
          Text(remote.name.isEmpty ? 'REMOTE' : remote.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitle),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('IR REMOTE', style: AppType.meta),
              const Spacer(),
              TagPill('${remote.buttons.length} KEYS'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RemoteRow extends StatelessWidget {
  const _RemoteRow({required this.remote, required this.index, required this.onPressed, this.entry = false});
  final Remote remote;
  final int index;
  final VoidCallback onPressed;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleList,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
      child: Row(
        children: [
          IconChip(csRemoteGlyph(index), tone: csTone(index), dim: 56, radius: AppRadii.r13, iconSize: AppIconSizes.cardChip),
          const SizedBox(width: 18),
          Expanded(
            child: Text(remote.name.isEmpty ? 'REMOTE' : remote.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.listTitle),
          ),
          const SizedBox(width: 12),
          TagPill('${remote.buttons.length} KEYS'),
          const SizedBox(width: 14),
          const Sym(AppIcons.chevron, size: AppIconSizes.headerBtn, color: AppColors.ink),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onPressed, this.short = false, this.entry = false});
  final VoidCallback onPressed;
  final bool short;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r18,
      border: false,
      fill: Colors.transparent,
      fillFocused: AppColors.focusFillDashed,
      restShadow: const <BoxShadow>[],
      child: DottedBox(
        radius: AppRadii.r18,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: short ? 18 : 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Sym(AppIcons.add, size: AppIconSizes.addTile, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text('ADD REMOTE', style: AppType.buttonLabel.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A SINGLE toggle button — shows the current view (GRID/LIST) and flips it on
/// press. One button, not two.
class _SegToggle extends StatelessWidget {
  const _SegToggle({required this.grid, required this.onChanged});
  final bool grid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: () => onChanged(!grid),
      borderRadius: AppRadii.r12,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      restShadow: AppShadows.sm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show the view you'll switch TO (list while in grid, grid while in list).
          Sym(grid ? AppIcons.viewList : AppIcons.gridView,
              size: AppIconSizes.headerCtl, color: AppColors.ink),
          const SizedBox(width: 10),
          Text(grid ? 'LIST' : 'GRID', style: AppType.buttonLabel),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      borderRadius: AppRadii.r12,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      restShadow: AppShadows.sm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.search, size: AppIconSizes.headerCtl, color: AppColors.ink),
          const SizedBox(width: 10),
          Text('SEARCH', style: AppType.buttonLabel),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r12),
        boxShadow: AppShadows.sm,
      ),
      child: Text('${_idx(count)} DEVICES', style: AppType.buttonLabel),
    );
  }
}

String _idx(int n) => n < 10 ? '0$n' : '$n';
