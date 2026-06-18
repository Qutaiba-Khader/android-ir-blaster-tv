import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:irblaster_controller/ir_finder/ir_db_updater.dart';
import 'package:irblaster_controller/models/timed_macro.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/ir_transmitter_platform.dart';
import 'package:irblaster_controller/utils/remote.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_theme.dart';
import '../widgets/fire_flash.dart';
import 'about_screen_cs.dart';
import 'add_remote_screen.dart';
import 'create_remote_cs.dart';
import 'github_store_cs.dart';
import 'ir_finder_cs.dart';
import 'learning_cs.dart';
import 'macro_editor_cs.dart';
import 'macro_run_cs.dart';
import 'macros_screen.dart';
import 'nav_rail.dart';
import 'remote_view_screen.dart';
import 'remotes_screen.dart';
import 'search_cs.dart';
import 'settings_detail_cs.dart';
import 'settings_screen.dart';
import 'tester_screen.dart';
import 'universal_power_cs.dart';

/// Control Surface shell — leanback "browse" home (rail + content) plus a real
/// route stack for internal pages (the "fragments" model):
///
///  • HOME route: the left rail (REMOTES/MACROS/TESTER/SETTINGS) + the content
///    pane. Focusing a header previews its page; OK/▶ enters the content; ◀ goes
///    back to the active header. dpad (region nav + focus memory) drives focus.
///  • INTERNAL pages (remote view, editors, IR finder, search, …) are PUSHED onto
///    a nested [Navigator] as full-screen routes — the rail is hidden behind them
///    and each page carries its own top back button. Popping a page returns to the
///    home route and Flutter RESTORES the focus you left (the exact card you opened
///    it from), and nested pages form a proper back stack.
class CsShell extends StatefulWidget {
  const CsShell({super.key});

  @override
  State<CsShell> createState() => _CsShellState();
}

class _CsShellState extends State<CsShell> {
  final FireFlashController _flash = FireFlashController();
  final GlobalKey<NavigatorState> _pages = GlobalKey<NavigatorState>();

  final ValueNotifier<int> _nav = ValueNotifier<int>(0);
  bool _bannerDismissed = false;
  // Explicit rail nodes so launch focus / page-close focus land on the right header.
  final List<FocusNode> _railNodes =
      List.generate(4, (i) => FocusNode(debugLabel: 'cs-rail-$i'));

  IrTransmitterCapabilities? _caps;
  StreamSubscription<IrTransmitterCapabilities>? _capsSub;

  @override
  void initState() {
    super.initState();
    _loadCaps();
    _capsSub = IrTransmitterPlatform.capabilitiesEvents().listen((c) {
      if (mounted) setState(() => _caps = c);
    });
    // Warm the IR-code database in the background at startup so the finder opens
    // instantly later instead of copying the bundled DB on first open.
    // The IR-code DB is downloaded on demand the first time the finder/import is
    // opened (kept out of the APK to keep it small). If one is already cached,
    // check the manifest in the background and stage a newer one for next launch.
    unawaited(IrDbUpdater.checkAndStage());
    _focusHeader(); // launch → REMOTES header
  }

