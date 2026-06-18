import 'dart:async';

import 'package:flutter/material.dart';
import 'package:irblaster_controller/models/macro_step.dart';
import 'package:irblaster_controller/models/timed_macro.dart';
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

/// Macro Run (spec §5.5 / §7.4): a centered full-screen hero — kicker + big macro
/// name + status line + a vertical step list (~760 wide) that highlights LIVE as
/// the sequence executes. The active step gets a [AppColors.focus] fill + glow
/// ([AppShadows.runActive]); finished steps go [AppColors.success] + a check.
///
/// Execution reuses the existing engine's contract exactly: SEND steps resolve a
/// button in `remote.buttons` (by id, then by normalized ref) and transmit via the
/// app's real [sendIR]; DELAY steps wait `delayMs`; MANUAL-CONTINUE steps pause for
/// an OK press. Each IR send drives [FireFlashController.fire] (the §7.3 flash).
/// Non-delay steps advance every [AppMotion.runAdvance] (~950 ms).
class MacroRunCs extends StatefulWidget {
  const MacroRunCs({
    super.key,
    required this.macro,
    required this.remote,
    required this.onBack,
    required this.flash,
  });

  final TimedMacro macro;
  final Remote remote;
  final VoidCallback onBack;
  final FireFlashController flash;

  @override
  State<MacroRunCs> createState() => _MacroRunCsState();
}

class _MacroRunCsState extends State<MacroRunCs> {
  bool _running = false;
  bool _waitingForManual = false;
  bool _executing = false;
  bool _completed = false;
  int _currentStep = 0;
  int _remainingMs = 0;

  @override
  void initState() {
    super.initState();
    // Auto-run on entry — the user arrived here by pressing RUN.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _running = false;
    _waitingForManual = false;
    super.dispose();
  }

  // --- Button resolution: mirrors the existing MacroRunScreen exactly. ---

  IRButton? _findButtonById(String? id) {
    final key = (id ?? '').trim();
    if (key.isEmpty) return null;
    try {
      return widget.remote.buttons.firstWhere((b) => b.id == key);
    } catch (_) {
      return null;
    }
  }

  IRButton? _findButtonByRef(String? ref) {
    final key = normalizeButtonKey(ref ?? '');
    if (key.isEmpty) return null;
    try {
      return widget.remote.buttons
          .firstWhere((b) => normalizeButtonKey(b.image) == key);
    } catch (_) {
      return null;
    }
  }

  IRButton? _resolveButton(MacroStep step) {
    final byId = _findButtonById(step.buttonId);
    if (byId != null) return byId;
    return _findButtonByRef(step.buttonRef) ?? _findButtonByRef(step.buttonId);
  }

  // --- Execution engine (re-implemented from MacroRunScreen). ---

  Future<void> _start() async {
    if (_executing) return;
    if (widget.macro.steps.isEmpty) return;
    setState(() {
      _running = true;
      _waitingForManual = false;
      _completed = false;
      _currentStep = 0;
      _remainingMs = 0;
    });
    await _executeSteps();
  }

  void _stop() {
    setState(() {
      _running = false;
      _waitingForManual = false;
      _remainingMs = 0;
    });
  }

  Future<void> _continueManual() async {
    if (!_waitingForManual || _executing) return;
    setState(() {
      _waitingForManual = false;
      if (_currentStep < widget.macro.steps.length) _currentStep++;
    });
    if (_running) await _executeSteps();
  }

