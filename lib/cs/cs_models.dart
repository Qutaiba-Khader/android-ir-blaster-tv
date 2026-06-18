import 'package:flutter/material.dart';
import 'package:irblaster_controller/utils/remote.dart';
import 'package:irblaster_controller/utils/button_label.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'theme/app_colors.dart';

/// Adapters that map the app's real domain models (Remote / IRButton /
/// IrTransmitterCapabilities) onto the values the Control Surface UI needs.
/// The UI never touches storage — it only reads these.

const List<Color> _csTones = <Color>[
  AppColors.toneTv,
  AppColors.toneAudio,
  AppColors.toneLearning,
  AppColors.toneAppearance,
  AppColors.toneNeutral,
];

/// Stable category tone for a remote/macro by index (cycles the 5 design tones).
Color csTone(int index) => _csTones[index % _csTones.length];

/// A representative glyph for a remote card (real remotes carry no brand icon).
const List<IconData> _csRemoteGlyphs = <IconData>[
  Symbols.tv,
  Symbols.speaker,
  Symbols.mode_fan,
  Symbols.cast,
  Symbols.devices_other,
];

IconData csRemoteGlyph(int index) => _csRemoteGlyphs[index % _csRemoteGlyphs.length];

/// Maps a normalized (UPPERCASE, trimmed) remote-button label to a
/// Material Symbols Rounded icon. Same icon source as [AppIcons]
/// (`material_symbols_icons` → `Symbols.xxx`). Returns null for labels we
/// don't recognize (and for pure-number keys, so the digit renders as text).
const Map<String, IconData> _csLabelIcons = <String, IconData>{
  // Power
  'POWER': Symbols.power_settings_new,
  'PWR': Symbols.power_settings_new,
  'ON': Symbols.power_settings_new,
  'OFF': Symbols.power_settings_new,
  'STANDBY': Symbols.power_settings_new,

  // Volume
  'VOL+': Symbols.volume_up,
  'VOL +': Symbols.volume_up,
  'VOL UP': Symbols.volume_up,
  'VOLUME UP': Symbols.volume_up,
  'VOLUME+': Symbols.volume_up,
  'V+': Symbols.volume_up,
  'VOL-': Symbols.volume_down,
  'VOL -': Symbols.volume_down,
  'VOL DOWN': Symbols.volume_down,
  'VOLUME DOWN': Symbols.volume_down,
  'VOLUME-': Symbols.volume_down,
  'V-': Symbols.volume_down,
  'MUTE': Symbols.volume_off,
  'MUTING': Symbols.volume_off,

  // Channel
  'CH+': Symbols.keyboard_arrow_up,
  'CH +': Symbols.keyboard_arrow_up,
  'CH UP': Symbols.keyboard_arrow_up,
  'CHANNEL UP': Symbols.keyboard_arrow_up,
  'CHANNEL+': Symbols.keyboard_arrow_up,
  'CH-': Symbols.keyboard_arrow_down,
  'CH -': Symbols.keyboard_arrow_down,
  'CH DOWN': Symbols.keyboard_arrow_down,
  'CHANNEL DOWN': Symbols.keyboard_arrow_down,
  'CHANNEL-': Symbols.keyboard_arrow_down,

  // D-pad
  'UP': Symbols.keyboard_arrow_up,
  'DOWN': Symbols.keyboard_arrow_down,
  'LEFT': Symbols.keyboard_arrow_left,
  'RIGHT': Symbols.keyboard_arrow_right,

  // Select / navigation
  'OK': Symbols.radio_button_checked,
  'ENTER': Symbols.radio_button_checked,
  'SELECT': Symbols.radio_button_checked,
  'HOME': Symbols.home,
  'BACK': Symbols.arrow_back,
  'RETURN': Symbols.arrow_back,
  'EXIT': Symbols.arrow_back,
  'MENU': Symbols.menu,
  'INFO': Symbols.info,
  'GUIDE': Symbols.grid_view,
  'EPG': Symbols.grid_view,

  // Input / source
  'INPUT': Symbols.input,
  'SOURCE': Symbols.input,
  'AV': Symbols.settings_input_hdmi,
  'HDMI': Symbols.settings_input_hdmi,

  // Transport
  'PLAY': Symbols.play_arrow,
  'PAUSE': Symbols.pause,
  'PLAY/PAUSE': Symbols.play_arrow,
  'STOP': Symbols.stop,
  'REC': Symbols.fiber_manual_record,
  'RECORD': Symbols.fiber_manual_record,
  'REWIND': Symbols.fast_rewind,
  'REW': Symbols.fast_rewind,
  'FORWARD': Symbols.fast_forward,
  'FF': Symbols.fast_forward,
  'FFWD': Symbols.fast_forward,
  'NEXT': Symbols.skip_next,
  'SKIP': Symbols.skip_next,
  'PREV': Symbols.skip_previous,
  'PREVIOUS': Symbols.skip_previous,

  // Colour keys (the colour comes from the label text; keep icon ink-colored)
  'RED': Symbols.circle,
  'GREEN': Symbols.circle,
  'BLUE': Symbols.circle,
  'YELLOW': Symbols.circle,

  // Voice / search
  'MIC': Symbols.mic,
  'VOICE': Symbols.mic,
  'SEARCH': Symbols.search,

  // Misc
  'SETTINGS': Symbols.settings,
  'NETFLIX': Symbols.apps,
  'YOUTUBE': Symbols.apps,
  'APPS': Symbols.apps,
};

/// The icon for a real IRButton.
///
/// Priority:
///   1. The button's stored custom icon from the icon picker, if any.
///   2. A Material Symbols icon mapped from its display label (common remote
///      keys like POWER, VOL+, OK, PLAY…).
///   3. null — the caller falls back to a default icon.
IconData? csButtonIcon(IRButton b) {
  // 1. Highest priority: a user-picked custom icon.
  final cp = b.iconCodePoint;
  if (cp != null) {
    return IconData(cp, fontFamily: b.iconFontFamily, fontPackage: b.iconFontPackage);
  }

  // 2. Map the normalized label to a recognizable remote-key icon.
  final l = csButtonLabel(b).toUpperCase().trim();
  if (l.isEmpty) return null;

  final exact = _csLabelIcons[l];
  if (exact != null) return exact;

  // 3. Unknown label → null (numbers fall through here so the digit shows as text).
  return null;
}

/// The display label for a real IRButton (mirrors the app's own logic).
String csButtonLabel(IRButton b) =>
    displayButtonLabel(b, fallback: '', iconFallback: '');

/// Keypad keys are now uniform cream and only turn orange on FOCUS, so no key
/// gets a permanent accent fill. Kept (callers still reference it) but always
/// returns false.
bool csIsAccentKey(IRButton b) => false;

/// True when any transmitter (internal / USB / audio) is usable.
/// Drives the home hardware banner.
bool csHasTransmitter(IrTransmitterCapabilities? c) {
  if (c == null) return false;
  return c.hasInternal || c.hasUsb || c.hasAudio;
}

/// Short status text for the bottom rail dongle pill.
String csTransmitterStatusLabel(IrTransmitterCapabilities? c) {
  if (c == null) return 'CHECKING…';
  if (c.usbReady) return 'IR READY';
  if (c.hasInternal) return 'IR READY';
  if (c.hasUsb) return 'USB FOUND';
  if (c.hasAudio) return 'AUDIO IR';
  return 'NO IR DONGLE';
}
