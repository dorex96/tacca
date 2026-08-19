import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/info_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/ai_import_cubit.dart';
import '../cubit/ai_import_state.dart';
import 'ai_import_review_args.dart';

/// Import di una scheda via AI (RF-03): foto, immagini dalla galleria e/o
/// testo. Al termine la proposta apre l'editor (RF-02) per la revisione.
class AiImportPage extends StatelessWidget {
  const AiImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<AiImportCubit, AiImportState>(
      listenWhen: (previous, current) =>
          previous.status != current.status &&
          current.status == AiImportStatus.review,
      listener: (context, state) {
        final notices = <String>[
          if (state.usedOcr) l10n.aiImportOcrNotice,
          if (state.usedFallback) l10n.aiImportFallbackNotice,
        ];
        if (notices.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(notices.join(' '))));
        }
        context.pushReplacement(
          '/plans/new/review',
          extra: AiImportReviewArgs(draft: state.draft!),
        );
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.aiImportTitle)),
          body: switch (state.status) {
            AiImportStatus.processing => const _ProcessingView(),
            _ when state.configChecked && !state.isConfigured =>
              const _NotConfiguredView(),
            _ => _InputView(state: state),
          },
        );
      },
    );
  }
}

/// Le funzioni AI non si nascondono: si spiegano e si rimanda alle
/// impostazioni (RF-08).
class _NotConfiguredView extends StatelessWidget {
  const _NotConfiguredView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.key_off_outlined,
      message: l10n.aiImportNotConfiguredBody,
      action: FilledButton.icon(
        onPressed: () async {
          final cubit = context.read<AiImportCubit>();
          await context.push('/settings/ai');
          await cubit.refreshConfiguration();
        },
        icon: const Icon(Icons.settings_outlined),
        label: Text(l10n.aiImportGoToSettings),
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.aiImportProcessing,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputView extends StatelessWidget {
  const _InputView({required this.state});

  final AiImportState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<AiImportCubit>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (state.errorMessage != null) ...[
          InfoBanner(
            icon: Icons.error_outline,
            tone: InfoBannerTone.alert,
            message: state.errorMessage!,
            onDismiss: cubit.dismissError,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // Avviso privacy: le immagini/testi inviati lasciano il dispositivo.
        InfoBanner(message: l10n.aiSettingsPrivacyNotice),
        const SizedBox(height: AppSpacing.xl),
        if (state.images.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (var i = 0; i < state.images.length; i++)
                _ImageThumbnail(
                  key: ValueKey('import-image-$i'),
                  bytes: state.images[i],
                  onRemove: () => cubit.removeImage(i),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cubit.addFromCamera,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.aiImportSourceCamera),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cubit.addFromGallery,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.aiImportSourceGallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        TextFormField(
          key: const ValueKey('import-text'),
          initialValue: state.text,
          decoration: InputDecoration(
            labelText: l10n.aiImportTextLabel,
            hintText: l10n.aiImportTextHint,
            alignLabelWithHint: true,
          ),
          minLines: 4,
          maxLines: 12,
          onChanged: cubit.updateText,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          key: const ValueKey('import-hint'),
          initialValue: state.hint,
          decoration: InputDecoration(labelText: l10n.aiImportHintLabel),
          onChanged: cubit.updateHint,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: state.hasInput ? cubit.submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.aiImportSubmit),
        ),
        if (!state.hasInput) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              l10n.aiImportNoInput,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.bytes,
    required this.onRemove,
    super.key,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.memory(
            bytes,
            width: 104,
            height: 104,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: IconButton.filled(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.85),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.close),
            tooltip: l10n.aiImportRemoveImage,
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
