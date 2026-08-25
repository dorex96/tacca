import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../l10n/app_localizations.dart';

/// Impostazioni (RF-08): punto d'ingresso della configurazione AI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AppScaffold(
      title: l10n.settingsTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.tabBarClearance,
        ),
        children: [
          SettingsTile(
            icon: AppIcons.cpu,
            title: l10n.settingsAiTile,
            subtitle: l10n.settingsAiTileSubtitle,
            onTap: () => context.push('/settings/ai'),
          ),
        ],
      ),
    );
  }
}

/// Riga delle impostazioni: quadratino lime con l'icona, titolo, spiegazione
/// e la freccia che dice che porta da qualche parte.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final LinearIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.card,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: AppColors.lime,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(child: LinearIcon(icon, color: AppColors.ink)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.rowStrong),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTypography.paragraphSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const LinearIcon(
            AppIcons.chevronRight,
            size: 20,
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}
