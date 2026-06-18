import 'dart:async';

import 'package:flutter/material.dart';
import 'package:irblaster_controller/ir_finder/irblaster_db.dart';
import 'package:irblaster_controller/state/haptics.dart';
import 'package:irblaster_controller/universal_power/power_code_repository.dart';
import 'package:irblaster_controller/universal_power/universal_power_controller.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/fire_flash.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// Universal Power-off (spec §5.6 tester tool) in the Control Surface look —
/// "blast every brand's OFF code in sequence".
///
/// Backend reused EXACTLY from the app's `UniversalPowerScreen`:
///  • `PowerCodeRepository.loadAllPowerCodes` / `loadPowerCodes` build the queue
///    (all brands, or filtered by [initialBrand]/[initialModel]);
///  • `UniversalPowerController.start/stop` drives the blast loop, progress
///    (`index`/`queue.length`), `lastSent`, `lastError` — its own internal timer
///    + `_send` (raw vs encoded protocol) is untouched;
///  • a capabilities listener gates "no transmitter".
///
/// CS additions: each emitted code triggers [flash].fire() (the §7.3 radial
/// transmit flash, the only visible "it fired" cue) and a big STOP CTA.
class UniversalPowerCs extends StatefulWidget {
  const UniversalPowerCs({
    super.key,
    required this.onBack,
    this.flash,
    this.initialBrand,
    this.initialModel,
  });

  final VoidCallback onBack;
  final FireFlashController? flash;
  final String? initialBrand;
  final String? initialModel;

  @override
  State<UniversalPowerCs> createState() => _UniversalPowerCsState();
}

