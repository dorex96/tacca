import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../../core/design/app_radius.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/meta_chip.dart';
import '../../../data/entities/block.dart';
import '../../../data/entities/workout_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/block_type_labels.dart';
import '../bloc/block_timer_spec.dart';
import '../bloc/session_item.dart';
import '../bloc/workout_session_bloc.dart';
import '../bloc/workout_session_event.dart';
import '../bloc/workout_session_state.dart';
import '../widgets/session_exercise_card.dart';
import '../widgets/session_summary_sheet.dart';
import '../widgets/set_log_sheet.dart';
import '../widgets/timer_bar.dart';

/// Modalità allenamento (RF-06): la schermata che si usa in palestra.
///
/// Osserva il lifecycle dell'app per delegare al Bloc la programmazione delle
/// notifiche quando si va in background e la riconciliazione al rientro (§7).
class WorkoutSessionPage extends StatefulWidget {
  const WorkoutSessionPage({super.key});

  @override
  State<WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<WorkoutSessionPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final toBackground = state != AppLifecycleState.resumed;
    context.read<WorkoutSessionBloc>().add(
      AppLifecycleChanged(
        toBackground: toBackground,
        notificationTitle: l10n.workoutNotificationTitle,
        notificationBody: l10n.workoutNotificationBody,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return BlocConsumer<WorkoutSessionBloc, WorkoutSessionState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.pendingTimerRequest != current.pendingTimerRequest ||
          previous.status != current.status,
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<WorkoutSessionBloc>().add(const SessionErrorDismissed());
        }
        if (state.pendingTimerRequest != null) {
          _confirmTimerReplacement(context, l10n);
        }
        if (state.status == WorkoutSessionStatus.finished) {
          final logId = state.log?.id;
          if (logId != null) {
            context.pushReplacement('/history/$logId');
          } else {
            context.pop();
          }
        }
      },
      builder: (context, state) {
        switch (state.status) {
          case WorkoutSessionStatus.loading:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case WorkoutSessionStatus.notFound:
            return Scaffold(
              appBar: AppBar(),
              body: EmptyState(
                icon: Icons.help_outline,
                message: l10n.workoutSessionNotFound,
              ),
            );
          case WorkoutSessionStatus.finished:
          case WorkoutSessionStatus.ready:
            return _SessionScaffold(state: state);
        }
      },
    );
  }

  Future<void> _confirmTimerReplacement(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bloc = context.read<WorkoutSessionBloc>();
    final spec = bloc.state.pendingTimerRequest;
    if (spec == null) return;

    final replace = await showConfirmDialog(
      context,
      title: l10n.workoutReplaceTimerTitle,
      message: l10n.workoutReplaceTimerBody,
      confirmLabel: l10n.workoutReplaceTimerConfirm,
    );

    if (replace) {
      bloc.add(TimerRequested(spec, force: true));
    } else {
      bloc.add(const TimerRequestDismissed());
    }
  }
}

class _SessionScaffold extends StatelessWidget {
  const _SessionScaffold({required this.state});

  final WorkoutSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bloc = context.read<WorkoutSessionBloc>();
    final items = state.items;
    final log = state.log;

