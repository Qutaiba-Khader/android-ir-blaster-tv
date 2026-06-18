import 'package:flutter/material.dart';
import 'package:irblaster_controller/state/app_theme.dart';
import 'package:irblaster_controller/state/dynamic_color.dart';
import 'package:irblaster_controller/state/macros_state.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';
import 'package:irblaster_controller/utils/macros_io.dart';
import 'package:irblaster_controller/utils/remote.dart';
import 'package:irblaster_controller/utils/remotes_io.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

// =============================================================================
// Shared drill scaffold — a Control Surface detail screen with a back button,
// kicker + title header, and a centred, max-width body column.
// =============================================================================

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.kicker,
    required this.title,
    required this.onBack,
    required this.children,
    this.hint = '◀ BACK',
    this.backAutofocus = true,
  });

  final String kicker;
  final String title;
  final VoidCallback onBack;
  final List<Widget> children;
  final String hint;
  final bool backAutofocus;

  @override
  Widget build(BuildContext context) {
    final back = FocusableSurface(
      onPressed: onBack,
      borderRadius: AppRadii.r14,
      padding: const EdgeInsets.all(15),
      restShadow: AppShadows.sm,
      child: const Sym(AppIcons.back,
          size: AppIconSizes.headerBtn, color: AppColors.ink),
    );
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              backAutofocus
                  ? PrimaryFocus(builder: (n) => _BackButton(node: n, onBack: onBack))
                  : back,
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eyebrow removed per design — title only.
                    Text(title.toUpperCase(), style: AppType.drillHeader),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(clipBehavior: Clip.none, 
                  padding: const EdgeInsets.all(16),
                  children: children,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          HintStrip(hint),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.node, required this.onBack});
  final FocusNode node;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onBack,
      focusNode: node,
      borderRadius: AppRadii.r14,
      padding: const EdgeInsets.all(15),
      restShadow: AppShadows.sm,
      child: const Sym(AppIcons.back,
          size: AppIconSizes.headerBtn, color: AppColors.ink),
    );
  }
}

/// Section eyebrow label inside a detail body.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14, top: 4),
        child: Text(text.toUpperCase(), style: AppType.eyebrow),
      );
}

/// A cream selectable option row: chip · title (+ optional sub) · trailing
/// (selected check or a tag pill). Used for theme modes, transmitter types, etc.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.onPressed,
    this.subtitle,
    this.selected = false,
    this.focusNode,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String? subtitle;
  final VoidCallback onPressed;
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      selected: selected,
      selectedFill: AppColors.focusFillSelected,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          IconChip(icon,
              tone: tone,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.listTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppType.meta),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (selected)
            const Sym(AppIcons.check,
                size: AppIconSizes.headerBtn, color: AppColors.focus)
          else
            const SizedBox(width: AppIconSizes.headerBtn),
        ],
      ),
    );
  }
}

/// A cream toggle row driven by [FocusableSurface] (pressing flips [value]).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onToggle,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: () => onToggle(!value),
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          IconChip(icon,
              tone: tone,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(subtitle, style: AppType.meta),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Switch(value: value),
        ],
      ),
    );
  }
}

/// A small static switch graphic (the row itself is the focus/press target).
class _Switch extends StatelessWidget {
  const _Switch({required this.value});
  final bool value;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.focusToggle,
      curve: AppMotion.curve,
      width: 66,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: value ? AppColors.focus : AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: value ? Colors.white : AppColors.ink,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// A plain info row (no action) — chip · label · value.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color tone;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        boxShadow: AppShadows.md,
      ),
      child: Row(
        children: [
          IconChip(icon,
              tone: tone,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(child: Text(label, style: AppType.listTitle)),
          Text(value,
              style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
        ],
      ),
    );
  }
}

const SizedBox _gap = SizedBox(height: 14);
const SizedBox _gapL = SizedBox(height: 26);

// =============================================================================
// AppearanceCs — theme mode + dynamic color + text size.
// Wired to AppThemeController / DynamicColorController (the same controllers the
// existing Settings screen mutates).
// =============================================================================

