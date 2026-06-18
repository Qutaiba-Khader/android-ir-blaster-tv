import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Control Surface — typography.
/// Two families: Sora (titles/names/numbers) + Space Mono (labels/meta/caps).
/// Convention: Sora = names, titles, numbers. Space Mono = labels, meta, captions,
/// hints, all UPPERCASE micro-text. Design uses weight 700 almost everywhere.
/// Hard 15sp floor — no text below 15.
///
/// Fonts are bundled locally (assets/fonts, registered in pubspec) so there is NO
/// runtime fetch — offline-safe and no first-frame jank on TV.
///
/// Flutter notes: `letterSpacing` is in logical px (matches the spec's px values).
/// `height` is a multiplier (= line-height ÷ font-size) — spec gives it directly
/// (0.9 / 1.0 / 1.4 / 1.5).
class AppType {
  AppType._();

  /// Global type scale — bump all text a little (user request).
  static const double _scale = 1.12;

  static const String fontDisplay = 'Sora';
  static const String fontMono = 'Space Mono';

  static TextStyle _sora(double size, double ls, double h, [Color c = AppColors.textPrimary]) =>
      TextStyle(fontFamily: fontDisplay, fontSize: size * _scale, fontWeight: FontWeight.w700,
          letterSpacing: ls, height: h, color: c);

  static TextStyle _mono(double size, double ls, double h, Color c) =>
      TextStyle(fontFamily: fontMono, fontSize: size * _scale, fontWeight: FontWeight.w700,
          letterSpacing: ls, height: h, color: c);

  // ---- Sora (display) ----
  static final screenTitle   = _sora(60, -2.0, 0.9);   // REMOTES, MACROS…
  static final screenTitleSm = _sora(54, -2.0, 0.9);   // Focus Spec / States
  static final heroTitle     = _sora(70, -2.5, 0.9);   // macro-run hero
  static final drillHeader   = _sora(38, -1.0, 1.0);   // device/finder/editor name (36–38)
  static final cardTitle     = _sora(27, -0.5, 1.0, AppColors.ink); // remote name
  static final rowTitle      = _sora(25, -0.5, 1.0, AppColors.ink); // macro / option row
  static final listTitle     = _sora(23, -0.5, 1.0, AppColors.ink); // list / setting row
  static final candidateCode = _sora(44, -1.0, 1.0, AppColors.ink); // candidate IR code
  static final searchQuery   = _sora(26, -0.5, 1.0, AppColors.ink);

  // ---- Space Mono (labels/meta) ----
  static final kicker     = _mono(15, 2.0, 1.0, AppColors.accentLabel); // "// CONTROL SURFACE — TV"
  static final navLabel   = _mono(15, 1.0, 1.0, AppColors.textSecondary); // (white when selected)
  static final utilLabel  = _mono(15, 0.5, 1.0, AppColors.textSecondary);
  static final buttonLabel= _mono(15, 0.5, 1.0, AppColors.ink);          // button / IR-key label
  static final keyGlyph   = _mono(20, 0.0, 1.0, AppColors.ink);          // keyboard key glyph
  static final meta       = _mono(16, 0.0, 1.4, AppColors.textMuted);    // card subtitle / list meta
  static final microLabel = _mono(15, 1.5, 1.0, AppColors.textMutedAlt); // "CANDIDATE CODE"
  static final eyebrow    = _mono(15, 2.0, 1.0, AppColors.textSecondary);// "BUTTON STATES"
  static final hintFooter = _mono(16, 0.0, 1.0, AppColors.textSecondary);// "◀ NAV · ENTER…"
  static final badge      = _mono(15, 0.0, 1.0, AppColors.ink);
  static final tagPill    = _mono(14, 0.0, 1.0, AppColors.ink);          // READY / JSON / v3.3
}
