import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/extensions/log_set_format.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../data/entities/log_set.dart';
import '../../../data/repositories/workout_log_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../bloc/session_item.dart';

/// Card di un esercizio in sessione (RF-06): esercizio corrente evidenziato,
/// spunta per serie e log rapido a portata di pollice.
class SessionExerciseCard extends StatelessWidget {
  const SessionExerciseCard({
    required this.item,
    required this.isCurrent,
    required this.lastPerformance,
    required this.onToggleSet,
    required this.onEditSet,
    required this.onFocus,
    this.onStartRest,
    this.groupMarker,
    super.key,
  });

  final SessionItem item;
  final bool isCurrent;
  final LastPerformance? lastPerformance;

  /// Posizione dentro un gruppo a giri ("A", "B", …): rende visibile a colpo
  /// d'occhio quali esercizi si alternano nello stesso giro. Null fuori dai
  /// superset e dai circuiti.
  final String? groupMarker;

  /// Spunta/despunta la serie.
  final void Function(int setNumber) onToggleSet;

  /// Apre il log rapido della serie.
  final void Function(int setNumber) onEditSet;

  final VoidCallback onFocus;

  /// Null quando l'esercizio non ha un recupero configurato.
  final VoidCallback? onStartRest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sets = item.displayedSets;
    // Nei blocchi a giri una "serie" è un giro del gruppo: chiamarla col suo
    // nome è ciò che rende leggibile un superset durante l'allenamento.
    final rounds = item.isRoundBased;
    String setLabel(int number) =>
        rounds ? l10n.workoutRoundLabel(number) : l10n.workoutSetLabel(number);

    // L'esercizio corrente è l'unico colorato: si ritrova senza cercarlo,
    // anche guardando lo schermo da lontano.
    final onCard = isCurrent ? scheme.onPrimaryContainer : scheme.onSurface;
    final onCardVariant = isCurrent
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final accent = isCurrent ? scheme.onPrimaryContainer : scheme.primary;

    return Card(
      color: isCurrent ? scheme.primaryContainer : null,
      shape: isCurrent
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onFocus,
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (groupMarker != null) ...[
                    _GroupMarker(label: groupMarker!, color: accent),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      item.name,
                      style:
                          (isCurrent
                                  ? theme.textTheme.headlineSmall
                                  : theme.textTheme.titleLarge)
                              ?.copyWith(color: onCard),
                    ),
                  ),
                  if (sets > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: MetaChip(
                        label: rounds
                            ? l10n.workoutRoundsDone(
                                item.completedSets.length,
                                sets,
                              )
                            : l10n.workoutSetsDone(
                                item.completedSets.length,
                                sets,
                              ),
                        tone: isCurrent ? onCardVariant : null,
                      ),
                    ),
                  if (onStartRest != null)
                    IconButton(
                      onPressed: onStartRest,
                      icon: const Icon(Icons.timer_outlined),
                      color: accent,
                      tooltip: rounds
                          ? l10n.workoutStartRoundRest
                          : l10n.workoutStartRestTimer,
                    )
                  else
                    const SizedBox(width: AppSpacing.sm),
                ],
              ),
              if (_prescription.isNotEmpty)
                Text(
                  _prescription,
                  style: theme.textTheme.titleMedium?.copyWith(color: onCard),
                ),
              if ((item.exercise?.notes ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    item.exercise!.notes!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onCardVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              _LastTimeLine(last: lastPerformance, color: onCardVariant),
              const SizedBox(height: AppSpacing.md),
              if (sets == 0)
                _SetRow(
                  // Senza serie prescritte si registra comunque la prima.
                  label: setLabel(1),
                  set: item.setNumbered(1),
                  accent: accent,
                  onCard: onCard,
                  onCardVariant: onCardVariant,
                  onToggle: () => onToggleSet(1),
                  onEdit: () => onEditSet(1),
                )
              else
                for (var number = 1; number <= sets; number++)
                  _SetRow(
                    label: setLabel(number),
                    set: item.setNumbered(number),
                    accent: accent,
                    onCard: onCard,
                    onCardVariant: onCardVariant,
                    onToggle: () => onToggleSet(number),
                    onEdit: () => onEditSet(number),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  String get _prescription {
    final exercise = item.exercise;
    if (exercise == null) return '';
    final parts = <String>[
      if (exercise.sets != null)
        '${exercise.sets}×${exercise.reps ?? '?'}'
      else if (exercise.reps != null)
        exercise.reps!,
      if ((exercise.load ?? '').isNotEmpty) exercise.load!,
      if (exercise.restSeconds != null) 'rec ${exercise.restSeconds}s',
      if (exercise.durationSeconds != null) '${exercise.durationSeconds}s',
    ];
    return parts.join(' · ');
  }
}

/// Lettera dell'esercizio dentro un gruppo a giri: la stessa notazione della
/// scheda ("A ss B"), così l'abbinamento si legge senza spiegazioni.
class _GroupMarker extends StatelessWidget {
  const _GroupMarker({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 28,
      width: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

class _LastTimeLine extends StatelessWidget {
  const _LastTimeLine({required this.last, required this.color});

  final LastPerformance? last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);

    final performance = last;
    if (performance == null) {
      return Text(l10n.workoutLastTimeNever, style: style);
    }

    final summary = performance.sets.map((set) => set.summary).join(' · ');
    return Text(
      '${l10n.workoutLastTime(performance.performedAt)}: $summary',
      style: style,
    );
  }
}

/// Riga di una serie: spunta a sinistra (l'azione più frequente, sotto il
/// pollice), valori a destra, tutta la riga apre il log rapido.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.set,
    required this.accent,
    required this.onCard,
    required this.onCardVariant,
    required this.onToggle,
    required this.onEdit,
  });

  /// "Serie 2" oppure "Giro 2": lo decide il tipo di blocco.
  final String label;
  final LogSet? set;
  final Color accent;
  final Color onCard;
  final Color onCardVariant;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = set != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: done ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: done
              ? Colors.transparent
              : onCardVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onToggle,
            iconSize: 30,
            icon: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? accent : onCardVariant,
            ),
            tooltip: label,
          ),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                  horizontal: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: onCardVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      done ? set!.summary : '—',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onCard,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(Icons.edit_outlined, size: 18, color: onCardVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
