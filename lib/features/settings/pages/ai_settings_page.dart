import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// Configurazione AI (RF-08): provider (OpenRouter), API key, modello dal
/// catalogo JSON, test connessione e avviso privacy.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _keyController = TextEditingController();

  /// Mostra il campo key anche quando una key è già salvata ("Sostituisci").
  bool _editingKey = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final cubit = context.read<SettingsCubit>();
          final catalog = cubit.catalog;
          final selectedModel = state.selectedModelId == null
              ? null
              : catalog.byId(state.selectedModelId!);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              // Avviso esplicito richiesto da RF-08: i contenuti inviati
              // all'AI lasciano il dispositivo.
              InfoBanner(message: l10n.aiSettingsPrivacyNotice),
              if (!state.hasApiKey) ...[
                const SizedBox(height: AppSpacing.md),
                InfoBanner(
                  icon: Icons.lock_outline,
                  tone: InfoBannerTone.alert,
                  message: l10n.aiSettingsDisabledBanner,
                ),
              ],
              SectionHeader(label: l10n.aiSettingsProviderLabel),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('OpenRouter'),
                ),
              ),
              SectionHeader(label: l10n.aiSettingsKeyLabel),
              if (state.hasApiKey && !_editingKey)
                _SavedKeyTile(
                  onReplace: () => setState(() => _editingKey = true),
                  onRemove: () => _confirmRemoveKey(context),
                )
              else
                _KeyEditor(
                  controller: _keyController,
                  onSave: () async {
                    await cubit.saveApiKey(_keyController.text);
                    _keyController.clear();
                    if (mounted) setState(() => _editingKey = false);
                  },
                ),
              SectionHeader(label: l10n.aiSettingsModelLabel),
              DropdownButtonFormField<String>(
                initialValue: selectedModel?.id,
                decoration: InputDecoration(
                  labelText: l10n.aiSettingsModelLabel,
                ),
                items: [
                  for (final model in catalog.models)
                    DropdownMenuItem(value: model.id, child: Text(model.label)),
                ],
                onChanged: (value) {
                  if (value != null) cubit.selectModel(value);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              _TestConnectionSection(state: state),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemoveKey(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.aiSettingsKeyRemoveConfirmTitle,
      message: l10n.aiSettingsKeyRemoveConfirmBody,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) await cubit.removeApiKey();
  }
}

class _SavedKeyTile extends StatelessWidget {
  const _SavedKeyTile({required this.onReplace, required this.onRemove});

  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.aiSettingsKeySaved,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onReplace,
                  child: Text(l10n.aiSettingsKeyReplace),
                ),
                TextButton(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text(l10n.commonDelete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyEditor extends StatelessWidget {
  const _KeyEditor({required this.controller, required this.onSave});

  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: l10n.aiSettingsKeyHint,
              prefixIcon: const Icon(Icons.key_outlined),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _TestConnectionSection extends StatelessWidget {
  const _TestConnectionSection({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final testing = state.testStatus == AiConnectionTestStatus.testing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: state.hasApiKey && !testing
              ? () => context.read<SettingsCubit>().testConnection()
              : null,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: testing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering),
          label: Text(l10n.aiSettingsTestConnection),
        ),
        const SizedBox(height: AppSpacing.md),
        switch (state.testStatus) {
          AiConnectionTestStatus.success => Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.aiSettingsTestSuccess,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          AiConnectionTestStatus.failure => InfoBanner(
            icon: Icons.error_outline,
            tone: InfoBannerTone.alert,
            message: state.testErrorMessage ?? '',
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}
