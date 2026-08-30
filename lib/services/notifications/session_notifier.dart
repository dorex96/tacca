import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_host.dart';

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
  LocalSessionNotifier({NotificationHost? host})
    : _host = host ?? NotificationHost();

  /// Intervallo di id riservato ai segnali del timer: `cancelPending` li
  /// annulla uno per uno senza toccare eventuali notifiche di altre feature.
  static const int _firstId = 9100;

  static const _channelId = 'workout_timer';
  static const _channelName = 'Timer allenamento';
  static const _channelDescription =
      'Segnali dei timer durante la sessione di allenamento';

  final NotificationHost _host;
  bool _ready = false;
  int _scheduledCount = 0;

  @override
  Future<void> prepare() async {
    _ready = await _host.ensureInitialized();
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
        await _host.plugin.zonedSchedule(
          id: _firstId + i,
          scheduledDate: tz.TZDateTime.from(capped[i], tz.local),
          title: title,
          body: body,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        _scheduledCount = i + 1;
      } catch (error, stackTrace) {
        reportNotificationError('programmazione notifica', error, stackTrace);
        break;
      }
    }
  }

  @override
  Future<void> cancelPending() async {
    for (var i = 0; i < _scheduledCount; i++) {
      try {
        await _host.plugin.cancel(id: _firstId + i);
      } catch (error, stackTrace) {
        reportNotificationError('annullamento notifica', error, stackTrace);
      }
    }
    _scheduledCount = 0;
  }
}
