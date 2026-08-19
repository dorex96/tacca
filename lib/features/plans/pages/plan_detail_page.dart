import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../workout/widgets/day_picker_sheet.dart';
import '../cubit/plans_cubit.dart';
import '../cubit/plans_state.dart';
import '../../../core/block_type_labels.dart';

enum _DetailAction { setActive, duplicate, archiveToggle, delete }

/// Consultazione di una scheda (RF-01): sola lettura, con azioni di lista
/// disponibili anche da qui. Legge da [PlansCubit] (già in memoria, niente
/// nuovo Cubit dedicato: vedi nota in `app/di.dart`).
class PlanDetailPage extends StatelessWidget {
  const PlanDetailPage({required this.planId, super.key});

  final int planId;

  WorkoutPlan? _findPlan(PlansState state) {
    for (final plan in state.activePlans) {
      if (plan.id == planId) return plan;
    }
    for (final plan in state.archivedPlans) {
      if (plan.id == planId) return plan;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<PlansCubit>().state;
    final plan = _findPlan(state);

    if (plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.help_outline,
          message: l10n.planEditorPlanNotFound,
        ),
      );
    }

    final cubit = context.read<PlansCubit>();
    final showDayLabels = plan.days.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.planDetailEditAction,
            onPressed: () => context.push('/plans/${plan.id}/edit'),
          ),
          PopupMenuButton<_DetailAction>(
            onSelected: (action) => _handle(context, cubit, plan, action, l10n),
            itemBuilder: (context) => [
              if (!plan.isActive && !plan.isArchived)
                PopupMenuItem(
                  value: _DetailAction.setActive,
                  child: Text(l10n.plansActionSetActive),
                ),
              PopupMenuItem(
                value: _DetailAction.duplicate,
                child: Text(l10n.plansActionDuplicate),
              ),
              PopupMenuItem(
                value: _DetailAction.archiveToggle,
                child: Text(
                  plan.isArchived
                      ? l10n.plansActionRestore
                      : l10n.plansActionArchive,
                ),
              ),
              PopupMenuItem(
                value: _DetailAction.delete,
                child: Text(
                  l10n.plansActionDelete,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: plan.days.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _startWorkout(context, plan),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.workoutStartAction),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.fabClearance,
        ),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              MetaChip(
                icon: Icons.calendar_today_outlined,
                label: l10n.plansDaysCount(plan.days.length),
              ),
              if (plan.isActive)
                MetaChip(
                  icon: Icons.check_circle_outline,
                  label: l10n.plansInUseBadge,
                  tone: theme.colorScheme.primary,
                ),
              if (plan.isArchived)
                MetaChip(
                  icon: Icons.archive_outlined,
                  label: l10n.plansSectionArchived,
                ),
            ],
          ),
          if ((plan.description ?? '').isNotEmpty) ...[
            SectionHeader(
              label: l10n.planDetailDescriptionLabel,
              padding: const EdgeInsets.only(
                top: AppSpacing.xl,
                bottom: AppSpacing.xs,
              ),
            ),
            Text(plan.description!, style: theme.textTheme.bodyLarge),
          ],
          if ((plan.notes ?? '').isNotEmpty) ...[
            SectionHeader(
              label: l10n.planDetailNotesLabel,
              padding: const EdgeInsets.only(
                top: AppSpacing.xl,
                bottom: AppSpacing.xs,
              ),
            ),
            Text(plan.notes!, style: theme.textTheme.bodyLarge),
          ],
          if (plan.imagePaths.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            // Immagini originali dell'import AI, riapribili in qualsiasi
            // momento (RF-03).
            Card(
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(l10n.planDetailImagesLabel(plan.imagePaths.length)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push('/plan-images', extra: plan.imagePaths),
              ),
            ),
          ],
          for (final day in plan.days)
            _DaySection(day: day, showLabel: showDayLabels),
        ],
      ),
    );
  }

  /// Avvia la sessione (RF-06). La scelta del giorno compare solo sulle schede
  /// multi-giorno: quella a giorno singolo ne ha uno implicito (§5.1).
  Future<void> _startWorkout(BuildContext context, WorkoutPlan plan) async {
    final days = plan.days.toList();
    var dayId = days.first.id;
    if (days.length > 1) {
      final chosen = await showDayPickerSheet(context, days: days);
      if (chosen == null || !context.mounted) return;
      dayId = chosen;
    }
    if (!context.mounted) return;
    context.push('/workout/new?planId=${plan.id}&dayId=$dayId');
  }

  Future<void> _handle(
    BuildContext context,
    PlansCubit cubit,
    WorkoutPlan plan,
    _DetailAction action,
    AppLocalizations l10n,
  ) async {
    switch (action) {
      case _DetailAction.setActive:
        cubit.setActivePlan(plan.id);
      case _DetailAction.duplicate:
        cubit.duplicatePlan(plan.id);
      case _DetailAction.archiveToggle:
        if (plan.isArchived) {
          cubit.restorePlan(plan.id);
        } else {
          cubit.archivePlan(plan.id);
        }
      case _DetailAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.plansDeleteConfirmTitle,
          message: l10n.plansDeleteConfirmBody(plan.name),
          confirmLabel: l10n.commonDelete,
          destructive: true,
        );
        if (confirmed && context.mounted) {
          cubit.deletePlan(plan.id);
          Navigator.of(context).pop();
        }
    }
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.showLabel});

  final WorkoutDay day;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel) ...[
            Text(day.label, style: theme.textTheme.titleLarge),
            if ((day.notes ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  day.notes!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (day.blocks.isEmpty)
            Text(
              l10n.dayNoBlocks,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final block in day.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BlockSection(block: block),
              ),
        ],
      ),
    );
  }
}

