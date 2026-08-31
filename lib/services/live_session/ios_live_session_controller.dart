import 'dart:async';

import 'package:flutter/services.dart';

import '../notifications/notification_host.dart';
import 'live_session_controller.dart';

/// Live Activity di ActivityKit (iOS 16.2+).
///
/// Tutto il lavoro sta nel nativo (`ios/TaccaLiveActivity`, `ios/LiveSessionShared`):
/// qui c'è solo il ponte sul `MethodChannel`. Il pulsante della Live Activity
/// non chiama questo canale: il suo App Intent può girare con l'app sospesa e
/// nessun motore Dart vivo, quindi scrive l'azione nell'App Group e l'app la
/// raccoglie con [drainPendingActions] al rientro in primo piano. [actions]
/// copre il caso in cui l'app fosse ancora viva e il nativo abbia potuto
/// consegnarla subito.
class IosLiveSessionController implements LiveSessionController {
  IosLiveSessionController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const String channelName = 'tacca/live_session';

  final MethodChannel _channel;
  final _actions = StreamController<LiveSessionAction>.broadcast();

  @override
  Stream<LiveSessionAction> get actions => _actions.stream;

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'onAction') {
      final action = LiveSessionAction.tryParse(call.arguments);
      if (action != null && !_actions.isClosed) _actions.add(action);
    }
    return null;
  }

  @override
  Future<bool> isSupported() async =>
      await _invoke<bool>('isSupported') ?? false;

  @override
  Future<void> start(LiveSessionSnapshot snapshot) =>
      _invoke<void>('start', snapshot.toMap());

  @override
  Future<void> update(LiveSessionSnapshot snapshot) =>
      _invoke<void>('update', snapshot.toMap());

  @override
  Future<void> stop() => _invoke<void>('stop');

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async {
    final raw = await _invoke<List<Object?>>('drainPendingActions');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (LiveSessionAction.tryParse(entry) case final action?) action,
    ];
  }

  @override
  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _actions.close();
  }

  /// Un canale assente (build senza l'estensione) non è un errore: la sessione
  /// funziona lo stesso, semplicemente senza banner.
  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } catch (error, stackTrace) {
      reportNotificationError('Live Activity: $method', error, stackTrace);
      return null;
    }
  }
}
