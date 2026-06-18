import 'package:flutter/material.dart';

/// Control Surface — color tokens (IR Blaster TV).
/// Shipping default = Dark theme. Light neutrals in [AppColorsLight].
/// All values are ARGB. Single orange accent (0xFFFF5A1F) is BOTH brand + focus.
class AppColors {
  AppColors._();

  // ---- Core palette — Dark (default) ----
  static const background      = Color(0xFF2A2318); // app scaffold bg (warm near-black)
  static const railBackground  = Color(0xFF1E1810); // left nav rail fill
  static const railBorder      = Color(0xFF3A3322); // rail right border, header dividers
  static const railDivider     = Color(0xFF2A251A); // rail internal dividers
  static const surface         = Color(0xFFF4EEDD); // all cards/rows/buttons/fields (cream)
  static const surfaceFocused  = Color(0xFFFFFFFF); // any surface while focused
  static const ink             = Color(0xFF16130D); // borders + text ON cream
  static const textPrimary     = Color(0xFFF4EEDD); // primary text on dark
  static const textSecondary   = Color(0xFFCDBF95); // rail labels, subtitles on dark
  static const textMuted       = Color(0xFF6B6450); // hint footers, captions on cream
  static const textMutedAlt    = Color(0xFF8A7F63); // mono micro-labels on cream
  static const dashed          = Color(0xFF463F30); // dashed add/empty borders

  // ---- Accent / focus (unified orange) ----
  static const accent      = Color(0xFFFF5A1F); // logo, primary CTA fills, hard-shadow color
  static const accentLabel = Color(0xFFFF7A45); // "// kicker" section labels
  static const focus       = Color(0xFFFF5A1F); // every focus ring, selected nav fill, fired

  // ---- Semantic ----
  static const success        = Color(0xFF3FD08A); // worked, SAVE, READY dot
  static const warning        = Color(0xFFFFB000); // hardware-banner chip, no-tx dot
  static const warningSurface = Color(0xFFFFE2B0); // hardware-banner bg
  static const error          = Color(0xFFFFB0A8); // next code, delete, error, amber status
  static const fireFlash      = Color(0x4DFF5A1F); // transmit feedback radial flash (30%)

  // ---- Disabled / dividers ----
  static const textDisabledOnDark  = Color(0x61F4EEDD); // 38% on dark canvas
  static const textDisabledOnCream = Color(0x6116130D); // 38% on cream
  static const dividerOnCream      = Color(0x1F16130D); // 12% hairline inside cream panels
  static const dividerOnDark       = Color(0xFF2A251A); // section dividers on dark / rail

  // ---- Focus fills (translucent overlays) ----
  static const focusFillSelected = Color(0x38FF5A1F); // unselected rail item, focused (22%)
  static const focusFillUtil     = Color(0x33FF5A1F); // util rail item, focused (20%)
  static const focusFillDashed   = Color(0x1AFF5A1F); // dashed add-tile, focused (10%)

  // ---- Device / category accent tones (icon chips, category fills) ----
  static const toneTv         = Color(0xFFFFC9A8); // TV / warm (peach)
  static const toneAudio      = Color(0xFFA8C7FF); // soundbar / audio (blue)
  static const toneLearning   = Color(0xFF9FE7C4); // AC / learning (mint)
  static const toneAppearance = Color(0xFFD9B8FF); // projector / appearance (lilac)
  static const toneNeutral    = Color(0xFFE4DECB); // Apple TV / neutral (stone)

  // ---- Confirm (finder) focused-fill variants ----
  static const successFocused = Color(0xFF5FE6A4);
  static const errorFocused   = Color(0xFFFFC8C2);

  // ---- Misc fills referenced in flows ----
  static const importSelectedRow = Color(0xFFEAF2FF); // selected key row in import sheet
}

/// Light theme — only neutrals change; accent/focus/semantic stay identical.
class AppColorsLight {
  AppColorsLight._();

  static const background     = Color(0xFFE9E0CB);
  static const railBackground = Color(0xFFF2EAD7);
  static const railBorder     = Color(0xFF16130D);
  static const railDivider    = Color(0xFFD6CBAF);
  static const surface        = Color(0xFFFFFFFF);
  static const ink            = Color(0xFF16130D);
  static const textPrimary    = Color(0xFF16130D);
  static const textSecondary  = Color(0xFF8A7F63);
  static const textMuted      = Color(0xFF6F6650);
  static const dashed         = Color(0xFFB3A786);
}
