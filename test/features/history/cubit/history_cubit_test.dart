import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/features/history/cubit/history_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeWorkoutLogRepository repository;

  WorkoutLog finishedLog({
    required String planName,
    required DateTime startedAt,
    String dayLabel = 'Giorno A',
    WorkoutStatus status = WorkoutStatus.completed,
  }) {
    return WorkoutLog(
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(minutes: 50)),
      dbStatus: status.name,
      planNameSnapshot: planName,
      dayLabelSnapshot: dayLabel,
    );
  }

  setUp(() => repository = FakeWorkoutLogRepository());
  tearDown(() => repository.dispose());

  test('parte in caricamento e riceve le sessioni concluse', () async {
    final cubit = HistoryCubit(repository: repository);
    expect(cubit.state.isLoading, isTrue);

    repository.saveLog(
      finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 1)),
    );
    await pumpEventQueue();

    expect(cubit.state.isLoading, isFalse);
    expect(cubit.state.logs, hasLength(1));

    await cubit.close();
  });

  test('le sessioni in corso non compaiono nello storico', () async {
    repository.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 15),
        planNameSnapshot: 'Upper / Lower',
        dayLabelSnapshot: 'Giorno A',
      ),
    );
    final cubit = HistoryCubit(repository: repository);
    await pumpEventQueue();

    expect(cubit.state.logs, isEmpty);

    await cubit.close();
  });

  test('filterByPlan restringe l\'elenco a una sola scheda', () async {
    repository
      ..saveLog(
        finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 1)),
      )
      ..saveLog(
        finishedLog(planName: 'Full Body', startedAt: DateTime(2026, 8, 5)),
      )
      ..saveLog(
        finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 8)),
      );

    final cubit = HistoryCubit(repository: repository);
    await pumpEventQueue();
    expect(cubit.state.filteredLogs, hasLength(3));

    cubit.filterByPlan('Upper / Lower');
    expect(cubit.state.filteredLogs, hasLength(2));
    expect(
      cubit.state.filteredLogs.every(
        (l) => l.planNameSnapshot == 'Upper / Lower',
      ),
      isTrue,
    );

    cubit.filterByPlan(null);
    expect(cubit.state.filteredLogs, hasLength(3));

    await cubit.close();
  });

  test('planOptions elenca ogni scheda una volta sola', () async {
    repository
      ..saveLog(
        finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 1)),
      )
      ..saveLog(
        finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 8)),
      )
      ..saveLog(
        finishedLog(planName: 'Full Body', startedAt: DateTime(2026, 8, 5)),
      );

    final cubit = HistoryCubit(repository: repository);
    await pumpEventQueue();

    expect(cubit.state.planOptions, ['Upper / Lower', 'Full Body']);

    await cubit.close();
  });

  test('deleteLog rimuove la sessione e l\'elenco si aggiorna', () async {
    final id = repository.saveLog(
      finishedLog(planName: 'Upper / Lower', startedAt: DateTime(2026, 8, 1)),
    );
    final cubit = HistoryCubit(repository: repository);
    await pumpEventQueue();
    expect(cubit.state.logs, hasLength(1));

    cubit.deleteLog(id);
    await pumpEventQueue();

    expect(cubit.state.logs, isEmpty);

    await cubit.close();
  });
}
