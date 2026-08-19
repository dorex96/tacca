import 'package:flutter/material.dart';

import '../../../core/design/app_spacing.dart';
import '../../../data/entities/block.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';
import 'block_params_fields.dart';
import '../../../core/block_type_labels.dart';
import 'exercise_tile.dart';

/// Card espandibile per un [Block]: intestazione con riepilogo (tap per
/// espandere/comprimere) + corpo con tipo, parametri, note ed esercizi.
///
/// Il tipo non è nell'intestazione apposta: un `DropdownButtonFormField` lì
/// intercetterebbe il tap prima che possa aprire/chiudere la tile.
class BlockCard extends StatelessWidget {
  const BlockCard({
    required this.block,
    required this.index,
    required this.dayIndex,
    required this.cubit,
    super.key,
  });

  final Block block;
  final int index;
  final int dayIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final instanceKey = identityHashCode(block);

    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        key: PageStorageKey('block-tile-$instanceKey'),
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(
            Icons.drag_indicator,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          blockTypeLabel(l10n, block.type),
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          _summary(l10n),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.planEditorRemoveBlock,
          onPressed: () => cubit.removeBlock(dayIndex, index),
        ),
        children: [
          // Bucket isolato: gli `EditableText` annidati (campi numerici,
          // note, esercizi) usano PageStorage per il proprio scroll interno
          // e altrimenti collidono con lo stato bool di ExpansionTile
          // (flutter/flutter#36539).
          PageStorage(
            bucket: PageStorageBucket(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<BlockType>(
                    initialValue: block.type,
                    decoration: InputDecoration(
                      labelText: l10n.planEditorBlockTypeLabel,
                    ),
                    items: [
                      for (final type in BlockType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(blockTypeLabel(l10n, type)),
                        ),
                    ],
                    onChanged: (type) {
                      if (type != null) {
                        cubit.changeBlockType(dayIndex, index, type);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  BlockParamsFields(
                    block: block,
                    cubit: cubit,
                    dayIndex: dayIndex,
                    blockIndex: index,
                  ),
                  if (block.type != BlockType.freeText) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: ValueKey('block-notes-$instanceKey'),
                      initialValue: block.notes ?? '',
                      decoration: InputDecoration(
                        labelText: l10n.planEditorBlockNotesLabel,
                      ),
                      onChanged: (v) =>
                          cubit.updateBlockNotes(dayIndex, index, v),
                    ),
                    const Divider(),
                    _ExerciseList(
                      block: block,
                      dayIndex: dayIndex,
                      blockIndex: index,
                      cubit: cubit,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => cubit.addExercise(dayIndex, index),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.planEditorAddExercise),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summary(AppLocalizations l10n) {
    if (block.type == BlockType.freeText) {
      final content = block.freeTextContent ?? '';
      return content.trim().isEmpty ? l10n.planEditorFreeTextHint : content;
    }
    return l10n.planEditorExercisesCount(block.exercises.length);
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({
    required this.block,
    required this.dayIndex,
    required this.blockIndex,
    required this.cubit,
  });

  final Block block;
  final int dayIndex;
  final int blockIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exercises = block.exercises.toList();

    if (exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.blockNoExercises,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ReorderableListView(
      key: PageStorageKey('exercise-list-${identityHashCode(block)}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          cubit.reorderExercises(dayIndex, blockIndex, oldIndex, newIndex),
      children: [
        for (var i = 0; i < exercises.length; i++)
          ExerciseTile(
            key: ValueKey('exercise-${identityHashCode(exercises[i])}'),
            exercise: exercises[i],
            index: i,
            onNameChanged: (v) =>
                cubit.setExerciseName(dayIndex, blockIndex, i, v),
            onSetsChanged: (v) =>
                cubit.setExerciseSets(dayIndex, blockIndex, i, v),
            onRepsChanged: (v) =>
                cubit.setExerciseReps(dayIndex, blockIndex, i, v),
            onLoadChanged: (v) =>
                cubit.setExerciseLoad(dayIndex, blockIndex, i, v),
            onRestChanged: (v) =>
                cubit.setExerciseRestSeconds(dayIndex, blockIndex, i, v),
            onDurationChanged: (v) =>
                cubit.setExerciseDurationSeconds(dayIndex, blockIndex, i, v),
            onNotesChanged: (v) =>
                cubit.setExerciseNotes(dayIndex, blockIndex, i, v),
            onRemove: () => cubit.removeExercise(dayIndex, blockIndex, i),
          ),
      ],
    );
  }
}