  Future<void> _executeSteps() async {
    if (_executing) return;
    _executing = true;
    try {
      final steps = widget.macro.steps;
      while (mounted && _running && _currentStep < steps.length) {
        final step = steps[_currentStep];

        if (!step.isValid) {
          _stop();
          return;
        }

        if (step.type == MacroStepType.send) {
          final button = _resolveButton(step);
          if (button != null) {
            widget.flash.fire(); // §7.3 transmit feedback
            try {
              await sendIR(button); // the app's real IR send
            } catch (_) {/* errors are surfaced inside sendIR */}
          }
          if (!mounted) return;
          // Hold the highlight on this step for the advance beat (~950 ms).
          await Future<void>.delayed(AppMotion.runAdvance);
          if (!mounted || !_running) return;
          setState(() => _currentStep++);
          continue;
        }

        if (step.type == MacroStepType.delay) {
          final ms = step.delayMs ?? 0;
          if (!mounted) return;
          setState(() => _remainingMs = ms);
          await _delayWithCountdown(ms);
          if (!mounted || !_running) return;
          setState(() {
            _remainingMs = 0;
            _currentStep++;
          });
          continue;
        }

        if (step.type == MacroStepType.manualContinue) {
          if (!mounted) return;
          setState(() => _waitingForManual = true);
          return; // resumes from _continueManual()
        }
      }

      if (!mounted || !_running) return;
      setState(() {
        _running = false;
        _waitingForManual = false;
        _remainingMs = 0;
        _completed = true;
      });
    } finally {
      _executing = false;
    }
  }

  Future<void> _delayWithCountdown(int ms) async {
    if (ms <= 0) {
      if (mounted) setState(() => _remainingMs = 0);
      return;
    }
    final sw = Stopwatch()..start();
    const tickMs = 100;
    while (mounted && _running) {
      final remaining = ms - sw.elapsedMilliseconds;
      if (remaining <= 0) {
        setState(() => _remainingMs = 0);
        return;
      }
      setState(() => _remainingMs = remaining);
      final sleep = remaining < tickMs ? remaining : tickMs;
      await Future<void>.delayed(Duration(milliseconds: sleep));
    }
  }

  String _stepText(MacroStep step) {
    switch (step.type) {
      case MacroStepType.send:
        final button = _resolveButton(step);
        if (button != null) {
          final label = csButtonLabel(button);
          return label.isEmpty ? 'SEND KEY' : 'SEND · ${label.toUpperCase()}';
        }
        final fallback = (step.buttonRef ?? step.buttonId ?? '').trim();
        return fallback.isEmpty ? 'SEND · UNKNOWN' : 'SEND · ${fallback.toUpperCase()}';
      case MacroStepType.delay:
        return 'WAIT ${step.delayMs ?? 0} MS';
      case MacroStepType.manualContinue:
        return 'WAIT FOR OK';
    }
  }

  String _statusLine(int total) {
    if (total == 0) return 'NO STEPS';
    if (_completed) return 'SEQUENCE COMPLETE · $total / $total';
    if (_waitingForManual) return 'PAUSED · PRESS OK TO CONTINUE';
    if (_running && _remainingMs > 0) {
      final sec = (_remainingMs / 1000).toStringAsFixed(1);
      return 'WAITING · ${sec}S · STEP ${(_currentStep + 1).clamp(1, total)} / $total';
    }
    if (_running) {
      return 'RUNNING · STEP ${(_currentStep + 1).clamp(1, total)} / $total';
    }
    return 'STOPPED · STEP ${(_currentStep + 1).clamp(1, total)} / $total';
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.macro.steps;
    final total = steps.length;
    final name = widget.macro.name.isEmpty ? 'MACRO' : widget.macro.name;

    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ---- Hero header (kicker + big name + status line) ----
          const Kicker('RUNNING SEQUENCE'),
          const SizedBox(height: 10),
          Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppType.heroTitle,
          ),
          const SizedBox(height: 14),
          Text(_statusLine(total), style: AppType.eyebrow),
          const SizedBox(height: 26),
          // ---- Live step list (~760 wide) ----
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 760,
                child: total == 0
                    ? const _EmptySteps()
                    : ListView.separated(clipBehavior: Clip.none, 
                        padding: const EdgeInsets.all(16),
                        itemCount: total,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final isActive = i == _currentStep && _running;
                          final isDone = i < _currentStep ||
                              (_completed && i < total);
                          return RepaintBoundary(
                            child: _RunStepRow(
                              index: i,
                              text: _stepText(steps[i]),
                              kind: _kindLabel(steps[i].type),
                              tone: _stepTone(steps[i].type),
                              icon: _stepIcon(steps[i].type),
                              isActive: isActive,
                              isDone: isDone,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ---- STOP (primary focus) ----
          PrimaryFocus(
            builder: (n) => _StopButton(
              focusNode: n,
              completed: _completed,
              onPressed: () {
                if (_completed || !_running) {
                  widget.onBack();
                } else {
                  _stop();
                }
              },
              onContinue: _waitingForManual ? _continueManual : null,
            ),
          ),
          const SizedBox(height: 16),
          const HintStrip('OK = STOP · BACK LEAVES WHEN IDLE'),
        ],
      ),
    );
  }

  String _kindLabel(MacroStepType t) {
    switch (t) {
      case MacroStepType.send:
        return 'SEND';
      case MacroStepType.delay:
        return 'DELAY';
      case MacroStepType.manualContinue:
        return 'MANUAL';
    }
  }

  IconData _stepIcon(MacroStepType t) {
    switch (t) {
      case MacroStepType.send:
        return AppIcons.txFired;
      case MacroStepType.delay:
        return AppIcons.stepDelay;
      case MacroStepType.manualContinue:
        return AppIcons.stepManual;
    }
  }

  Color _stepTone(MacroStepType t) {
    switch (t) {
      case MacroStepType.send:
        return AppColors.toneAudio;
      case MacroStepType.delay:
        return AppColors.toneLearning;
      case MacroStepType.manualContinue:
        return AppColors.toneAppearance;
    }
  }
}

