import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../notifications/notification_host.dart';
import 'live_session_controller.dart';
import 'pending_action_queue.dart';

/// Id dell'azione "serie fatta" sulla notifica di sessione. Vive fuori dalla
/// classe perché lo legge anche l'isolate di background, che non ha istanze.
const String kCompleteSetActionId = 'live_session.complete_set';

/// Nome del file della coda dentro la directory di supporto dell'app.
const String kPendingActionsFileName = 'live_session_actions.json';

/// Notifica persistente della sessione su Android.
///
/// È l'equivalente della Live Activity di iOS con i mezzi del sistema: una
/// notifica `ongoing`, con il countdown disegnato dal sistema
/// (`usesChronometer` + `chronometerCountDown`, quindi esatto anche a processo
/// fermo) e un pulsante che conferma la serie senza aprire l'app.
///
/// Non c'è un foreground service: la notifica sopravvive comunque alla morte
/// del processo, il countdown lo disegna il sistema e il beep di fine recupero
/// è già un alarm esatto programmato da `SessionNotifier`. Il prezzo è che, se
/// il processo viene ucciso, il testo della notifica resta fermo fino alla
/// riapertura dell'app — la conferma però non si perde: finisce nella coda.
class AndroidLiveSessionController implements LiveSessionController {
  AndroidLiveSessionController({
    required NotificationHost host,
    Future<Directory> Function()? supportDirectory,
    DateTime Function()? now,
  }) : _host = host,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  /// Id riservato: sta fuori dall'intervallo dei segnali del timer (9100+).
  static const int _notificationId = 9200;

  static const _channelId = 'workout_live';
  static const _channelName = 'Sessione in corso';
  static const _channelDescription =
      'Esercizio corrente e recupero, con la conferma della serie';

  final NotificationHost _host;
  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _now;

  final _actions = StreamController<LiveSessionAction>.broadcast();

  PendingActionQueue? _queue;
  StreamSubscription<NotificationResponse>? _responses;
  LiveSessionSnapshot? _shown;

  @override
  Stream<LiveSessionAction> get actions => _actions.stream;

  @override
  Future<bool> isSupported() => _host.ensureInitialized();

  @override
  Future<void> start(LiveSessionSnapshot snapshot) async {
    if (!await _host.ensureInitialized()) return;
    _queue ??= PendingActionQueue(
      File('${(await _supportDirectory()).path}/$kPendingActionsFileName'),
    );
    _responses ??= _host.responses.listen(_onResponse);
    await _publish(snapshot);
  }

  @override
  Future<void> update(LiveSessionSnapshot snapshot) async {
    // Fuori da una sessione avviata non si pubblica nulla, e uno snapshot
    // identico non merita un ridisegno.
    if (_queue == null || snapshot == _shown) return;
    await _publish(snapshot);
  }

  @override
  Future<void> stop() async {
    _shown = null;
    _queue?.clear();
    _queue = null;
    try {
      await _host.plugin.cancel(id: _notificationId);
    } catch (error, stackTrace) {
      reportNotificationError('notifica di sessione', error, stackTrace);
    }
  }

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async =>
      _queue?.drain() ?? const [];

  @override
  Future<void> dispose() async {
    await _responses?.cancel();
    await _actions.close();
  }

  Future<void> _publish(LiveSessionSnapshot snapshot) async {
    final countdown = snapshot.countdownEndsAt;
    final label = snapshot.countdownLabel;
    // A serie esaurite non c'è nessun numero da mostrare: resta il titolo.
    final sets = switch (snapshot) {
      _ when snapshot.setNumber <= 0 => snapshot.labels.title,
      _ when snapshot.totalSets > 0 =>
        '${snapshot.labels.setsLabel} ${snapshot.setNumber}/${snapshot.totalSets}',
      _ => '${snapshot.labels.setsLabel} ${snapshot.setNumber}',
    };
    final details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      // Bassa importanza: è uno stato, non un allarme. Il beep di fine
      // recupero resta quello del canale dei timer.
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.workout,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      subText: snapshot.labels.title,
      showWhen: countdown != null,
      when: countdown?.millisecondsSinceEpoch,
      usesChronometer: countdown != null,
      chronometerCountDown: countdown != null,
      actions: [
        if (snapshot.canCompleteSet)
          AndroidNotificationAction(
            kCompleteSetActionId,
            snapshot.labels.completeAction,
            // Il pulsante non deve aprire l'app né far sparire la notifica:
            // è tutto il senso della cosa.
            showsUserInterface: false,
            cancelNotification: false,
          ),
      ],
    );

