import 'package:flutter/material.dart';
import 'package:irblaster_controller/ir_finder/irblaster_db.dart';
import 'package:irblaster_controller/state/remotes_state.dart';
import 'package:irblaster_controller/utils/db_button_import.dart';
import 'package:irblaster_controller/utils/remote.dart';
import 'package:irblaster_controller/widgets/remote_editor/remote_editor_actions.dart';
import '../cs_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/dotted_box.dart';
import '../widgets/fire_flash.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';
import 'brand_model_picker_cs.dart';

/// Create / Edit Remote — "Remote Studio" (spec §10).
///
/// The Control Surface editor for a single remote. Used for BOTH "create from
/// scratch" (pass `remote: null`) and "edit an existing remote" (pass the remote).
///
/// Backend reuse — this screen invents NO editing logic. It only orchestrates the
/// app's existing dialogs/sheets and the canonical save path:
///   • per-button edit/add  → [RemoteEditorActions.addButton] / .editButton
///                             (these push the real `CreateButton` screen, which
///                             owns the icon picker / color picker / IR signal entry)
///   • imports               → [RemoteEditorActions.importFromDatabase] /
///                             .importFromExistingRemotes (bottom-sheets)
///   • GitHub                → [RemoteEditorActions.browseGithubStore]
///   • persist               → mutate the global [remotes] list, [writeRemotelist],
///                             then [notifyRemotesChanged] — EXACTLY as
///                             `remote_list.dart` / `create_remote.dart` do.
class CreateRemoteCs extends StatefulWidget {
  const CreateRemoteCs({
    super.key,
    this.remote,
    required this.onBack,
    this.flash,
  });

  /// When null, a fresh remote is created. When provided, that remote is edited
  /// in place (matched back into [remotes] by id on save).
  final Remote? remote;

  /// Clears the drill / returns to the previous screen (the shell owns this).
  final VoidCallback onBack;

  /// Optional transmit-flash controller (unused for editing, accepted so the
  /// shell can pass it through uniformly with the other drill screens).
  final FireFlashController? flash;

  @override
  State<CreateRemoteCs> createState() => _CreateRemoteCsState();
}

class _CreateRemoteCsState extends State<CreateRemoteCs> {
  late final TextEditingController _nameCtrl;

  /// Working copy. For a NEW remote we build an empty one; for an EDIT we mutate
  /// a copy of the buttons so a "back without save" can't corrupt the live list.
  late Remote _remote;

  bool get _isEditing => widget.remote != null;

