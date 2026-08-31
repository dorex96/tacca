import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_host.dart';

/// Tetto di notifiche programmate per volta (§7): si copre l'immediato
/// futuro senza inondare il sistema di alarm.
const int kMaxScheduledSignals = 10;

/// Primo id dell'intervallo riservato ai segnali del timer.
const int kFirstSignalId = 9100;

/// Id del beep di fine recupero programmato dall'isolate di background quando
/// l'utente conferma una serie dalla notifica ad app ferma.
///
/// Sta in coda all'intervallo dei segnali perché *è* un segnale del timer,
/// programmato al posto dell'app: così se ne occupa [SessionNotifier] come di
/// tutti gli altri, e sparisce appena l'app riprende in mano la sessione.
const int kBackgroundRestReminderId = kFirstSignalId + kMaxScheduledSignals;

/// Notifica di un segnale del timer.
///
/// Vive fuori dalla classe perché non la programma solo l'app: la usa anche
/// l'isolate di background della notifica di sessione, che non ha né host né
/// servizi.
const NotificationDetails kTimerSignalDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'workout_timer',
    'Timer allenamento',
    channelDescription: 'Segnali dei timer durante la sessione di allenamento',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    playSound: true,
    enableVibration: true,
  ),
  iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
);

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

  final NotificationHost _host;
  bool _ready = false;

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

    final capped = times.length > kMaxScheduledSignals
        ? times.sublist(0, kMaxScheduledSignals)
        : times;
    for (var i = 0; i < capped.length; i++) {
      try {
        await _host.plugin.zonedSchedule(
          id: kFirstSignalId + i,
          scheduledDate: tz.TZDateTime.from(capped[i], tz.local),
          title: title,
          body: body,
          notificationDetails: kTimerSignalDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (error, stackTrace) {
        reportNotificationError('programmazione notifica', error, stackTrace);
        break;
      }
    }
  }

  /// Annulla **tutto** l'intervallo riservato, non solo quello che ha
  /// programmato questa istanza: dopo un riavvio del processo un contatore
  /// ripartirebbe da zero mentre le notifiche di prima sono ancora lì, e il
  /// beep di fine recupero può averlo programmato l'isolate di background.
  @override
  Future<void> cancelPending() async {
    // Senza plugin non c'è niente da annullare, e undici chiamate destinate a
    // fallire riempirebbero il log a ogni cambio di stato.
    if (!_ready) return;
    for (var id = kFirstSignalId; id <= kBackgroundRestReminderId; id++) {
      try {
        await _host.plugin.cancel(id: id);
      } catch (error, stackTrace) {
        reportNotificationError('annullamento notifica', error, stackTrace);
      }
    }
  }
}
