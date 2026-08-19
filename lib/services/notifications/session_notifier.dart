import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Tetto di notifiche programmate per volta (§7): si copre l'immediato
/// futuro senza inondare il sistema di alarm.
const int kMaxScheduledSignals = 10;

/// Notifiche locali che sostituiscono il beep quando l'app non è in primo
/// piano (§7).
///
/// Astratta per non trascinare un platform channel dentro Bloc e test.
abstract interface class SessionNotifier {
  /// Inizializza il plugin e chiede i permessi. Va chiamata una sola volta.
  Future<void> prepare();

  /// Programma una notifica per ciascun istante di [times] (già filtrati e
  /// limitati da `TimerEngine.upcomingSignalTimes`).
  Future<void> scheduleSignals(
    List<DateTime> times, {
    required String title,
    required String body,
  });

  /// Annulla tutte le notifiche programmate da questo servizio.
  Future<void> cancelPending();
}

/// Implementazione su `flutter_local_notifications`.
///
/// ⚠️ Limite noto (spike S-01, §11): il suono è quello della notifica di
/// sistema, non un audio custom continuo. La puntualità dipende dal sistema
/// operativo — su iOS in particolare — e va verificata su device reale. La
/// modalità primaria resta lo schermo acceso con wake lock.
class LocalSessionNotifier implements SessionNotifier {
  LocalSessionNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Intervallo di id riservato ai segnali del timer: `cancelPending` li
  /// annulla uno per uno senza toccare eventuali notifiche di altre feature.
  static const int _firstId = 9100;

  static const _channelId = 'workout_timer';
  static const _channelName = 'Timer allenamento';
  static const _channelDescription =
      'Segnali dei timer durante la sessione di allenamento';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _scheduledCount = 0;

  @override
  Future<void> prepare() async {
    if (_ready) return;
    try {
      tz_data.initializeTimeZones();
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // I permessi si chiedono all'avvio della prima sessione, non
            // all'apertura dell'app: il consenso arriva quando il motivo è
            // evidente all'utente.
            requestAlertPermission: true,
            requestSoundPermission: true,
            requestBadgePermission: false,
          ),
        ),
      );

      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();

      _ready = true;
    } catch (error, stackTrace) {
      _report('inizializzazione notifiche', error, stackTrace);
    }
  }

  @override
  Future<void> scheduleSignals(
    List<DateTime> times, {
    required String title,
    required String body,
  }) async {
    await cancelPending();
    if (!_ready || times.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    final capped = times.length > kMaxScheduledSignals
        ? times.sublist(0, kMaxScheduledSignals)
        : times;
    for (var i = 0; i < capped.length; i++) {
      try {
        await _plugin.zonedSchedule(
          id: _firstId + i,
          scheduledDate: tz.TZDateTime.from(capped[i], tz.local),
          title: title,
          body: body,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        _scheduledCount = i + 1;
      } catch (error, stackTrace) {
        _report('programmazione notifica', error, stackTrace);
        break;
      }
    }
  }

  @override
  Future<void> cancelPending() async {
    for (var i = 0; i < _scheduledCount; i++) {
      try {
        await _plugin.cancel(id: _firstId + i);
      } catch (error, stackTrace) {
        _report('annullamento notifica', error, stackTrace);
      }
    }
    _scheduledCount = 0;
  }

  void _report(String what, Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'session_notifier',
        context: ErrorDescription(what),
      ),
    );
  }
}
