import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tacca/services/live_session/live_session_controller.dart';
import 'package:tacca/services/live_session/pending_action_queue.dart';

/// La coda è il punto in cui una conferma data a telefono bloccato
/// sopravvive alla morte del processo: qui si verifica che sopravviva davvero
/// e che un file rovinato non porti giù la sessione.
void main() {
  late Directory dir;
  late PendingActionQueue queue;

  LiveSessionAction action(String id, {int setNumber = 1}) => LiveSessionAction(
    id: id,
    kind: LiveSessionActionKind.setCompleted,
    logId: 7,
    entryIndex: 2,
    setNumber: setNumber,
    at: DateTime(2026, 8, 15, 18, 30),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tacca_live_queue');
    queue = PendingActionQueue(File('${dir.path}/actions.json'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('drain restituisce le azioni accodate, nell\'ordine di arrivo', () {
    queue.append(action('a', setNumber: 1));
    queue.append(action('b', setNumber: 2));

    final drained = queue.drain();

    expect(drained.map((a) => a.id), ['a', 'b']);
    expect(drained.first.setNumber, 1);
    expect(drained.first.logId, 7);
    expect(drained.first.entryIndex, 2);
    expect(drained.first.at, DateTime(2026, 8, 15, 18, 30));
  });

  test('drain svuota la coda: la stessa serie non si registra due volte', () {
    queue.append(action('a'));

    expect(queue.drain(), hasLength(1));
    expect(queue.drain(), isEmpty);
  });

  test('senza file la coda è semplicemente vuota', () {
    expect(queue.drain(), isEmpty);
  });

  test('un file illeggibile non fa saltare la sessione', () {
    queue.file.writeAsStringSync('{ questo non è json');

    expect(queue.drain(), isEmpty);

    // E la coda torna utilizzabile per le conferme successive.
    queue.append(action('a'));
    expect(queue.drain(), hasLength(1));
  });

  test('le voci non riconosciute vengono scartate, le altre restano', () {
    queue.file.writeAsStringSync(
      jsonEncode([
        {'kind': 'setCompleted'},
        action('buona').toMap(),
      ]),
    );

    final drained = queue.drain();

    expect(drained, hasLength(1));
    expect(drained.single.id, 'buona');
  });
}
