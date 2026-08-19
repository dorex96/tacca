import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/entities/log_entry.dart';
import '../../../data/entities/log_set.dart';
import '../../../data/entities/workout_day.dart';
import '../../../data/entities/workout_log.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../data/repositories/workout_log_repository.dart';
import '../../../services/feedback/session_feedback.dart';
import '../../../services/notifications/session_notifier.dart';
import '../../../services/timer/timer_engine.dart';
import '../../../services/wakelock/screen_wake.dart';
import 'block_timer_spec.dart';
import 'session_item.dart';
import 'workout_session_event.dart';
import 'workout_session_state.dart';

/// Sessione di allenamento (RF-06).
///
/// Regole implementative (§5.1):
/// - **autosave**: ogni handler che muta lo stato persiste subito il
///   [WorkoutLog]. È così che si supera il crash test, non con un salvataggio
///   periodico;
/// - il Bloc si iscrive a [TimerEngine.stream] e ritrasmette come
///   [TimerTicked]: mai `emit` da una callback esterna;
/// - suoni, notifiche e wake lock passano da servizi astratti, così la
///   sessione resta testabile senza plugin.
class WorkoutSessionBloc
    extends Bloc<WorkoutSessionEvent, WorkoutSessionState> {
  WorkoutSessionBloc({
    required PlanRepository planRepository,
    required WorkoutLogRepository logRepository,
    required TimerEngine timerEngine,
    required SessionFeedback feedback,
    required SessionNotifier notifier,
    required ScreenWake screenWake,
    DateTime Function()? now,
  }) : _planRepository = planRepository,
       _logRepository = logRepository,
       _timerEngine = timerEngine,
       _feedback = feedback,
       _notifier = notifier,
       _screenWake = screenWake,
       _now = now ?? DateTime.now,
       super(const WorkoutSessionState()) {
    on<SessionStarted>(_onSessionStarted);
    on<SessionResumed>(_onSessionResumed);
    on<SetCompleted>(_onSetCompleted);
    on<SetUnchecked>(_onSetUnchecked);
    on<SetLogged>(_onSetLogged);
    on<ExerciseFocused>(_onExerciseFocused);
    on<TimerRequested>(_onTimerRequested);
    on<TimerRequestDismissed>(_onTimerRequestDismissed);
    on<TimerTicked>(_onTimerTicked);
    on<TimerSignalled>(_onTimerSignalled);
    on<TimerStopped>(_onTimerStopped);
    on<AutoStartRestToggled>(_onAutoStartRestToggled);
    on<AppLifecycleChanged>(_onAppLifecycleChanged);
    on<SessionFinished>(_onSessionFinished);
    on<SessionErrorDismissed>(
      (event, emit) => emit(state.copyWith(errorMessage: null)),
    );

    _tickSub = _timerEngine.stream.listen((timer) => add(TimerTicked(timer)));
    _signalSub = _timerEngine.signals.listen(
      (signal) => add(TimerSignalled(signal)),
    );
  }

  final PlanRepository _planRepository;
  final WorkoutLogRepository _logRepository;
  final TimerEngine _timerEngine;
  final SessionFeedback _feedback;
  final SessionNotifier _notifier;
  final ScreenWake _screenWake;
  final DateTime Function() _now;

  late final StreamSubscription<TimerState> _tickSub;
  late final StreamSubscription<TimerSignal> _signalSub;

  // --- apertura della sessione ---

  Future<void> _onSessionStarted(
    SessionStarted event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final plan = _planRepository.getById(event.planId);
    WorkoutDay? day;
    for (final candidate in plan?.days ?? const <WorkoutDay>[]) {
      if (candidate.id == event.dayId) {
        day = candidate;
        break;
      }
    }
    if (plan == null || day == null) {
      emit(state.copyWith(status: WorkoutSessionStatus.notFound));
      return;
    }

    try {
      final log = _logRepository.startSession(plan: plan, day: day);
      emit(
        state.copyWith(
          status: WorkoutSessionStatus.ready,
          log: log,
          day: day,
          lastPerformances: _loadLastPerformances(log),
          revision: state.revision + 1,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: WorkoutSessionStatus.notFound,
          errorMessage: error.toString(),
        ),
      );
      return;
    }

    await _prepareDevices();
  }

  Future<void> _onSessionResumed(
    SessionResumed event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final log = _logRepository.getById(event.logId);
    if (log == null) {
      emit(state.copyWith(status: WorkoutSessionStatus.notFound));
      return;
    }

    final day = log.day.target;
    // La scheda può essere cambiata mentre la sessione era aperta: le entry
    // vengono riallineate alla sequenza attuale del giorno, senza perdere
    // quelle che non hanno più un esercizio corrispondente.
    if (day != null && _reconcileEntries(log, day)) {
      _save(log);
    }

    emit(
      state.copyWith(
        status: WorkoutSessionStatus.ready,
        log: log,
        day: day,
        lastPerformances: _loadLastPerformances(log),
        currentIndex: _firstUnfinishedIndex(log),
        revision: state.revision + 1,
      ),
    );

    await _prepareDevices();
  }

  Future<void> _prepareDevices() async {
    await _screenWake.enable();
    await _feedback.prepare();
    await _notifier.prepare();
  }

  /// Allinea le entry del log alla sequenza di esercizi del giorno.
  /// Ritorna `true` se qualcosa è cambiato (e quindi va persistito).
  bool _reconcileEntries(WorkoutLog log, WorkoutDay day) {
    final planned = flattenExercises(day);
    final pool = log.entries.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final aligned = <LogEntry>[];
    var changed = false;

    for (final exercise in planned) {
      final index = pool.indexWhere(
        (entry) => entry.exerciseNameSnapshot == exercise.name,
      );
      if (index >= 0) {
        aligned.add(pool.removeAt(index));
      } else {
        final created = LogEntry(exerciseNameSnapshot: exercise.name);
        log.entries.add(created);
        aligned.add(created);
        changed = true;
      }
    }

    for (final orphan in pool) {
      if (orphan.sets.isEmpty) {
        // Esercizio tolto dalla scheda e mai svolto: niente da conservare.
        log.entries.remove(orphan);
        changed = true;
      } else {
        aligned.add(orphan);
      }
    }

    for (var i = 0; i < aligned.length; i++) {
      if (aligned[i].sortOrder != i) {
        aligned[i].sortOrder = i;
        changed = true;
      }
    }
    return changed;
  }

  Map<String, LastPerformance> _loadLastPerformances(WorkoutLog log) {
    final result = <String, LastPerformance>{};
    for (final entry in log.entries) {
      final name = entry.exerciseNameSnapshot;
      if (result.containsKey(name)) continue;
      final last = _logRepository.lastPerformance(name, excludeLogId: log.id);
      if (last != null) result[name] = last;
    }
    return result;
  }

  /// Alla ripresa si riparte dal primo esercizio senza serie registrate.
  int _firstUnfinishedIndex(WorkoutLog log) {
    final entries = log.entries.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].sets.isEmpty) return i;
    }
    return 0;
  }

  // --- registrazione delle serie ---

  void _onSetCompleted(SetCompleted event, Emitter<WorkoutSessionState> emit) {
    final item = _itemAt(event.entryIndex);
    if (item == null || item.isSetDone(event.setNumber)) return;

    final prefill = _prefillFor(item, event.setNumber);
    item.entry.sets.add(
      LogSet(
        setNumber: event.setNumber,
        reps: prefill.reps,
        weightKg: prefill.weightKg,
        completedAt: _now(),
      ),
    );

    _persist(emit, currentIndex: event.entryIndex);

    // L'avvio automatico non interrompe mai un timer già in corso: il
    // conflitto va risolto dall'utente, non silenziosamente (§9).
    if (!state.autoStartRest || _timerEngine.isRunning) return;
    final spec = restTimerSpec(item, label: item.name);
    if (spec != null) add(TimerRequested(spec));
  }

  void _onSetUnchecked(SetUnchecked event, Emitter<WorkoutSessionState> emit) {
    final item = _itemAt(event.entryIndex);
    final set = item?.setNumbered(event.setNumber);
    if (item == null || set == null) return;

    item.entry.sets.remove(set);
    _persist(emit);
  }

  void _onSetLogged(SetLogged event, Emitter<WorkoutSessionState> emit) {
    final item = _itemAt(event.entryIndex);
    if (item == null) return;

    final existing = item.setNumbered(event.setNumber);
    if (existing == null) {
      item.entry.sets.add(
        LogSet(
          setNumber: event.setNumber,
          reps: event.reps,
          weightKg: event.weightKg,
          notes: event.notes,
          completedAt: _now(),
        ),
      );
    } else {
      existing
        ..reps = event.reps
        ..weightKg = event.weightKg
        ..notes = event.notes;
    }

    _persist(emit, currentIndex: event.entryIndex);
  }

  void _onExerciseFocused(
    ExerciseFocused event,
    Emitter<WorkoutSessionState> emit,
  ) {
    final all = state.items;
    if (all.isEmpty) return;
    emit(state.copyWith(currentIndex: event.index.clamp(0, all.length - 1)));
  }

  ({double? weightKg, String? reps}) _prefillFor(
    SessionItem item,
    int setNumber,
  ) {
    // Minimo attrito (RF-06): si riparte dall'ultimo valore usato in questa
    // sessione, poi da quello dell'ultima volta, infine dalla prescrizione.
    final earlier = item.completedSets
        .where((s) => s.setNumber < setNumber)
        .toList();
    if (earlier.isNotEmpty) {
      final previous = earlier.last;
      return (weightKg: previous.weightKg, reps: previous.reps);
    }

    final last = state.lastPerformances[item.name];
    if (last != null && last.sets.isNotEmpty) {
      final reference = last.sets.last;
      return (weightKg: reference.weightKg, reps: reference.reps);
    }

    return (weightKg: null, reps: item.exercise?.reps);
  }

  // --- timer ---

  void _onTimerRequested(
    TimerRequested event,
    Emitter<WorkoutSessionState> emit,
  ) {
    if (_timerEngine.isRunning && !event.force) {
      emit(state.copyWith(pendingTimerRequest: event.spec));
      return;
    }
    emit(state.copyWith(pendingTimerRequest: null));
    _timerEngine.start(event.spec);
  }

  void _onTimerRequestDismissed(
    TimerRequestDismissed event,
    Emitter<WorkoutSessionState> emit,
  ) {
    emit(state.copyWith(pendingTimerRequest: null));
  }

  void _onTimerTicked(TimerTicked event, Emitter<WorkoutSessionState> emit) {
    emit(state.copyWith(timer: event.timer));
  }

  Future<void> _onTimerSignalled(
    TimerSignalled event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    await _feedback.emit(event.signal);
  }

  void _onTimerStopped(TimerStopped event, Emitter<WorkoutSessionState> emit) {
    _timerEngine.stop();
    emit(state.copyWith(timer: null));
  }

  void _onAutoStartRestToggled(
    AutoStartRestToggled event,
    Emitter<WorkoutSessionState> emit,
  ) {
    emit(state.copyWith(autoStartRest: event.enabled));
  }

  // --- lifecycle ---

  Future<void> _onAppLifecycleChanged(
    AppLifecycleChanged event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    if (event.toBackground) {
      final times = _timerEngine.upcomingSignalTimes(max: kMaxScheduledSignals);
      await _notifier.scheduleSignals(
        times,
        title: event.notificationTitle,
        body: event.notificationBody,
      );
      return;
    }

    await _notifier.cancelPending();
    // Al rientro i tick sono stati sospesi dal sistema ma il tempo è passato:
    // lo stato si ricalcola dall'orologio (§7).
    _timerEngine.reconcile();
  }

  // --- chiusura ---

  Future<void> _onSessionFinished(
    SessionFinished event,
    Emitter<WorkoutSessionState> emit,
  ) async {
    final log = state.log;
    if (log != null) {
      final notes = event.notes?.trim();
      log
        ..status = event.status
        ..finishedAt = _now()
        ..notes = (notes == null || notes.isEmpty) ? null : notes;
      _save(log);
    }

    _timerEngine.stop();
    emit(
      state.copyWith(
        status: WorkoutSessionStatus.finished,
        timer: null,
        revision: state.revision + 1,
      ),
    );

    await _notifier.cancelPending();
    await _screenWake.disable();
  }

  // --- helper ---

  SessionItem? _itemAt(int index) {
    final all = state.items;
    if (index < 0 || index >= all.length) return null;
    return all[index];
  }

  /// Persiste e notifica la mutazione. L'autosave è sincrono di proposito:
  /// alla riapertura dopo un crash il log deve essere già a posto.
  void _persist(Emitter<WorkoutSessionState> emit, {int? currentIndex}) {
    final log = state.log;
    if (log == null) return;
    String? error;
    try {
      _logRepository.saveLog(log);
    } catch (e) {
      error = e.toString();
    }
    emit(
      state.copyWith(
        revision: state.revision + 1,
        currentIndex: currentIndex ?? state.currentIndex,
        errorMessage: error,
      ),
    );
  }

  void _save(WorkoutLog log) {
    try {
      _logRepository.saveLog(log);
    } catch (_) {
      // L'errore viene mostrato dal successivo _persist; qui non c'è un emit
      // disponibile e la sessione non deve interrompersi.
    }
  }

  @override
  Future<void> close() async {
    // Il timer si ferma per primo, in modo sincrono: uscendo dalla sessione
    // non deve restare un `Timer.periodic` vivo in attesa delle `await`.
    _timerEngine.stop();
    await _tickSub.cancel();
    await _signalSub.cancel();
    await _notifier.cancelPending();
    await _screenWake.disable();
    return super.close();
  }
}
