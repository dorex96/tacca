import 'package:tacca/services/timer/timer_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Il tempo "vero" del test: [FakeAsync.elapsed] avanza sia con `elapse`
/// (i timer scattano) sia con `elapseBlocking` (l'orologio va avanti ma i
/// timer restano fermi, come quando il sistema sospende l'app in background).
final _start = DateTime(2026, 8, 15, 18);

void main() {
  group('TimerEngine', () {
    test('il recupero si calcola dall\'orologio, non dai tick', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final states = <TimerState>[];
        engine.stream.listen(states.add);

        engine.start(TimerSpec.rest(const Duration(seconds: 90)));
        async.elapse(const Duration(seconds: 30));

        expect(states.last.remaining, const Duration(seconds: 60));
        expect(states.last.isFinished, isFalse);
        expect(engine.isRunning, isTrue);

        async.elapse(const Duration(seconds: 61));

        expect(states.last.remaining, Duration.zero);
        expect(states.last.isFinished, isTrue);
        expect(engine.isRunning, isFalse);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('a fine recupero emette un solo segnale di fine', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final signals = <TimerSignal>[];
        engine.signals.listen(signals.add);

        engine.start(TimerSpec.rest(const Duration(seconds: 10)));
        async.elapse(const Duration(seconds: 30));

        expect(signals, [TimerSignal.finished]);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('EMOM: un segnale a ogni inizio round e uno alla fine', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final signals = <TimerSignal>[];
        final states = <TimerState>[];
        engine.signals.listen(signals.add);
        engine.stream.listen(states.add);

        engine.start(
          TimerSpec.emom(
            interval: const Duration(seconds: 60),
            total: const Duration(minutes: 3),
          ),
        );
        async.flushMicrotasks();
        expect(states.last.round, 1);
        expect(states.last.totalRounds, 3);

        async.elapse(const Duration(seconds: 60));
        expect(states.last.round, 2);

        async.elapse(const Duration(seconds: 60));
        expect(states.last.round, 3);

        async.elapse(const Duration(seconds: 60));
        expect(states.last.isFinished, isTrue);

        // Inizio del 2° e del 3° round, poi la fine: l'inizio del 1° coincide
        // con l'avvio e non produce beep.
        expect(signals, [
          TimerSignal.interval,
          TimerSignal.interval,
          TimerSignal.finished,
        ]);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test(
      'dopo un periodo in background lo stato è esatto e i segnali arretrati '
      'non si accumulano',
      () {
        fakeAsync((async) {
          final engine = TimerEngine(now: () => _start.add(async.elapsed));
          final signals = <TimerSignal>[];
          engine.signals.listen(signals.add);

          engine.start(
            TimerSpec.emom(
              interval: const Duration(seconds: 60),
              total: const Duration(minutes: 10),
            ),
          );

          // App in background: l'orologio avanza, i timer no.
          async.elapseBlocking(const Duration(minutes: 3, seconds: 30));
          engine.reconcile();
          async.flushMicrotasks();

          expect(engine.current!.round, 4);
          expect(
            engine.current!.elapsed,
            const Duration(minutes: 3, seconds: 30),
          );
          expect(
            engine.current!.phaseRemaining,
            const Duration(seconds: 30),
            reason: 'mancano 30s alla fine del 4° minuto',
          );
          expect(
            signals,
            [TimerSignal.interval],
            reason: 'un solo segnale, non i tre round maturati in background',
          );

          engine.dispose();
          async.flushMicrotasks();
        });
      },
    );

    test('Tabata: alterna lavoro e recupero e conta i round', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final states = <TimerState>[];
        engine.stream.listen(states.add);

        engine.start(
          TimerSpec.tabata(
            interval: const Duration(seconds: 20),
            restInterval: const Duration(seconds: 10),
            rounds: 8,
          ),
        );
        async.flushMicrotasks();
        expect(states.last.phase, TimerPhase.work);
        expect(states.last.spec.total, const Duration(seconds: 240));

        async.elapse(const Duration(seconds: 25));
        expect(states.last.round, 1);
        expect(states.last.phase, TimerPhase.rest);
        expect(states.last.phaseRemaining, const Duration(seconds: 5));

        async.elapse(const Duration(seconds: 10));
        expect(states.last.round, 2);
        expect(states.last.phase, TimerPhase.work);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('For Time senza time cap conta in avanti senza mai finire', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final states = <TimerState>[];
        engine.stream.listen(states.add);

        engine.start(TimerSpec.forTime());
        async.elapse(const Duration(minutes: 12));

        expect(states.last.elapsed, const Duration(minutes: 12));
        expect(states.last.remaining, isNull);
        expect(states.last.isFinished, isFalse);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('start su un timer attivo sostituisce quello in corso', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));

        engine.start(TimerSpec.rest(const Duration(minutes: 5)));
        async.elapse(const Duration(seconds: 30));
        expect(engine.isRunning, isTrue);

        engine.start(TimerSpec.rest(const Duration(seconds: 60)));
        async.flushMicrotasks();

        expect(engine.current!.spec.total, const Duration(seconds: 60));
        expect(engine.current!.elapsed, Duration.zero);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('stop azzera il timer corrente e ferma le emissioni', () {
      fakeAsync((async) {
        final engine = TimerEngine(now: () => _start.add(async.elapsed));
        final states = <TimerState>[];
        engine.stream.listen(states.add);

        engine.start(TimerSpec.rest(const Duration(minutes: 2)));
        async.elapse(const Duration(seconds: 10));
        final emitted = states.length;

        engine.stop();
        async.elapse(const Duration(seconds: 10));

        expect(engine.current, isNull);
        expect(engine.isRunning, isFalse);
        expect(states.length, emitted);

        engine.dispose();
        async.flushMicrotasks();
      });
    });

    group('upcomingSignalTimes', () {
      test('EMOM: inizio dei round futuri più la fine', () {
        fakeAsync((async) {
          final engine = TimerEngine(now: () => _start.add(async.elapsed));
          engine.start(
            TimerSpec.emom(
              interval: const Duration(seconds: 60),
              total: const Duration(minutes: 3),
            ),
          );

          expect(engine.upcomingSignalTimes(), [
            _start.add(const Duration(minutes: 1)),
            _start.add(const Duration(minutes: 2)),
            _start.add(const Duration(minutes: 3)),
          ]);

          // A metà del secondo minuto restano solo gli eventi futuri.
          async.elapse(const Duration(seconds: 90));
          expect(engine.upcomingSignalTimes(), [
            _start.add(const Duration(minutes: 2)),
            _start.add(const Duration(minutes: 3)),
          ]);

          engine.dispose();
          async.flushMicrotasks();
        });
      });

      test('rispetta il tetto massimo richiesto', () {
        fakeAsync((async) {
          final engine = TimerEngine(now: () => _start.add(async.elapsed));
          engine.start(
            TimerSpec.emom(
              interval: const Duration(seconds: 60),
              total: const Duration(minutes: 30),
            ),
          );

          expect(engine.upcomingSignalTimes(max: 10), hasLength(10));

          engine.dispose();
          async.flushMicrotasks();
        });
      });

      test('nessun evento quando non c\'è un timer attivo', () {
        fakeAsync((async) {
          final engine = TimerEngine(now: () => _start.add(async.elapsed));
          expect(engine.upcomingSignalTimes(), isEmpty);
          engine.dispose();
          async.flushMicrotasks();
        });
      });
    });
  });
}
