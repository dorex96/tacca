import 'dart:async';

/// Superficie di sistema che mostra la sessione fuori dall'app e accetta la
/// conferma di una serie a telefono bloccato (RF-06).
///
/// Le due piattaforme la realizzano in modo diverso — Live Activity di
/// ActivityKit su iOS, notifica persistente su Android — ma il contratto è lo
/// stesso: si pubblica uno [LiveSessionSnapshot] e si raccolgono le
/// [LiveSessionAction] che l'utente ha eseguito da lì.
///
/// **Il tap non passa dal motore Dart.** Su iOS l'App Intent gira ad app
/// sospesa, su Android il broadcast può arrivare a processo ucciso: in
/// entrambi i casi l'azione viene messa in una coda durabile e l'app la drena
/// al rientro ([drainPendingActions]). [actions] serve solo alla consegna
/// immediata quando l'app è ancora viva; l'id dell'azione permette di
/// riconoscere il doppione fra le due strade.
abstract interface class LiveSessionController {
  /// Azioni consegnate mentre l'app è in esecuzione.
  Stream<LiveSessionAction> get actions;

  /// `false` dove la superficie non esiste (iOS < 16.2, Live Activity
  /// disattivate dall'utente, piattaforme desktop): la sessione funziona
  /// comunque, semplicemente senza banner.
  Future<bool> isSupported();

  /// Mostra la superficie. Su iOS va chiamata con l'app in primo piano:
  /// ActivityKit non permette di avviare un'attività dal background.
  Future<void> start(LiveSessionSnapshot snapshot);

  /// Aggiorna la superficie già avviata. Non va chiamata a ogni tick del
  /// timer: il countdown lo disegna il sistema a partire da
  /// [LiveSessionSnapshot.countdownEndsAt].
  Future<void> update(LiveSessionSnapshot snapshot);

  /// Rimuove la superficie (fine o abbandono della sessione).
  Future<void> stop();

  /// Restituisce e svuota le azioni accumulate mentre l'app non era attiva.
  Future<List<LiveSessionAction>> drainPendingActions();

  Future<void> dispose();
}

/// Stato pubblicato sulla superficie di sistema.
///
/// Contiene tutto quello che serve al nativo per disegnare il banner **e** per
/// reagire da solo al tap: [restSecondsOnComplete] gli permette di far partire
/// il countdown, i campi `next*` di spostare il banco sull'esercizio dopo —
/// entrambi senza aspettare che l'app si risvegli.
class LiveSessionSnapshot {
  const LiveSessionSnapshot({
    required this.logId,
    required this.exerciseName,
    required this.entryIndex,
    required this.setNumber,
    required this.totalSets,
    required this.canCompleteSet,
    required this.restSecondsOnComplete,
    required this.labels,
    this.countdownStartsAt,
    this.countdownEndsAt,
    this.countdownLabel,
    this.nextExerciseName,
    this.nextEntryIndex = 0,
    this.nextSetNumber = 0,
    this.nextTotalSets = 0,
    this.nextRestSecondsOnComplete = 0,
  });

  /// Sessione a cui appartiene: un'azione rimasta in coda da un allenamento
  /// precedente viene scartata invece di finire nel log sbagliato.
  final int logId;

  final String exerciseName;

  /// Posizione dell'esercizio nella sequenza del giorno (`LogEntry.sortOrder`).
  final int entryIndex;

  /// Prossima serie da confermare.
  final int setNumber;

  /// Serie previste per l'esercizio; 0 se la scheda non le specifica.
  final int totalSets;

  /// `false` quando non c'è più niente da spuntare: il nativo nasconde il
  /// pulsante invece di registrare una serie che non esiste.
  final bool canCompleteSet;

  /// Recupero da avviare alla conferma, in secondi. 0 significa nessun
  /// countdown (recupero non configurato o avvio automatico disattivato).
  final int restSecondsOnComplete;

  /// Inizio del countdown in corso: serve al nativo per disegnare la barra di
  /// avanzamento, non solo il tempo che manca.
  final DateTime? countdownStartsAt;

  /// Fine del countdown in corso, se ce n'è uno.
  final DateTime? countdownEndsAt;

  /// Etichetta del countdown in corso ("Recupero", o il nome del blocco per i
  /// timer EMOM/AMRAP/Tabata).
  final String? countdownLabel;

  /// Esercizio su cui si sposta il banner quando le serie di questo finiscono,
  /// `null` se non ne resta nessuno.
  ///
  /// È l'unico passo avanti che il nativo può fare da solo: senza, alla
  /// conferma dell'ultima serie mostrerebbe una serie che non esiste ("4/3").
  /// Il passo successivo lo ricalcola l'app al risveglio.
  final String? nextExerciseName;

  /// Coordinate della prima serie da spuntare di [nextExerciseName]: viaggiano
  /// nell'azione messa in coda, quindi devono essere quelle vere e non un
  /// "serie 1" dato per scontato.
  final int nextEntryIndex;
  final int nextSetNumber;
  final int nextTotalSets;

  /// Recupero da avviare confermando una serie di [nextExerciseName].
  final int nextRestSecondsOnComplete;

  final LiveSessionLabels labels;

