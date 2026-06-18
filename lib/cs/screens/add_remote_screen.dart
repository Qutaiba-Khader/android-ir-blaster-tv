import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/atoms.dart';
import '../widgets/focusable_surface.dart';
import '../widgets/primary_focus.dart';

/// Add Remote (spec §5.10 / §10): pick a method, then branch into the matching
/// flow. Three method cards: from the database, community store, from scratch.
class AddRemoteScreen extends StatelessWidget {
  const AddRemoteScreen({
    super.key,
    required this.onBack,
    required this.onFromDatabase,
    required this.onFromStore,
    required this.onFromScratch,
  });

  final VoidCallback onBack;
  final VoidCallback onFromDatabase;
  final VoidCallback onFromStore;
  final VoidCallback onFromScratch;

  @override
  Widget build(BuildContext context) {
    final methods = <_Method>[
      _Method('From the database', 'PICK A BRAND + MODEL, IMPORT ITS BUTTONS',
          AppIcons.fromDatabase, AppColors.toneAudio, onFromDatabase),
      _Method('Community store', 'BROWSE GITHUB IR-CODE REPOSITORIES',
          AppIcons.fromStore, AppColors.toneLearning, onFromStore),
      _Method('Create from scratch', 'BUILD A REMOTE BUTTON-BY-BUTTON',
          AppIcons.fromScratch, AppColors.toneAppearance, onFromScratch),
    ];
    return Padding(
      padding: AppSpacing.screenPadDrill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FocusableSurface(
                onPressed: onBack,
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
                    const Kicker('ADD A REMOTE — CHOOSE A METHOD'),
                    const SizedBox(height: 6),
                    Text('ADD REMOTE', style: AppType.drillHeader),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: GridView.count(clipBehavior: Clip.none, 
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: 3,
                  crossAxisSpacing: 22,
                  mainAxisSpacing: 22,
                  childAspectRatio: 1.05,
                  children: [
                    for (var i = 0; i < methods.length; i++)
                      RepaintBoundary(
                        child: i == 0
                            ? PrimaryFocus(builder: (n) => _MethodCard(method: methods[0], focusNode: n))
                            : _MethodCard(method: methods[i]),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const HintStrip('◀ BACK · ▶ CHOOSE A METHOD · ENTER OPENS'),
        ],
      ),
    );
  }
}

class _Method {
  const _Method(this.title, this.desc, this.icon, this.tone, this.onPressed);
  final String title;
  final String desc;
  final IconData icon;
  final Color tone;
  final VoidCallback onPressed;
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.method, this.focusNode});
  final _Method method;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onPressed: method.onPressed,
      focusNode: focusNode,
      borderRadius: AppRadii.r18,
      scale: AppFocus.scaleList,
      fill: method.tone,
      fillFocused: method.tone,
      restShadow: AppShadows.lg,
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.ink, width: 3),
              borderRadius: BorderRadius.circular(AppRadii.r16),
            ),
            alignment: Alignment.center,
            child: Sym(method.icon, size: AppIconSizes.toolCard, color: AppColors.ink),
          ),
          const Spacer(),
          Text(method.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.drillHeader.copyWith(fontSize: 28, color: AppColors.ink)),
          const SizedBox(height: 10),
          Text(method.desc, style: AppType.meta.copyWith(color: AppColors.textMutedAlt)),
        ],
      ),
    );
  }
}
