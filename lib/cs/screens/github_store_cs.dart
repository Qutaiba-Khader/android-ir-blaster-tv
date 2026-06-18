import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:irblaster_controller/github_store/github_store_service.dart';
import 'package:irblaster_controller/github_store/models.dart';
import 'package:irblaster_controller/github_store/url_parser.dart';
import 'package:irblaster_controller/widgets/github_store_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// GitHub Store (spec §10) — Control Surface front-end for the community IR-code
/// browser.
///
/// Backend reuse — this screen owns NO networking or import logic of its own:
///   • [parseGitHubUrl] turns the URL field into a [RepoRef].
///   • [GitHubStoreService.listDirectory] lists folders/files (cached, token-aware).
///   • Source persistence uses the SAME SharedPreferences keys/format as the
///     legacy screen (`irblaster.store.lastRepo` / `irblaster.store.sources`)
///     so saved sources are shared between both UIs.
///   • Opening a FILE delegates to the existing full [GitHubStoreScreen] (pushed
///     via Navigator). That screen owns the heavy parse → preview → "create new
///     remote" / "add to existing" import + save machinery (private to that file),
///     which we deliberately do not duplicate.
class GithubStoreCs extends StatefulWidget {
  const GithubStoreCs({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<GithubStoreCs> createState() => _GithubStoreCsState();
}

class _GithubStoreCsState extends State<GithubStoreCs> {
  static const String _defaultRepoUrl =
      'https://github.com/Lucaslhm/Flipper-IRDB';
  static const String _lastRepoKey = 'irblaster.store.lastRepo';
  static const String _sourcesKey = 'irblaster.store.sources';

  final TextEditingController _urlCtrl = TextEditingController();
  final GitHubStoreService _service = GitHubStoreService();

  RepoRef? _repo;
  String _currentPath = '';
  List<RepoItem> _items = const <RepoItem>[];
  bool _loading = false;
  bool _hasLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _defaultRepoUrl;
    _bootstrap();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    // Reuse the legacy token so authenticated browsing keeps working.
    final token = prefs.getString('irblaster.store.githubAuthToken')?.trim();
    _service.setAuthToken(token == null || token.isEmpty ? null : token);
    final last = _loadLastRepo(prefs);
    if (!mounted) return;
    if (last != null) {
      setState(() {
        _repo = last;
        _currentPath = last.path;
        _urlCtrl.text = last.originalUrl;
      });
    }
  }

  RepoRef? _loadLastRepo(SharedPreferences prefs) {
    final raw = prefs.getString(_lastRepoKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final repo = RepoRef.fromJson(Map<String, dynamic>.from(map));
      if (repo.owner.isEmpty || repo.repo.isEmpty) return null;
      return repo;
    } catch (_) {
      return null;
    }
  }

  String _relativePath() {
    final repo = _repo;
    if (repo == null) return '';
    final root = repo.path;
    if (root.isNotEmpty && _currentPath.startsWith(root)) {
      final rel = _currentPath.substring(root.length);
      return rel.startsWith('/') ? rel.substring(1) : rel;
    }
    return _currentPath;
  }

  bool get _canNavigateUp {
    final repo = _repo;
    if (repo == null) return false;
    final root = repo.path.trim();
    final current = _currentPath.trim();
    if (current.isEmpty) return false;
    if (root.isEmpty) return true;
    return current != root;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }

  Future<void> _browseFromUrl() async {
    final parsed = parseGitHubUrl(_urlCtrl.text.trim());
    if (parsed == null) {
      _showSnack('Only GitHub repository links are supported');
      return;
    }
    setState(() {
      _repo = parsed;
      _currentPath = parsed.path;
      _items = const <RepoItem>[];
      _error = null;
      _hasLoaded = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRepoKey, jsonEncode(parsed.toJson()));
    await _loadDirectory();
  }

  Future<void> _loadDirectory({bool forceRefresh = false}) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.listDirectory(
        repo,
        subPath: _relativePath(),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _hasLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _hasLoaded = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSource() async {
    final repo = _repo;
    if (repo == null) {
      _showSnack('Browse a repository first');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sourcesKey);
    final list = <RepoRef>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(decoded
              .whereType<Map>()
              .map((m) => RepoRef.fromJson(Map<String, dynamic>.from(m)))
              .where((r) => r.owner.isNotEmpty && r.repo.isNotEmpty));
        }
      } catch (_) {}
    }
    final exists = list.any((s) =>
        s.owner == repo.owner &&
        s.repo == repo.repo &&
        s.branch == repo.branch &&
        s.path == repo.path);
    if (exists) {
      _showSnack('Source already saved');
      return;
    }
    final alias = '${repo.owner}/${repo.repo}';
    list.add(repo.copyWith(alias: alias));
    await prefs.setString(
        _sourcesKey, jsonEncode(list.map((s) => s.toJson()).toList()));
    _showSnack('Source saved');
  }

  Future<void> _navigateUp() async {
    if (!_canNavigateUp) return;
    final currentParts =
        _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    final rootParts =
        (_repo?.path ?? '').split('/').where((p) => p.isNotEmpty).toList();
    if (currentParts.length <= rootParts.length) return;
    setState(() {
      _currentPath = currentParts.sublist(0, currentParts.length - 1).join('/');
    });
    await _loadDirectory();
  }