  Map<String, Object?> toMap() => {
    'logId': logId,
    'exerciseName': exerciseName,
    'entryIndex': entryIndex,
    'setNumber': setNumber,
    'totalSets': totalSets,
    'canCompleteSet': canCompleteSet,
    'restSecondsOnComplete': restSecondsOnComplete,
    'countdownStartsAt': countdownStartsAt?.millisecondsSinceEpoch,
    'countdownEndsAt': countdownEndsAt?.millisecondsSinceEpoch,
    'countdownLabel': countdownLabel,
    'nextExerciseName': nextExerciseName,
    'nextEntryIndex': nextEntryIndex,
    'nextSetNumber': nextSetNumber,
    'nextTotalSets': nextTotalSets,
    'nextRestSecondsOnComplete': nextRestSecondsOnComplete,
    ...labels.toMap(),
  };

  @override
  bool operator ==(Object other) =>
      other is LiveSessionSnapshot &&
      other.logId == logId &&
      other.exerciseName == exerciseName &&
      other.entryIndex == entryIndex &&
      other.setNumber == setNumber &&
      other.totalSets == totalSets &&
      other.canCompleteSet == canCompleteSet &&
      other.restSecondsOnComplete == restSecondsOnComplete &&
      other.countdownStartsAt == countdownStartsAt &&
      other.countdownEndsAt == countdownEndsAt &&
      other.countdownLabel == countdownLabel &&
      other.nextExerciseName == nextExerciseName &&
      other.nextEntryIndex == nextEntryIndex &&
      other.nextSetNumber == nextSetNumber &&
      other.nextTotalSets == nextTotalSets &&
      other.nextRestSecondsOnComplete == nextRestSecondsOnComplete &&
      other.labels == labels;

  @override
  int get hashCode => Object.hash(
    logId,
    exerciseName,
    entryIndex,
    setNumber,
    totalSets,
    canCompleteSet,
    restSecondsOnComplete,
    countdownStartsAt,
    countdownEndsAt,
    countdownLabel,
    nextExerciseName,
    nextEntryIndex,
    nextSetNumber,
    nextTotalSets,
    nextRestSecondsOnComplete,
    labels,
  );
}

/// Stringhe localizzate che viaggiano insieme allo stato.
///
/// Il codice nativo non può leggere gli ARB e il pulsante deve restare in
/// italiano anche quando lo disegna SwiftUI: le etichette si passano, non si
/// scrivono di là.
class LiveSessionLabels {
  const LiveSessionLabels({
    required this.title,
    required this.setsLabel,
    required this.completeAction,
    required this.restLabel,
    required this.restDoneLabel,
  });

  /// Nome della superficie ("Allenamento").
  final String title;

  /// Parola per le serie: il nativo ci accosta "2/4".
  final String setsLabel;

  /// Etichetta del pulsante ("Serie fatta").
  final String completeAction;

  /// Etichetta del countdown di recupero.
  final String restLabel;

  /// Testo mostrato quando il countdown è finito.
  final String restDoneLabel;

  Map<String, Object?> toMap() => {
    'title': title,
    'setsLabel': setsLabel,
    'completeAction': completeAction,
    'restLabel': restLabel,
    'restDoneLabel': restDoneLabel,
  };

  @override
  bool operator ==(Object other) =>
      other is LiveSessionLabels &&
      other.title == title &&
      other.setsLabel == setsLabel &&
      other.completeAction == completeAction &&
      other.restLabel == restLabel &&
      other.restDoneLabel == restDoneLabel;

  @override
  int get hashCode =>
      Object.hash(title, setsLabel, completeAction, restLabel, restDoneLabel);
}

/// Cosa ha premuto l'utente sulla superficie di sistema.
enum LiveSessionActionKind {
  /// Conferma della serie corrente: registra la serie e avvia il recupero.
  setCompleted;

  static LiveSessionActionKind? parse(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// Azione eseguita fuori dall'app.
///
/// [at] è il momento del tap, non quello della consegna: il recupero deve
/// partire da quando l'utente ha finito la serie, anche se l'app riapre gli
/// occhi cinque minuti dopo.
class LiveSessionAction {
  const LiveSessionAction({
    required this.id,
    required this.kind,
    required this.logId,
    required this.entryIndex,
    required this.setNumber,
    required this.at,
  });

  /// Identificatore univoco generato dal nativo: la stessa azione può
  /// arrivare sia da [LiveSessionController.actions] sia dal drain.
  final String id;

  final LiveSessionActionKind kind;
  final int logId;
  final int entryIndex;
  final int setNumber;
  final DateTime at;

  /// Decodifica una voce della coda nativa; `null` se il payload non è
  /// utilizzabile (versione vecchia della coda, campo mancante).
  static LiveSessionAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = LiveSessionActionKind.parse(raw['kind'] as String?);
    final id = raw['id'];
    final at = raw['at'];
    if (kind == null || id is! String || at is! int) return null;
    final logId = raw['logId'];
    final entryIndex = raw['entryIndex'];
    final setNumber = raw['setNumber'];
    if (logId is! int || entryIndex is! int || setNumber is! int) return null;
    return LiveSessionAction(
      id: id,
      kind: kind,
      logId: logId,
      entryIndex: entryIndex,
      setNumber: setNumber,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'logId': logId,
    'entryIndex': entryIndex,
    'setNumber': setNumber,
    'at': at.millisecondsSinceEpoch,
  };
}

/// Nessuna superficie di sistema: piattaforme senza supporto e test.
class NoopLiveSessionController implements LiveSessionController {
  const NoopLiveSessionController();

  @override
  Stream<LiveSessionAction> get actions => const Stream.empty();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> start(LiveSessionSnapshot snapshot) async {}

  @override
  Future<void> update(LiveSessionSnapshot snapshot) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<List<LiveSessionAction>> drainPendingActions() async => const [];

  @override
  Future<void> dispose() async {}
}
