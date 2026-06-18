import 'dart:async';

import 'package:flutter/material.dart';
import 'package:irblaster_controller/ir/ir_protocol_registry.dart';
import 'package:irblaster_controller/ir/ir_protocol_types.dart';
import 'package:irblaster_controller/ir_finder/ir_finder_models.dart';
import 'package:irblaster_controller/ir_finder/ir_finder_run_controller.dart';
import 'package:irblaster_controller/ir_finder/irblaster_db.dart';
import 'package:irblaster_controller/state/continue_context_prefs.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/ir.dart';
import 'package:irblaster_controller/utils/remote.dart';
import 'package:uuid/uuid.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/fire_flash.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';
import 'brand_model_picker_cs.dart';

/// IR Finder — Control Surface (spec §5.7 / §10.1).
///
/// The database "did-it-work?" loop: pick a brand (+ optional model), then step
/// through that brand's candidate IR codes one at a time. The left card shows the
/// current candidate code + meta + a procedurally-drawn waveform of the real
/// encoded pattern and a "Blast again" re-transmit. The right column asks
/// "Did the TV respond?" with a big ✓ (success — saves & returns) and ✗ (error —
/// step to the next candidate).
///
/// Backend is reused EXACTLY: this drives the app's [IrFinderRunController] with
/// the same `fetchCandidate` / `sendCandidate` wiring the legacy screen uses —
/// `IrBlasterDb.fetchCandidateKeys` for stepping, the same param-building / hex
/// fitting, `IrProtocolRegistry.encoderFor().encode()` + `transmitRaw()` to send,
/// and the same save path (`ContinueContextsPrefs.saveLastIrFinderHit` +
/// create/append a [Remote]). The controller is run in manual/paused mode and
/// advanced one candidate per `step()` so the loop is fully user-driven.
class IrFinderCs extends StatefulWidget {
  const IrFinderCs({
    super.key,
    required this.onBack,
    this.flash,
    this.initialBrand,
    this.initialModel,
    this.initialProtocolId,
    this.initialPageIndex = 0,
  });

  /// Return to the parent screen (Tester / Remotes) — called after a ✓ save.
  final VoidCallback onBack;

  /// Optional shared fire-flash controller; `fire()` on every blast (spec §7.3).
  final FireFlashController? flash;

  /// Pre-selected brand/model/protocol; if [initialBrand] is null the screen
  /// opens the brand picker on first frame.
  final String? initialBrand;
  final String? initialModel;
  final String? initialProtocolId;

  /// Kept for call-site parity with the legacy `IrFinderScreen`.
  final int initialPageIndex;

  @override
  State<IrFinderCs> createState() => _IrFinderCsState();
}

class _IrFinderCsState extends State<IrFinderCs> {
  final IrBlasterDb _db = IrBlasterDb.instance;
  late final IrFinderRunController _run;

  bool _dbReady = false;
  bool _starting = false;
  bool _exhausted = false; // stepped past the last candidate for this brand

  String? _brand;
  String? _model;
  String _protocolId = 'nec';

  // Latest encoded pattern for the waveform (mirrors what was transmitted).
  List<int> _pattern = const <int>[];
  int _frequencyHz = 38000;

  // Approx. candidate-space size for the "CODE n / N" header.
  int _totalCandidates = 0;

