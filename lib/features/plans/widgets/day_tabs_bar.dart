import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../data/entities/workout_day.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/plan_editor_cubit.dart';

/// Selettore orizzontale dei giorni, visibile solo per schede multi-giorno
/// (analisi funzionale §5.1: il giorno singolo è implicito e non compare).
///
/// Tap per selezionare, pressione prolungata per rinominare/rimuovere.
class DayTabsBar extends StatelessWidget {
  const DayTabsBar({
    required this.days,
    required this.selectedIndex,
    required this.cubit,
    super.key,
  });

  final List<WorkoutDay> days;
  final int selectedIndex;
  final PlanEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
    );

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          if (i == days.length) {
            return ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              shape: shape,
              label: Text(l10n.planEditorAddDay),
              onPressed: cubit.addDay,
            );
          }
          final day = days[i];
          final selected = i == selectedIndex;
          return Material(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              onTap: () => cubit.selectDay(i),
              onLongPress: () => _showDayMenu(context, l10n, i, day),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Text(
                  day.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showDayMenu(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    WorkoutDay day,
  ) async {
    final action = await showModalBottomSheet<_DayAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.commonRename),
              onTap: () => Navigator.of(context).pop(_DayAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.planEditorRemoveDay),
              onTap: () => Navigator.of(context).pop(_DayAction.remove),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;
    switch (action) {
      case _DayAction.rename:
        await _renameDay(context, l10n, index, day.label);
      case _DayAction.remove:
        await _removeDay(context, l10n, index, day.label);
    }
  }

  Future<void> _renameDay(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    String currentLabel,
  ) async {
    final controller = TextEditingController(text: currentLabel);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.planEditorRenameDayTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.planEditorDayLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (newLabel != null && newLabel.isNotEmpty) {
      cubit.updateDayLabel(index, newLabel);
    }
  }

  Future<void> _removeDay(
    BuildContext context,
    AppLocalizations l10n,
    int index,
    String label,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.planEditorRemoveDayConfirmTitle,
      message: l10n.planEditorRemoveDayConfirmBody(label),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) {
      cubit.removeDay(index);
    }
  }
}

enum _DayAction { rename, remove }