    try {
      await _host.plugin.show(
        id: _notificationId,
        title: snapshot.exerciseName,
        body: label != null ? '$label · $sets' : sets,
        notificationDetails: NotificationDetails(android: details),
        payload: LiveActionPayload.forSnapshot(
          snapshot,
          queuePath: _queue?.file.path ?? '',
        ).encode(),
      );
      _shown = snapshot;
    } catch (error, stackTrace) {
      reportNotificationError('notifica di sessione', error, stackTrace);
    }
  }

  void _onResponse(NotificationResponse response) {
    if (response.actionId != kCompleteSetActionId) return;
    final payload = LiveActionPayload.tryParse(response.payload);
    if (payload == null || _actions.isClosed) return;
    // Consegna diretta: quando la risposta arriva qui, l'isolate di background
    // non è stato usato e la coda è rimasta vuota.
    _actions.add(payload.toAction(_now()));
  }
}

/// Dati che viaggiano nel payload della notifica.
///
/// Contiene anche il percorso della coda: così l'isolate di background non ha
/// bisogno di `path_provider` — e quindi di registrare i plugin — per sapere
/// dove scrivere.
class LiveActionPayload {
  const LiveActionPayload({
    required this.queuePath,
    required this.logId,
    required this.entryIndex,
    required this.setNumber,
  });

  factory LiveActionPayload.forSnapshot(
    LiveSessionSnapshot snapshot, {
    required String queuePath,
  }) => LiveActionPayload(
    queuePath: queuePath,
    logId: snapshot.logId,
    entryIndex: snapshot.entryIndex,
    setNumber: snapshot.setNumber,
  );

  final String queuePath;
  final int logId;
  final int entryIndex;
  final int setNumber;

  String encode() => jsonEncode({
    'queuePath': queuePath,
    'logId': logId,
    'entryIndex': entryIndex,
    'setNumber': setNumber,
  });

  static LiveActionPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final queuePath = decoded['queuePath'];
      final logId = decoded['logId'];
      final entryIndex = decoded['entryIndex'];
      final setNumber = decoded['setNumber'];
      if (queuePath is! String ||
          logId is! int ||
          entryIndex is! int ||
          setNumber is! int) {
        return null;
      }
      return LiveActionPayload(
        queuePath: queuePath,
        logId: logId,
        entryIndex: entryIndex,
        setNumber: setNumber,
      );
    } catch (_) {
      return null;
    }
  }

  LiveSessionAction toAction(DateTime at) => LiveSessionAction(
    // Deterministico: la stessa conferma consegnata due volte (stream e coda)
    // viene riconosciuta e applicata una volta sola.
    id: 'set-$logId-$entryIndex-$setNumber-${at.millisecondsSinceEpoch}',
    kind: LiveSessionActionKind.setCompleted,
    logId: logId,
    entryIndex: entryIndex,
    setNumber: setNumber,
    at: at,
  );
}

/// Conferma arrivata a processo ucciso: gira in un isolate senza Bloc, senza
/// database e senza plugin registrati.
///
/// Fa una cosa sola, in modo sincrono: mette l'azione in coda. Non ridisegna
/// la notifica (servirebbe reinizializzare il plugin in un isolate che sta per
/// spegnersi): il banner resta fermo fino alla riapertura dell'app, ma la
/// serie confermata non si perde.
@pragma('vm:entry-point')
void liveSessionActionBackground(NotificationResponse response) {
  if (response.actionId != kCompleteSetActionId) return;
  final payload = LiveActionPayload.tryParse(response.payload);
  if (payload == null || payload.queuePath.isEmpty) return;
  PendingActionQueue(
    File(payload.queuePath),
  ).append(payload.toAction(DateTime.now()));
}