  @override
  void initState() {
    super.initState();
    _brand = widget.initialBrand;
    _model = widget.initialModel;
    _protocolId = (widget.initialProtocolId ?? 'nec').trim().toLowerCase();

    _run = IrFinderRunController(
      fetchCandidate: _fetchCandidateForRun,
      sendCandidate: _sendCandidateForRun,
    )..addListener(() {
        if (mounted) setState(() {});
      });

    _initDb();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  Future<void> _initDb() async {
    try {
      await _db.ensureInitialized();
      if (!mounted) return;
      setState(() => _dbReady = true);
      if (_brand == null || _brand!.trim().isEmpty) {
        // No brand chosen yet — prompt for one after first layout.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_pickBrand());
        });
      } else {
        await _beginRun();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _dbReady = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Backend wiring — identical behaviour to the legacy IrFinderScreen.
  // ---------------------------------------------------------------------------

  void _syncRunConfig() {
    _run.configure(
      mode: IrFinderMode.database,
      protocolId: _protocolId,
      delayMs: 500,
      maxKeysToTest: 1000000,
      bruteMaxAttempts: 200,
      bruteAllCombinations: false,
      prefixRaw: '',
      kaseikyoVendor: '2002',
      onlySelectedProtocol: false,
      quickWinsFirst: true,
      brand: _brand,
      model: _model,
    );
  }

  /// Starts the controller in manual mode (paused) and pulls the first candidate.
  Future<void> _beginRun() async {
    if (!_dbReady || _brand == null) return;
    setState(() {
      _starting = true;
      _exhausted = false;
    });
    _syncRunConfig();
    _totalCandidates = await _countCandidates();
    // start() flips running=true; we immediately pause so the timer never
    // auto-advances — every step is user-driven via _nextCandidate().
    await _run.start();
    _run.pause();
    await _nextCandidate();
    if (mounted) setState(() => _starting = false);
  }

  Future<int> _countCandidates() async {
    try {
      return await _db.countCandidateKeys(
        brand: _brand!,
        model: _model,
        selectedProtocolId: null,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Fetch + transmit the next candidate (advances the cursor). `step()` on a
  /// paused controller does exactly one fetch→send→advance cycle.
  Future<void> _nextCandidate() async {
    if (!_run.running) return;
    await _run.step();
    // No candidate came back → we've stepped past the last code for this brand.
    if (mounted && _run.lastCandidate == null) {
      setState(() => _exhausted = true);
    }
  }

  Future<IrFinderCandidate?> _fetchCandidateForRun(
      IrFinderRunController ctl) async {
    if (!_dbReady) return null;
    final String? brand = _brand;
    if (brand == null || brand.trim().isEmpty) return null;

    final rows = await _db.fetchCandidateKeys(
      brand: brand,
      model: _model,
      selectedProtocolId: null,
      quickWinsFirst: true,
      limit: 1,
      offset: ctl.currentOffset,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final String normId =
        row.protocol.trim().toLowerCase().replaceAll('-', '_');

    IrProtocolDefinition def;
    try {
      def = _definitionFor(normId);
    } catch (_) {
      return null;
    }

    Map<String, dynamic> params;
    try {
      params = _buildParamsForProtocol(protocolId: normId, codeHex: row.hexcode);
    } catch (e) {
      ctl.lastError = e;
      return null;
    }

    return IrFinderCandidate(
      protocolId: normId,
      displayProtocol: def.displayName,
      displayCode: _fitHexDigitsForProtocol(normId, row.hexcode),
      params: params,
      source: IrFinderSource.database,
      dbRemoteId: row.remoteId,
      dbLabel: row.label,
      dbBrand: _brand,
      dbModel: _model,
    );
  }

  Future<void> _sendCandidateForRun(IrFinderCandidate c) async {
    final enc = IrProtocolRegistry.encoderFor(c.protocolId);
    final IrEncodeResult res = enc.encode(c.params);
    final int freq = (res.frequencyHz <= 0) ? 38000 : res.frequencyHz;
    // Capture the real pattern so the waveform matches what was sent.
    if (mounted) {
      setState(() {
        _pattern = res.pattern;
        _frequencyHz = freq;
        _protocolId = c.protocolId;
      });
    }
    widget.flash?.fire();
    await transmitRaw(freq, res.pattern);
  }

  /// "Blast again" — resend the current candidate without advancing.
  Future<void> _blastAgain() async {
    if (_run.lastCandidate == null) return;
    await _run.trigger();
  }

  // ---- ✓ worked: save the hit + create/append remote, then return ----------

  Future<void> _confirmWorked() async {
    final c = _run.lastCandidate;
    if (c == null) return;

    final hit = IrFinderHit(
      savedAt: DateTime.now(),
      protocolId: c.protocolId,
      protocolName: c.displayProtocol,
      code: c.displayCode,
      source: c.source,
      dbBrand: c.dbBrand,
      dbModel: c.dbModel,
      dbRemoteId: c.dbRemoteId,
      dbLabel: c.dbLabel,
    );

    await ContinueContextsPrefs.saveLastIrFinderHit(hit);
    await _saveHitToRemote(hit);

    await _run.stop(clearPersistedSession: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${hit.protocolName} ${hit.code}')),
    );
    widget.onBack();
  }

  /// Append to the first remote, or create one from the hit (same logic as the
  /// legacy screen's _appendHitToRemote / _createRemoteFromHit, brand-default).
  Future<void> _saveHitToRemote(IrFinderHit hit) async {
    try {
      final uuid = const Uuid();
      final IRButton btn = IRButton(
        id: uuid.v4(),
        code: null,
        rawData: null,
        frequency: null,
        image: hit.dbLabel ?? hit.code,
        isImage: false,
        protocol: hit.protocolId,
        protocolParams: <String, dynamic>{'hex': hit.code},
      );
      if (remotes.isEmpty) {
        remotes.add(
          Remote(
            name: hit.dbBrand ?? 'New Remote',
            buttons: <IRButton>[btn],
            useNewStyle: true,
          ),
        );
      } else {
        remotes.first.buttons.add(btn);
      }
      await writeRemotelist(remotes);
      notifyRemotesChanged();
    } catch (_) {/* non-fatal — the hit is still persisted to ContinueContexts */}
  }

  // ---- ✗ next: advance to the next candidate -------------------------------

  Future<void> _rejectNext() async {
    if (!_run.running) return;
    await _nextCandidate();
  }

  // ---------------------------------------------------------------------------
  // Brand picker (database) — uses the real IrBlasterDb.listBrands.
  // ---------------------------------------------------------------------------

  Future<void> _pickBrand() async {
    if (!_dbReady) return;
    final String? picked = await showDbSearchPicker(context, title: 'SELECT BRAND');
    if (!mounted || picked == null) return;

    // Auto-select the first registry-known protocol this brand uses.
    String newProtocol = _protocolId;
    try {
      final List<String> protos = await _db.listProtocolsForBrand(picked);
      for (final p in protos) {
        final id = p.trim().toLowerCase().replaceAll('-', '_');
        try {
          _definitionFor(id);
          newProtocol = id;
          break;
        } catch (_) {/* skip unknown */}
      }
    } catch (_) {/* keep current */}

    if (!mounted) return;
    setState(() {
      _brand = picked;
      _model = null;
      _protocolId = newProtocol;
    });
    await _beginRun();
  }

  // ---------------------------------------------------------------------------
  // Pure helpers — ported verbatim from IrFinderScreen so candidates encode
  // identically. (Database mode only path used here.)
  // ---------------------------------------------------------------------------

  IrProtocolDefinition _definitionFor(String protocolId) =>
      IrProtocolRegistry.encoderFor(protocolId).definition;

  static const Map<String, String> _protocolExampleHex = <String, String>{
    'denon': '0000', 'f12_relaxed': '100', 'jvc': '0000', 'kaseikyo': '80D003',
    'nec': '000000FF', 'nec2': '000800FF', 'necx1': '000008F7',
    'necx2': '000C08F7', 'nrc17': '5C61', 'pioneer': '1A2B', 'proton': '0000',
    'rc5': '0000', 'rc6': '800F', 'rca_38': 'F00', 'rcc0082': '000',
    'rcc2026': '0087FBC03FC', 'rec80': '28C600212100', 'recs80': '000',
    'recs80_l': '000', 'samsung32': '0000', 'samsung36': '00C0001',
    'sharp': '2024', 'sony12': '000', 'sony15': '0014', 'sony20': '0002F',
    'thomson7': '300', 'xsat': '5935',
  };

  final String _kaseikyoVendor = '2002';

  static String _normalizeHexDigitsOnlyUpper(String s) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final int u = s.codeUnitAt(i);
      final bool isHex = (u >= 48 && u <= 57) ||
          (u >= 65 && u <= 70) ||
          (u >= 97 && u <= 102);
      if (isHex) out.writeCharCode(u);
    }
    return out.toString().toUpperCase();
  }

  int _totalHexDigitsForProtocol(String protocolId) {
    final ex = _protocolExampleHex[protocolId];
    if (ex != null && ex.isNotEmpty) return ex.length;
    try {
      final spec = IrFinderBruteSpec.forProtocol(protocolId);
      if (spec != null && spec.totalHexDigits > 0) return spec.totalHexDigits;
    } catch (_) {}
    try {
      final def = _definitionFor(protocolId);
      if (def.fields.isNotEmpty) {
        final f = def.fields.first;
        final int? maxLen = f.maxLength;
        if (f.type == IrFieldType.string && maxLen != null && maxLen > 0) {
          return maxLen.clamp(1, 64);
        }
      }
    } catch (_) {}
    return 0;
  }

  String _fitHexDigitsForProtocol(String protocolId, String codeHexAny) {
    final String pid = protocolId.trim().toLowerCase();
    final int want = _totalHexDigitsForProtocol(pid);
    String s = _normalizeHexDigitsOnlyUpper(codeHexAny);
    if (want <= 0) return s;
    if (s.length > want) {
      s = s.substring(s.length - want);
    } else if (s.length < want) {
      s = s.padLeft(want, '0');
    }
    return s;
  }

  static String _bytesToSpacedHex(List<String> bytes2) =>
      bytes2.map((e) => e.toUpperCase()).join(' ');

  Map<String, dynamic> _buildKaseikyoParams({
    required String codeHexAny,
    required String vendorAny,
  }) {
    final String vendor =
        _normalizeHexDigitsOnlyUpper(vendorAny).padLeft(4, '0');
    if (!RegExp(r'^[0-9A-F]{4}$').hasMatch(vendor)) {
      throw ArgumentError('Kaseikyo vendor must be 4 hex digits');
    }
    final String vMsb = vendor.substring(0, 2);
    final String vLsb = vendor.substring(2, 4);
    final String code = _normalizeHexDigitsOnlyUpper(codeHexAny);

    if (code.length == 16) {
      final addr = <String>[
        code.substring(0, 2), code.substring(2, 4),
        code.substring(4, 6), code.substring(6, 8),
      ];
      final cmd = <String>[
        code.substring(8, 10), code.substring(10, 12),
        code.substring(12, 14), code.substring(14, 16),
      ];
      return <String, dynamic>{
        'address': _bytesToSpacedHex(addr),
        'command': _bytesToSpacedHex(cmd),
      };
    }
    if (code.length == 8) {
      final b0 = code.substring(0, 2);
      final cmd0 = code.substring(2, 4);
      final cmd1 = code.substring(4, 6);
      final idByte = code.substring(6, 8);
      return <String, dynamic>{
        'address': _bytesToSpacedHex(<String>[b0, vLsb, vMsb, idByte]),
        'command': _bytesToSpacedHex(<String>[cmd0, cmd1, '00', '00']),
      };
    }
    if (code.length == 6) {
      final b0 = code.substring(0, 2);
      final cmd0 = code.substring(2, 4);
      final cmd1 = code.substring(4, 6);
      return <String, dynamic>{
        'address': _bytesToSpacedHex(<String>[b0, vLsb, vMsb, '00']),
        'command': _bytesToSpacedHex(<String>[cmd0, cmd1, '00', '00']),
      };
    }
    throw ArgumentError('Kaseikyo brute code must be 6, 8, or 16 hex digits');
  }

  Map<String, dynamic> _buildParamsForProtocol({
    required String protocolId,
    required String codeHex,
  }) {
    final String pid = protocolId.trim().toLowerCase();
    final String fitted = _fitHexDigitsForProtocol(pid, codeHex);

    if (pid == 'kaseikyo') {
      return _buildKaseikyoParams(codeHexAny: fitted, vendorAny: _kaseikyoVendor);
    }
    if (pid == 'pioneer' || pid == 'rc5' || pid == 'xsat') {
      if (fitted.length != 4) {
        throw ArgumentError('$pid brute code must be 4 hex digits');
      }
      return <String, dynamic>{
        'address': fitted.substring(0, 2),
        'command': fitted.substring(2, 4),
      };
    }
    if (pid == 'rca_38') {
      if (fitted.length != 3) {
        throw ArgumentError('RCA brute code must be 3 hex digits');
      }
      return <String, dynamic>{
        'address': fitted.substring(0, 1),
        'command': fitted.substring(1, 3),
      };
    }
    if (pid == 'thomson7') {
      try {
        final def = _definitionFor(pid);
        if (def.fields.isNotEmpty) {
          final f = def.fields.first;
          if (f.type == IrFieldType.intDecimal) {
            return <String, dynamic>{
              f.id: int.parse(fitted.isEmpty ? '0' : fitted, radix: 16),
            };
          }
          if (f.type == IrFieldType.string) {
            return <String, dynamic>{f.id: fitted};
          }
        }
      } catch (_) {}
      return <String, dynamic>{
        'code': int.parse(fitted.isEmpty ? '0' : fitted, radix: 16),
      };
    }

    try {
      final def = _definitionFor(pid);
      if (def.fields.isEmpty) return <String, dynamic>{'hex': fitted};
      if (def.fields.length == 1) {
        final f = def.fields.first;
        if (f.type == IrFieldType.intDecimal) {
          return <String, dynamic>{
            f.id: int.parse(fitted.isEmpty ? '0' : fitted, radix: 16),
          };
        }
        return <String, dynamic>{f.id: fitted};
      }
      final byId = <String, IrFieldDef>{for (final f in def.fields) f.id: f};
      if (byId.containsKey('address') &&
          byId.containsKey('command') &&
          fitted.length >= 4) {
        return <String, dynamic>{
          'address': fitted.substring(0, 2),
          'command': fitted.substring(2, 4),
        };
      }
      return <String, dynamic>{def.fields.first.id: fitted};
    } catch (_) {
      return <String, dynamic>{'hex': fitted};
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _run.lastCandidate;
    final int shownIndex = _run.attempted; // 1-based "n" once we've stepped once
    final int total = _totalCandidates;

    final String brandLine = [
      if (_brand != null && _brand!.trim().isNotEmpty) _brand!.trim(),
      if (_model != null && _model!.trim().isNotEmpty) _model!.trim(),
    ].join(' · ');

    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FinderHeader(
            onBack: widget.onBack,
            kicker: brandLine.isEmpty
                ? 'IR FINDER — DID IT WORK?'
                : '$brandLine — DID IT WORK?',
            codeIndex: shownIndex,
            codeTotal: total,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: (!_dbReady)
                ? const _FinderState(
                    icon: AppIcons.stateLoading, text: 'LOADING IR DATABASE…')
                : _exhausted
                    ? _FinderExhausted(onPickBrand: _pickBrand)
                    : (_starting || c == null)
                    ? const _FinderState(
                        icon: AppIcons.stateLoading, text: 'FINDING CANDIDATES…')
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left: code card (1.15fr).
                          Expanded(
                            flex: 115,
                            child: _CodeCard(
                              candidate: c,
                              pattern: _pattern,
                              frequencyHz: _frequencyHz,
                              onBlastAgain: _blastAgain,
                            ),
                          ),
                          const SizedBox(width: 22),
                          // Right: confirm column (1fr).
                          Expanded(
                            flex: 100,
                            child: _ConfirmColumn(
                              onWorked: _confirmWorked,
                              onNext: _rejectNext,
                            ),
                          ),
                        ],
                      ),
          ),
          const SizedBox(height: 16),
          const HintStrip(
              '◀ BACK · ▶ CONFIRM · ENTER = ✓ SAVES / ✗ NEXT CODE'),
        ],
      ),
    );
  }
}

