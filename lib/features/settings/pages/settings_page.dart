import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// Impostazioni (RF-08): punto d'ingresso della configurazione AI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: ListTile(
              leading: Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              title: Text(l10n.settingsAiTile),
              subtitle: Text(l10n.settingsAiTileSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/ai'),
            ),
          ),
        ],
      ),
    );
  }
}