/// One live step row. Resting = cream surface; active = orange focus fill + glow;
/// done = success fill + a check glyph (spec §7.4 / §8 macro step row).
class _RunStepRow extends StatelessWidget {
  const _RunStepRow({
    required this.index,
    required this.text,
    required this.kind,
    required this.tone,
    required this.icon,
    required this.isActive,
    required this.isDone,
  });

  final int index;
  final String text;
  final String kind;
  final Color tone;
  final IconData icon;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final Color fill = isActive
        ? AppColors.focus
        : (isDone ? AppColors.success : AppColors.surface);
    final Color fg = isActive ? Colors.white : AppColors.ink;
    final List<BoxShadow> shadow =
        isActive ? AppShadows.runActive : AppShadows.md;

    return AnimatedContainer(
      duration: AppMotion.runStep,
      curve: AppMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: isActive ? AppColors.focus : AppColors.ink,
          width: isActive ? AppFocus.ringWidth : AppBorders.width,
        ),
        borderRadius: BorderRadius.circular(AppRadii.r16),
        boxShadow: shadow,
      ),
      child: Row(
        children: [
          // Step number / done check.
          SizedBox(
            width: 34,
            child: isDone && !isActive
                ? Sym(AppIcons.check, size: 24, color: fg)
                : Text('${index + 1}',
                    style: AppType.keyGlyph.copyWith(color: fg)),
          ),
          const SizedBox(width: 12),
          IconChip(icon, tone: tone, dim: 46, iconSize: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind,
                    style: AppType.microLabel.copyWith(
                        color: isActive
                            ? Colors.white
                            : AppColors.textMutedAlt)),
                const SizedBox(height: 4),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowTitle.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({
    required this.focusNode,
    required this.completed,
    required this.onPressed,
    this.onContinue,
  });

  final FocusNode focusNode;
  final bool completed;
  final VoidCallback onPressed;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final bool isContinue = onContinue != null;
    final String label = isContinue
        ? 'CONTINUE'
        : (completed ? 'DONE — BACK' : 'STOP');
    final IconData icon =
        isContinue ? AppIcons.run : (completed ? AppIcons.check : AppIcons.off);
    return SizedBox(
      width: 360,
      child: FocusableSurface(
        focusNode: focusNode,
        onPressed: isContinue ? onContinue! : onPressed,
        borderRadius: AppRadii.r16,
        fill: completed && !isContinue ? AppColors.success : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Sym(icon, size: 22, color: AppColors.ink),
            const SizedBox(width: 10),
            Text(label, style: AppType.buttonLabel),
          ],
        ),
      ),
    );
  }
}

class _EmptySteps extends StatelessWidget {
  const _EmptySteps();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.stateEmpty,
              size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('THIS MACRO HAS NO STEPS', style: AppType.eyebrow),
        ],
      ),
    );
  }
}
