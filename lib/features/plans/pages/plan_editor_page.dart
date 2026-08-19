import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';
import '../cubit/plan_editor_state.dart';
import '../widgets/block_card.dart';
import '../../../core/block_type_labels.dart';
import '../widgets/day_tabs_bar.dart';

/// Editor manuale di una scheda (RF-02): metadati, giorni, blocchi ed
/// esercizi con riordino via drag & drop.
class PlanEditorPage extends StatelessWidget {
  const PlanEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<PlanEditorCubit, PlanEditorState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.saveSuccess != current.saveSuccess,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<PlanEditorCubit>().dismissError();
        }
        if (state.saveSuccess) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(l10n.planEditorSaved)));
          Navigator.of(context).pop();
        }
      },
      builder: (context, state) {
        if (state.isLoading) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final cubit = context.read<PlanEditorCubit>();

        return PopScope(
          canPop: !state.isDirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final discard = await _confirmDiscard(context, l10n);
            if (discard && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                state.isNew
                    ? l10n.planEditorNewTitle
                    : l10n.planEditorEditTitle,
              ),
              actions: [
                if (state.draft.imagePaths.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    tooltip: l10n.planImagesTitle,
                    onPressed: () => context.push(
                      '/plan-images',
                      extra: state.draft.imagePaths,
                    ),
                  ),
                IconButton(
                  icon: state.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  tooltip: l10n.commonSave,
                  onPressed: state.isSaving ? null : cubit.save,
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                TextFormField(
                  key: const ValueKey('plan-name'),
                  initialValue: state.draft.name,
                  decoration: InputDecoration(
                    labelText: l10n.planEditorNameLabel,
                    hintText: l10n.planEditorNameHint,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: cubit.updateName,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('plan-description'),
                  initialValue: state.draft.description ?? '',
                  decoration: InputDecoration(
                    labelText: l10n.planEditorDescriptionLabel,
                  ),
                  onChanged: cubit.updateDescription,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('plan-notes'),
                  initialValue: state.draft.notes ?? '',
                  decoration: InputDecoration(
                    labelText: l10n.planEditorNotesLabel,
                  ),
                  minLines: 1,
                  maxLines: 4,
                  onChanged: cubit.updatePlanNotes,
                ),
                // Separa i dati della scheda dalla struttura dei giorni: da
                // qui in giù si lavora sul contenuto dell'allenamento.
                const Divider(),
                if (state.showDayTabs)
                  DayTabsBar(
                    days: state.draft.days.toList(),
                    selectedIndex: state.selectedDayIndex,
                    cubit: cubit,
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: cubit.addDay,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.planEditorAddDay),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                _DayBlocksSection(
                  key: ValueKey('day-blocks-${state.selectedDayIndex}'),
                  day: state.draft.days[state.selectedDayIndex],
                  dayIndex: state.selectedDayIndex,
                  showDayNotes: state.showDayTabs,
                  cubit: cubit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDiscard(BuildContext context, AppLocalizations l10n) {
    return showConfirmDialog(
      context,
      title: l10n.planEditorDiscardTitle,
      message: l10n.planEditorDiscardBody,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
  }
}

class _DayBlocksSection extends StatelessWidget {
  const _DayBlocksSection({
    required this.day,
    required this.dayIndex,
    required this.showDayNotes,
    required this.cubit,
    super.key,
  });

  final WorkoutDay day;
  final int dayIndex;
  final bool showDayNotes;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final blocks = day.blocks.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDayNotes) ...[
          TextFormField(
            key: ValueKey('day-notes-${identityHashCode(day)}'),
            initialValue: day.notes ?? '',
            decoration: InputDecoration(labelText: l10n.planEditorNotesLabel),
            onChanged: (v) => cubit.updateDayNotes(dayIndex, v),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text(
                l10n.dayNoBlocks,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ReorderableListView(
            key: PageStorageKey('block-list-${identityHashCode(day)}'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) =>
                cubit.reorderBlocks(dayIndex, oldIndex, newIndex),
            children: [
              for (var i = 0; i < blocks.length; i++)
                BlockCard(
                  key: ValueKey('block-${identityHashCode(blocks[i])}'),
                  block: blocks[i],
                  index: i,
                  dayIndex: dayIndex,
                  cubit: cubit,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _pickBlockType(context, l10n, dayIndex),
            icon: const Icon(Icons.add),
            label: Text(l10n.planEditorAddBlock),
          ),
        ),
      ],
    );
  }

  Future<void> _pickBlockType(
    BuildContext context,
    AppLocalizations l10n,
    int dayIndex,
  ) async {
    final type = await showModalBottomSheet<BlockType>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.planEditorBlockTypeLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final blockType in BlockType.values)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xs,
                ),
                title: Text(blockTypeLabel(l10n, blockType)),
                onTap: () => Navigator.of(context).pop(blockType),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (type != null) cubit.addBlock(dayIndex, type);
  }
}