  @override
  void initState() {
    super.initState();
    final source = widget.remote;
    if (source == null) {
      _remote = Remote(buttons: <IRButton>[], name: '');
    } else {
      // Work on a detached button list; keep the same id so save replaces it.
      _remote = Remote(
        id: source.id,
        buttons: List<IRButton>.from(source.buttons),
        name: source.name,
        useNewStyle: source.useNewStyle,
      );
    }
    _nameCtrl = TextEditingController(text: _remote.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  // ── Button editing (existing dialogs) ──────────────────────────────────────

  Future<void> _editButtonAt(int index) async {
    final current = _remote.buttons[index];
    final updated = await RemoteEditorActions.editButton(context, current);
    if (updated == null || !mounted) return;
    setState(() => _remote.buttons[index] = updated);
  }

  Future<void> _addButton() async {
    final button = await RemoteEditorActions.addButton(context);
    if (button == null || !mounted) return;
    setState(() => _remote.buttons.add(button));
  }

  // ── Source actions (existing sheets / screens) ─────────────────────────────

  Future<void> _importFromDatabase() async {
    // Step 1 — pick a brand with the full-screen Control Surface picker.
    final String? brand = await _showDbPicker(title: 'SELECT BRAND');
    if (brand == null || !mounted) return;

    // Step 2 — pick a model of that brand (same picker, model mode).
    final String? model = await _showDbPicker(title: 'SELECT MODEL', brand: brand);
    if (model == null || !mounted) return;

    // Pull every candidate key for brand+model and map each DB row into an
    // IRButton (the same conversion the old import sheet used).
    final List<IRButton> imported = <IRButton>[];
    try {
      const int pageSize = 200;
      int offset = 0;
      while (true) {
        final rows = await IrBlasterDb.instance.fetchCandidateKeys(
          brand: brand,
          model: model,
          quickWinsFirst: true,
          limit: pageSize,
          offset: offset,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          final btn = buildButtonFromDbRow(row);
          if (btn != null) imported.add(btn);
        }
        offset += rows.length;
        if (rows.length < pageSize) break;
      }
    } catch (_) {
      if (mounted) _showSnack('Failed to load keys from database');
      return;
    }

    if (!mounted) return;
    if (imported.isEmpty) {
      _showSnack('No keys found for $brand $model');
      return;
    }

    // Auto-fill a sensible remote name from the chosen device, but only if the
    // user hasn't typed one of their own.
    if (_nameCtrl.text.trim().isEmpty) {
      final String auto = _autoRemoteName(brand, model);
      _nameCtrl.text = auto;
      _remote.name = auto;
    }

    // Persist exactly as before: append to the working remote's button list.
    setState(() => _remote.buttons.addAll(imported));
    _showSnack('Imported ${imported.length} button'
        '${imported.length == 1 ? '' : 's'}');
  }

  /// "SAMSUNG" + "UE40H6400" → "Samsung UE40H6400".
  String _autoRemoteName(String brand, String model) {
    String titleCase(String s) => s
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
    final String b = titleCase(brand.trim());
    final String m = model.trim();
    return (m.isEmpty ? b : '$b $m').trim();
  }

  /// Shows the reusable [DbSearchPickerCs] as a full-screen ROUTE (not a bottom
  /// sheet — that hides the TV keyboard) and resolves to the picked name.
  Future<String?> _showDbPicker({required String title, String? brand}) {
    return showDbSearchPicker(context, title: title, brand: brand);
  }

  Future<void> _importFromRemotes() async {
    final before = _remote.buttons.length;
    final imported = await RemoteEditorActions.importFromExistingRemotes(
      context,
      existingButtons: _remote.buttons,
      currentRemoteId: _remote.id,
    );
    if (imported == null || imported.isEmpty || !mounted) return;
    setState(() => _remote.buttons.addAll(imported));
    final added = _remote.buttons.length - before;
    _showSnack('Imported $added button${added == 1 ? '' : 's'} from remotes');
  }

  Future<void> _browseGithub() async {
    await RemoteEditorActions.browseGithubStore(context);
    // The GitHub flow persists directly into `remotes`; nothing to merge here.
  }

  // ── Save (canonical path — mirrors remote_list.dart) ───────────────────────

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Remote name can’t be empty');
      return;
    }
    _remote.name = name;

    if (_isEditing) {
      final idx = remotes.indexWhere((r) => r.id == _remote.id);
      if (idx >= 0) {
        remotes[idx] = _remote;
      } else {
        // The original was removed while editing — fall back to appending.
        remotes.add(_remote);
      }
    } else {
      remotes.add(_remote);
    }

    await writeRemotelist(remotes);
    notifyRemotesChanged();
    if (!mounted) return;
    _showSnack(_isEditing ? 'Remote saved' : 'Remote created');
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final buttons = _remote.buttons;
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            nameController: _nameCtrl,
            isEditing: _isEditing,
            buttonCount: buttons.length,
            onBack: widget.onBack,
            onSave: _save,
          ),
          const SizedBox(height: 22),
          _SourceRow(
            onImportDatabase: _importFromDatabase,
            onImportRemotes: _importFromRemotes,
            onBrowseGithub: _browseGithub,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: buttons.isEmpty
                ? _EmptyButtons(onAdd: _addButton)
                : GridView.builder(clipBehavior: Clip.none, 
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: AppSizes.irKeyCols,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: 1.0,
              ),
              // +1 trailing "ADD BUTTON" tile.
              itemCount: buttons.length + 1,
              itemBuilder: (context, i) {
                if (i == buttons.length) {
                  return RepaintBoundary(child: _AddTile(onPressed: _addButton));
                }
                final tile = _ButtonTile(
                  button: buttons[i],
                  onPressed: () => _editButtonAt(i),
                );
                return RepaintBoundary(child: tile);
              },
            ),
          ),
          const SizedBox(height: 16),
          const HintStrip(
              '◀ BACK · ENTER EDITS A BUTTON · ＋ ADDS · SAVE PERSISTS'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.nameController,
    required this.isEditing,
    required this.buttonCount,
    required this.onBack,
    required this.onSave,
  });

  final TextEditingController nameController;
  final bool isEditing;
  final int buttonCount;
  final VoidCallback onBack;
  final VoidCallback onSave;

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
              Kicker(isEditing
                  ? 'REMOTE STUDIO — EDIT'
                  : 'REMOTE STUDIO — NEW REMOTE'),
              const SizedBox(height: 8),
              _NameField(controller: nameController),
              const SizedBox(height: 6),
              Text('$buttonCount KEY${buttonCount == 1 ? '' : 'S'}',
                  style: AppType.meta.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        FocusableSurface(
          onPressed: onSave,
          borderRadius: AppRadii.r14,
          fill: AppColors.success,
          fillFocused: AppColors.successFocused,
          restShadow: AppShadows.md,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Sym(AppIcons.save,
                  size: AppIconSizes.status, color: AppColors.ink),
              const SizedBox(width: 10),
              Text('SAVE',
                  style: AppType.buttonLabel.copyWith(color: AppColors.ink)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Editable remote-name field, styled as a cream CS surface.
class _NameField extends StatelessWidget {
  const _NameField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.ink, width: AppBorders.width),
        borderRadius: BorderRadius.circular(AppRadii.r14),
        boxShadow: AppShadows.sm,
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        cursorColor: AppColors.accent,
        style: AppType.listTitle.copyWith(color: AppColors.ink),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'REMOTE NAME',
          hintStyle: AppType.listTitle.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Import / browse source actions (reuse the existing sheets & store screen).
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.onImportDatabase,
    required this.onImportRemotes,
    required this.onBrowseGithub,
  });

  final VoidCallback onImportDatabase;
  final VoidCallback onImportRemotes;
  final VoidCallback onBrowseGithub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PrimaryFocus(
            builder: (n) => _SourceButton(
              focusNode: n,
              icon: AppIcons.fromDatabase,
              tone: AppColors.toneAudio,
              label: 'IMPORT FROM DB',
              onPressed: onImportDatabase,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SourceButton(
            icon: AppIcons.syncAlt,
            tone: AppColors.toneLearning,
            label: 'FROM REMOTES',
            onPressed: onImportRemotes,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SourceButton(
            icon: AppIcons.storefront,
            tone: AppColors.toneAppearance,
            label: 'BROWSE GITHUB',
            onPressed: onBrowseGithub,
          ),
        ),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.tone,
    required this.label,
    required this.onPressed,
    this.focusNode,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r16,
      scale: AppFocus.scaleRow,
      restShadow: AppShadows.md,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconChip(icon, tone: tone, dim: 56, radius: AppRadii.r13, iconSize: 30),
          const SizedBox(width: 14),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.listTitle),
          ),
        ],
      ),
    );
  }
}

