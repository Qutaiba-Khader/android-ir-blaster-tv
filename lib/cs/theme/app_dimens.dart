import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Control Surface — spacing, sizing, radii, borders, shadows, motion.
/// Shipping default = **Premium** style (2dp borders, soft shadows). The **Normal**
/// alternate (3dp borders, hard offset shadows, line grid) is in [AppShadowsHard].
class AppSpacing {
  AppSpacing._();
  // Base-4 scale; gaps cluster on 14/18/22/24.
  static const s4 = 4.0, s8 = 8.0, s9 = 9.0, s12 = 12.0, s14 = 14.0, s16 = 16.0;
  static const s18 = 18.0, s20 = 20.0, s22 = 22.0, s24 = 24.0, s26 = 26.0;
  static const s30 = 30.0, s36 = 36.0, s40 = 40.0, s52 = 52.0;

  // Screen padding
  static const screenPad      = EdgeInsets.symmetric(vertical: 40, horizontal: 52);
  static const screenPadDrill = EdgeInsets.symmetric(vertical: 36, horizontal: 52);
}

class AppRadii {
  AppRadii._();
  static const r10 = 10.0, r11 = 11.0, r12 = 12.0, r13 = 13.0, r14 = 14.0;
  static const r15 = 15.0, r16 = 16.0, r18 = 18.0, r20 = 20.0, r22 = 22.0, r26 = 26.0;
  static const pill = 999.0;
}

class AppBorders {
  AppBorders._();
  static const width     = 2.0; // Premium default (3.0 in Normal)
  static const railWidth = 2.0; // rail right border (4.0 in Normal)
  static const inner     = 3.0; // inner dividers 3–4dp
}

class AppSizes {
  AppSizes._();
  static const canvasW   = 1920.0;
  static const canvasH   = 1080.0;
  static const railWidth = 248.0;

  static const railLogo      = 48.0;  // r12
  static const remoteCardH   = 212.0; // grid card, r18
  static const irKeyCols     = 7;     // smaller keys, more per row
  static const headerBtn     = 58.0;  // back / overflow, r14
  static const minFocusTarget= 56.0;  // rows/buttons; never below 44
  static const minHitArea    = 44.0;
}

/// Motion — durations (ms) + standard easing. No animation may delay D-pad nav.
class AppMotion {
  AppMotion._();
  static const focusCard    = Duration(milliseconds: 120);
  static const focusDefault = Duration(milliseconds: 110); // buttons, rows, rail, CTAs
  static const focusToggle  = Duration(milliseconds: 100); // segmented control
  static const focusKey     = Duration(milliseconds: 90);  // keyboard keys
  static const runStep      = Duration(milliseconds: 200); // macro-run row change
  static const sheet        = Duration(milliseconds: 200); // bottom-sheet entrance
  static const modal        = Duration(milliseconds: 160); // dialog entrance (150–160)
  static const fireFlash    = Duration(milliseconds: 460); // transmit flash
  static const pulse        = Duration(milliseconds: 1100);// learning receiver pulse
  static const scan         = Duration(milliseconds: 1300);// loading scan bar
  static const runAdvance   = Duration(milliseconds: 950); // macro step advance

  static const curve = Curves.easeOut; // Material standard
}

/// Premium (default) — SOFT shadows.
class AppShadows {
  AppShadows._();
  static const sm = [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4),  blurRadius: 12)];
  static const md = [BoxShadow(color: Color(0x5C000000), offset: Offset(0, 8),  blurRadius: 20)];
  static const lg = [BoxShadow(color: Color(0x6B000000), offset: Offset(0, 16), blurRadius: 36)];

  /// Focus = 4dp accent ring (spread) + orange glow.
  static const focus = [
    BoxShadow(color: AppColors.focus, blurRadius: 0, spreadRadius: 4),
    BoxShadow(color: Color(0x6BFF5A1F), offset: Offset(0, 16), blurRadius: 38),
  ];

  /// Macro-run active step glow.
  static const runActive = [
    BoxShadow(color: AppColors.focus, blurRadius: 0, spreadRadius: 4),
    BoxShadow(color: Color(0x66FF5A1F), offset: Offset(0, 12), blurRadius: 30),
  ];
}

/// Normal alternate — HARD offset shadows (offset = accent, blur 0).
class AppShadowsHard {
  AppShadowsHard._();
  static const sm    = [BoxShadow(color: AppColors.accent, offset: Offset(5, 5),   blurRadius: 0)];
  static const md    = [BoxShadow(color: AppColors.accent, offset: Offset(6, 6),   blurRadius: 0)];
  static const lg    = [BoxShadow(color: AppColors.accent, offset: Offset(8, 8),   blurRadius: 0)];
  static const focus = [BoxShadow(color: AppColors.focus,  offset: Offset(12, 12), blurRadius: 0)];
}

/// Global focus ring (applies to every focusable element, on top of per-component look).
class AppFocus {
  AppFocus._();
  static const ringWidth  = 4.0;
  static const ringOffset = 2.0;
  static const ringColor  = AppColors.focus;
  // No focus SCALE anywhere — scaling made neighbouring items look like they
  // shove each other while navigating. Focus is shown by the white fill + 4dp
  // orange ring + lift shadow instead. (Kept as 1.0 so call sites need no change.)
  static const scaleCard  = 1.0;
  static const scaleList  = 1.0;
  static const scaleRow   = 1.0;
  static const scaleNav   = 1.0;
}
