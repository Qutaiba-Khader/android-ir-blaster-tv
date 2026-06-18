import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:irblaster_controller/models/macro_step.dart';
import 'package:irblaster_controller/models/timed_macro.dart';
import 'package:irblaster_controller/state/macros_state.dart';
import 'package:irblaster_controller/utils/macros_io.dart';
import 'package:irblaster_controller/utils/remote.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/dotted_box.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// Macro Editor (spec §5.4 / §8 macro step row): header (back · "// EDIT SEQUENCE"
/// + name field · SAVE) → numbered reorderable vertical step list → 3 dashed
/// add-step buttons (SEND / DELAY / MANUAL).
///
/// Persistence reuses the app's real macro store EXACTLY: on SAVE it builds a
/// [TimedMacro] (same shape the existing editor builds), upserts it into the global
/// `macros` list, then `writeMacrosList(macros)` + `notifyMacrosChanged()` — the
/// same sequence `macros_tab.dart` runs after its editor returns. SEND steps are
/// added through a button-pick bottom sheet over `remote.buttons`.
class MacroEditorCs extends StatefulWidget {
  const MacroEditorCs({
    super.key,
    this.macro,
    required this.remote,
    required this.onBack,
  });

  final TimedMacro? macro;
  final Remote remote;
  final VoidCallback onBack;

  @override
  State<MacroEditorCs> createState() => _MacroEditorCsState();
}

class _MacroEditorCsState extends State<MacroEditorCs> {
  final TextEditingController _nameCtl = TextEditingController();
  final List<MacroStep> _steps = <MacroStep>[];

  @override
  void initState() {
    super.initState();
    final m = widget.macro;
    _nameCtl.text = m?.name ?? '';
    _nameCtl.addListener(_onNameChanged);
    final loaded = (m?.steps ?? const <MacroStep>[])
        .map((s) => s.id.trim().isEmpty ? s.copyWith(id: MacroStep.newId()) : s)
        .toList();
    _steps.addAll(loaded);
  }

