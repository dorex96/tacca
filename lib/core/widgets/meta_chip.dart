import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/app_spacing.dart';

/// Etichetta compatta per un dato secondario (durata, numero di serie, tipo
/// di blocco, parametri).
///
/// È volutamente *non* tappabile: sostituisce le stringhe concatenate con
/// " · ", che a colpo d'occhio sono un blocco di testo unico e illeggibile.
class MetaChip extends StatelessWidget {
  const MetaChip({required this.label, this.icon, this.tone, super.key});

  final String label;
  final IconData? icon;

  /// Colore del contenuto quando il dato va notato (es. sessione interrotta).
  /// Null = tono neutro.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = tone ?? scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone == null
            ? scheme.surfaceContainerHighest
            : tone!.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}