  Future<void> _openItem(RepoItem item) async {
    if (item.type == RepoItemType.dir) {
      setState(() => _currentPath = item.path);
      await _loadDirectory();
      return;
    }
    // FILE → hand off to the existing full store screen, which owns the parse +
    // preview + import/save flow (and re-seeds `remotes`). We pre-seed its
    // "last repo" so it lands on the same place the user is browsing.
    final prefs = await SharedPreferences.getInstance();
    if (_repo != null) {
      await prefs.setString(_lastRepoKey, jsonEncode(_repo!.toJson()));
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const GitHubStoreScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(onBack: widget.onBack),
          const SizedBox(height: 22),
          _RepoCard(
            urlController: _urlCtrl,
            loading: _loading,
            onBrowse: _browseFromUrl,
            onSave: _saveSource,
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildBody()),
          const SizedBox(height: 16),
          const HintStrip(
              '◀ BACK · ENTER OPENS A FOLDER/FILE · FILES IMPORT ON THE NEXT SCREEN'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return _Message(
        icon: AppIcons.stateError,
        title: 'COULDN’T LOAD',
        body: _error!,
        bodyColor: AppColors.error,
      );
    }
    if (!_hasLoaded) {
      return const _Message(
        icon: AppIcons.storefront,
        title: 'EXAMPLE SOURCE',
        body:
            'THE DEFAULT REPOSITORY (LUCASLHM/FLIPPER-IRDB) IS JUST AN EXAMPLE. '
            'PASTE ANY GITHUB REPO URL ABOVE, THEN BROWSE.',
      );
    }
    if (_items.isEmpty) {
      return const _Message(
        icon: AppIcons.stateNoMatch,
        title: 'NOTHING HERE',
        body: 'NO FILES OR FOLDERS WERE FOUND AT THIS PATH.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _currentPath.isEmpty ? '/' : '/$_currentPath',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta.copyWith(color: AppColors.textSecondary),
              ),
            ),
            if (_canNavigateUp)
              FocusableSurface(
                onPressed: _navigateUp,
                borderRadius: AppRadii.r12,
                restShadow: AppShadows.sm,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Sym(AppIcons.back,
                        size: AppIconSizes.headerCtl, color: AppColors.ink),
                    const SizedBox(width: 8),
                    Text('UP', style: AppType.buttonLabel),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(clipBehavior: Clip.none, 
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final row = _ItemRow(item: _items[i], onPressed: () => _openItem(_items[i]));
              if (i == 0) {
                return RepaintBoundary(
                  child: PrimaryFocus(
                    builder: (n) => _ItemRow(
                      item: _items[0],
                      focusNode: n,
                      onPressed: () => _openItem(_items[0]),
                    ),
                  ),
                );
              }
              return RepaintBoundary(child: row);
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
              const Kicker('COMMUNITY STORE — GITHUB IR-CODE REPOS'),
              const SizedBox(height: 6),
              Text('GITHUB STORE', style: AppType.drillHeader),
            ],
          ),
        ),
      ],
    );
  }
}

/// Repo URL field + Browse / Save source actions (spec §10 repo card).
class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.urlController,
    required this.loading,
    required this.onBrowse,
    required this.onSave,
  });

  final TextEditingController urlController;
  final bool loading;
  final VoidCallback onBrowse;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
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
              const Sym(AppIcons.link,
                  size: AppIconSizes.status, color: AppColors.ink),
              const SizedBox(width: 10),
              Text('REPOSITORY URL',
                  style: AppType.eyebrow.copyWith(color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceFocused,
              border:
                  Border.all(color: AppColors.ink, width: AppBorders.width),
              borderRadius: BorderRadius.circular(AppRadii.r12),
            ),
            child: TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              cursorColor: AppColors.accent,
              onSubmitted: (_) => onBrowse(),
              style: AppType.listTitle.copyWith(color: AppColors.ink),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'https://github.com/OWNER/REPO[/tree/BRANCH/PATH]',
                hintStyle:
                    AppType.meta.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FocusableSurface(
                  onPressed: loading ? () {} : onBrowse,
                  borderRadius: AppRadii.r14,
                  fill: AppColors.accent,
                  fillFocused: AppColors.accentLabel,
                  restShadow: AppShadows.md,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Sym(AppIcons.storefront,
                          size: AppIconSizes.status, color: AppColors.ink),
                      const SizedBox(width: 10),
                      Text('BROWSE',
                          style: AppType.buttonLabel
                              .copyWith(color: AppColors.ink)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FocusableSurface(
                  onPressed: onSave,
                  borderRadius: AppRadii.r14,
                  restShadow: AppShadows.md,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Sym(AppIcons.bookmarkAdd,
                          size: AppIconSizes.status, color: AppColors.ink),
                      const SizedBox(width: 10),
                      Text('SAVE SOURCE', style: AppType.buttonLabel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One folder/file row.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onPressed, this.focusNode});
  final RepoItem item;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final isDir = item.type == RepoItemType.dir;
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r14,
      scale: AppFocus.scaleRow,
      restShadow: AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          IconChip(
            isDir ? AppIcons.gridView : AppIcons.fromDatabase,
            tone: isDir ? AppColors.toneNeutral : AppColors.toneAudio,
            dim: 44,
            radius: 12,
            iconSize: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.listTitle),
                const SizedBox(height: 4),
                Text(item.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppType.meta.copyWith(color: AppColors.textMutedAlt)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Sym(isDir ? AppIcons.chevron : AppIcons.openInNew,
              size: AppIconSizes.headerBtn, color: AppColors.ink),
        ],
      ),
    );
  }
}

/// Centered empty/error/example message block.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.bodyColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Sym(icon,
                size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(title, style: AppType.eyebrow),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: AppType.meta
                    .copyWith(color: bodyColor ?? AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
