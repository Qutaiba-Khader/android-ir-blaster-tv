import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:irblaster_controller/l10n/app_localizations.dart';
import 'package:irblaster_controller/l10n/l10n.dart';
import 'package:irblaster_controller/l10n/icon_picker_names.dart';
import 'package:irblaster_controller/models/macro_step.dart';
import 'package:irblaster_controller/models/timed_macro.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/button_label.dart';
import 'package:irblaster_controller/utils/ir.dart';
import 'package:irblaster_controller/utils/macros_io.dart';
import 'package:irblaster_controller/utils/remote.dart';
import 'package:irblaster_controller/widgets/quick_tile_chooser.dart';

/// Initial route used by [ShortcutPickerActivity] (native) to render the minimal
/// "bind a key to a button/macro" picker instead of the full app.
const String shortcutPickerRoute = 'shortcut_picker';

const MethodChannel _pickerChannel = MethodChannel('org.nslabs/shortcut_picker');

/// Manual-continue macro steps cannot pause silently when fired from a remapped
/// key, so they are converted to a fixed wait.
const int _manualContinueFallbackMs = 800;

enum _ShortcutKind { button, macro }

/// Minimal app shown when launched via ACTION_CREATE_SHORTCUT. It lets a launcher
/// or key-remapper tool (tvQuickActions, Button Mapper, Key Mapper, ...) bind a
/// physical key to a single IR button or a macro, then returns the resolved IR
/// payload to the native side via [_pickerChannel].
class ShortcutPickerApp extends StatelessWidget {
  const ShortcutPickerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5));
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        focusColor: lightScheme.primary.withValues(alpha: 0.20),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        focusColor: darkScheme.primary.withValues(alpha: 0.22),
      ),
      home: const _ShortcutPickerHome(),
    );
  }
}

class _ShortcutPickerHome extends StatefulWidget {
  const _ShortcutPickerHome();

  @override
  State<_ShortcutPickerHome> createState() => _ShortcutPickerHomeState();
}

class _ShortcutPickerHomeState extends State<_ShortcutPickerHome> {
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final kind = await _chooseKind();
    if (!mounted) return;
    if (kind == null) {
      await _cancel();
      return;
    }

    Map<String, dynamic>? payload;
    if (kind == _ShortcutKind.button) {
      final pick = await _pickButton();
      if (!mounted) return;
      if (pick == null) {
        await _cancel();
        return;
      }
      payload = await buildButtonShortcutPayload(pick);
    } else {
      final macro = await _pickMacro();
      if (!mounted) return;
      if (macro == null) {
        await _cancel();
        return;
      }
      payload = await buildMacroShortcutPayload(macro);
    }

