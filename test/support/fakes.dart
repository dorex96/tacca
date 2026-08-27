import 'dart:async';
import 'dart:typed_data';

import 'package:tacca/data/entities/log_entry.dart';
import 'package:tacca/data/entities/log_set.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/settings_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/services/clipboard/clipboard_service.dart';
import 'package:tacca/services/feedback/session_feedback.dart';
import 'package:tacca/services/images/image_input.dart';
import 'package:tacca/services/images/ocr_service.dart';
import 'package:tacca/services/images/plan_image_store.dart';
import 'package:tacca/services/links/link_opener.dart';
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

/// OCR pilotato: a ogni immagine il testo che deve riconoscere, e la
/// possibilità di farla fallire.
class FakeOcrService implements OcrService {
  final texts = <Uint8List, String>{};
  final failing = <Uint8List>{};
  final calls = <Uint8List>[];

  @override
  Future<String> recognizeText(Uint8List bytes) async {
    calls.add(bytes);
    if (failing.contains(bytes)) throw Exception('OCR fallito');
    return texts[bytes] ?? '';
  }
}

/// Fotocamera e galleria senza plugin: restituiscono ciò che il test ha
/// preparato.
class FakeImageInput implements ImageInput {
  Uint8List? cameraResult;
  List<Uint8List> galleryResult = const [];

  @override
  Future<Uint8List?> takePhoto() async => cameraResult;

  @override
  Future<List<Uint8List>> pickFromGallery() async => galleryResult;
}

/// Niente disco nei test: la "compressione" è un marker in coda ai byte e il
/// salvataggio registra i path senza scrivere niente.
class FakeImageStore extends PlanImageStore {
  final saved = <Uint8List>[];

  @override
  Future<Uint8List> compressForUpload(Uint8List bytes) async =>
      Uint8List.fromList([...bytes, 99]);

  @override
  Future<String> saveOriginal(Uint8List bytes) async {
    saved.add(bytes);
    return 'plan_images/img_${saved.length}.jpg';
  }
}

/// Appunti in memoria: registra tutto ciò che ci viene scritto, così i test
/// possono guardare *cosa* è stato copiato e non solo che si è copiato.
class RecordingClipboardService implements ClipboardService {
  final written = <String>[];
  String? content;

  String? get last => written.isEmpty ? null : written.last;

  @override
  Future<void> write(String text) async {
    written.add(text);
    content = text;
  }

  @override
  Future<String?> read() async => content;
}

/// Serie di comodo per costruire uno storico nei test.
LogSet buildLogSet(int number, {double? weightKg, String? reps}) => LogSet(
  setNumber: number,
  weightKg: weightKg,
  reps: reps,
  completedAt: DateTime(2026, 8, 1),
);

/// [SettingsRepository] in memoria: nessun secure storage nei test.
///
/// Key e modello sono per provider come in produzione; [apiKey] e [modelId]
/// restano scorciatoie per il provider di default dei test ([providerId]).
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    String? apiKey,
    String? modelId,
    this.providerId,
    this.acceptedLegalNoticeVersion,
    this.defaultProviderId = 'openrouter',
  }) {
    if (apiKey != null) apiKeys[defaultProviderId] = apiKey;
    if (modelId != null) modelIds[defaultProviderId] = modelId;
  }

  /// Versione dell'informativa legale già accettata; null = primo avvio.
  int? acceptedLegalNoticeVersion;

  /// Provider su cui puntano [apiKey] e [modelId].
  final String defaultProviderId;

  String? providerId;
  final Map<String, String> apiKeys = {};
  final Map<String, String> modelIds = {};

  String? get apiKey => apiKeys[defaultProviderId];

  set apiKey(String? value) => _put(apiKeys, defaultProviderId, value);

  String? get modelId => modelIds[defaultProviderId];

  set modelId(String? value) => _put(modelIds, defaultProviderId, value);

  @override
  Future<String?> getAiProviderId() async => providerId;

  @override
  Future<void> setAiProviderId(String? id) async => providerId = id;

  @override
  Future<String?> getApiKey(String providerId) async => apiKeys[providerId];

  @override
  Future<void> setApiKey(String providerId, String? key) async =>
      _put(apiKeys, providerId, key);

  @override
  Future<String?> getModelId(String providerId) async => modelIds[providerId];

  @override
  Future<void> setModelId(String providerId, String? modelId) async =>
      _put(modelIds, providerId, modelId);

  @override
  Future<int?> getAcceptedLegalNoticeVersion() async =>
      acceptedLegalNoticeVersion;

  @override
  Future<void> setAcceptedLegalNoticeVersion(int version) async =>
      acceptedLegalNoticeVersion = version;

  void _put(Map<String, String> into, String key, String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      into.remove(key);
    } else {
      into[key] = trimmed;
    }
  }
}

/// [LinkOpener] che non apre niente: registra gli indirizzi richiesti e
/// decide se l'apertura riesce, così si può provare anche il piano B (link
/// copiato negli appunti).
class FakeLinkOpener implements LinkOpener {
  FakeLinkOpener({this.succeeds = true});

  /// False = nessun browser disponibile.
  final bool succeeds;

  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return succeeds;
  }
}
