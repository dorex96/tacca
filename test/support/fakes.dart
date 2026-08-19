import 'dart:async';

import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/services/feedback/session_feedback.dart';
import 'package:tacca/services/notifications/session_notifier.dart';
import 'package:tacca/services/timer/timer_engine.dart';
import 'package:tacca/services/wakelock/screen_wake.dart';

/// Doppi di test condivisi: tengono i test lontani da ObjectBox e dai plugin
/// di piattaforma, che nei widget test non sono disponibili.

/// [PlanRepository] in memoria: le schede vengono servite così come sono
/// state registrate con [add].
class FakePlanRepository implements PlanRepository {
  final Map<int, WorkoutPlan> plans = {};

  void add(WorkoutPlan plan) => plans[plan.id] = plan;

  @override
  Stream<List<WorkoutPlan>> watchActive() =>
      Stream.value(plans.values.where((p) => !p.isArchived).toList());

  @override
  Stream<List<WorkoutPlan>> watchArchived() =>
      Stream.value(plans.values.where((p) => p.isArchived).toList());

  @override
  WorkoutPlan? getById(int id) => plans[id];

  @override
  WorkoutPlan? getActivePlan() {
    for (final plan in plans.values) {
      if (plan.isActive) return plan;
    }
    return null;
  }

  @override
  int savePlan(WorkoutPlan plan) {
    plans[plan.id] = plan;
    return plan.id;
  }

  @override
  void setActivePlan(int planId) => throw UnimplementedError();

  @override
  void clearActivePlan() => throw UnimplementedError();

  @override
  void setArchived(int planId, {required bool archived}) =>
      throw UnimplementedError();

  @override
  int duplicatePlan(int planId) => throw UnimplementedError();

  @override
  void deletePlan(int planId) => plans.remove(planId);
}

/// [WorkoutLogRepository] in memoria. Conserva i riferimenti agli stessi
/// oggetti passati dal Bloc: quello che conta nei test è **quante volte** e
/// **con quale contenuto** viene chiamato [saveLog] (autosave, RF-06).
class FakeWorkoutLogRepository implements WorkoutLogRepository {
  final Map<int, WorkoutLog> logs = {};
  final Map<String, LastPerformance> lastPerformances = {};

  /// Numero di autosave richiesti: un handler che muta e non salva si vede.
  int saveCount = 0;

  int _nextId = 1;
  final _controller = StreamController<List<WorkoutLog>>.broadcast();

  @override
  WorkoutLog startSession({
    required WorkoutPlan plan,
    required WorkoutDay day,
    DateTime? startedAt,
  }) {
    final log = WorkoutLog.start(
      startedAt: startedAt ?? DateTime(2026, 8, 15, 18),
      planNameSnapshot: plan.name,
      dayLabelSnapshot: day.label,
    );
    log.plan.target = plan;
    log.day.target = day;
    final exercises = flattenExercises(day);
    for (var i = 0; i < exercises.length; i++) {
      log.entries.add(
        LogEntry(exerciseNameSnapshot: exercises[i].name, sortOrder: i),
      );
    }
    saveLog(log);
    return log;
  }

  @override
  WorkoutLog? findInProgress() {
    for (final log in logs.values) {
      if (log.status == WorkoutStatus.inProgress) return log;
    }
    return null;
  }

  @override
  WorkoutLog? getById(int id) => logs[id];

  @override
  Stream<List<WorkoutLog>> watchFinished() async* {
    yield _finished();
    yield* _controller.stream;
  }

  List<WorkoutLog> _finished() =>
      logs.values
          .where((log) => log.status != WorkoutStatus.inProgress)
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  @override
  int saveLog(WorkoutLog log) {
    if (log.id == 0) log.id = _nextId++;
    logs[log.id] = log;
    saveCount++;
    if (!_controller.isClosed) _controller.add(_finished());
    return log.id;
  }

  @override
  void deleteLog(int logId) {
    logs.remove(logId);
    if (!_controller.isClosed) _controller.add(_finished());
  }

  @override
  LastPerformance? lastPerformance(String exerciseName, {int? excludeLogId}) =>
      lastPerformances[exerciseName];

  Future<void> dispose() => _controller.close();
}

/// Registra i segnali resi percepibili, senza toccare audio o vibrazione.
class RecordingSessionFeedback implements SessionFeedback {
  final List<TimerSignal> signals = [];
  int prepareCount = 0;

  @override
  Future<void> prepare() async => prepareCount++;

  @override
  Future<void> emit(TimerSignal signal) async => signals.add(signal);

  @override
  Future<void> dispose() async {}
}

/// Registra le notifiche programmate invece di parlare con il sistema.
class RecordingSessionNotifier implements SessionNotifier {
  final List<List<DateTime>> scheduled = [];
  int cancelCount = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> scheduleSignals(
    List<DateTime> times, {
    required String title,
    required String body,
  }) async {
    scheduled.add(times);
  }

  @override
  Future<void> cancelPending() async => cancelCount++;
}

/// Traccia le richieste di wake lock.
class RecordingScreenWake implements ScreenWake {
  bool enabled = false;

  @override
  Future<void> enable() async => enabled = true;

  @override
  Future<void> disable() async => enabled = false;
}

/// Serie di comodo per costruire uno storico nei test.
LogSet buildLogSet(int number, {double? weightKg, String? reps}) => LogSet(
  setNumber: number,
  weightKg: weightKg,
  reps: reps,
  completedAt: DateTime(2026, 8, 1),
);

/// [SettingsRepository] in memoria: nessun secure storage nei test.
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.apiKey, this.modelId});

  String? apiKey;
  String? modelId;

  @override
  Future<String?> getOpenRouterApiKey() async => apiKey;

  @override
  Future<void> setOpenRouterApiKey(String? key) async {
    apiKey = (key == null || key.trim().isEmpty) ? null : key.trim();
  }

  @override
  Future<String?> getOpenRouterModelId() async => modelId;

  @override
  Future<void> setOpenRouterModelId(String? id) async => modelId = id;
}