    return PopScope(
      canPop: state.status != WorkoutSessionStatus.ready,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmExit(context, l10n);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(log?.dayLabelSnapshot ?? ''),
              Text(
                l10n.workoutProgress(state.completedExercises, items.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // L'avanzamento della sessione è un dato che si consulta di
          // continuo: una barra sottile lo rende leggibile senza contare.
          bottom: items.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    value: state.completedExercises / items.length,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => _finish(context, bloc, l10n),
              child: Text(l10n.workoutFinishAction),
            ),
            PopupMenuButton<_SessionMenuAction>(
              onSelected: (action) => _handleMenu(context, bloc, l10n, action),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: _SessionMenuAction.toggleAutoRest,
                  checked: state.autoStartRest,
                  child: Text(l10n.workoutAutoRestLabel),
                ),
                PopupMenuItem(
                  value: _SessionMenuAction.abort,
                  child: Text(l10n.workoutAbortAction),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.timer case final timer?)
              TimerBar(
                timer: timer,
                onStop: () => bloc.add(const TimerStopped()),
              ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: Icons.self_improvement_outlined,
                      message: l10n.workoutNoExercises,
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      children: _buildBody(context, bloc, l10n, items),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
    List<SessionItem> items,
  ) {
    final widgets = <Widget>[];

    if (state.day == null) {
      widgets.add(_PlanRemovedNotice(message: l10n.workoutPlanRemoved));
    }

    for (final block in state.blocks) {
      if (block.type == BlockType.freeText) {
        widgets.add(_BlockHeader(block: block, state: state));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(block.freeTextContent ?? ''),
          ),
        );
        continue;
      }

      final blockItems = items
          .where((item) => item.block?.id == block.id)
          .toList();
      // Superset e circuiti si eseguono insieme: vanno letti come un pezzo
      // unico, non come esercizi indipendenti messi in fila.
      final grouped =
          (block.type == BlockType.superset ||
              block.type == BlockType.circuit) &&
          blockItems.length > 1;

      final header = _BlockHeader(block: block, state: state, inGroup: grouped);
      final cards = [
        for (var i = 0; i < blockItems.length; i++)
          _card(
            context,
            bloc,
            blockItems[i],
            groupMarker: grouped ? String.fromCharCode(0x41 + i) : null,
          ),
      ];

      if (grouped) {
        widgets.add(_BlockGroup(children: [header, ...cards]));
      } else {
        widgets
          ..add(header)
          ..addAll(cards);
      }
    }

    // Esercizi registrati che non esistono più in scheda: restano in fondo,
    // non vengono mai nascosti (analisi funzionale §9).
    widgets.addAll(
      items
          .where((item) => item.block == null)
          .map((item) => _card(context, bloc, item)),
    );

    return widgets;
  }

  Widget _card(
    BuildContext context,
    WorkoutSessionBloc bloc,
    SessionItem item, {
    String? groupMarker,
  }) {
    final rest = restTimerSpec(item, label: item.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SessionExerciseCard(
        key: ValueKey('session-item-${item.index}'),
        item: item,
        isCurrent: item.index == state.currentIndex,
        lastPerformance: state.lastPerformances[item.name],
        groupMarker: groupMarker,
        onFocus: () => bloc.add(ExerciseFocused(item.index)),
        onToggleSet: (setNumber) {
          if (item.isSetDone(setNumber)) {
            bloc.add(
              SetUnchecked(entryIndex: item.index, setNumber: setNumber),
            );
          } else {
            bloc.add(
              SetCompleted(entryIndex: item.index, setNumber: setNumber),
            );
          }
        },
        onEditSet: (setNumber) => _editSet(context, bloc, item, setNumber),
        onStartRest: rest == null ? null : () => bloc.add(TimerRequested(rest)),
      ),
    );
  }

  Future<void> _editSet(
    BuildContext context,
    WorkoutSessionBloc bloc,
    SessionItem item,
    int setNumber,
  ) async {
    final suggestion = state.lastPerformances[item.name];
    final reference = suggestion == null || suggestion.sets.isEmpty
        ? null
        : suggestion.sets.last;

    final outcome = await showSetLogSheet(
      context,
      exerciseName: item.name,
      setNumber: setNumber,
      current: item.setNumbered(setNumber),
      suggestedWeightKg: reference?.weightKg,
      suggestedReps: reference?.reps ?? item.exercise?.reps,
    );

    switch (outcome) {
      case null:
        return;
      case SetLogRemoved():
        bloc.add(SetUnchecked(entryIndex: item.index, setNumber: setNumber));
      case SetLogSaved(:final weightKg, :final reps, :final notes):
        bloc.add(
          SetLogged(
            entryIndex: item.index,
            setNumber: setNumber,
            weightKg: weightKg,
            reps: reps,
            notes: notes,
          ),
        );
    }
  }

