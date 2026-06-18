import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';

/// Persistent 248 dp left navigation rail (spec §1 / §5). No top tabs, ever.
/// Logo → 4 primary destinations → TOOLS → 4 utility entries → dongle pill.
class CsNavRail extends StatelessWidget {
  const CsNavRail({
    super.key,
    required this.selectedIndex,
    required this.railNodes,
    required this.onPreview,
    required this.caps,
  });

  final int selectedIndex;
  final List<FocusNode> railNodes;
  /// Called when a rail item gains focus → switch the page (live preview).
  final ValueChanged<int> onPreview;
  final IrTransmitterCapabilities? caps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.railWidth,
      decoration: const BoxDecoration(
        color: AppColors.railBackground,
        border: Border(
          right: BorderSide(color: AppColors.railBorder, width: AppBorders.railWidth),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RailHeader(),
          const SizedBox(height: 12),
          _RailItem(
            icon: AppIcons.remotes, label: 'REMOTES', focusNode: railNodes[0],
            selected: selectedIndex == 0, onFocused: () => onPreview(0),
          ),
          _RailItem(
            icon: AppIcons.macros, label: 'MACROS', focusNode: railNodes[1],
            selected: selectedIndex == 1, onFocused: () => onPreview(1),
          ),
          _RailItem(
            icon: AppIcons.tester, label: 'TESTER', focusNode: railNodes[2],
            selected: selectedIndex == 2, onFocused: () => onPreview(2),
          ),
          _RailItem(
            icon: AppIcons.settings, label: 'SETTINGS', focusNode: railNodes[3],
            selected: selectedIndex == 3, onFocused: () => onPreview(3),
          ),
          const Spacer(),
          _DonglePill(caps: caps),
        ],
      ),
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.railBorder, width: AppBorders.inner)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.railLogo,
            height: AppSizes.railLogo,
            decoration: BoxDecoration(
              color: AppColors.accent,
              border: Border.all(color: AppColors.ink, width: 3),
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            alignment: Alignment.center,
            child: const Text('IR', style: TextStyle(
              fontFamily: AppType.fontDisplay, fontSize: 20, fontWeight: FontWeight.w700,
              color: AppColors.ink, height: 1.0)),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Text('CONTROL\nSURFACE', style: TextStyle(
              fontFamily: AppType.fontMono, fontSize: 13, fontWeight: FontWeight.w700,
              letterSpacing: 1.0, height: 1.2, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.onFocused,
    this.selected = false,
    this.util = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onFocused; // gain focus → preview page
  final bool selected;
  final bool util;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final iconSize = util ? AppIconSizes.railUtil : AppIconSizes.railPrimary;
    final labelStyle = (util ? AppType.utilLabel : AppType.navLabel).copyWith(
      color: selected ? Colors.white : AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: FocusableSurface(
        // OK on a header enters the page content (▶ does the same via dpad edge).
        onPressed: () => Dpad.of(context).moveRight(),
        focusNode: focusNode,
        onFocusChange: (f) { if (f) onFocused(); },
        border: false,
        borderRadius: AppRadii.r14,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        fill: Colors.transparent,
        fillFocused: util ? AppColors.focusFillUtil : AppColors.focusFillSelected,
        selected: selected,
        selectedFill: AppColors.focus,
        scale: AppFocus.scaleNav,
        restShadow: const <BoxShadow>[],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Sym(icon, size: iconSize,
                color: selected ? Colors.white : AppColors.textMuted),
            const SizedBox(height: 6),
            Text(label, style: labelStyle, textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _DonglePill extends StatelessWidget {
  const _DonglePill({required this.caps});
  final IrTransmitterCapabilities? caps;

  @override
  Widget build(BuildContext context) {
    final has = csHasTransmitter(caps);
    final color = has ? AppColors.success : AppColors.warning;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(AppRadii.r12),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
            color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(csTransmitterStatusLabel(caps),
                style: AppType.utilLabel.copyWith(color: color),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
