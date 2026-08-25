import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/block_type_labels.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/design/app_typography.dart';
import '../../../core/design/linear_icons.dart';
import '../../../core/widgets/app_menu.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/linear_icon.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/square_icon_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/exercise.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../../workout/widgets/day_picker_sheet.dart';
import '../cubit/plans_cubit.dart';
import '../cubit/plans_state.dart';

enum _DetailAction { setActive, duplicate, archiveToggle, delete }

/// Consultazione di una scheda (RF-01): sola lettura, con azioni di lista
/// disponibili anche da qui. Legge da [PlansCubit] (già in memoria, niente
/// nuovo Cubit dedicato: vedi nota in `app/di.dart`).
///
/// Il titolo sta nel contenuto e non nella testata: è lungo, va a capo, e
/// mentre si scorre la scheda serve lo spazio, non il promemoria del nome.
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
    final state = context.watch<PlansCubit>().state;
    final plan = _findPlan(state);

    if (plan == null) {
      return AppScaffold(
        leading: const AppBackButton(),
        body: EmptyState(
          icon: AppIcons.search,
          message: l10n.planEditorPlanNotFound,
        ),
      );
    }

    final cubit = context.read<PlansCubit>();
    final showDayLabels = plan.days.length > 1;

    return AppScaffold(
      leading: const AppBackButton(),
      actions: [
        SquareIconButton(
          icon: AppIcons.pencil,
          tooltip: l10n.planDetailEditAction,
          onPressed: () => context.push('/plans/${plan.id}/edit'),
        ),
        AppMenuButton<_DetailAction>(
          onSelected: (action) => _handle(context, cubit, plan, action, l10n),
          itemBuilder: (context) => [
            if (!plan.isActive && !plan.isArchived)
              appMenuItem(
                value: _DetailAction.setActive,
                label: l10n.plansActionSetActive,
              ),
            appMenuItem(
              value: _DetailAction.duplicate,
              label: l10n.plansActionDuplicate,
            ),
            appMenuItem(
              value: _DetailAction.archiveToggle,
              label: plan.isArchived
                  ? l10n.plansActionRestore
                  : l10n.plansActionArchive,
            ),
            appMenuItem(
              value: _DetailAction.delete,
              label: l10n.plansActionDelete,
              icon: AppIcons.trash,
              destructive: true,
            ),
          ],
        ),
      ],
      dock: plan.days.isEmpty
          ? null
          : PillButton(
              label: l10n.workoutStartAction,
              icon: AppIcons.play,
              onPressed: () => _startWorkout(context, plan),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.actionClearance,
        ),
        children: [
          Text(plan.name, style: AppTypography.screenTitle),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              MetaChip(
                icon: AppIcons.calendar,
                label: l10n.plansDaysCount(plan.days.length),
                tone: ChipTone.onBackground,
                small: false,
              ),
              if (plan.isActive)
                MetaChip(
                  icon: AppIcons.check,
                  label: l10n.plansInUseBadge,
                  tone: ChipTone.accent,
                  small: false,
                ),
              if (plan.isArchived)
                MetaChip(
                  label: l10n.plansSectionArchived,
                  tone: ChipTone.onBackground,
                  small: false,
                ),
            ],
          ),
          if ((plan.description ?? '').isNotEmpty)
            Section(
              label: l10n.planDetailDescriptionLabel,
              child: _TextCard(text: plan.description!),
            ),
          if ((plan.notes ?? '').isNotEmpty)
            Section(
              label: l10n.planDetailNotesLabel,
              child: _TextCard(text: plan.notes!),
            ),
          if (plan.imagePaths.isNotEmpty)
            Section(
              // Immagini originali dell'import AI, riapribili in qualsiasi
              // momento (RF-03).
              child: SurfaceCard(
                onTap: () =>
                    context.push('/plan-images', extra: plan.imagePaths),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const LinearIcon(
                      AppIcons.gallery,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.planDetailImagesLabel(plan.imagePaths.length),
                        style: AppTypography.row,
                      ),
                    ),
                    const LinearIcon(
                      AppIcons.chevronRight,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
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

/// Descrizione e note della scheda: prosa, quindi carattere di sistema dentro
/// una card bianca.
class _TextCard extends StatelessWidget {
  const _TextCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.card,
        vertical: AppSpacing.lg,
      ),
      child: Text(text, style: AppTypography.paragraph),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day, required this.showLabel});

  final WorkoutDay day;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLabel) ...[
            Text(day.label, style: AppTypography.subtitle),
            if ((day.notes ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs + 2),
              Text(day.notes!, style: AppTypography.paragraphSmall),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (day.blocks.isEmpty)
            Text(l10n.dayNoBlocks, style: AppTypography.paragraphSmall)
          else
            for (final block in day.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _BlockCard(block: block),
              ),
        ],
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = block.exercises.toList();

    return SurfaceCard(
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
                style: AppTypography.blockType,
              ),
              for (final param in _params(l10n)) MetaChip(label: param),
            ],
          ),
          if ((block.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(block.notes!, style: AppTypography.paragraphSmall),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (block.type == BlockType.freeText)
            Text(block.freeTextContent ?? '', style: AppTypography.paragraph)
          else if (exercises.isEmpty)
            Text(l10n.blockNoExercises, style: AppTypography.paragraphSmall)
          else
            for (var i = 0; i < exercises.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.lg),
              _ExerciseRow(exercise: exercises[i], position: i + 1),
            ],
        ],
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExercisePosition(position: position),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exercise.name, style: AppTypography.row),
              if (details.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(details.join(' · '), style: AppTypography.meta),
              ],
              if ((exercise.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  exercise.notes!,
                  style: AppTypography.paragraphSmall.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (volume.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(volume, style: AppTypography.metaStrong.copyWith(fontSize: 14)),
        ],
      ],
    );
  }
}

/// Quadratino con il numero d'ordine dell'esercizio dentro il blocco.
class ExercisePosition extends StatelessWidget {
  const ExercisePosition({required this.position, super.key});

  final int position;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      width: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text('$position', style: AppTypography.chip),
    );
  }
}
