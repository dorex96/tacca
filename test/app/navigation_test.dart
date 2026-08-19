import 'package:tacca/app/router.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/history/cubit/history_cubit.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/workout/cubit/resume_session_cubit.dart';
import 'package:tacca/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../support/fakes.dart';

// Smoke test della navigazione a 3 tab. Monta shell + router con repository
// fake in memoria: le pagine dipendono dai Cubit di feature, ma il test resta
// senza ObjectBox e senza plugin.
void main() {
  // Le date localizzate passano da DateFormat, che vuole i simboli caricati
  // (in produzione lo fa `main()`).
  setUpAll(() => initializeDateFormatting('it'));

  Future<void> pumpApp(WidgetTester tester) async {
    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlanRepository>.value(value: plans),
          RepositoryProvider<WorkoutLogRepository>.value(value: logs),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<HistoryCubit>(
              create: (context) => HistoryCubit(repository: logs),
            ),
            BlocProvider<ResumeSessionCubit>(
              create: (context) => ResumeSessionCubit(repository: logs),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: createRouter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra tre destinazioni e parte dalle Schede', (tester) async {
    await pumpApp(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    // Ramo iniziale: archivio schede.
    expect(find.text('Le mie schede'), findsOneWidget);
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('naviga tra Schede, Storico e Impostazioni', (tester) async {
    await pumpApp(tester);

    // → Storico (icona non selezionata = variante outlined).
    await tester.tap(find.byIcon(Icons.history_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Nessun allenamento registrato.'), findsOneWidget);

    // → Impostazioni.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Intelligenza artificiale'), findsOneWidget);

    // → di nuovo Schede.
    await tester.tap(find.byIcon(Icons.fitness_center_outlined));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('all\'avvio propone di riprendere la sessione interrotta', (
    tester,
  ) async {
    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    logs.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 14, 19, 30),
        planNameSnapshot: 'Push Pull Legs',
        dayLabelSnapshot: 'Giorno A',
      ),
    );

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlanRepository>.value(value: plans),
          RepositoryProvider<WorkoutLogRepository>.value(value: logs),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<PlansCubit>(
              create: (context) => PlansCubit(repository: plans),
            ),
            BlocProvider<HistoryCubit>(
              create: (context) => HistoryCubit(repository: logs),
            ),
            BlocProvider<ResumeSessionCubit>(
              create: (context) => ResumeSessionCubit(repository: logs),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: createRouter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Riprendere l\'allenamento?'), findsOneWidget);
    expect(find.textContaining('Push Pull Legs'), findsOneWidget);

    // "Più tardi": la sessione resta in corso, la proposta non si ripete.
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Riprendere l\'allenamento?'), findsNothing);
  });
}
