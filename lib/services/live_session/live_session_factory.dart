import 'dart:io';

import '../notifications/notification_host.dart';
import 'android_live_session_controller.dart';
import 'ios_live_session_controller.dart';
import 'live_session_controller.dart';

/// Sceglie la superficie di sistema adatta alla piattaforma.
///
/// Le due implementazioni non condividono niente se non il contratto: su iOS
/// è una Live Activity disegnata da un'estensione widget, su Android una
/// notifica persistente. Altrove (test sull'host, desktop) non c'è superficie
/// e la sessione funziona esattamente come prima.
LiveSessionController createLiveSessionController({
  required NotificationHost host,
}) {
  if (Platform.isIOS) return IosLiveSessionController();
  if (Platform.isAndroid) return AndroidLiveSessionController(host: host);
  return const NoopLiveSessionController();
}