class AppearanceCs extends StatefulWidget {
  const AppearanceCs({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<AppearanceCs> createState() => _AppearanceCsState();
}

class _AppearanceCsState extends State<AppearanceCs> {
  final AppThemeController _theme = AppThemeController.instance;
  final DynamicColorController _dyn = DynamicColorController.instance;
  // Text size: the app has no dedicated controller — it follows the system font
  // scale (MediaQuery.textScaler). We surface the live value read-only rather
  // than fabricate a setting that wouldn't persist anywhere.
  static const List<ThemeMode> _modes = <ThemeMode>[
    ThemeMode.light,
    ThemeMode.dark,
    ThemeMode.system,
  ];

  @override
  void initState() {
    super.initState();
    _theme.addListener(_refresh);
    _dyn.addListener(_refresh);
  }

  @override
  void dispose() {
    _theme.removeListener(_refresh);
    _dyn.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  IconData _modeIcon(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return AppIcons.macSun;
      case ThemeMode.dark:
        return AppIcons.macNight;
      case ThemeMode.system:
        return AppIcons.setAppearance;
    }
  }

  Color _modeTone(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return AppColors.toneTv;
      case ThemeMode.dark:
        return AppColors.toneAudio;
      case ThemeMode.system:
        return AppColors.toneAppearance;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _theme.mode;
    final scale = MediaQuery.maybeOf(context)?.textScaler.scale(1.0) ?? 1.0;
    final scaleLabel = '${(scale * 100).round()}%';

    final children = <Widget>[
      const _SectionLabel('Theme mode'),
      for (int i = 0; i < _modes.length; i++) ...[
        i == 0
            ? PrimaryFocus(
                builder: (n) => _OptionRow(
                  focusNode: n,
                  icon: _modeIcon(_modes[i]),
                  tone: _modeTone(_modes[i]),
                  title: _modes[i].displayName,
                  subtitle: _modes[i] == ThemeMode.system
                      ? 'Follow the TV / system theme'
                      : null,
                  selected: _modes[i] == current,
                  onPressed: () => _theme.setMode(_modes[i]),
                ),
              )
            : _OptionRow(
                icon: _modeIcon(_modes[i]),
                tone: _modeTone(_modes[i]),
                title: _modes[i].displayName,
                subtitle: _modes[i] == ThemeMode.system
                    ? 'Follow the TV / system theme'
                    : null,
                selected: _modes[i] == current,
                onPressed: () => _theme.setMode(_modes[i]),
              ),
        if (i < _modes.length - 1) _gap,
      ],
      _gapL,
      const _SectionLabel('Accent'),
      _ToggleRow(
        icon: AppIcons.recolor,
        tone: AppColors.toneAppearance,
        title: 'Dynamic color',
        subtitle: 'Use the system wallpaper accent (Android 12+)',
        value: _dyn.enabled,
        onToggle: (v) => _dyn.setEnabled(v),
      ),
      _gapL,
      const _SectionLabel('Text size'),
      _InfoRow(
        icon: AppIcons.setAppearance,
        tone: AppColors.toneNeutral,
        label: 'System font scale',
        value: scaleLabel,
      ),
    ];

    return _DetailScaffold(
      kicker: 'SETTINGS — APPEARANCE',
      title: 'Appearance',
      onBack: widget.onBack,
      backAutofocus: false,
      hint: '◀ BACK · ▲▼ BROWSE · ENTER SELECTS',
      children: children,
    );
  }
}

// =============================================================================
// TransmitterCs — show capabilities, pick the preferred transmitter type, and
// request USB. Reuses IrTransmitterPlatform exactly.
// =============================================================================

class TransmitterCs extends StatefulWidget {
  const TransmitterCs({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<TransmitterCs> createState() => _TransmitterCsState();
}

class _TransmitterCsState extends State<TransmitterCs> {
  IrTransmitterCapabilities? _caps;
  IrTransmitterType? _preferred;
  bool _busy = false;

  static const List<IrTransmitterType> _types = <IrTransmitterType>[
    IrTransmitterType.internal,
    IrTransmitterType.usb,
    IrTransmitterType.audio1Led,
    IrTransmitterType.audio2Led,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final caps = await IrTransmitterPlatform.getCapabilities();
      final pref = await IrTransmitterPlatform.getPreferredType();
      if (mounted) {
        setState(() {
          _caps = caps;
          _preferred = pref;
        });
      }
    } catch (_) {}
  }

  Future<void> _setPreferred(IrTransmitterType t) async {
    setState(() => _preferred = t);
    try {
      final applied = await IrTransmitterPlatform.setPreferredType(t);
      if (mounted) setState(() => _preferred = applied);
    } catch (_) {}
    await _load();
  }

  Future<void> _requestUsb() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await IrTransmitterPlatform.usbScanAndRequest();
    } catch (_) {}
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  String _typeName(IrTransmitterType t) {
    switch (t) {
      case IrTransmitterType.internal:
        return 'Built-in IR';
      case IrTransmitterType.usb:
        return 'USB dongle';
      case IrTransmitterType.audio1Led:
        return 'Audio jack · 1 LED';
      case IrTransmitterType.audio2Led:
        return 'Audio jack · 2 LED';
    }
  }

  IconData _typeIcon(IrTransmitterType t) {
    switch (t) {
      case IrTransmitterType.internal:
        return AppIcons.builtInIr;
      case IrTransmitterType.usb:
        return AppIcons.usbDongle;
      case IrTransmitterType.audio1Led:
      case IrTransmitterType.audio2Led:
        return AppIcons.audioAdapter;
    }
  }

  bool _available(IrTransmitterType t, IrTransmitterCapabilities c) {
    switch (t) {
      case IrTransmitterType.internal:
        return c.hasInternal;
      case IrTransmitterType.usb:
        return c.hasUsb;
      case IrTransmitterType.audio1Led:
      case IrTransmitterType.audio2Led:
        return c.hasAudio;
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = _caps;
    final children = <Widget>[
      const _SectionLabel('Status'),
      _InfoRow(
        icon: AppIcons.usbDongle,
        tone: AppColors.toneLearning,
        label: caps == null ? 'Checking…' : _usbStatusLabel(caps),
        value: caps == null
            ? '—'
            : (caps.usbReady ? 'READY' : (caps.hasUsb ? 'FOUND' : 'NO DONGLE')),
      ),
      _gap,
      PrimaryFocus(
        builder: (n) => FocusableSurface(
          focusNode: n,
          onPressed: _requestUsb,
          borderRadius: AppRadii.r16,
          scale: AppFocus.scaleRow,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
          fill: AppColors.accent,
          fillFocused: AppColors.accent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Sym(AppIcons.usbDongle,
                  size: AppIconSizes.settingsRow, color: AppColors.ink),
              const SizedBox(width: 14),
              Text(_busy ? 'SCANNING…' : 'SCAN & REQUEST USB',
                  style: AppType.buttonLabel),
            ],
          ),
        ),
      ),
      _gapL,
      const _SectionLabel('Preferred transmitter'),
      for (int i = 0; i < _types.length; i++) ...[
        _OptionRow(
          icon: _typeIcon(_types[i]),
          tone: AppColors.toneAudio,
          title: _typeName(_types[i]),
          subtitle: caps != null && !_available(_types[i], caps)
              ? 'Not detected on this device'
              : null,
          selected: _preferred == _types[i],
          onPressed: () => _setPreferred(_types[i]),
        ),
        if (i < _types.length - 1) _gap,
      ],
    ];

    return _DetailScaffold(
      kicker: 'SETTINGS — TRANSMITTER',
      title: 'Transmitter',
      onBack: widget.onBack,
      backAutofocus: false,
      hint: '◀ BACK · ▲▼ BROWSE · ENTER SELECTS / SCANS',
      children: children,
    );
  }

  String _usbStatusLabel(IrTransmitterCapabilities c) {
    if (c.usbReady) return 'USB IR ready';
    if (c.hasUsb) return 'USB dongle found — grant permission';
    if (c.hasInternal) return 'Built-in IR blaster';
    if (c.hasAudio) return 'Audio-jack IR available';
    return 'No transmitter found';
  }
}

// =============================================================================
// KeyBindingCs — explains the ACTION_CREATE_SHORTCUT binding method and lists
// the app's dynamic launcher shortcuts (the only "bound" surface the app owns).
// =============================================================================

class KeyBindingCs extends StatelessWidget {
  const KeyBindingCs({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // The app exposes binding ONLY via Android's ACTION_CREATE_SHORTCUT picker
    // (see state/ir_key_shortcuts.dart → ShortcutPickerApp) plus the dynamic
    // launcher shortcuts in state/app_shortcuts.dart. There is no in-app list of
    // physical-key→button maps to read back (the remapper tool owns those), so we
    // document the method and surface what the app itself provides.
    final children = <Widget>[
      const _SectionLabel('How to bind a remote key'),
      const _StepCard(
        index: 1,
        icon: AppIcons.bindKey,
        title: 'Open your key-remapper',
        body:
            'Use a launcher key-mapper (tvQuickActions, Button Mapper, Key Mapper). '
            'Pick "create shortcut" and choose IR Blaster.',
      ),
      _gap,
      const _StepCard(
        index: 2,
        icon: AppIcons.add,
        title: 'Pick a button or macro',
        body:
            'The picker (ACTION_CREATE_SHORTCUT) lets you bind one IR button or a '
            'whole macro. The resolved IR payload is handed back to the remapper.',
      ),
      _gap,
      const _StepCard(
        index: 3,
        icon: AppIcons.txFired,
        title: 'Press the key — fires silently',
        body:
            'The bound key replays the captured IR payload natively, with no app '
            'window. Manual-continue macro steps fall back to a fixed wait.',
      ),
      _gapL,
      const _SectionLabel('App quick shortcuts'),
      const _InfoRow(
        icon: AppIcons.remotes,
        tone: AppColors.toneTv,
        label: 'Last remote · Signal Tester · Learning',
        value: 'LAUNCHER',
      ),
      _gap,
      const _InfoRow(
        icon: AppIcons.macros,
        tone: AppColors.toneAudio,
        label: 'Last macro · Universal Power',
        value: 'LAUNCHER',
      ),
    ];

    return _DetailScaffold(
      kicker: 'SETTINGS — KEY BINDING',
      title: 'Key Binding',
      onBack: onBack,
      hint: '◀ BACK',
      children: children,
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });
  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        boxShadow: AppShadows.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconChip(icon,
              tone: AppColors.toneAppearance,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('STEP 0$index', style: AppType.microLabel),
                    const SizedBox(width: 10),
                    Expanded(child: Text(title, style: AppType.listTitle)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body, style: AppType.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BackupCs — export / import all data as JSON. Reuses the EXACT calls the
// existing Settings screen makes (remotes_io / macros_io).
// =============================================================================

class BackupCs extends StatefulWidget {
  const BackupCs({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<BackupCs> createState() => _BackupCsState();
}

class _BackupCsState extends State<BackupCs> {
  String? _status;
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await exportRemotesToDownloads(
        context,
        remotes: remotes,
        macros: macros,
      );
      if (mounted) setState(() => _status = 'Exported to Downloads as JSON');
    } catch (_) {
      if (mounted) setState(() => _status = 'Export failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await importRemotesFromPicker(context, current: remotes);
      if (result == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final msg = result.message;
      final isFailure = msg.toLowerCase().contains('failed') ||
          msg.toLowerCase().contains('unsupported') ||
          msg.toLowerCase().contains('invalid');
      if (!(result.remotes.isEmpty && isFailure)) {
        // Same persistence path as SettingsScreen._doImport.
        remotes = result.remotes;
        await writeRemotelist(remotes);
        remotes = await readRemotes();
        notifyRemotesChanged();
        if (result.macros != null) {
          await writeMacrosList(result.macros!);
          final fresh = await readMacros();
          setMacros(fresh);
        }
      }
      if (mounted) setState(() => _status = msg);
    } catch (_) {
      if (mounted) setState(() => _status = 'Import failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const _SectionLabel('Backup'),
      PrimaryFocus(
        builder: (n) => _ActionCard(
          node: n,
          icon: AppIcons.setBackup,
          tone: AppColors.toneTv,
          title: 'Export all data',
          subtitle:
              'Write every remote & macro to Downloads as a JSON backup file.',
          pill: 'JSON',
          onPressed: _export,
        ),
      ),
      _gap,
      _ActionCard(
        icon: AppIcons.fromStore,
        tone: AppColors.toneLearning,
        title: 'Import / restore',
        subtitle:
            'Pick a JSON backup (or Flipper / irplus / LIRC file) and replace your data.',
        pill: 'RESTORE',
        onPressed: _import,
      ),
      if (_status != null) ...[
        _gapL,
        _InfoRow(
          icon: AppIcons.check,
          tone: AppColors.toneNeutral,
          label: _status!,
          value: _busy ? 'WORKING…' : 'DONE',
        ),
      ],
    ];

    return _DetailScaffold(
      kicker: 'SETTINGS — BACKUP',
      title: 'Backup & Restore',
      onBack: widget.onBack,
      backAutofocus: false,
      hint: '◀ BACK · ENTER = EXPORT / IMPORT',
      children: children,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.pill,
    required this.onPressed,
    this.node,
  });
  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;
  final String pill;
  final VoidCallback onPressed;
  final FocusNode? node;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: node,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      child: Row(
        children: [
          IconChip(icon,
              tone: tone,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(subtitle, style: AppType.meta),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TagPill(pill),
        ],
      ),
    );
  }
}