  @override
  void dispose() {
    _nameCtl.removeListener(_onNameChanged);
    _nameCtl.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSave {
    final nameOk = _nameCtl.text.trim().isNotEmpty;
    final stepsOk = _steps.isNotEmpty && _steps.every((s) => s.isValid);
    return nameOk && stepsOk;
  }

  // --- Button resolution / labels (mirrors the existing editor). ---

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

  String _stepText(MacroStep step) {
    switch (step.type) {
      case MacroStepType.send:
        final button = _findButtonById(step.buttonId) ??
            _findButtonByRef(step.buttonRef) ??
            _findButtonByRef(step.buttonId);
        if (button != null) {
          final label = csButtonLabel(button);
          return label.isEmpty ? 'KEY' : label.toUpperCase();
        }
        final fallback = (step.buttonRef ?? step.buttonId ?? '').trim();
        return fallback.isEmpty ? 'UNKNOWN' : fallback.toUpperCase();
      case MacroStepType.delay:
        return 'WAIT ${step.delayMs ?? 0} MS';
      case MacroStepType.manualContinue:
        return 'WAIT FOR OK';
    }
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

  // --- Add-step actions. ---

  Future<void> _addSendStep() async {
    final button = await _pickButton();
    if (button == null) return;
    setState(() {
      _steps.add(MacroStep(
        id: MacroStep.newId(),
        type: MacroStepType.send,
        buttonId: button.id,
        buttonRef: button.image,
      ));
    });
  }

  Future<void> _addDelayStep() async {
    final ms = await _pickDelay();
    if (ms == null) return;
    setState(() {
      _steps.add(MacroStep(
        id: MacroStep.newId(),
        type: MacroStepType.delay,
        delayMs: ms,
      ));
    });
  }

  void _addManualStep() {
    setState(() {
      _steps.add(MacroStep(
        id: MacroStep.newId(),
        type: MacroStepType.manualContinue,
      ));
    });
  }

  void _deleteStep(int index) {
    setState(() => _steps.removeAt(index));
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final step = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, step);
    });
  }

  // --- Persistence: reuse the real macro store, exactly like macros_tab.dart. ---

  Future<void> _save() async {
    if (!_canSave) return;
    final macro = TimedMacro(
      id: widget.macro?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtl.text.trim(),
      remoteName: widget.remote.name,
      steps: List<MacroStep>.from(_steps),
      version: 1,
    );

    // Upsert into the global list (match the existing macro by id).
    final idx = macros.indexWhere((m) => m.id == macro.id);
    if (idx >= 0) {
      macros[idx] = macro;
    } else {
      macros.add(macro);
    }

    try {
      await writeMacrosList(macros);
      notifyMacrosChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save macro')),
      );
      return;
    }
    if (mounted) widget.onBack();
  }

  // --- SEND: button-pick bottom sheet over the remote's real buttons. ---

  Future<IRButton?> _pickButton() async {
    if (widget.remote.buttons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This remote has no buttons')),
      );
      return null;
    }
    return showModalBottomSheet<IRButton>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('SELECT A COMMAND'),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(clipBehavior: Clip.none, 
                    shrinkWrap: true,
                    itemCount: widget.remote.buttons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final b = widget.remote.buttons[i];
                      final label = csButtonLabel(b);
                      final icon = csButtonIcon(b);
                      return FocusableSurface(
                        autofocus: i == 0,
                        onPressed: () => Navigator.of(ctx).pop(b),
                        borderRadius: AppRadii.r16,
                        scale: AppFocus.scaleRow,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            IconChip(icon ?? AppIcons.bolt,
                                tone: csTone(i), dim: 44, iconSize: 22),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                label.isEmpty ? 'KEY' : label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.rowTitle,
                              ),
                            ),
                            const Sym(AppIcons.chevron,
                                size: AppIconSizes.headerBtn,
                                color: AppColors.ink),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- DELAY: preset picker sheet. ---

  Future<int?> _pickDelay() async {
    const presets = <int>[250, 500, 1000, 1500, 2000, 3000, 5000];
    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Kicker('SELECT A DELAY'),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(clipBehavior: Clip.none, 
                    shrinkWrap: true,
                    itemCount: presets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final ms = presets[i];
                      return FocusableSurface(
                        autofocus: i == 0,
                        onPressed: () => Navigator.of(ctx).pop(ms),
                        borderRadius: AppRadii.r16,
                        scale: AppFocus.scaleRow,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            IconChip(AppIcons.stepDelay,
                                tone: AppColors.toneLearning,
                                dim: 44,
                                iconSize: 22),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text('$ms MS',
                                  style: AppType.rowTitle),
                            ),
                            const Sym(AppIcons.chevron,
                                size: AppIconSizes.headerBtn,
                                color: AppColors.ink),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 26),
          Expanded(
            child: ListView(clipBehavior: Clip.none, 
              padding: const EdgeInsets.all(16),
              children: [
                if (_steps.isEmpty)
                  _emptySteps()
                else
                  ReorderableListView.builder(clipBehavior: Clip.none, 
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _steps.length,
                    onReorder: _reorderSteps,
                    itemBuilder: (context, i) =>
                        _stepRow(_steps[i], i, key: ValueKey(_steps[i].id)),
                  ),
                const SizedBox(height: 22),
                _addButtons(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const HintStrip(
              '◀ BACK · NAME + STEPS REQUIRED · SAVE WRITES THE SEQUENCE'),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Back (primary focus target — spec §6 default-focus).
        PrimaryFocus(
          builder: (n) => FocusableSurface(
            focusNode: n,
            onPressed: widget.onBack,
            borderRadius: AppRadii.r14,
            padding: const EdgeInsets.all(15),
            restShadow: AppShadows.sm,
            child: const Sym(AppIcons.back,
                size: AppIconSizes.headerBtn, color: AppColors.ink),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Kicker('EDIT SEQUENCE'),
              const SizedBox(height: 8),
              _NameField(controller: _nameCtl),
            ],
          ),
        ),
        const SizedBox(width: 18),
        // SAVE.
        SizedBox(
          width: 220,
          child: FocusableSurface(
            onPressed: _save,
            borderRadius: AppRadii.r14,
            fill: _canSave ? AppColors.success : AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Sym(AppIcons.check, size: 22, color: AppColors.ink),
                const SizedBox(width: 10),
                Text('SAVE', style: AppType.buttonLabel),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepRow(MacroStep step, int index, {required Key key}) {
    final tone = _stepTone(step.type);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          // Step number (mono, muted).
          SizedBox(
            width: 40,
            child: Text('${index + 1}',
                textAlign: TextAlign.center,
                style: AppType.keyGlyph.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: FocusableSurface(
              onPressed: () {
                // Tapping a step focuses it; reordering uses the drag listener.
              },
              borderRadius: AppRadii.r16,
              scale: AppFocus.scaleRow,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  IconChip(_stepIcon(step.type),
                      tone: tone, dim: 48, iconSize: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_kindLabel(step.type),
                            style: AppType.microLabel),
                        const SizedBox(height: 4),
                        Text(_stepText(step),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.rowTitle),
                      ],
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Sym(AppIcons.dragHandle,
                          size: 24, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Delete.
          FocusableSurface(
            onPressed: () => _deleteStep(index),
            borderRadius: AppRadii.r14,
            padding: const EdgeInsets.all(15),
            restShadow: AppShadows.sm,
            child: const Sym(AppIcons.delete,
                size: AppIconSizes.overflowRow, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _addButtons() {
    final specs = <_AddSpec>[
      _AddSpec('SEND', AppIcons.txFired, _addSendStep),
      _AddSpec('DELAY', AppIcons.stepDelay, _addDelayStep),
      _AddSpec('MANUAL', AppIcons.stepManual, () async => _addManualStep()),
    ];
    return Row(
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(width: 18),
          Expanded(
            child: SizedBox(
              height: 84,
              child: FocusableSurface(
                onPressed: () => specs[i].onPressed(),
                borderRadius: AppRadii.r16,
                border: false,
                fill: Colors.transparent,
                fillFocused: AppColors.focusFillDashed,
                restShadow: const <BoxShadow>[],
                child: DottedBox(
                  radius: AppRadii.r16,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Sym(specs[i].icon,
                            size: 26, color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Text(specs[i].label,
                            style: AppType.buttonLabel
                                .copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptySteps() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.macros,
              size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('NO STEPS YET — ADD ONE BELOW', style: AppType.eyebrow),
        ],
      ),
    );
  }
}

class _AddSpec {
  const _AddSpec(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
}

/// Cream name field. On TV we keep the system IME (the design's display-only
/// keyboard is reserved for search) — a plain [TextField] styled to the cream
/// surface, since the macro name is the one place free text is unavoidable.
class _NameField extends StatelessWidget {
  const _NameField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r14),
        boxShadow: AppShadows.md,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      child: TextField(
        controller: controller,
        cursorColor: AppColors.ink,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(60)],
        style: AppType.drillHeader.copyWith(color: AppColors.ink),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'MACRO NAME',
          hintStyle: AppType.drillHeader.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