    if (!mounted) return;
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read IR data for that selection.'),
        ),
      );
      await _cancel();
      return;
    }
    await _submit(payload);
  }

  Future<_ShortcutKind?> _chooseKind() {
    return _showPickerSheet<_ShortcutKind>(
      title: 'Bind this key to…',
      builder: (sheetContext) => [
        _TvOption(
          autofocus: true,
          icon: Icons.smart_button_outlined,
          title: 'A single button',
          subtitle: 'Send one IR button when the key is pressed',
          onTap: () => Navigator.of(sheetContext).pop(_ShortcutKind.button),
        ),
        _TvOption(
          icon: Icons.playlist_play_outlined,
          title: 'A macro (sequence)',
          subtitle: 'Run a saved macro when the key is pressed',
          onTap: () => Navigator.of(sheetContext).pop(_ShortcutKind.macro),
        ),
      ],
    );
  }

  Future<QuickTilePick?> _pickButton() async {
    await _ensureRemotesLoaded();
    if (!mounted) return null;
    if (remotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No remotes available.')),
      );
      return null;
    }

    final Remote? remote = await _showPickerSheet<Remote>(
      title: 'Pick a remote',
      builder: (sheetContext) => [
        for (int i = 0; i < remotes.length; i++)
          _TvOption(
            autofocus: i == 0,
            icon: Icons.settings_remote_outlined,
            title: remotes[i].name,
            subtitle: '${remotes[i].buttons.length} buttons',
            onTap: () => Navigator.of(sheetContext).pop(remotes[i]),
          ),
      ],
    );
    if (remote == null || !mounted) return null;
    if (remote.buttons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That remote has no buttons.')),
      );
      return null;
    }

    final IRButton? button = await showModalBottomSheet<IRButton>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ButtonSearchSheet(
        buttons: remote.buttons,
        labelFor: _labelFor,
      ),
    );
    if (button == null || !mounted) return null;

    return QuickTilePick(
      remote: remote,
      button: button,
      title: _labelFor(button),
    );
  }

  Future<TimedMacro?> _pickMacro() async {
    List<TimedMacro> macros;
    try {
      macros = await readMacros();
    } catch (_) {
      macros = const [];
    }
    if (!mounted) return null;
    if (macros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No macros saved yet.')),
      );
      return null;
    }
    return _showPickerSheet<TimedMacro>(
      title: 'Pick a macro',
      builder: (sheetContext) => [
        for (int i = 0; i < macros.length; i++)
          _TvOption(
            autofocus: i == 0,
            icon: Icons.playlist_play_outlined,
            title: macros[i].name,
            subtitle: macros[i].remoteName.trim().isEmpty
                ? '${macros[i].steps.length} steps'
                : '${macros[i].remoteName} · ${macros[i].steps.length} steps',
            onTap: () => Navigator.of(sheetContext).pop(macros[i]),
          ),
      ],
    );
  }

  String _labelFor(IRButton button) => displayButtonLabel(
        button,
        fallback: context.l10n.unnamedButton,
        iconFallback: context.l10n.iconFallback,
        iconNameLocalizer: (name) => localizedIconPickerName(context.l10n, name),
      );

  /// Scrollable, D-pad-friendly bottom sheet of [_TvOption]s with a title.
  Future<T?> _showPickerSheet<T>({
    required String title,
    required List<Widget> Function(BuildContext) builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: builder(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(Map<String, dynamic> payload) async {
    if (_finished) return;
    _finished = true;
    try {
      await _pickerChannel.invokeMethod('submit', payload);
    } catch (_) {
      // The native side finishes the activity; nothing more to do here.
    }
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _finished = true;
    try {
      await _pickerChannel.invokeMethod('cancel');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// A large, D-pad-friendly selectable row with a clearly visible focus ring — the
/// default Material focus tint is too subtle to read across a TV room.
class _TvOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  const _TvOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
  });

  @override
  State<_TvOption> createState() => _TvOptionState();
}

class _TvOptionState extends State<_TvOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: _focused ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: widget.autofocus,
          onFocusChange: (f) => setState(() => _focused = f),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? cs.primary : Colors.transparent,
                width: 3,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: _focused ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color:
                              _focused ? cs.onPrimaryContainer : cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: (_focused
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant)
                                .withValues(alpha: 0.9),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Button picker with a search box (important for remotes with many buttons) and a
/// clearly visible TV focus ring on both the search field and the list rows.
class _ButtonSearchSheet extends StatefulWidget {
  final List<IRButton> buttons;
  final String Function(IRButton) labelFor;

  const _ButtonSearchSheet({required this.buttons, required this.labelFor});

  @override
  State<_ButtonSearchSheet> createState() => _ButtonSearchSheetState();
}

class _ButtonSearchSheetState extends State<_ButtonSearchSheet> {
  String _query = '';

  // On a TV the search box otherwise traps the D-pad — arrow-down/up here hand
  // focus to the surrounding list instead of staying stuck in the text field.
  late final FocusNode _searchFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          node.nextFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          node.previousFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
  );

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.buttons
        : widget.buttons
            .where((b) => widget.labelFor(b).toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text('Pick a button', style: theme.textTheme.titleLarge),
            ),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search ${widget.buttons.length} buttons',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: cs.outlineVariant, width: 1),
                ),
                // Thick primary border so the search box is obviously focused on a TV.
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 3),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching buttons',
                          textAlign: TextAlign.center),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _TvOption(
                        // Only auto-grab focus before the user starts typing,
                        // so filtering doesn't yank focus off the search box.
                        autofocus: i == 0 && q.isEmpty,
                        icon: Icons.radio_button_checked_outlined,
                        title: widget.labelFor(filtered[i]),
                        onTap: () => Navigator.of(context).pop(filtered[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a single button to a self-contained IR payload (frequency + raw pattern)
/// that can be transmitted natively with no Flutter engine running.
Future<Map<String, dynamic>?> buildButtonShortcutPayload(
    QuickTilePick pick) async {
  await _ensureRemotesLoaded();
  IRButton? resolved;
  Remote? owner;
  for (final r in remotes) {
    for (final b in r.buttons) {
      if (b.id == pick.button.id) {
        resolved = b;
        owner = r;
        break;
      }
    }
    if (resolved != null) break;
  }
  if (resolved == null) return null;

  final IrPreview preview;
  try {
    preview = previewIRButton(resolved);
  } catch (_) {
    return null;
  }

  return <String, dynamic>{
    'title': pick.title,
    'subtitle': owner?.name ?? pick.remote.name,
    'fallbackButtonId': resolved.id,
    'steps': <Map<String, dynamic>>[
      {
        'frequencyHz': preview.frequencyHz,
        'pattern': preview.pattern,
        'delayAfterMs': 0,
      },
    ],
  };
}

/// Resolves a macro into an ordered list of IR bursts with inter-burst delays, so
/// it can be played back natively and silently.
Future<Map<String, dynamic>?> buildMacroShortcutPayload(
    TimedMacro macro) async {
  await _ensureRemotesLoaded();

  Remote? remote;
  for (final r in remotes) {
    if (r.name == macro.remoteName) {
      remote = r;
      break;
    }
  }
  if (remote == null) return null;

  final steps = <Map<String, dynamic>>[];
  Map<String, dynamic>? current;
  String? fallbackButtonId;

  void addDelay(int ms) {
    if (current == null || ms <= 0) return;
    current!['delayAfterMs'] = (current!['delayAfterMs'] as int) + ms;
  }

  for (final step in macro.steps) {
    switch (step.type) {
      case MacroStepType.send:
        final button = _resolveMacroButton(remote, step);
        if (button == null) break;
        final IrPreview preview;
        try {
          preview = previewIRButton(button);
        } catch (_) {
          break;
        }
        if (current != null) steps.add(current);
        current = <String, dynamic>{
          'frequencyHz': preview.frequencyHz,
          'pattern': preview.pattern,
          'delayAfterMs': 0,
        };
        fallbackButtonId ??= button.id;
        break;
      case MacroStepType.delay:
        addDelay((step.delayMs ?? 0).clamp(0, 600000).toInt());
        break;
      case MacroStepType.manualContinue:
        addDelay(_manualContinueFallbackMs);
        break;
    }
  }
  if (current != null) steps.add(current);
  if (steps.isEmpty || fallbackButtonId == null) return null;

  return <String, dynamic>{
    'title': macro.name,
    'subtitle': macro.remoteName,
    'fallbackButtonId': fallbackButtonId,
    'steps': steps,
  };
}

IRButton? _resolveMacroButton(Remote remote, MacroStep step) {
  final id = (step.buttonId ?? '').trim();
  if (id.isNotEmpty) {
    for (final b in remote.buttons) {
      if (b.id == id) return b;
    }
  }
  final ref = normalizeButtonKey(step.buttonRef ?? '');
  if (ref.isNotEmpty) {
    for (final b in remote.buttons) {
      if (normalizeButtonKey(b.image) == ref) return b;
    }
  }
  final refFromId = normalizeButtonKey(step.buttonId ?? '');
  if (refFromId.isNotEmpty) {
    for (final b in remote.buttons) {
      if (normalizeButtonKey(b.image) == refFromId) return b;
    }
  }
  return null;
}

Future<void> _ensureRemotesLoaded() async {
  if (remotes.isNotEmpty) return;
  try {
    remotes = await readRemotes();
  } catch (_) {}
}
