import 'package:app_palestra/data/entities/block.dart';
import 'package:app_palestra/data/entities/exercise.dart';
import 'package:app_palestra/data/entities/log_entry.dart';
import 'package:app_palestra/data/entities/workout_day.dart';
import 'package:app_palestra/data/entities/workout_log.dart';
import 'package:app_palestra/data/entities/workout_plan.dart';
import 'package:app_palestra/data/repositories/workout_log_repository.dart';
import 'package:app_palestra/features/workout/bloc/workout_session_bloc.dart';
import 'package:app_palestra/features/workout/bloc/workout_session_event.dart';
import 'package:app_palestra/features/workout/bloc/workout_session_state.dart';
import 'package:app_palestra/services/timer/timer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

final _now = DateTime(2026, 8, 15, 18);

void main() {
  late FakePlanRepository plans;
  late FakeWorkoutLogRepository logs;
  late RecordingSessionFeedback feedback;
  late RecordingSessionNotifier notifier;
  late RecordingScreenWake screenWake;
  late TimerEngine timerEngine;

  /// Scheda a un giorno: due esercizi in un blocco standard, il primo con
  /// recupero configurato (serve all'avvio automatico del countdown).
  WorkoutPlan buildPlan() {
    final plan = WorkoutPlan(
      name: 'Upper / Lower',
      createdAt: _now,
      updatedAt: _now,
    )..id = 1;
    final day = WorkoutDay(label: 'Giorno A')..id = 10;
    final block = Block.ofType(BlockType.standard)..id = 100;
    block.exercises.addAll([
      Exercise(name: 'Panca piana', sets: 3, reps: '8', restSeconds: 120)
        ..id = 1000,
      Exercise(name: 'Rematore', sets: 3, reps: '10')..id = 1001,
    ]);
    day.blocks.add(block);
    plan.days.add(day);

    // Giorno a superset: i giri e il recupero stanno sul blocco, gli esercizi
    // portano solo le ripetizioni — è la forma con cui arriva dalla scheda.
    final supersetDay = WorkoutDay(label: 'Giorno B', sortOrder: 1)..id = 11;
    final superset = Block.ofType(BlockType.superset)
      ..id = 101
      ..rounds = 4
      ..restBetweenRoundsSeconds = 60;
    superset.exercises.addAll([
      Exercise(name: 'Curl EZ', reps: '10')..id = 1002,
      Exercise(name: 'French press', reps: '10', sortOrder: 1)..id = 1003,
    ]);
    supersetDay.blocks.add(superset);
    plan.days.add(supersetDay);
    return plan;
  }

  WorkoutSessionBloc buildBloc() => WorkoutSessionBloc(
    planRepository: plans,
    logRepository: logs,
    timerEngine: timerEngine,
    feedback: feedback,
    notifier: notifier,
    screenWake: screenWake,
    now: () => _now,
  );

  Future<WorkoutSessionBloc> startedSession({int dayId = 10}) async {
    final bloc = buildBloc()..add(SessionStarted(planId: 1, dayId: dayId));
    await pumpEventQueue();
    return bloc;
  }

  setUp(() {
    plans = FakePlanRepository()..add(buildPlan());
    logs = FakeWorkoutLogRepository();
    feedback = RecordingSessionFeedback();
    notifier = RecordingSessionNotifier();
    screenWake = RecordingScreenWake();
    timerEngine = TimerEngine(now: () => _now);
  });

  tearDown(() async {
    await timerEngine.dispose();
    await logs.dispose();
  });

  group('apertura della sessione', () {
    test('SessionStarted crea il log e tiene lo schermo acceso', () async {
      final bloc = await startedSession();

      expect(bloc.state.status, WorkoutSessionStatus.ready);
      expect(bloc.state.log, isNotNull);
      expect(bloc.state.day?.label, 'Giorno A');
      expect(bloc.state.items.map((i) => i.name), ['Panca piana', 'Rematore']);
      expect(screenWake.enabled, isTrue);
      expect(feedback.prepareCount, 1);

      await bloc.close();
    });

    test(
      'SessionStarted su scheda o giorno inesistenti finisce in notFound',
      () async {
        final bloc = buildBloc()
          ..add(const SessionStarted(planId: 1, dayId: 999));
        await pumpEventQueue();

        expect(bloc.state.status, WorkoutSessionStatus.notFound);

        await bloc.close();
      },
    );

    test('SessionResumed riallinea le entry alla scheda modificata', () async {
      // Sessione registrata su una scheda con "Panca piana" e "Curl", con una
      // serie svolta sul curl che è poi stato tolto dalla scheda.
      final plan = plans.plans[1]!;
      final day = plan.days.first;
      final log = WorkoutLog.start(
        startedAt: _now,
        planNameSnapshot: plan.name,
        dayLabelSnapshot: day.label,
      );
      log.plan.target = plan;
      log.day.target = day;
      final removed = LogEntry(exerciseNameSnapshot: 'Curl', sortOrder: 1);
      removed.sets.add(buildLogSet(1, weightKg: 12, reps: '12'));
      log.entries.addAll([
        LogEntry(exerciseNameSnapshot: 'Panca piana', sortOrder: 0),
        removed,
      ]);
      final logId = logs.saveLog(log);

      final bloc = buildBloc()..add(SessionResumed(logId));
      await pumpEventQueue();

      final names = bloc.state.items.map((i) => i.name).toList();
      expect(
        names,
        ['Panca piana', 'Rematore', 'Curl'],
        reason:
            'gli esercizi in scheda vengono riallineati, quelli svolti ma non '
            'più prescritti restano in coda',
      );
      expect(bloc.state.items[1].exercise?.name, 'Rematore');
      expect(
        bloc.state.items[2].block,
        isNull,
        reason: 'l\'esercizio orfano non ha più una prescrizione',
      );

      await bloc.close();
    });

    test('SessionResumed su un log inesistente finisce in notFound', () async {
      final bloc = buildBloc()..add(const SessionResumed(404));
      await pumpEventQueue();

      expect(bloc.state.status, WorkoutSessionStatus.notFound);

      await bloc.close();
    });
  });

  group('registrazione delle serie', () {
    test('SetCompleted registra la serie e salva subito (autosave)', () async {
      final bloc = await startedSession();
      final savesBefore = logs.saveCount;

      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      final item = bloc.state.items.first;
      expect(item.isSetDone(1), isTrue);
      expect(
        logs.saveCount,
        savesBefore + 1,
        reason: 'ogni mutazione persiste subito (RF-06)',
      );

      await bloc.close();
    });

    test(
      'la serie eredita i valori della precedente della stessa sessione',
      () async {
        final bloc = await startedSession();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();
        bloc.add(
          const SetLogged(entryIndex: 0, setNumber: 1, weightKg: 80, reps: '8'),
        );
        await pumpEventQueue();
        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 2));
        await pumpEventQueue();

        final second = bloc.state.items.first.setNumbered(2)!;
        expect(second.weightKg, 80);
        expect(second.reps, '8');

        await bloc.close();
      },
    );

    test(
      'senza serie precedenti eredita i valori dell\'ultima volta',
      () async {
        logs.lastPerformances['Panca piana'] = LastPerformance(
          performedAt: DateTime(2026, 8, 8),
          sets: [buildLogSet(1, weightKg: 75, reps: '8')],
        );
        final bloc = await startedSession();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        final first = bloc.state.items.first.setNumbered(1)!;
        expect(first.weightKg, 75);
        expect(first.reps, '8');

        await bloc.close();
      },
    );

    test('SetUnchecked rimuove la serie e salva', () async {
      final bloc = await startedSession();
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();
      final savesBefore = logs.saveCount;

      bloc.add(const SetUnchecked(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.items.first.isSetDone(1), isFalse);
      expect(logs.saveCount, savesBefore + 1);

      await bloc.close();
    });

    test('SetLogged crea la serie se non era ancora spuntata', () async {
      final bloc = await startedSession();

      bloc.add(
        const SetLogged(entryIndex: 1, setNumber: 1, weightKg: 40, reps: '10'),
      );
      await pumpEventQueue();

      final item = bloc.state.items[1];
      expect(item.isSetDone(1), isTrue);
      expect(item.setNumbered(1)!.weightKg, 40);

      await bloc.close();
    });
  });

  group('superset', () {
    test('i giri del blocco valgono come serie di ogni esercizio', () async {
      final bloc = await startedSession(dayId: 11);

      final items = bloc.state.items;
      expect(items.map((i) => i.name), ['Curl EZ', 'French press']);
      expect(items.every((i) => i.isRoundBased), isTrue);
      expect(items.map((i) => i.displayedSets), [4, 4]);
      expect(items.map((i) => i.isLastOfBlock), [false, true]);

      await bloc.close();
    });

    test('il recupero parte a fine giro, non fra i due esercizi', () async {
      final bloc = await startedSession(dayId: 11);

      // Primo esercizio del giro: si passa subito al secondo, niente timer.
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();
      expect(bloc.state.timer, isNull);

      // Ultimo esercizio: il giro è chiuso, parte il recupero del blocco.
      bloc.add(const SetCompleted(entryIndex: 1, setNumber: 1));
      await pumpEventQueue();
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);
      expect(bloc.state.timer!.spec.total, const Duration(seconds: 60));

      await bloc.close();
    });
  });

  group('timer', () {
    test('la spunta avvia da sola il recupero dell\'esercizio', () async {
      final bloc = await startedSession();

      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.timer, isNotNull);
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);
      expect(bloc.state.timer!.spec.total, const Duration(seconds: 120));

      await bloc.close();
    });

    test('nessun avvio automatico se l\'esercizio non ha recupero', () async {
      final bloc = await startedSession();

      bloc.add(const SetCompleted(entryIndex: 1, setNumber: 1));
      await pumpEventQueue();

      expect(bloc.state.timer, isNull);

      await bloc.close();
    });

    test(
      'con l\'avvio automatico disattivato la spunta non parte il timer',
      () async {
        final bloc = await startedSession();
        bloc.add(const AutoStartRestToggled(false));
        await pumpEventQueue();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        expect(bloc.state.timer, isNull);

        await bloc.close();
      },
    );

    test(
      'un timer già attivo non viene interrotto dall\'avvio automatico',
      () async {
        final bloc = await startedSession();
        bloc.add(TimerRequested(TimerSpec.amrap(const Duration(minutes: 15))));
        await pumpEventQueue();

        bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
        await pumpEventQueue();

        expect(bloc.state.timer!.spec.kind, TimerKind.amrap);
        expect(bloc.state.pendingTimerRequest, isNull);

        await bloc.close();
      },
    );

    test('avviare a mano un timer con uno attivo chiede conferma', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.amrap(const Duration(minutes: 15))));
      await pumpEventQueue();

      bloc.add(TimerRequested(TimerSpec.rest(const Duration(seconds: 90))));
      await pumpEventQueue();

      expect(bloc.state.pendingTimerRequest, isNotNull);
      expect(
        bloc.state.timer!.spec.kind,
        TimerKind.amrap,
        reason: 'finché non c\'è conferma il timer in corso resta',
      );

      bloc.add(
        TimerRequested(
          TimerSpec.rest(const Duration(seconds: 90)),
          force: true,
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.pendingTimerRequest, isNull);
      expect(bloc.state.timer!.spec.kind, TimerKind.rest);

      await bloc.close();
    });

    test('TimerStopped ferma il timer e libera la barra', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(minutes: 2))));
      await pumpEventQueue();

      bloc.add(const TimerStopped());
      await pumpEventQueue();

      expect(bloc.state.timer, isNull);
      expect(timerEngine.isRunning, isFalse);

      await bloc.close();
    });

    test('i segnali del timer diventano beep e vibrazione', () async {
      final bloc = await startedSession();

      bloc.add(const TimerSignalled(TimerSignal.interval));
      await pumpEventQueue();

      expect(feedback.signals, [TimerSignal.interval]);

      await bloc.close();
    });
  });

  group('lifecycle', () {
    test('in background programma le notifiche dei segnali futuri', () async {
      final bloc = await startedSession();
      bloc.add(
        TimerRequested(
          TimerSpec.emom(
            interval: const Duration(seconds: 60),
            total: const Duration(minutes: 5),
          ),
        ),
      );
      await pumpEventQueue();

      bloc.add(
        const AppLifecycleChanged(
          toBackground: true,
          notificationTitle: 'Timer',
          notificationBody: 'Segnale',
        ),
      );
      await pumpEventQueue();

      expect(notifier.scheduled, hasLength(1));
      expect(
        notifier.scheduled.single,
        hasLength(5),
        reason: 'quattro inizi round più la fine',
      );

      await bloc.close();
    });

    test('al rientro annulla le notifiche pendenti', () async {
      final bloc = await startedSession();

      bloc.add(const AppLifecycleChanged(toBackground: false));
      await pumpEventQueue();

      expect(notifier.cancelCount, greaterThan(0));

      await bloc.close();
    });
  });

  group('chiusura', () {
    test('SessionFinished chiude il log come completato e lo salva', () async {
      final bloc = await startedSession();
      bloc.add(const SetCompleted(entryIndex: 0, setNumber: 1));
      await pumpEventQueue();

      bloc.add(
        const SessionFinished(
          status: WorkoutStatus.completed,
          notes: '  Buona sessione  ',
        ),
      );
      await pumpEventQueue();

      final log = bloc.state.log!;
      expect(bloc.state.status, WorkoutSessionStatus.finished);
      expect(log.status, WorkoutStatus.completed);
      expect(log.finishedAt, _now);
      expect(log.notes, 'Buona sessione');
      expect(logs.logs[log.id]!.status, WorkoutStatus.completed);
      expect(screenWake.enabled, isFalse);

      await bloc.close();
    });

    test(
      'SessionFinished con esito interrotto resta comunque nello storico',
      () async {
        final bloc = await startedSession();

        bloc.add(const SessionFinished(status: WorkoutStatus.aborted));
        await pumpEventQueue();

        expect(bloc.state.log!.status, WorkoutStatus.aborted);
        expect(bloc.state.log!.notes, isNull);

        await bloc.close();
      },
    );

    test('chiudere il Bloc spegne timer, notifiche e wake lock', () async {
      final bloc = await startedSession();
      bloc.add(TimerRequested(TimerSpec.rest(const Duration(minutes: 2))));
      await pumpEventQueue();

      await bloc.close();

      expect(timerEngine.isRunning, isFalse);
      expect(screenWake.enabled, isFalse);
    });
  });
}
