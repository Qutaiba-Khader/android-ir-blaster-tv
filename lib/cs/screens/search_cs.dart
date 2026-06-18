import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
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

/// Global Search — full-screen. Uses a PLAIN native [TextField] (system Gboard
/// keyboard), exactly like the dpad package's own example: focusing the field
/// floats Gboard up; the dpad package handles d-pad ↔ text-edit coexistence so
/// you can enter, leave (▼ / edge) and RE-ENTER the field freely. No custom
/// keyboard, no manual FocusNode/requestFocus (that was what broke re-focus).
///
/// Results MIX matching REMOTES (open) and BUTTONS (transmit via [sendIR]),
/// mirroring `GlobalSearchDelegate._collectResults`.
class SearchCs extends StatefulWidget {
  const SearchCs({
    super.key,
    required this.onBack,
    required this.onOpenRemote,
    this.flash,
  });

  final VoidCallback onBack;

  /// Opens a remote (the shell drills into Remote View). Always a [Remote].
  final void Function(dynamic remote) onOpenRemote;

  /// Optional flash controller for the §7.3 transmit feedback.
  final FireFlashController? flash;

  @override
  State<SearchCs> createState() => _SearchCsState();
}

class _SearchCsState extends State<SearchCs> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _firedLabel;
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ---- Search (mirrors GlobalSearchDelegate) ----
  List<_Hit> _collect(String raw) {
    final q = raw.trim().toLowerCase();
    final out = <_Hit>[];
    if (q.isEmpty) {
      for (final r in remotes.take(8)) {
        out.add(_Hit.remote(r));
      }
      return out;
    }
    for (final remote in remotes) {
      final name = remote.name.trim();
      final nameMatches = name.toLowerCase().contains(q);
      if (nameMatches) out.add(_Hit.remote(remote));
      for (final button in remote.buttons) {
        final label = csButtonLabel(button);
        if (label.toLowerCase().contains(q) || nameMatches) {
          out.add(_Hit.button(remote, button, label));
        }
      }
    }
    return _dedupe(out);
  }

  List<_Hit> _dedupe(List<_Hit> items) {
    final seen = <String>{};
    final out = <_Hit>[];
    for (final h in items) {
      if (seen.add(h.key)) out.add(h);
    }
    return out;
  }

  Future<void> _select(_Hit hit) async {
    if (hit.type == _HitType.remote) {
      widget.onOpenRemote(hit.remote);
      return;
    }
    final label = hit.title.isEmpty ? 'KEY' : hit.title.toUpperCase();
    setState(() => _firedLabel = label);
    widget.flash?.fire();
    try {
      await sendIR(hit.button!);
    } catch (_) {/* errors surface inside sendIR */}
    _revert?.cancel();
    _revert = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _firedLabel = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hits = _collect(_query);
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FocusableSurface(
                onPressed: widget.onBack,
                borderRadius: AppRadii.r14,
                padding: const EdgeInsets.all(15),
                restShadow: AppShadows.sm,
                child: const Sym(AppIcons.back, size: AppIconSizes.headerBtn, color: AppColors.ink),
              ),
              const SizedBox(width: 18),
              Expanded(child: _SearchField(controller: _controller, onChanged: (v) => setState(() => _query = v))),
              const SizedBox(width: 14),
              if (_firedLabel != null) _FiredPill(label: _firedLabel!) else _CountPill(count: hits.length),
            ],
          ),
          const SizedBox(height: 22),
          Expanded(
            child: DpadRegion(
              memoryKey: 'cs-search-results',
              child: hits.isEmpty
                  ? const _NoMatch()
                  : ListView.separated(
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.only(bottom: AppSpacing.screenPadDrill.bottom),
                      itemCount: hits.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => RepaintBoundary(
                        child: _ResultRow(hit: hits[i], onPressed: () => _select(hits[i])),
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
/// d-pad enter/leave/re-enter it. Styled cream to match Control Surface.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
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
        hintText: 'SEARCH REMOTES & KEYS',
        hintStyle: AppType.listTitle.copyWith(color: AppColors.textMuted),
        prefixIcon: const Icon(AppIcons.search, color: AppColors.ink, size: AppIconSizes.headerCtl),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r12),
          borderSide: const BorderSide(color: AppColors.ink, width: AppBorders.width),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.r12),
          borderSide: const BorderSide(color: AppColors.focus, width: AppFocus.ringWidth),
        ),
      ),
    );
  }
}

enum _HitType { remote, button }

class _Hit {
  const _Hit._({
    required this.type,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.remote,
    required this.button,
  });

  final _HitType type;
  final String key;
  final String title;
  final String subtitle;
  final Remote remote;
  final IRButton? button;

  factory _Hit.remote(Remote r) => _Hit._(
        type: _HitType.remote,
        key: 'remote:${r.id}:${r.name}',
        title: r.name.isEmpty ? 'REMOTE' : r.name,
        subtitle: '${r.buttons.length} BUTTONS',
        remote: r,
        button: null,
      );

  factory _Hit.button(Remote r, IRButton b, String label) => _Hit._(
        type: _HitType.button,
        key: 'button:${b.id}',
        title: label.isEmpty ? 'KEY' : label,
        subtitle: r.name.isEmpty ? 'REMOTE' : r.name,
        remote: r,
        button: b,
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onPressed});
  final _Hit hit;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isRemote = hit.type == _HitType.remote;
    final chipTone = isRemote ? AppColors.toneTv : AppColors.toneAudio;
    final glyph = isRemote ? AppIcons.remotes : AppIcons.txFired;
    final trailingGlyph = isRemote ? AppIcons.chevron : AppIcons.bolt;
    return FocusableSurface(
      onPressed: onPressed,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      child: Row(
        children: [
          IconChip(glyph, tone: chipTone, dim: 56, radius: AppRadii.r13, iconSize: AppIconSizes.settingsRow),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(hit.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Sym(trailingGlyph, size: AppIconSizes.headerBtn, color: AppColors.ink),
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
      child: Text('${count < 10 ? '0$count' : count} HITS', style: AppType.buttonLabel),
    );
  }
}

class _FiredPill extends StatelessWidget {
  const _FiredPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.focus,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r12),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.txFired, size: AppIconSizes.headerCtl, color: Colors.white),
          const SizedBox(width: 8),
          Text('SENT · $label', style: AppType.buttonLabel.copyWith(color: Colors.white)),
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
          const Sym(AppIcons.stateNoMatch, size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('NO MATCHES', style: AppType.eyebrow),
        ],
      ),
    );
  }
}
