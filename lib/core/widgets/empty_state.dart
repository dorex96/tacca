import 'package:flutter/material.dart';

import '../design/app_spacing.dart';

/// Stato vuoto uniforme: icona, messaggio e — quando esiste una sola cosa
/// sensata da fare — l'azione che lo risolve.
///
/// Uno stato vuoto è una schermata a tutti gli effetti: lasciarlo come una
/// riga di testo centrata fa sembrare l'app rotta invece che nuova.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;

  /// Pulsante mostrato sotto il messaggio. Null quando l'azione è già
  /// altrove nella schermata (tipicamente il FAB) e ripeterla sarebbe rumore.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHighest,
              ),
              child: Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