/// A single remote button in the 5-col keypad — same look as Remote View.
class _ButtonTile extends StatelessWidget {
  const _ButtonTile({required this.button, required this.onPressed});
  final IRButton button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = csIsAccentKey(button);
    final icon = csButtonIcon(button);
    final label = csButtonLabel(button);
    return FocusableSurface(
      onPressed: onPressed,
      borderRadius: AppRadii.r16,
      scale: 1.0,
      fill: accent ? AppColors.accent : AppColors.surface,
      restShadow: AppShadows.md,
      padding: const EdgeInsets.all(8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Sym(icon ?? AppIcons.bolt,
                size: AppIconSizes.irKey, color: AppColors.ink),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.buttonLabel),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state — no buttons yet. A dashed "ADD BUTTON" tile alongside the
/// grid_view chip + "NO BUTTONS YET" caption (spec §10).
class _EmptyButtons extends StatelessWidget {
  const _EmptyButtons({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Sym(AppIcons.gridView,
                size: AppIconSizes.stateGlyph, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('NO BUTTONS YET', style: AppType.eyebrow),
            const SizedBox(height: 6),
            Text('ADD A BUTTON OR IMPORT FROM A SOURCE ABOVE',
                textAlign: TextAlign.center,
                style:
                    AppType.meta.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              height: 130,
              child: _AddTile(onPressed: onAdd),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashed "ADD BUTTON" tile → existing add-button dialog.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: onPressed,
      borderRadius: AppRadii.r16,
      scale: 1.0,
      fill: AppColors.background,
      fillFocused: AppColors.focusFillDashed,
      border: false,
      restShadow: const <BoxShadow>[],
      padding: const EdgeInsets.all(16),
      child: DottedBox(
        radius: AppRadii.r16,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Sym(AppIcons.add,
                  size: AppIconSizes.addTile, color: AppColors.textSecondary),
              const SizedBox(height: 8),
              Text('ADD BUTTON',
                  style: AppType.eyebrow
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
