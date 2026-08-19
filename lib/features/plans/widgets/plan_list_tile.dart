import 'package:flutter/material.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../data/entities/workout_plan.dart';
import '../../../l10n/app_localizations.dart';

enum _PlanAction { setActive, edit, duplicate, archiveToggle, delete }

/// Riga dell'archivio schede (RF-01): apertura al tap, azioni nel menu.
///
/// La scheda in uso è l'unica colorata della lista: un solo elemento in
/// evidenza per schermata, altrimenti non è più in evidenza nulla.
class PlanListTile extends StatelessWidget {
  const PlanListTile({
    required this.plan,
    required this.onOpen,
    required this.onEdit,
    required this.onDuplicate,
    required this.onArchiveToggle,
    required this.onDelete,
    this.onSetActive,
    this.highlighted = false,
    super.key,
  });

  final WorkoutPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;

  /// Null quando l'azione non ha senso (già in uso, oppure scheda archiviata).
  final VoidCallback? onSetActive;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final foreground = highlighted ? scheme.onPrimaryContainer : null;

    return Card(
      color: highlighted ? scheme.primaryContainer : null,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: highlighted
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  highlighted ? Icons.check_rounded : Icons.fitness_center,
                  color: highlighted ? scheme.onPrimary : scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    MetaChip(
                      icon: Icons.calendar_today_outlined,
                      label: l10n.plansDaysCount(plan.days.length),
                      tone: foreground,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_PlanAction>(
                onSelected: (action) => _handle(context, action),
                iconColor: foreground,
                itemBuilder: (context) => [
                  if (onSetActive != null)
                    _item(
                      value: _PlanAction.setActive,
                      icon: Icons.play_circle_outline,
                      label: l10n.plansActionSetActive,
                    ),
                  _item(
                    value: _PlanAction.edit,
                    icon: Icons.edit_outlined,
                    label: l10n.plansActionEdit,
                  ),
                  _item(
                    value: _PlanAction.duplicate,
                    icon: Icons.copy_all_outlined,
                    label: l10n.plansActionDuplicate,
                  ),
                  _item(
                    value: _PlanAction.archiveToggle,
                    icon: plan.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    label: plan.isArchived
                        ? l10n.plansActionRestore
                        : l10n.plansActionArchive,
                  ),
                  _item(
                    value: _PlanAction.delete,
                    icon: Icons.delete_outline,
                    label: l10n.plansActionDelete,
                    color: scheme.error,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Icona + etichetta: nel menu l'icona è il primo aggancio visivo, il testo
  /// toglie ogni ambiguità.
  PopupMenuItem<_PlanAction> _item({
    required _PlanAction value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  Future<void> _handle(BuildContext context, _PlanAction action) async {
    switch (action) {
      case _PlanAction.setActive:
        onSetActive?.call();
      case _PlanAction.edit:
        onEdit();
      case _PlanAction.duplicate:
        onDuplicate();
      case _PlanAction.archiveToggle:
        onArchiveToggle();
      case _PlanAction.delete:
        await _confirmDelete(context);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.plansDeleteConfirmTitle,
      message: l10n.plansDeleteConfirmBody(plan.name),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) onDelete();
  }
}
