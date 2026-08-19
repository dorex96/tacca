import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';

/// Scelta del giorno all'avvio della sessione (RF-06).
///
/// Va mostrata solo per le schede multi-giorno: quella a giorno singolo ha un
/// giorno implicito che l'UI non deve mostrare (analisi funzionale §5.1).
Future<int?> showDayPickerSheet(
  BuildContext context, {
  required List<WorkoutDay> days,
}) {
  final l10n = AppLocalizations.of(context);

  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Text(
              l10n.workoutChooseDayTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final day in days)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xs,
              ),
              leading: _DayAvatar(label: day.label),
              title: Text(day.label),
              subtitle: (day.notes ?? '').isEmpty ? null : Text(day.notes!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(day.id),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

/// Sigla del giorno ("Giorno A" → "A"): dà a ogni riga un aggancio visivo
/// che si riconosce prima di leggere l'etichetta.
class _DayAvatar extends StatelessWidget {
  const _DayAvatar({required this.label});

  final String label;

  String get _initial {
    final words = label.trim().split(RegExp(r'\s+'));
    final last = words.isEmpty ? '' : words.last;
    if (last.isEmpty) return '?';
    return last.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      width: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        _initial,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