class _UniversalPowerCsState extends State<UniversalPowerCs>
    with WidgetsBindingObserver {
  final IrBlasterDb _db = IrBlasterDb.instance;
  late final PowerCodeRepository _repo = PowerCodeRepository(db: _db);
  final UniversalPowerController _controller = UniversalPowerController();

  StreamSubscription<IrTransmitterCapabilities>? _capsSub;
  IrTransmitterCapabilities? _caps;

  bool _dbReady = false;
  bool _dbInitFailed = false;
  bool _starting = false;
  String? _notice;

  String? _brand;
  String? _model;

  // Drives flash.fire() once per newly-sent code (controller index advances).
  int _lastFiredIndex = -1;
  bool _pausedByLifecycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _brand = widget.initialBrand?.trim();
    _model = widget.initialModel?.trim();
    _controller.addListener(_onControllerChange);
    _initDb();
    _capsSub = IrTransmitterPlatform.capabilitiesEvents().listen((caps) {
      if (!mounted) return;
      setState(() => _caps = caps);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _capsSub?.cancel();
    _controller.removeListener(_onControllerChange);
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mirror the app screen: auto-pause the blast when backgrounded.
    if (!_controller.running) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_controller.paused) return;
      _controller.pause();
      _pausedByLifecycle = true;
      setState(() {});
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      _controller.resume();
      setState(() {});
    }
  }

  Future<void> _initDb() async {
    try {
      await _db.ensureInitialized();
      if (!mounted) return;
      setState(() {
        _dbReady = true;
        _dbInitFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dbReady = false;
        _dbInitFailed = true;
      });
    }
  }

  void _onControllerChange() {
    if (!mounted) return;
    // Fire the transmit flash exactly when a new code has just been sent.
    final fired = _controller.index - 1; // _send increments index after success
    if (_controller.running &&
        _controller.lastSent != null &&
        fired >= 0 &&
        fired != _lastFiredIndex) {
      _lastFiredIndex = fired;
      widget.flash?.fire();
    }
    if (!_controller.running) _lastFiredIndex = -1;
    setState(() {});
  }

  bool _hasTransmitter() {
    final caps = _caps;
    if (caps == null) return true; // optimistic until caps arrive
    return caps.hasInternal || caps.usbReady || caps.hasAudio;
  }

  Future<void> _start() async {
    if (!_dbReady || _starting || _controller.running) return;
    if (!_hasTransmitter()) {
      setState(() => _notice = 'NO IR TRANSMITTER AVAILABLE');
      return;
    }
    setState(() {
      _starting = true;
      _notice = null;
    });
    try {
      final brand = _brand?.trim();
      // Same repository calls + tuning the app uses (depth 2, no broaden).
      final codes = (brand == null || brand.isEmpty)
          ? await _repo.loadAllPowerCodes(
              broadenSearch: false,
              maxCodes: 1200,
              depth: 2,
            )
          : await _repo.loadPowerCodes(
              brand: brand,
              model: _model?.trim(),
              broadenSearch: false,
              maxCodes: 600,
              depth: 2,
            );
      if (!mounted) return;
      if (codes.isEmpty) {
        setState(() {
          _starting = false;
          _notice = 'NO POWER CODES FOUND';
        });
        return;
      }
      _lastFiredIndex = -1;
      final ok = await _controller.start(
        queue: codes,
        delayMs: 800,
        loop: false,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _starting = false;
          _notice = 'UNABLE TO START';
        });
        return;
      }
      setState(() => _starting = false);
      await Haptics.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _notice = 'START FAILED — ${e.toString().toUpperCase()}';
      });
    }
  }

  Future<void> _stop() async {
    await _controller.stop();
    if (!mounted) return;
    setState(() {});
    await Haptics.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(brand: _brand, model: _model, onBack: widget.onBack),
          const SizedBox(height: 22),
          Expanded(child: _content(context)),
          const SizedBox(height: 16),
          const HintStrip(
              '◀ BACK · ENTER = BLAST / STOP · STOP WHEN THE DEVICE TURNS OFF'),
        ],
      ),
    );

    // Pushed routes don't inherit the shell's FireFlashOverlay — own one here so
    // the radial transmit flash is visible on this screen when a controller is given.
    if (widget.flash != null) {
      return FireFlashOverlay(controller: widget.flash!, child: body);
    }
    return body;
  }

  Widget _content(BuildContext context) {
    final running = _controller.running;
    final queueSize = _controller.queue.length;
    final index = _controller.index.clamp(0, queueSize);
    final progress = queueSize == 0 ? 0.0 : index / queueSize;
    final last = _controller.lastSent;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBlock(
              running: running,
              paused: _controller.paused,
              dbReady: _dbReady,
              dbInitFailed: _dbInitFailed,
              index: index,
              queueSize: queueSize,
              progress: progress,
              lastLabel: last == null
                  ? null
                  : '${last.label} · ${last.protocolId.toUpperCase()} ${last.hexCode}',
              lastError: _controller.lastError?.toString(),
              notice: _notice,
            ),
            const SizedBox(height: 28),
            Center(
              child: running
                  ? PrimaryFocus(
                      builder: (n) => _BigButton(
                        focusNode: n,
                        icon: AppIcons.close,
                        label: 'STOP',
                        tone: AppColors.error,
                        onPressed: _stop,
                      ),
                    )
                  : PrimaryFocus(
                      builder: (n) => _BigButton(
                        focusNode: n,
                        icon: AppIcons.powerOff,
                        label: _starting ? 'PREPARING…' : 'BLAST OFF CODES',
                        tone: AppColors.accent,
                        onPressed: (_dbReady && !_starting) ? _start : () {},
                      ),
                    ),
            ),
            if (!_dbReady) ...[
              const SizedBox(height: 18),
              Center(
                child: _RetryRow(
                  failed: _dbInitFailed,
                  onRetry: _initDb,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.brand, required this.model, required this.onBack});
  final String? brand;
  final String? model;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final scope = (brand == null || brand!.isEmpty)
        ? 'ALL BRANDS'
        : model == null || model!.isEmpty
            ? brand!.toUpperCase()
            : '${brand!.toUpperCase()} · ${model!.toUpperCase()}';
    return Row(
      children: [
        FocusableSurface(
          onPressed: onBack,
          borderRadius: AppRadii.r14,
          padding: const EdgeInsets.all(15),
          restShadow: AppShadows.sm,
          child: const Sym(AppIcons.back,
              size: AppIconSizes.headerBtn, color: AppColors.ink),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kicker('DIAGNOSTICS — UNIVERSAL POWER-OFF'),
              const SizedBox(height: 6),
              Text('POWER-OFF', style: AppType.drillHeader),
              const SizedBox(height: 6),
              Text('SCOPE · $scope',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.running,
    required this.paused,
    required this.dbReady,
    required this.dbInitFailed,
    required this.index,
    required this.queueSize,
    required this.progress,
    required this.lastLabel,
    required this.lastError,
    required this.notice,
  });

  final bool running;
  final bool paused;
  final bool dbReady;
  final bool dbInitFailed;
  final int index;
  final int queueSize;
  final double progress;
  final String? lastLabel;
  final String? lastError;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final state = !dbReady
        ? (dbInitFailed ? 'DATABASE FAILED' : 'PREPARING DATABASE…')
        : running
            ? (paused ? 'PAUSED' : 'BLASTING…')
            : 'IDLE';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r18),
        boxShadow: AppShadows.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(AppIcons.powerOff,
                  tone: running ? AppColors.error : AppColors.toneTv),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state, style: AppType.rowTitle),
                    const SizedBox(height: 4),
                    Text(
                      queueSize > 0
                          ? 'SENT $index OF $queueSize CODES'
                          : 'EVERY BRAND’S OFF CODE, IN SEQUENCE',
                      style: AppType.meta.copyWith(color: AppColors.textMutedAlt),
                    ),
                  ],
                ),
              ),
              if (queueSize > 0)
                TagPill('$index/$queueSize',
                    fill: running ? AppColors.focus : AppColors.surface,
                    textColor: running ? Colors.white : AppColors.ink),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: queueSize == 0 ? null : progress,
              minHeight: 12,
              backgroundColor: AppColors.dividerOnCream,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          if (lastLabel != null) ...[
            const SizedBox(height: 16),
            Text('LAST SENT', style: AppType.microLabel),
            const SizedBox(height: 4),
            Text(lastLabel!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.buttonLabel),
          ],
          if (notice != null) ...[
            const SizedBox(height: 14),
            _Notice(text: notice!, tone: AppColors.error),
          ],
          if (lastError != null) ...[
            const SizedBox(height: 14),
            _Notice(text: 'SEND ERROR · ${lastError!.toUpperCase()}',
                tone: AppColors.error),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(AppRadii.r12),
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.buttonLabel.copyWith(color: AppColors.ink)),
    );
  }
}

class _RetryRow extends StatelessWidget {
  const _RetryRow({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (!failed) {
      return Text('PREPARING THE IR CODE DATABASE…',
          style: AppType.meta.copyWith(color: AppColors.textSecondary));
    }
    return _BigButton(
      icon: AppIcons.txFired,
      label: 'RETRY DATABASE',
      tone: AppColors.surface,
      onPressed: onRetry,
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r20,
      scale: AppFocus.scaleList,
      fill: tone,
      fillFocused: tone,
      restShadow: AppShadows.lg,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 26),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sym(icon, size: 40, color: AppColors.ink),
          const SizedBox(width: 16),
          Text(label,
              style: AppType.drillHeader
                  .copyWith(fontSize: 30, color: AppColors.ink)),
        ],
      ),
    );
  }
}