class _BlockSection extends StatelessWidget {
  const _BlockSection({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final exercises = block.exercises.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  blockTypeLabel(l10n, block.type),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                for (final param in _params(l10n)) MetaChip(label: param),
              ],
            ),
            if ((block.notes ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  block.notes!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (block.type == BlockType.freeText)
              Text(
                block.freeTextContent ?? '',
                style: theme.textTheme.bodyLarge,
              )
            else if (exercises.isEmpty)
              Text(
                l10n.blockNoExercises,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (var i = 0; i < exercises.length; i++)
                _ExerciseRow(exercise: exercises[i], position: i + 1),
          ],
        ),
      ),
    );
  }

  List<String> _params(AppLocalizations l10n) {
    final parts = <String>[];
    void add(String label, int? value) {
      if (value != null) parts.add('$label: $value');
    }

    switch (block.type) {
      case BlockType.standard:
      case BlockType.freeText:
        break;
      case BlockType.superset:
      case BlockType.circuit:
        add(l10n.planEditorParamRounds, block.rounds);
        add(
          l10n.planEditorParamRestBetweenRounds,
          block.restBetweenRoundsSeconds,
        );
      case BlockType.emom:
        add(l10n.planEditorParamIntervalSeconds, block.intervalSeconds);
        add(l10n.planEditorParamTotalMinutes, block.totalMinutes);
      case BlockType.amrap:
        add(l10n.planEditorParamDurationSeconds, block.durationSeconds);
      case BlockType.tabata:
        add(l10n.planEditorParamWorkSeconds, block.workSeconds);
        add(l10n.planEditorParamRestSeconds, block.restSeconds);
        add(l10n.planEditorParamRounds, block.rounds);
      case BlockType.forTime:
        add(l10n.planEditorParamTimeCapSeconds, block.timeCapSeconds);
    }
    return parts;
  }
}

/// Riga di un esercizio: numero, nome e — allineata a destra, dove l'occhio
/// la ritrova sempre — la prescrizione serie × ripetizioni.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.position});

  final Exercise exercise;
  final int position;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final volume = exercise.sets != null
        ? '${exercise.sets}×${exercise.reps ?? '?'}'
        : (exercise.reps ?? '');
    final details = <String>[
      if ((exercise.load ?? '').isNotEmpty) exercise.load!,
      if (exercise.restSeconds != null)
        l10n.planDetailExerciseRest(exercise.restSeconds!),
      if (exercise.durationSeconds != null)
        l10n.planDetailExerciseDuration(exercise.durationSeconds!),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 26,
            width: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              '$position',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: theme.textTheme.bodyLarge),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if ((exercise.notes ?? '').isNotEmpty)
                  Text(
                    exercise.notes!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (volume.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              volume,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
