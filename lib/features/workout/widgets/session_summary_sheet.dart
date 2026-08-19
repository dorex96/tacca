import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/extensions/log_set_format.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/session_item.dart';

/// Conferma di chiusura della sessione con le note inserite.
class SessionSummaryConfirmed {
  const SessionSummaryConfirmed(this.notes);

  final String? notes;
}

/// Riepilogo di fine sessione (RF-06): durata, esercizi completati, carichi e
/// note libere prima di consegnare il log allo storico.
Future<SessionSummaryConfirmed?> showSessionSummarySheet(
  BuildContext context, {
  required Duration elapsed,
  required int completedExercises,
  required int totalExercises,
  required int loggedSets,
  required List<SessionItem> items,
  String? initialNotes,
}) {
  return showModalBottomSheet<SessionSummaryConfirmed>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _SessionSummarySheet(
        elapsed: elapsed,
        completedExercises: completedExercises,
        totalExercises: totalExercises,
        loggedSets: loggedSets,
        items: items,
        initialNotes: initialNotes,
      ),
    ),
  );
}

class _SessionSummarySheet extends StatefulWidget {
  const _SessionSummarySheet({
    required this.elapsed,
    required this.completedExercises,
    required this.totalExercises,
    required this.loggedSets,
    required this.items,
    required this.initialNotes,
  });

  final Duration elapsed;
  final int completedExercises;
  final int totalExercises;
  final int loggedSets;
  final List<SessionItem> items;
  final String? initialNotes;

  @override
  State<_SessionSummarySheet> createState() => _SessionSummarySheetState();
}

class _SessionSummarySheetState extends State<_SessionSummarySheet> {
  late final TextEditingController _notes = TextEditingController(
    text: widget.initialNotes ?? '',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final performed = widget.items
        .where((item) => item.entry.sets.isNotEmpty)
        .toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.workoutSummaryTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              // I tre numeri che riassumono la sessione, alla stessa
              // altezza: si leggono in un colpo d'occhio.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Stat(
                      label: l10n.workoutSummaryDuration,
                      value: widget.elapsed.compact,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Stat(
                      label: l10n.workoutSummaryExercises,
                      value:
                          '${widget.completedExercises}/'
                          '${widget.totalExercises}',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _Stat(
                      label: l10n.workoutSummarySets,
                      value: '${widget.loggedSets}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in performed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                item.completedSets
                                    .map((set) => set.summary)
                                    .join(' · '),
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('session-notes'),
                controller: _notes,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.workoutSummaryNotesLabel,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonContinue),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 52),
                    ),
                    onPressed: () => Navigator.of(context).pop(
                      SessionSummaryConfirmed(
                        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                      ),
                    ),
                    icon: const Icon(Icons.check),
                    label: Text(l10n.workoutSummaryConfirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
