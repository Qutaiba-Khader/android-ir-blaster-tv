import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:irblaster_controller/ir_finder/irblaster_db.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';

/// DbSearchPickerCs — a REUSABLE full-screen Google-TV-style brand→model picker
/// in the Control Surface design language.
///
/// Drives the real [IrBlasterDb]: in BRAND mode ([brand] == null) it lists
/// brands via `listBrands`; in MODEL mode ([brand] != null) it lists that
/// brand's models via `listModelsDistinct`. The search box is a PLAIN native
/// [TextField] (system Gboard keyboard), styled cream EXACTLY like
/// `search_cs._SearchField` — autofocus, onChanged→setState; the `dpad` package
/// handles d-pad ↔ text-edit coexistence (enter / leave / re-enter), so there is
/// NO custom on-screen keyboard and NO manual `FocusNode.requestFocus` on the
/// field (that breaks Android-TV re-focus).
///
/// Typing is DEBOUNCED ~250ms, then the DB is queried (limit 200). An empty
/// query loads the first 200 results. Rapid typing is handled by a monotonic
/// generation counter so stale results are ignored. Selecting a row calls
/// [onPick] with the chosen name.
class DbSearchPickerCs extends StatefulWidget {
  const DbSearchPickerCs({
    super.key,
    required this.title,
    this.brand,
    required this.onPick,
    required this.onBack,
  });

  /// Header title (e.g. 'SELECT BRAND' / 'SELECT MODEL').
  final String title;

  /// MODEL mode when non-null (models of this brand); BRAND mode when null.
  final String? brand;

  /// Called with the picked brand or model name.
  final void Function(String value) onPick;

  /// Dismisses the picker (the host pops the route / sheet).
  final VoidCallback onBack;

  @override
  State<DbSearchPickerCs> createState() => _DbSearchPickerCsState();
}

class _DbSearchPickerCsState extends State<DbSearchPickerCs> {
  final TextEditingController _controller = TextEditingController();

  String _query = '';
  Timer? _debounce;

  /// Monotonic request id — only the newest load is allowed to commit results.
  int _generation = 0;

  bool _loading = true;
  List<String> _results = const <String>[];

  bool get _isModelMode => widget.brand != null;

  @override
  void initState() {
    super.initState();
    // First load (empty query → first 200) once the DB is ready.
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _load(reset: false);
    });
  }

  Future<void> _load({required bool reset}) async {
    final int requestId = ++_generation;
    if (mounted) setState(() => _loading = true);

    try {
      await IrBlasterDb.instance.ensureInitialized();
      final String search = _query.trim();
      final List<String> rows = _isModelMode
          ? await IrBlasterDb.instance.listModelsDistinct(
              brand: widget.brand!,
              search: search,
              limit: 200,
            )
          : await IrBlasterDb.instance.listBrands(
              search: search,
              limit: 200,
            );

      // Ignore stale responses (the user typed again before this returned).
      if (!mounted || requestId != _generation) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _generation) return;
      setState(() {
        _results = const <String>[];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final bool showLoading = _loading && results.isEmpty;
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: back · search field · count pill ──
          Row(
            children: [
              FocusableSurface(
                onPressed: widget.onBack,
                borderRadius: AppRadii.r14,
                padding: const EdgeInsets.all(15),
                restShadow: AppShadows.sm,
                child: const Sym(AppIcons.back,
                    size: AppIconSizes.headerBtn, color: AppColors.ink),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _SearchField(
                  controller: _controller,
                  hint: _isModelMode ? 'SEARCH MODELS' : 'SEARCH BRANDS',
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(width: 14),
              _CountPill(count: results.length),
            ],
          ),
          const SizedBox(height: 12),
          Kicker(widget.title),
          const SizedBox(height: 16),
          // ── Live results ──
          Expanded(
            child: DpadRegion(
              memoryKey: _isModelMode
                  ? 'cs-db-picker-models-${widget.brand}'
                  : 'cs-db-picker-brands',
              child: showLoading
                  ? const _PickerLoading()
                  : results.isEmpty
                      ? const _NoMatch()
                      : ListView.separated(
                          clipBehavior: Clip.none,
                          padding: EdgeInsets.only(
                              bottom: AppSpacing.screenPadDrill.bottom),
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) => RepaintBoundary(
                            child: _NameRow(
                              name: results[i],
                              entry: i == 0,
                              onPressed: () => widget.onPick(results[i]),
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain native TextField — Gboard appears on focus; the dpad package lets the
/// d-pad enter/leave/re-enter it. Styled cream to match Control Surface (copied
/// from `search_cs._SearchField`).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: true,
      textInputAction: TextInputAction.search,
      cursorColor: AppColors.accent,
      style: AppType.listTitle.copyWith(color: AppColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppType.listTitle.copyWith(color: AppColors.textMuted),
        prefixIcon: const Icon(AppIcons.search,
            color: AppColors.ink, size: AppIconSizes.headerCtl),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r12),
          borderSide:
              const BorderSide(color: AppColors.ink, width: AppBorders.width),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r12),
          borderSide:
              const BorderSide(color: AppColors.focus, width: AppFocus.ringWidth),
        ),
      ),
    );
  }
}

/// A single brand/model result row. The first row is the region's [entry]
/// target so focus lands predictably when the list is entered.
class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.name,
    required this.onPressed,
    required this.entry,
  });
  final String name;
  final VoidCallback onPressed;
  final bool entry;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      entry: entry,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          IconChip(AppIcons.factory_,
              tone: AppColors.toneNeutral,
              dim: 56,
              radius: AppRadii.r13,
              iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.listTitle,
            ),
          ),
          const SizedBox(width: 14),
          const Sym(AppIcons.chevron,
              size: AppIconSizes.headerBtn, color: AppColors.ink),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r12),
        boxShadow: AppShadows.sm,
      ),
      child: Text('${count < 10 ? '0$count' : count} HITS',
          style: AppType.buttonLabel),
    );
  }
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.stateLoading,
              size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('LOADING CODE DATABASE…', style: AppType.eyebrow),
        ],
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.stateNoMatch,
              size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('NO MATCHES', style: AppType.eyebrow),
        ],
      ),
    );
  }
}

/// Show the picker as a full-screen ROUTE (NOT a bottom sheet — an autofocus
/// TextField inside a bottom sheet hides the TV keyboard, flutter#166386). The
/// 1920×1080 canvas + DpadRegion match the rest of the shell. Resolves to the
/// picked brand/model name, or null on back.
Future<String?> showDbSearchPicker(
  BuildContext context, {
  required String title,
  String? brand,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      // Onboarding-style horizontal slide: the next step (brand → model) slides
      // in from the right; popping slides it back out.
      transitionsBuilder: (ctx, anim, sec, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(curved),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.none,
              child: SizedBox(
                width: AppSizes.canvasW,
                height: AppSizes.canvasH,
                child: DpadRegion(
                  memoryKey: 'cs-db-picker-route',
                  child: DbSearchPickerCs(
                    title: title,
                    brand: brand,
                    onPick: (v) => Navigator.of(ctx).pop(v),
                    onBack: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
