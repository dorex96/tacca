import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/live_session/android_live_session_controller.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';

/// Lo snapshot e le azioni attraversano un confine di piattaforma: quello che
/// si rompe qui si rompe in Swift, dove nessun test arriva.
void main() {
  const labels = LiveSessionLabels(
    title: 'Allenamento',
    setsLabel: 'Serie',
    completeAction: 'Serie fatta',
    restLabel: 'Recupero',
    restDoneLabel: 'Recupero finito',
  );

  final snapshot = LiveSessionSnapshot(
    logId: 3,
    exerciseName: 'Panca piana',
    entryIndex: 1,
    setNumber: 2,
    totalSets: 4,
    canCompleteSet: true,
    restSecondsOnComplete: 90,
    countdownStartsAt: DateTime(2026, 8, 15, 18),
    countdownEndsAt: DateTime(2026, 8, 15, 18, 1, 30),
    countdownLabel: 'Recupero',
    labels: labels,
  );

  group('LiveSessionSnapshot', () {
    test('viaggia verso il nativo con date in millisecondi', () {
      final map = snapshot.toMap();

      expect(map['logId'], 3);
      expect(map['exerciseName'], 'Panca piana');
      expect(map['setNumber'], 2);
      expect(map['totalSets'], 4);
      expect(map['canCompleteSet'], isTrue);
      expect(map['restSecondsOnComplete'], 90);
      expect(
        map['countdownEndsAt'],
        DateTime(2026, 8, 15, 18, 1, 30).millisecondsSinceEpoch,
      );
      // Le etichette sono in linea con lo stato: il nativo legge una mappa
      // sola, non due.
      expect(map['completeAction'], 'Serie fatta');
    });

    test('senza countdown i campi temporali restano nulli', () {
      final map = LiveSessionSnapshot(
        logId: 1,
        exerciseName: 'Rematore',
        entryIndex: 0,
        setNumber: 1,
        totalSets: 3,
        canCompleteSet: true,
        restSecondsOnComplete: 0,
        labels: labels,
      ).toMap();

      expect(map['countdownStartsAt'], isNull);
      expect(map['countdownEndsAt'], isNull);
      expect(map['countdownLabel'], isNull);
    });
  });

  group('LiveSessionAction.tryParse', () {
    test('accetta quello che manda il nativo', () {
      final action = LiveSessionAction.tryParse({
        'id': 'abc',
        'kind': 'setCompleted',
        'logId': 3,
        'entryIndex': 1,
        'setNumber': 2,
        'at': DateTime(2026, 8, 15, 18).millisecondsSinceEpoch,
      });

      expect(action, isNotNull);
      expect(action!.kind, LiveSessionActionKind.setCompleted);
      expect(action.at, DateTime(2026, 8, 15, 18));
    });

    test('rifiuta payload incompleti o di tipo sconosciuto', () {
      expect(LiveSessionAction.tryParse(null), isNull);
      expect(LiveSessionAction.tryParse('setCompleted'), isNull);
      expect(
        LiveSessionAction.tryParse({'id': 'abc', 'kind': 'setCompleted'}),
        isNull,
      );
      expect(
        LiveSessionAction.tryParse({
          'id': 'abc',
          'kind': 'boh',
          'logId': 1,
          'entryIndex': 0,
          'setNumber': 1,
          'at': 0,
        }),
        isNull,
      );
    });
  });

  group('LiveActionPayload (Android)', () {
    test('fa andata e ritorno dentro il payload della notifica', () {
      final encoded = LiveActionPayload.forSnapshot(
        snapshot,
        queuePath: '/tmp/actions.json',
      ).encode();

      final decoded = LiveActionPayload.tryParse(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.queuePath, '/tmp/actions.json');
      expect(decoded.logId, 3);
      expect(decoded.entryIndex, 1);
      expect(decoded.setNumber, 2);
    });

    test('l\'id dell\'azione identifica la serie e il momento del tap', () {
      final at = DateTime(2026, 8, 15, 18);
      final payload = LiveActionPayload.forSnapshot(
        snapshot,
        queuePath: '/tmp/actions.json',
      );

      expect(payload.toAction(at).id, payload.toAction(at).id);
      expect(
        payload.toAction(at).id,
        isNot(payload.toAction(at.add(const Duration(seconds: 1))).id),
      );
    });

    test('un payload rovinato non produce azioni', () {
      expect(LiveActionPayload.tryParse(null), isNull);
      expect(LiveActionPayload.tryParse(''), isNull);
      expect(LiveActionPayload.tryParse('non json'), isNull);
      expect(LiveActionPayload.tryParse('{"logId":3}'), isNull);
    });
  });
}