  Future<void> _loadCaps() async {
    try {
      final c = await IrTransmitterPlatform.getCapabilities();
      if (mounted) setState(() => _caps = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    _capsSub?.cancel();
    _flash.dispose();
    for (final n in _railNodes) {
      n.dispose();
    }
    _nav.dispose();
    super.dispose();
  }

  // Focus the active rail header (used at launch and when no page is on top).
  // dpad resolves its own initial/entry focus a beat after mount, so we grab on
  // the next frame AND re-assert shortly after — but only if the header still
  // isn't focused, so we never fight the user once they start navigating.
  void _focusHeader() {
    void grab() {
      if (mounted && !_hasPage) _railNodes[_nav.value].requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => grab());
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted && !_hasPage && !_railNodes[_nav.value].hasPrimaryFocus) {
        grab();
      }
    });
  }

  bool get _hasPage => _pages.currentState?.canPop() ?? false;

  // Focusing a rail header → preview that page (no route change).
  void _previewNav(int i) => _nav.value = i;

  // Programmatic tab switch (banner button).
  void _selectNav(int i) {
    _nav.value = i;
    _focusHeader();
  }

  /// Push an internal page as a full-screen route. [build] receives the route's
  /// `pop` callback to wire into the page's back button.
  void _push(Widget Function(VoidCallback pop) build) {
    _pages.currentState?.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, _, __) =>
            _pageScaffold(build(() => Navigator.of(ctx).pop())),
      ),
    );
  }

  bool _back() {
    final nav = _pages.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop(); // Flutter restores the home route's focus (the card you left)
      return true;
    }
    if (_nav.value != 0) {
      _nav.value = 0;
      _focusHeader();
      return true;
    }
    return false; // on the home REMOTES header → exit
  }

  // ---- Remotes / editor ----
  void _openRemote(Remote r) {
    _push((pop) => RemoteViewScreen(
          remote: r,
          onBack: pop,
          flash: _flash,
          onEdit: () => _push((pop2) =>
              CreateRemoteCs(remote: r, onBack: pop2, flash: _flash)),
        ));
  }

  void _openAddRemote() {
    _push((pop) => AddRemoteScreen(
          onBack: pop,
          onFromDatabase: () =>
              _push((p2) => CreateRemoteCs(onBack: p2, flash: _flash)),
          onFromStore: () => _push((p2) => GithubStoreCs(onBack: p2)),
          onFromScratch: () =>
              _push((p2) => CreateRemoteCs(onBack: p2, flash: _flash)),
        ));
  }

  void _openSearch() {
    _push((pop) => SearchCs(
          onBack: pop,
          onOpenRemote: (r) => _openRemote(r as Remote),
          flash: _flash,
        ));
  }

  // ---- Macros ----
  Remote? _remoteForMacro(TimedMacro m) {
    for (final r in remotes) {
      if (r.name == m.remoteName) return r;
    }
    return null;
  }

  void _editMacro(TimedMacro m) {
    final r = _remoteForMacro(m);
    if (r == null) {
      _missingRemote(m);
      return;
    }
    _push((pop) => MacroEditorCs(macro: m, remote: r, onBack: pop));
  }

  void _runMacro(TimedMacro m) {
    final r = _remoteForMacro(m);
    if (r == null) {
      _missingRemote(m);
      return;
    }
    _push((pop) => MacroRunCs(macro: m, remote: r, onBack: pop, flash: _flash));
  }

  void _newMacro() {
    if (remotes.isEmpty) {
      _push((pop) => CreateRemoteCs(onBack: pop, flash: _flash));
      return;
    }
    _push((pop) => MacroEditorCs(remote: remotes.first, onBack: pop));
  }

  void _missingRemote(TimedMacro m) {
    final name = m.remoteName.isEmpty ? 'this macro' : '"${m.remoteName}"';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('The remote for $name is missing. Re-create or rename it to match.')),
    );
  }

  // ---- Settings rows: 0 Transmitter · 1 Backup · 2 About ----
  void _openSettingsRow(int i) {
    switch (i) {
      case 0:
        _push((pop) => TransmitterCs(onBack: pop));
        break;
      case 1:
        _push((pop) => BackupCs(onBack: pop));
        break;
      case 2:
        _push((pop) => AboutScreenCs(onBack: pop));
        break;
    }
  }

  Widget _primary(int idx) {
    switch (idx) {
      case 1:
        return MacrosScreen(
            gridView: _gridView, onEdit: _editMacro, onRun: _runMacro, onNew: _newMacro);
      case 2:
        return TesterScreen(
          gridView: _gridView,
          onFindCode: () => _push((pop) => IrFinderCs(onBack: pop, flash: _flash)),
          onLearning: () => _push((pop) => LearningCs(onBack: pop)),
          onUniversalPower: () =>
              _push((pop) => UniversalPowerCs(onBack: pop, flash: _flash)),
        );
      case 3:
        return CsSettingsScreen(gridView: _gridView, caps: _caps, onOpenRow: _openSettingsRow);
      case 0:
      default:
        return RemotesScreen(
          showBanner: !_bannerDismissed && _caps != null && !_hasTransmitter(),
          gridView: _gridView,
          onToggleView: _toggleView,
          onOpenRemote: _openRemote,
          onAddRemote: _openAddRemote,
          onSearch: _openSearch,
          onHowItWorks: () => _push((pop) => TransmitterCs(onBack: pop)),
          onOpenSettings: () => _selectNav(3),
          onDismissBanner: () => setState(() => _bannerDismissed = true),
        );
    }
  }

  bool _gridView = true;
  void _toggleView() {
    setState(() => _gridView = !_gridView);
  }

  bool _hasTransmitter() {
    final c = _caps;
    if (c == null) return false;
    return c.hasInternal || c.hasUsb || c.hasAudio;
  }

  // A full-screen page (internal route): opaque scaffold + the 1920×1080 canvas
  // + its own dpad region. The rail is NOT here, so the page fills the screen.
  Widget _pageScaffold(Widget child) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: AppSizes.canvasW,
              height: AppSizes.canvasH,
              child: FireFlashOverlay(
                controller: _flash,
                child: DpadRegion(memoryKey: 'cs-page', child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The home route: rail + content, scaled on the fixed canvas.
  Widget _homeScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: AppSizes.canvasW,
              height: AppSizes.canvasH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DpadRegion(
                    memoryKey: 'cs-rail',
                    verticalEdge: DpadEdgeBehavior.stop,
                    enter: DpadEnterBehavior.restore,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _nav,
                      builder: (context, idx, _) => CsNavRail(
                        selectedIndex: idx,
                        railNodes: _railNodes,
                        onPreview: _previewNav,
                        caps: _caps,
                      ),
                    ),
                  ),
                  Expanded(
                    child: DpadRegion(
                      memoryKey: 'cs-content',
                      enter: DpadEnterBehavior.entry,
                      child: ValueListenableBuilder<int>(
                        valueListenable: _nav,
                        builder: (context, idx, _) => _primary(idx),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_back()) SystemNavigator.pop();
        },
        child: Dpad(
          onBack: () {
            if (_back()) return true;
            SystemNavigator.pop();
            return true;
          },
          child: Navigator(
            key: _pages,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, __, ___) => _homeScaffold(),
            ),
          ),
        ),
      ),
    );
  }
}