// =============================================================================
// Header
// =============================================================================

class _FinderHeader extends StatelessWidget {
  const _FinderHeader({
    required this.onBack,
    required this.kicker,
    required this.codeIndex,
    required this.codeTotal,
  });

  final VoidCallback onBack;
  final String kicker;
  final int codeIndex;
  final int codeTotal;

  @override
  Widget build(BuildContext context) {
    final String count = codeTotal > 0
        ? 'CODE $codeIndex / $codeTotal'
        : 'CODE $codeIndex';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
              Kicker(kicker),
              const SizedBox(height: 6),
              Text('IR FINDER', style: AppType.drillHeader),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.ink, width: AppBorders.width),
            borderRadius: BorderRadius.circular(AppRadii.r14),
            boxShadow: AppShadows.sm,
          ),
          child: Text(count, style: AppType.buttonLabel),
        ),
      ],
    );
  }
}

// =============================================================================
// Left — candidate code card
// =============================================================================

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.candidate,
    required this.pattern,
    required this.frequencyHz,
    required this.onBlastAgain,
  });

  final IrFinderCandidate candidate;
  final List<int> pattern;
  final int frequencyHz;
  final VoidCallback onBlastAgain;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      candidate.displayProtocol,
      '${(frequencyHz / 1000).toStringAsFixed(1)} kHz',
      if (candidate.dbLabel != null && candidate.dbLabel!.trim().isNotEmpty)
        candidate.dbLabel!.trim().toUpperCase(),
      candidate.source == IrFinderSource.database ? 'DATABASE' : 'BRUTEFORCE',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r18),
        boxShadow: AppShadows.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CANDIDATE CODE', style: AppType.microLabel),
          const SizedBox(height: 12),
          Text(candidate.displayCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.candidateCode),
          const SizedBox(height: 8),
          Text(meta.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
          const SizedBox(height: 18),
          _Waveform(pattern: pattern),
          const Spacer(),
          const SizedBox(height: 18),
          // "Blast again" — re-transmit the current candidate.
          FocusableSurface(
            onPressed: onBlastAgain,
            borderRadius: AppRadii.r14,
            scale: AppFocus.scaleRow,
            restShadow: AppShadows.md,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Sym(AppIcons.txFired,
                    size: AppIconSizes.status, color: AppColors.ink),
                const SizedBox(width: 12),
                Text('BLAST AGAIN', style: AppType.buttonLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Procedurally-drawn IR waveform (spec, "waveform notes"): vertical bars on an
/// ink panel — mark bars in success-green, space gaps transparent. Derived from
/// the real encoded `pattern` (alternating mark/space microsecond durations).
class _Waveform extends StatelessWidget {
  const _Waveform({required this.pattern});
  final List<int> pattern;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadii.r12),
      ),
      child: pattern.isEmpty
          ? Center(
              child: Text('— NO SIGNAL —',
                  style: AppType.microLabel.copyWith(color: AppColors.textMuted)),
            )
          : ClipRect(
              child: CustomPaint(
                size: Size.infinite,
                painter: _WaveformPainter(pattern: pattern),
              ),
            ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.pattern});
  final List<int> pattern;

  @override
  void paint(Canvas canvas, Size size) {
    // Render the first ~80 durations as mark/space bars; mark = green bar whose
    // height scales with its microsecond duration, space = transparent gap.
    final int n = pattern.length.clamp(0, 80);
    if (n == 0) return;

    int maxDur = 1;
    for (int i = 0; i < n; i++) {
      if (pattern[i] > maxDur) maxDur = pattern[i];
    }

    const double gap = 3.0;
    final double unit = (size.width - gap * (n - 1)) / n;
    if (unit <= 0) return;

    final paint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.fill;

    double x = 0;
    for (int i = 0; i < n; i++) {
      final bool isMark = i.isEven; // even indices are "on" pulses
      final double frac = (pattern[i] / maxDur).clamp(0.08, 1.0);
      if (isMark) {
        // Height 40–96% of the box, by duration.
        final double h = size.height * (0.40 + 0.56 * frac);
        final double w = (unit * (0.5 + 0.5 * frac)).clamp(2.0, unit);
        final double top = size.height - h;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, top, w, h),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      x += unit + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.pattern != pattern;
}

// =============================================================================
// Right — "Did the TV respond?" confirm column
// =============================================================================

class _ConfirmColumn extends StatelessWidget {
  const _ConfirmColumn({required this.onWorked, required this.onNext});
  final VoidCallback onWorked;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DID THE TV RESPOND?', style: AppType.eyebrow),
        const SizedBox(height: 18),
        // ✓ Yes — it worked (default focus, saves & returns).
        Expanded(
          child: PrimaryFocus(
            builder: (n) => _ConfirmCard(
              focusNode: n,
              icon: AppIcons.worked,
              title: 'YES — IT WORKED',
              sub: 'SAVE THIS CODE & FINISH',
              fill: AppColors.success,
              fillFocused: AppColors.successFocused,
              onPressed: onWorked,
            ),
          ),
        ),
        const SizedBox(height: 18),
        // ✗ No — next code (steps the candidate).
        Expanded(
          child: _ConfirmCard(
            icon: AppIcons.next,
            title: 'NO — NEXT CODE',
            sub: 'TRY THE NEXT CANDIDATE',
            fill: AppColors.error,
            fillFocused: AppColors.errorFocused,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.fill,
    required this.fillFocused,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final String title;
  final String sub;
  final Color fill;
  final Color fillFocused;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleList,
      fill: fill,
      fillFocused: fillFocused,
      restShadow: AppShadows.lg,
      padding: const EdgeInsets.all(30),
      child: Row(
        children: [
          // Ink circle (64) holding the success/error-tinted glyph (spec §8).
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Sym(icon, size: AppIconSizes.toolCard, color: fill),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.rowTitle),
                const SizedBox(height: 8),
                Text(sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta.copyWith(color: AppColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Loading / empty state
// =============================================================================

/// Shown when the user has rejected every candidate for the chosen brand — gives
/// a clear terminal message + a focusable way to pick another brand (instead of
/// sitting on the "FINDING CANDIDATES…" spinner forever).
class _FinderExhausted extends StatelessWidget {
  const _FinderExhausted({required this.onPickBrand});
  final VoidCallback onPickBrand;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Sym(AppIcons.stateNoMatch,
              size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text('NO MORE CODES FOR THIS BRAND', style: AppType.eyebrow),
          const SizedBox(height: 20),
          PrimaryFocus(
            builder: (node) => FocusableSurface(
              focusNode: node,
              onPressed: onPickBrand,
              borderRadius: AppRadii.r14,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Sym(AppIcons.search,
                      size: AppIconSizes.headerCtl, color: AppColors.ink),
                  const SizedBox(width: 10),
                  Text('CHANGE BRAND', style: AppType.buttonLabel),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinderState extends StatelessWidget {
  const _FinderState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sym(icon, size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(text, style: AppType.eyebrow),
        ],
      ),
    );
  }
}
