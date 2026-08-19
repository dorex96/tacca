import 'package:flutter/material.dart';

import '../design/app_spacing.dart';

/// Intestazione di sezione: stessa forma in archivio, dettaglio scheda,
/// storico e sessione, così un gruppo si riconosce come tale ovunque.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(
      top: AppSpacing.xl,
      bottom: AppSpacing.sm,
    ),
    super.key,
  });

  final String label;

  /// Contenuto allineato a destra: tipicamente un conteggio o un'azione.
  final Widget? trailing;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
