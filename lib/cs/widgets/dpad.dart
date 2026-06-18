import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'spatial_traversal_policy.dart';

/// Fired when the user presses any "back" key on the remote. Wire it to your
/// router's pop (remoteView→remotes, etc — see FLUTTER_UI_GUIDE §1).
class BackIntent extends Intent {
  const BackIntent();
}

/// DpadScope — wrap the whole app (above MaterialApp's home, or around your shell)
/// to normalize the quirky set of keys real TV remotes / Android TV send. Mirrors the
/// prototype's GlobalKeyTranslator: many remotes deliver "back" as Escape, Backspace,
/// browserBack, goBack, or gameButtonB — not a single canonical key.
///
/// Directional ▲▼◀▶ already map to DirectionalFocusIntent via Flutter's default
/// shortcuts; this adds the missing BACK + extra SELECT bindings and installs the
/// SpatialTraversalPolicy so arrow movement matches the prototype's edge-gap +
/// cross-overlap scorer (same row for ◀▶, same column for ▲▼).
///
/// Rail-entry behavior (see FLUTTER_UI_GUIDE §8): entering the content from the rail —
/// whether by pressing ▶ on a rail item or by activating it (OK/tap) — should land
/// focus on the screen's MAIN region (the grid), skipping banner/header chrome. Drive
/// that from the shell: give the content its own FocusScopeNode and, on rail activate /
/// right-from-rail, call `contentScope.requestFocus()` (or focus an explicit
/// `firstCardNode`) AFTER the screen swap settles — `addPostFrameCallback`.
class DpadScope extends StatelessWidget {
  const DpadScope({super.key, required this.child, required this.onBack});

  final Widget child;
  final VoidCallback onBack;

  static const _backKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.gameButtonB,
  ];

  static const _selectKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.select,      // Android TV DPAD_CENTER
    LogicalKeyboardKey.gameButtonA,
  ];

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final k in _backKeys) SingleActivator(k): const BackIntent(),
        // Ensure the physical OK button also activates the focused control,
        // matching Enter/Space which Flutter already binds.
        for (final k in _selectKeys) SingleActivator(k): const ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
            onBack();
            return null;
          }),
        },
        child: FocusTraversalGroup(
          policy: SpatialTraversalPolicy(),
          child: child,
        ),
      ),
    );
  }
}
