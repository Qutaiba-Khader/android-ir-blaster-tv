import 'package:material_symbols_icons/symbols.dart';

/// Control Surface — iconography.
/// Source set: **Material Symbols Rounded**, axes `FILL 0, wght 700, GRAD 0, opsz 48`.
/// In Flutter, render via the `material_symbols_icons` package and set the axes on
/// the Icon widget:  Icon(AppIcons.settingsRemote, weight: 700, fill: 0, opticalSize: 48)
/// Color = the text/ink color of the element the icon sits in (see spec §3).
///
/// Sizes per context (dp) are in [AppIconSizes].
class AppIcons {
  AppIcons._();

  // ---- Navigation rail (28 dp visual; render at 27) ----
  static const remotes  = Symbols.settings_remote; // Remotes
  static const macros   = Symbols.playlist_play;   // Macros
  static const tester   = Symbols.radar;           // Tester
  static const settings = Symbols.settings;        // Settings

  // ---- Tools rail (22 dp) ----
  static const search    = Symbols.search;
  static const bindKey   = Symbols.add_link;
  static const focusSpec = Symbols.tune;
  static const states    = Symbols.dashboard;

  // ---- Hardware banner ----
  static const warning = Symbols.warning; // 30, on warning chip
  static const close   = Symbols.close;   // 24, dismiss

  // ---- Home header ----
  static const gridView = Symbols.grid_view;     // 20
  static const viewList = Symbols.view_list;     // 20
  static const add      = Symbols.add;           // 44 add-tile / 24–34 elsewhere
  static const chevron  = Symbols.chevron_right; // 28 list rows

  // ---- Remote View — IR keys (33 dp glyph) ----
  static const power      = Symbols.power_settings_new;   // POWER (accent fill)
  static const input      = Symbols.input;                // INPUT
  static const mute       = Symbols.volume_off;           // MUTE
  static const home       = Symbols.home;                 // HOME
  static const menu       = Symbols.menu;                 // MENU
  static const chUp       = Symbols.keyboard_arrow_up;    // CH +
  static const volUp      = Symbols.add;                  // VOL +
  static const ok         = Symbols.radio_button_checked; // OK (accent fill)
  static const volDown    = Symbols.remove;               // VOL −
  static const chDown     = Symbols.keyboard_arrow_down;  // CH −
  static const back       = Symbols.arrow_back;           // BACK / header back (28)
  static const guide      = Symbols.grid_view;            // GUIDE
  static const netflix    = Symbols.movie;                // NETFLIX
  static const youtube    = Symbols.smart_display;        // YOUTUBE
  static const off        = Symbols.power_off;            // OFF

  // ---- Remote header / transmit ----
  static const overflow      = Symbols.more_horiz;     // 28
  static const sensorsIdle   = Symbols.sensors;        // 24 idle status
  static const txFired       = Symbols.wifi_tethering; // 24 fired status / blast again (22)

  // ---- Macros ----
  static const macMovie  = Symbols.movie;
  static const macNight  = Symbols.bedtime;
  static const macGame   = Symbols.sports_esports;
  static const macSun    = Symbols.wb_sunny;
  static const run       = Symbols.play_arrow;   // 20 RUN

  // ---- Macro editor steps ----
  static const stepPower  = Symbols.power_settings_new;
  static const stepDelay  = Symbols.timer;
  static const stepInput  = Symbols.input;
  static const stepSpeaker= Symbols.speaker;
  static const stepManual = Symbols.pause_circle;
  static const stepVolume = Symbols.volume_up;   // 25 in chip
  static const dragHandle = Symbols.drag_indicator; // 24 reorder
  static const check      = Symbols.check;          // 20 SAVE / capture done

  // ---- Signal Tester tools (38 dp) ----
  static const findCode  = Symbols.radar;
  static const learning  = Symbols.sensors;
  static const powerOff  = Symbols.power_settings_new;

  // ---- IR Finder ----
  static const worked = Symbols.check; // 38 worked (on ink circle)
  static const next   = Symbols.close; // 38 next (on ink circle)

  // ---- Learning Mode ----
  static const receiver = Symbols.sensors;      // 90 receiver → check (90) captured
  static const replay   = Symbols.replay;       // 22
  static const save     = Symbols.save;         // 22

  // ---- Settings rows (30 dp) ----
  static const setTransmitter = Symbols.usb;
  static const setKeyBinding  = Symbols.vpn_key;
  static const setAppearance  = Symbols.palette;
  static const setBackup      = Symbols.cloud_sync;
  static const setAbout       = Symbols.info;

  // ---- Add Remote methods (30 dp) ----
  static const fromDatabase = Symbols.database;
  static const fromStore    = Symbols.cloud_download;
  static const fromScratch  = Symbols.dashboard_customize;

  // ---- Hardware sheet (32 dp) ----
  static const builtInIr     = Symbols.sensors_off;
  static const usbDongle     = Symbols.usb;
  static const audioAdapter  = Symbols.headphones;

  // ---- Per-button overflow (26 dp) ----
  static const edit        = Symbols.edit;
  static const recolor     = Symbols.palette;
  static const addToMacro  = Symbols.playlist_add;
  static const bindToKey   = Symbols.add_link;
  static const delete      = Symbols.delete;
  static const openInNew   = Symbols.open_in_new;

  // ---- States gallery (54 dp) ----
  static const stateEmpty   = Symbols.settings_remote;
  static const stateLoading = Symbols.radar;
  static const stateError   = Symbols.error;
  static const stateNoMatch = Symbols.search_off; // 50

  // ---- Studio / store / import ----
  static const hub          = Symbols.hub;
  static const addCircle    = Symbols.add_circle;
  static const syncAlt      = Symbols.sync_alt;
  static const link         = Symbols.link;
  static const storefront   = Symbols.storefront;
  static const bookmarkAdd  = Symbols.bookmark_add;
  static const factory_     = Symbols.factory;
  static const devicesOther = Symbols.devices_other;
  static const expandMore   = Symbols.expand_more;
  static const bolt         = Symbols.bolt;
  static const selectAll    = Symbols.select_all;
  static const deselect     = Symbols.deselect;
}

/// Icon sizes (dp) per context.
class AppIconSizes {
  AppIconSizes._();
  static const railPrimary = 27.0; // nav rail (28 visual)
  static const railUtil    = 22.0;
  static const headerBtn   = 28.0; // back / overflow / chevron
  static const headerCtl   = 20.0; // search / grid / list chips
  static const irKey       = 33.0; // IR key glyph
  static const status      = 24.0; // transmit status / banner close
  static const bannerChip  = 30.0; // warning chip
  static const addTile     = 44.0; // big add tile
  static const cardChip    = 30.0; // category chip in card
  static const settingsRow = 30.0;
  static const toolCard    = 38.0; // tester tool cards / finder confirm glyph
  static const hwOption    = 32.0;
  static const overflowRow = 26.0;
  static const stateGlyph  = 54.0; // states gallery (no-match = 50)
  static const receiver    = 90.0; // learning receiver
}
