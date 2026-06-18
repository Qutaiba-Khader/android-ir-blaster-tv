import 'dart:async';

import 'package:flutter/material.dart';
import 'package:irblaster_controller/utils/ir.dart';
import 'package:irblaster_controller/utils/remote.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/fire_flash.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// Remote View (spec §5.2): 5-col IR key grid for one remote. Pressing a key
/// transmits via the app's real `sendIR()` and fires the §7.3 feedback (radial
/// flash + status strip flip).
class RemoteViewScreen extends StatefulWidget {
  const RemoteViewScreen({
    super.key,
    required this.remote,
    required this.onBack,
    required this.flash,
    required this.onEdit,
  });

  final Remote remote;
  final VoidCallback onBack;
  final FireFlashController flash;
  final VoidCallback onEdit;

  @override
  State<RemoteViewScreen> createState() => _RemoteViewScreenState();
}

class _RemoteViewScreenState extends State<RemoteViewScreen> {
  String? _lastKey; // null = idle status strip
  Timer? _revert;

  Future<void> _fire(IRButton b) async {
    final label = csButtonLabel(b);
    setState(() => _lastKey = label.isEmpty ? 'KEY' : label.toUpperCase());
    widget.flash.fire();
    try {
      await sendIR(b);
    } catch (_) {/* errors are reported inside sendIR */}
    // Revert the status strip to idle after a moment; a single restartable timer.
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _lastKey = null);
    });
  }

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttons = widget.remote.buttons;
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            remote: widget.remote,
            firedKey: _lastKey,
            onBack: widget.onBack,
            onEdit: widget.onEdit,
          ),
          const SizedBox(height: 22),
          Expanded(
            child: buttons.isEmpty
                ? const _EmptyKeys()
                : GridView.builder(clipBehavior: Clip.none, 
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppSizes.irKeyCols,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 18,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: buttons.length,
                    itemBuilder: (context, i) => RepaintBoundary(
                      child: i == 0
                          ? PrimaryFocus(
                              builder: (n) => _IrKey(
                                button: buttons[0],
                                focusNode: n,
                                onPressed: () => _fire(buttons[0]),
                              ),
                            )
                          : _IrKey(
                              button: buttons[i],
                              onPressed: () => _fire(buttons[i]),
                            ),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          const HintStrip('◀ BACK · ENTER = TRANSMIT · ⋯ = PER-BUTTON ACTIONS'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.remote, required this.firedKey, required this.onBack, required this.onEdit});
  final Remote remote;
  final String? firedKey;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FocusableSurface(
          onPressed: onBack,
          autofocus: false,
          borderRadius: AppRadii.r14,
          padding: const EdgeInsets.all(15),
          restShadow: AppShadows.sm,
          child: const Sym(AppIcons.back, size: AppIconSizes.headerBtn, color: AppColors.ink),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(remote.name.isEmpty ? 'REMOTE' : remote.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.drillHeader),
              const SizedBox(height: 4),
              Text('${remote.buttons.length} KEYS · USB-IR · 38kHz',
                  style: AppType.meta.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FocusableSurface(
          onPressed: onEdit,
          borderRadius: AppRadii.r14,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          restShadow: AppShadows.sm,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Sym(AppIcons.edit, size: AppIconSizes.headerCtl, color: AppColors.ink),
              const SizedBox(width: 10),
              Text('EDIT', style: AppType.buttonLabel),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _StatusStrip(firedKey: firedKey),
      ],
    );
  }
}

/// Transmit status strip — idle (cream) ↔ fired (orange), spec §7.3.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.firedKey});
  final String? firedKey;

  @override
  Widget build(BuildContext context) {
    final fired = firedKey != null;
    return AnimatedContainer(
      duration: AppMotion.focusDefault,
      curve: AppMotion.curve,
      constraints: const BoxConstraints(minWidth: 330),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: fired ? AppColors.focus : AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r14),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sym(fired ? AppIcons.txFired : AppIcons.sensorsIdle,
              size: AppIconSizes.status, color: fired ? Colors.white : AppColors.ink),
          const SizedBox(width: 10),
          Text(
            fired ? '▶ $firedKey · TX 38.0kHz · SENT' : 'IR READY · 38.0kHz',
            style: AppType.buttonLabel.copyWith(color: fired ? Colors.white : AppColors.ink),
          ),
        ],
      ),
    );
  }
}

class _IrKey extends StatelessWidget {
  const _IrKey({required this.button, required this.onPressed, this.focusNode});
  final IRButton button;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final icon = csButtonIcon(button);
    final label = csButtonLabel(button);
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Sym(icon ?? AppIcons.bolt, size: AppIconSizes.irKey, color: AppColors.ink),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.buttonLabel),
        ],
      ],
    );
    // Keys are uniform cream (no random accent fill); orange only on focus.
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r14,
      scale: AppFocus.scaleCard,
      fill: AppColors.surface,
      restShadow: AppShadows.md,
      padding: const EdgeInsets.all(8),
      child: Center(child: content),
    );
  }
}

class _EmptyKeys extends StatelessWidget {
  const _EmptyKeys();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.stateEmpty, size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('NO BUTTONS YET', style: AppType.eyebrow),
        ],
      ),
    );
  }
}
