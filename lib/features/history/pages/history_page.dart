import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/extensions/duration_format.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../cubit/history_cubit.dart';
import '../cubit/history_state.dart';

/// Storico allenamenti (RF-07): sessioni per data, filtro per scheda,
/// eliminazione con conferma.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: BlocConsumer<HistoryCubit, HistoryState>(
        listenWhen: (previous, current) =>
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<HistoryCubit>().dismissError();
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.logs.isEmpty) {
            return EmptyState(
              icon: Icons.history_toggle_off_outlined,
              message: l10n.historyEmpty,
            );
          }

          final logs = state.filteredLogs;
          return Column(
            children: [
              _PlanFilter(state: state),
              Expanded(
                child: logs.isEmpty
                    ? EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        message: l10n.historyNoResults,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.xxl,
                        ),
                        itemCount: logs.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) =>
                            _HistoryTile(log: logs[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlanFilter extends StatelessWidget {
  const _PlanFilter({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = state.planOptions;
    if (options.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: DropdownButtonFormField<String?>(
        initialValue: state.planFilter,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.historyFilterLabel,
          prefixIcon: const Icon(Icons.filter_list),
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(l10n.historyFilterAll)),
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: context.read<HistoryCubit>().filterByPlan,
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.log});

  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aborted = log.status == WorkoutStatus.aborted;
    final setsCount = log.entries.fold<int>(
      0,
      (total, entry) => total + entry.sets.length,
    );

    return Card(
      child: InkWell(
        onTap: () => context.push('/history/${log.id}'),
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
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  aborted ? Icons.pause_rounded : Icons.check_rounded,
                  color: aborted ? scheme.error : scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.planNameSnapshot,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Data e ora in chiaro: è il dato con cui si cerca una
                    // sessione nello storico.
                    Text(
                      '${l10n.historySessionDate(log.startedAt)} · '
                      '${l10n.historySessionTime(log.startedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        MetaChip(label: log.dayLabelSnapshot),
                        MetaChip(
                          icon: Icons.timer_outlined,
                          label: log.duration().compact,
                        ),
                        MetaChip(label: l10n.historySetsCount(setsCount)),
                        if (aborted)
                          MetaChip(
                            label: l10n.historyStatusAborted,
                            tone: scheme.error,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.commonDelete,
                onPressed: () => _confirmDelete(context, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final cubit = context.read<HistoryCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.historyDeleteConfirmTitle,
      message: l10n.historyDeleteConfirmBody(log.startedAt),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) cubit.deleteLog(log.id);
  }
}