  Future<void> _finish(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
  ) async {
    final log = state.log;
    if (log == null) return;

    final result = await showSessionSummarySheet(
      context,
      elapsed: log.duration(),
      completedExercises: state.completedExercises,
      totalExercises: state.items.length,
      loggedSets: state.loggedSets,
      items: state.items,
      initialNotes: log.notes,
    );
    if (result == null) return;

    bloc.add(
      SessionFinished(status: WorkoutStatus.completed, notes: result.notes),
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WorkoutSessionBloc bloc,
    AppLocalizations l10n,
    _SessionMenuAction action,
  ) async {
    switch (action) {
      case _SessionMenuAction.toggleAutoRest:
        bloc.add(AutoStartRestToggled(!state.autoStartRest));
      case _SessionMenuAction.abort:
        final confirmed = await showConfirmDialog(
          context,
          title: l10n.workoutAbortConfirmTitle,
          message: l10n.workoutAbortConfirmBody,
          confirmLabel: l10n.workoutAbortAction,
          destructive: true,
        );
        if (confirmed) {
          bloc.add(const SessionFinished(status: WorkoutStatus.aborted));
        }
    }
  }

  Future<bool> _confirmExit(BuildContext context, AppLocalizations l10n) {
    return showConfirmDialog(
      context,
      title: l10n.workoutExitTitle,
      message: l10n.workoutExitBody,
      confirmLabel: l10n.workoutExitConfirm,
      cancelLabel: l10n.commonContinue,
    );
  }
}

/// La scheda collegata non esiste più: la sessione continua, ma va detto
/// perché non si vedono più esercizi previsti (analisi funzionale §9).
class _PlanRemovedNotice extends StatelessWidget {
  const _PlanRemovedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SessionMenuAction { toggleAutoRest, abort }

/// Riquadro di un gruppo che si esegue a giri (superset, circuito): tiene
/// insieme intestazione ed esercizi, così si legge come un pezzo unico invece
/// che come esercizi indipendenti messi in fila.
class _BlockGroup extends StatelessWidget {
  const _BlockGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Intestazione di un blocco: tipo, parametri e, dove esiste, il timer che
/// guida l'esecuzione dell'intero blocco.
class _BlockHeader extends StatelessWidget {
  const _BlockHeader({
    required this.block,
    required this.state,
    this.inGroup = false,
  });

  final Block block;
  final WorkoutSessionState state;

  /// L'intestazione è dentro il riquadro di un gruppo a giri: la spaziatura
  /// esterna la mette il riquadro.
  final bool inGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = blockTimerSpec(block, label: blockTypeLabel(l10n, block.type));
    final rounds = block.rounds;
    final roundRest = block.restBetweenRoundsSeconds;

    // Il "come si esegue" è la prima cosa da capire di un superset: giri e
    // recupero stanno accanto al nome del blocco, non sepolti negli esercizi.
    final params = <String>[
      if (block.type != BlockType.tabata && rounds != null && rounds > 0)
        l10n.workoutBlockRounds(rounds),
      if (roundRest != null && roundRest > 0)
        l10n.workoutBlockRestBetweenRounds(roundRest),
    ];

    final hint = switch (block.type) {
      BlockType.superset when inGroup => l10n.workoutSupersetHint,
      BlockType.circuit when inGroup => l10n.workoutCircuitHint,
      _ => null,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        inGroup ? AppSpacing.sm : 0,
        inGroup ? AppSpacing.md : AppSpacing.xl,
        inGroup ? AppSpacing.sm : 0,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  blockTypeLabel(l10n, block.type),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (spec != null)
                FilledButton.tonalIcon(
                  onPressed: () => context.read<WorkoutSessionBloc>().add(
                    TimerRequested(spec),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.workoutStartBlockTimer),
                ),
            ],
          ),
          if (params.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [for (final param in params) MetaChip(label: param)],
              ),
            ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if ((block.notes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                block.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
