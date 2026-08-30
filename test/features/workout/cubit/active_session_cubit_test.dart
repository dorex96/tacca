import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/features/workout/cubit/active_session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

/// La sessione aperta vista dalla UI (§8): una sola per volta, e sempre
/// aggiornata — è il Cubit che sostituisce la lettura una-tantum all'avvio.
void main() {
  late FakeWorkoutLogRepository logs;
  late ActiveSessionCubit cubit;

  setUp(() => logs = FakeWorkoutLogRepository());

  tearDown(() async {
    await cubit.close();
    await logs.dispose();
  });

  WorkoutPlan seedPlan({String name = 'Push Pull Legs'}) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(name: name, createdAt: now, updatedAt: now)
      ..id = 1;
    plan.days.add(WorkoutDay(label: 'Giorno A')..id = 1);
    return plan;
  }

  WorkoutLog seedOpenLog({DateTime? startedAt}) {
    final log = WorkoutLog.start(
      startedAt: startedAt ?? DateTime(2026, 8, 14, 19, 30),
      planNameSnapshot: 'Push Pull Legs',
      dayLabelSnapshot: 'Giorno A',
    );
    logs.saveLog(log);
    return log;
  }

  test('la sessione trovata aperta all\'avvio va proposta', () async {
    final log = seedOpenLog();
    cubit = ActiveSessionCubit(repository: logs);
    await pumpEventQueue();

    expect(cubit.state.log?.id, log.id);
    expect(cubit.state.hasSession, isTrue);
    expect(cubit.state.promptPending, isTrue);
  });

  test('senza sessione aperta non c\'è niente da proporre', () async {
    cubit = ActiveSessionCubit(repository: logs);
    await pumpEventQueue();

    expect(cubit.state.log, isNull);
    expect(cubit.state.promptPending, isFalse);
  });

  test('dismissPrompt spegne la proposta ma non chiude la sessione', () async {
    seedOpenLog();
    cubit = ActiveSessionCubit(repository: logs);
    await pumpEventQueue();

    cubit.dismissPrompt();

    expect(cubit.state.promptPending, isFalse);
    // "Più tardi" non è "chiudi": la sessione resta, ed è quello che tiene la
    // card in cima all'archivio.
    expect(cubit.state.hasSession, isTrue);
  });

  test(
    'una sessione aperta dopo l\'avvio si vede ma non si ripropone',
    () async {
      cubit = ActiveSessionCubit(repository: logs);
      await pumpEventQueue();

      final plan = seedPlan();
      final log = logs.startSession(plan: plan, day: plan.days.first);
      await pumpEventQueue();

      expect(cubit.state.log?.id, log.id);
      // L'utente l'ha appena aperta: chiedergli se vuole riprenderla sarebbe
      // un dialog che rincorre chi torna all'archivio.
      expect(cubit.state.promptPending, isFalse);
    },
  );

  test('la sessione chiusa sparisce dallo stato', () async {
    final log = seedOpenLog();
    cubit = ActiveSessionCubit(repository: logs);
    await pumpEventQueue();
    expect(cubit.state.hasSession, isTrue);

    log
      ..status = WorkoutStatus.completed
      ..finishedAt = DateTime(2026, 8, 14, 20, 30);
    logs.saveLog(log);
    await pumpEventQueue();

    expect(cubit.state.hasSession, isFalse);
  });

  test('currentSession rilegge dal repository, senza aspettare lo stream', () {
    final log = seedOpenLog();
    cubit = ActiveSessionCubit(repository: logs);

    // Nessun `pumpEventQueue`: lo stream non ha ancora emesso nulla, ma chi
    // sta per aprire una nuova sessione deve già sapere che ce n'è una.
    expect(cubit.state.log, isNull);
    expect(cubit.currentSession()?.id, log.id);
  });
}
