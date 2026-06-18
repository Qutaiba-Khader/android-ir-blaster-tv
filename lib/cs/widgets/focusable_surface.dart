import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// FocusableSurface — the single D-pad-focus primitive used by every interactive
/// element. The VISUAL is unchanged from the Control Surface spec: on focus it
/// swaps fill cream→white, draws the 4dp orange ring, lifts with a shadow, and
/// scales; `selected` (e.g. the active nav item) stays visible UNDER focus.
///
/// The focus ENGINE is now the `dpad` package (region-based traversal + focus
/// memory + auto-scroll), not a hand-rolled FocusTraversalPolicy. We render the
/// exact same decoration from `DpadFocusable`'s live [DpadFocusState] via its
/// `builder`, so nothing about the look changes — only the navigation gets the
/// native-feeling TV behavior (no focus steals, remembers where you were, scrolls
/// long lists/keypads into view automatically).
class FocusableSurface extends StatelessWidget {
  const FocusableSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.borderRadius = AppRadii.r18,
    this.padding,
    this.fill = AppColors.surface,
    this.fillFocused = AppColors.surfaceFocused,
    this.selected = false,
    this.selectedFill,
    this.scale = AppFocus.scaleRow,
    this.autofocus = false,
    this.border = true,
    this.restShadow,
    this.onFocusChange,
    this.entry = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final double borderRadius;
  final EdgeInsets? padding;
  final Color fill;
  final Color fillFocused;
  final bool selected;
  final Color? selectedFill;
  final double scale;
  final bool autofocus;
  final bool border;
  final List<BoxShadow>? restShadow;
  final ValueChanged<bool>? onFocusChange;

  /// Marks this surface as its [DpadRegion]'s entry target — the item focus
  /// lands on when the region is entered from the rail (OK / ▶). One per region.
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      entry: entry,
      onSelect: onPressed,
      onFocusChange: onFocusChange,
      child: child,
      builder: (context, state, child) {
        final focused = state.focused;
        final bg = focused
            ? fillFocused
            : (selected ? (selectedFill ?? fill) : fill);
        return AnimatedScale(
          scale: focused ? scale : 1.0,
          duration: AppMotion.focusDefault,
          curve: AppMotion.curve,
          child: AnimatedContainer(
            duration: AppMotion.focusDefault,
            curve: AppMotion.curve,
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: border
                  ? Border.all(
                      color: focused ? AppColors.focus : AppColors.ink,
                      width: focused ? AppFocus.ringWidth : AppBorders.width,
                    )
                  : null,
              boxShadow: focused
                  ? AppShadows.focus
                  : (restShadow ?? AppShadows.lg),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
