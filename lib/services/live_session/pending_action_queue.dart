import 'dart:convert';
import 'dart:io';

import 'live_session_controller.dart';

/// Coda durabile delle azioni eseguite dalla superficie di sistema.
///
/// Serve perché su Android il tap può arrivare a processo ucciso, in un
/// isolate di background che non ha né Bloc né database: lì l'azione si scrive
/// e basta, e l'app la ritrova alla riapertura.
///
/// **È volutamente sincrona.** L'isolate di background viene spento appena la
/// callback ritorna: una `Future` di scrittura potrebbe non completare mai e
/// la conferma dell'utente andrebbe persa. Il file è di poche centinaia di
/// byte, il costo del blocco è irrilevante.
///
/// È un file JSON e non un box ObjectBox di proposito: `Box`/`Store` vivono
/// solo dentro `data/` e non si aprono da un isolate secondario.
class PendingActionQueue {
  const PendingActionQueue(this.file);

  final File file;

  /// Aggiunge un'azione in coda. Gli errori di I/O non vengono propagati: una
  /// conferma persa è meno grave di un crash nell'isolate di background.
  void append(LiveSessionAction action) {
    try {
      final current = _read()..add(action.toMap());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(current), flush: true);
    } catch (_) {
      // Coda non scrivibile: l'utente ritroverà la serie non spuntata.
    }
  }

  /// Restituisce le azioni accumulate e svuota la coda.
  List<LiveSessionAction> drain() {
    final raw = _read();
    if (raw.isEmpty) return const [];
    clear();
    return [
      for (final entry in raw)
        if (LiveSessionAction.tryParse(entry) case final action?) action,
    ];
  }

  void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Al prossimo drain le azioni rimaste verranno comunque scartate dal
      // filtro sull'id della sessione.
    }
  }

  List<Object?> _read() {
    try {
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is List ? decoded.toList() : [];
    } catch (_) {
      return [];
    }
  }
}
