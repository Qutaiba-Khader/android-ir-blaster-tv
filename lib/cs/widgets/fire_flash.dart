import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Signature transmit feedback (spec §7.3): a full-screen radial orange flash that
/// fades .95 → 0 over 460 ms. IR is invisible, so this is the user's only "it fired"
/// confirmation. Driven by a [FireFlashController] so any screen can trigger it.
class FireFlashController extends ChangeNotifier {
  int _tick = 0;
  int get tick => _tick;
  void fire() {
    _tick++;
    notifyListeners();
  }
}

/// Wrap a screen's content in this to render the radial flash on top on each fire().
class FireFlashOverlay extends StatefulWidget {
  const FireFlashOverlay({super.key, required this.controller, required this.child});
  final FireFlashController controller;
  final Widget child;

  @override
  State<FireFlashOverlay> createState() => _FireFlashOverlayState();
}

class _FireFlashOverlayState extends State<FireFlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this, duration: AppMotion.fireFlash);
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _ac, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFire);
  }

  void _onFire() {
    // Restart: value 0→1 over 460ms; opacity is derived as 0.95·(1−eased).
    _ac.forward(from: 0.0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFire);
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, 
      children: [
        // Isolate the (static) screen so the animating flash never repaints it.
        RepaintBoundary(child: widget.child),
        // RepaintBoundary keeps the flash from invalidating the whole subtree.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ac,
                builder: (context, _) {
                  final t = _ac.value; // 0..1 elapsed
                  if (t >= 1.0 || _ac.status == AnimationStatus.dismissed) {
                    return const SizedBox.shrink();
                  }
                  final o = (0.95 * (1.0 - _opacity.value)).clamp(0.0, 0.95);
                  if (o <= 0.001) return const SizedBox.shrink();
                  return Opacity(
                    opacity: o,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.10, 0.0), // ~55% across
                          radius: 0.9,
                          // Opaque accent → the surrounding Opacity does the .95→0
                          // ramp on its own (no double-attenuation, spec §7.3).
                          colors: [AppColors.accent, Color(0x00FF5A1F)],
                          stops: [0.0, 0.58],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
