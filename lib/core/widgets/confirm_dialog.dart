import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Conferma unica per tutta l'app: stessa struttura (titolo, spiegazione di
/// cosa succede, annulla a sinistra e azione a destra) in ogni dialog.
///
/// Le conferme distruttive colorano il pulsante di conferma con il colore di
/// errore: è l'unico punto in cui il rosso compare nell'interfaccia, e serve
/// a farlo notare.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? l10n.commonCancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
