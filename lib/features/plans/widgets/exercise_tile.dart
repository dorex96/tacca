import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../data/entities/exercise.dart';
import '../../../l10n/app_localizations.dart';

/// Riga di editing per un [Exercise]: tutti i campi tranne il nome sono
/// opzionali (analisi funzionale §5.1).
///
/// I campi di un esercizio stanno in un riquadro proprio: in un blocco con
/// sei esercizi, senza contenitore non si capisce dove finisce uno e inizia
/// il successivo.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    required this.exercise,
    required this.index,
    required this.onNameChanged,
    required this.onSetsChanged,
    required this.onRepsChanged,
    required this.onLoadChanged,
    required this.onRestChanged,
    required this.onDurationChanged,
    required this.onNotesChanged,
    required this.onRemove,
    super.key,
  });

  final Exercise exercise;
  final int index;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<int?> onSetsChanged;
  final ValueChanged<String?> onRepsChanged;
  final ValueChanged<String?> onLoadChanged;
  final ValueChanged<int?> onRestChanged;
  final ValueChanged<int?> onDurationChanged;
  final ValueChanged<String?> onNotesChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final instanceKey = identityHashCode(exercise);

    Widget numberField({
      required String tag,
      required String label,
      required int? value,
      required ValueChanged<int?> onChanged,
    }) {
      return SizedBox(
        width: 128,
        child: TextFormField(
          key: ValueKey('ex-$tag-$instanceKey'),
          initialValue: value?.toString() ?? '',
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChanged(int.tryParse(v)),
        ),
      );
    }

    Widget textField({
      required String tag,
      required String label,
      required String value,
      required ValueChanged<String> onChanged,
      double width = 168,
    }) {
      return SizedBox(
        width: width,
        child: TextFormField(
          key: ValueKey('ex-$tag-$instanceKey'),
          initialValue: value,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    Icons.drag_handle,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('ex-name-$instanceKey'),
                  initialValue: exercise.name,
                  decoration: InputDecoration(
                    labelText: l10n.planEditorExerciseNameLabel,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: onNameChanged,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.planEditorRemoveExercise,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.md,
            children: [
              numberField(
                tag: 'sets',
                label: l10n.planEditorExerciseSetsLabel,
                value: exercise.sets,
                onChanged: onSetsChanged,
              ),
              textField(
                tag: 'reps',
                label: l10n.planEditorExerciseRepsLabel,
                value: exercise.reps ?? '',
                onChanged: onRepsChanged,
                width: 128,
              ),
              textField(
                tag: 'load',
                label: l10n.planEditorExerciseLoadLabel,
                value: exercise.load ?? '',
                onChanged: onLoadChanged,
              ),
              numberField(
                tag: 'rest',
                label: l10n.planEditorExerciseRestLabel,
                value: exercise.restSeconds,
                onChanged: onRestChanged,
              ),
              numberField(
                tag: 'duration',
                label: l10n.planEditorExerciseDurationLabel,
                value: exercise.durationSeconds,
                onChanged: onDurationChanged,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: TextFormField(
              key: ValueKey('ex-notes-$instanceKey'),
              initialValue: exercise.notes ?? '',
              decoration: InputDecoration(
                labelText: l10n.planEditorExerciseNotesLabel,
              ),
              onChanged: onNotesChanged,
            ),
          ),
        ],
      ),
    );
  }
}
