# Android TV support

This fork adds first-class **Android TV / Google TV** support to
[iodn/android-ir-blaster](https://github.com/iodn/android-ir-blaster) on top of the
upstream app, while keeping phone/tablet behaviour unchanged. All changes are additive.

## What's added

### 1. Runs as a real TV app
- **Leanback launcher entry** — the app now appears on the Android TV home screen
  (`LEANBACK_LAUNCHER` category on `MainActivity`).
- **TV banner** (`res/drawable-xhdpi/tv_banner.png`, 320×180) shown on the home row.
- Declared `leanback` / `touchscreen` / `faketouch` as **not required**, so it installs
  on TV devices that have no touchscreen.

### 2. D-pad navigation & visible focus
- The IR remote button grids draw a clear **focus ring** as you move with the D-pad
  (the default Material focus tint is too faint to read across a room).
- A global focus tint is set on the light/dark themes for the rest of the app.

### 3. Bind any button or macro to a physical remote key
The headline feature for TV: trigger an IR button (or a whole macro) from a **remapped
physical key** using a key-remapper app — tvQuickActions, Button Mapper, Key Mapper, or
any launcher that can create an app shortcut.

- The app advertises a standard **`ACTION_CREATE_SHORTCUT`** picker
  (`ShortcutPickerActivity`). In your remapper, choose "app shortcut" → **IR Blaster
  Remote** → pick a **remote → button** (with search) or a **macro**.
- Pressing the bound key fires the IR **silently, with no visible UI**
  (`IrShortcutFireActivity`). It transmits natively:
  - built-in IR emitter first, then
  - an attached & permitted **USB IR dongle** (same discovery the app uses), then
  - falls back to opening the app only if no transmitter can be acquired (e.g. USB
    permission was never granted).
- Macros are resolved to an ordered list of `{frequency, pattern, delayAfterMs}` steps and
  replayed in sequence. (A manual-continue step becomes a fixed 800 ms wait, since silent
  playback can't pause for input.)

The TV-optimized shortcut picker uses large, D-pad-friendly rows with a visible focus ring
and a search box for remotes that have many buttons.

## New / changed files

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | leanback launcher, banner, `CREATE_SHORTCUT` filter, fire activity |
| `android/app/src/main/res/drawable-xhdpi/tv_banner.png` | TV home-screen banner |
| `android/app/src/main/res/values/styles.xml` | transparent theme for the silent fire activity |
| `android/app/src/main/kotlin/.../IrShortcutStore.kt` | token → IR payload store |
| `android/app/src/main/kotlin/.../IrShortcutFireActivity.kt` | invisible native (internal + USB) transmit |
| `android/app/src/main/kotlin/.../ShortcutPickerActivity.kt` | isolated Flutter picker for `CREATE_SHORTCUT` |
| `lib/state/ir_key_shortcuts.dart` | picker UI + button/macro → payload resolvers |
| `lib/main.dart` | route into the minimal picker app; focus theme |
| `lib/widgets/remote_view.dart` | D-pad focus rings on the button grids |

## Building

This fork builds with the same toolchain the upstream CI uses:

- **Flutter 3.38.6** (see `.github/workflows/release.yml`). Newer Flutter (≥ 3.44) makes
  `IconData` a final class and breaks the pinned `font_awesome_flutter 10.12.0`.
- The IR database asset is generated, not committed — run it before building:
  ```bash
  python3 tools/build_ir_db.py        # creates assets/db/irblaster.sqlite
  flutter pub get
  flutter build apk --profile --no-tree-shake-icons
  ```
  `--no-tree-shake-icons` is required because the app builds `IconData` dynamically.

### Build-environment fixes carried in this fork
- `android/build.gradle` pins `androidx.glance:glance-appwidget` to **1.1.1**. The
  `home_widget` plugin requests `1.+`, which now resolves to a `1.3.0-alpha` that demands
  AGP 9.1 / compileSdk 37; the pin keeps the project building on the committed
  AGP 8.13.1 / compileSdk 36 toolchain.
- `android/gradle.properties` raises the Gradle heap to 4 GB (the Jetifier transform of the
  Flutter engine jar OOMs at the default 1536 MB).

## Credits

Fork of **[iodn/android-ir-blaster](https://github.com/iodn/android-ir-blaster)** — all
upstream functionality and licensing (see `LICENSE`) is retained.
