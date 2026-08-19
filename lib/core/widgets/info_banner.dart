import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';

/// Tono di un [InfoBanner]: informativo (avvisi, spiegazioni) oppure di
/// attenzione (errori, funzioni non disponibili).
enum InfoBannerTone { neutral, alert }

/// Riquadro informativo a larghezza piena: icona + testo, colore che dice
/// subito se è una spiegazione o un problema.
///
/// Esiste per non avere tre modi diversi di dare la stessa notizia
/// (avviso privacy, key mancante, errore di chiamata AI).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = InfoBannerTone.neutral,
    this.onDismiss,
    super.key,
  });

  final String message;
  final IconData icon;
  final InfoBannerTone tone;

  /// Quando presente, aggiunge la X per chiudere il riquadro.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alert = tone == InfoBannerTone.alert;

    final background = alert
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = alert
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        onDismiss == null ? AppSpacing.md : AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close),
              iconSize: 20,
              color: foreground,
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
