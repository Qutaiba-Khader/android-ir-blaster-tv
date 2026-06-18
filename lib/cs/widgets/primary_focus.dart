import 'package:flutter/material.dart';

/// Wraps a screen's primary (default-focus) item so it RELIABLY holds focus the
/// moment the screen appears — killing the intermittent "first D-pad press gets
/// absorbed while focus settles" issue on TV (a known focus-retention race after a
/// screen/drill swap).
///
/// It requests focus after the first frame, then re-asserts shortly after — but the
/// re-assert only fires if focus is still "nowhere" (null or parked on a scope), so
/// it never fights the user once they've started navigating.
class PrimaryFocus extends StatefulWidget {
  const PrimaryFocus({super.key, required this.builder});

  /// Builds the focusable child, passing the managed [FocusNode] to wire into its
  /// `FocusableSurface(focusNode: ...)`.
  final Widget Function(FocusNode node) builder;

  @override
  State<PrimaryFocus> createState() => _PrimaryFocusState();
}

class _PrimaryFocusState extends State<PrimaryFocus> {
  final FocusNode _node = FocusNode(debugLabel: 'cs-primary');

  @override
  void initState() {
    super.initState();
    // First assert: claim default focus once this screen has laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _node.requestFocus();
    });
    // Re-assert after the focus-retention race settles (drill/screen swap), but
    // ONLY if focus is still unplaced — never steal it back from the user.
    Future.delayed(const Duration(milliseconds: 130), () {
      if (!mounted) return;
      final pf = FocusManager.instance.primaryFocus;
      if (pf == null || pf is FocusScopeNode || !pf.hasPrimaryFocus) {
        _node.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_node);
}
