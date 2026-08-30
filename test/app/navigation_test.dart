import 'package:tacca/app/router.dart';
import 'package:tacca/data/entities/workout_day.dart';
import 'package:tacca/data/entities/workout_log.dart';
import 'package:tacca/data/entities/workout_plan.dart';
import 'package:tacca/data/repositories/plan_repository.dart';
import 'package:tacca/data/repositories/workout_log_repository.dart';
import 'package:tacca/features/history/cubit/history_cubit.dart';
import 'package:tacca/features/plans/cubit/plans_cubit.dart';
import 'package:tacca/features/workout/cubit/active_session_cubit.dart';
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

  /// Scheda a un giorno, quanto basta per aprire una sessione.
  WorkoutPlan seedPlan(FakePlanRepository plans) {
    final now = DateTime(2026, 1, 1);
    final plan = WorkoutPlan(
      name: 'Push Pull Legs',
      createdAt: now,
      updatedAt: now,
    )..id = 1;
    plan.days.add(WorkoutDay(label: 'Giorno A')..id = 1);
    plans.add(plan);
    return plan;
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakePlanRepository plans,
    required FakeWorkoutLogRepository logs,
  }) async {
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
            BlocProvider<ActiveSessionCubit>(
              create: (context) => ActiveSessionCubit(repository: logs),
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
    await pumpApp(
      tester,
      plans: FakePlanRepository(),
      logs: FakeWorkoutLogRepository(),
    );

    // Le destinazioni della tab bar flottante: solo quella attiva porta
    // l'etichetta a schermo, quindi si cercano per chiave.
    expect(find.byKey(const ValueKey('home-tab-Schede')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-Storico')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-Impostazioni')), findsOneWidget);
    // Ramo iniziale: archivio schede.
    expect(find.text('Le mie schede'), findsOneWidget);
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('naviga tra Schede, Storico e Impostazioni', (tester) async {
    await pumpApp(
      tester,
      plans: FakePlanRepository(),
      logs: FakeWorkoutLogRepository(),
    );

    // → Storico.
    await tester.tap(find.byKey(const ValueKey('home-tab-Storico')));
    await tester.pumpAndSettle();
    expect(find.text('Nessun allenamento registrato.'), findsOneWidget);

    // → Impostazioni.
    await tester.tap(find.byKey(const ValueKey('home-tab-Impostazioni')));
    await tester.pumpAndSettle();
    expect(find.text('Intelligenza artificiale'), findsOneWidget);

    // → di nuovo Schede.
    await tester.tap(find.byKey(const ValueKey('home-tab-Schede')));
    await tester.pumpAndSettle();
    expect(
      find.text('Nessuna scheda. Creane una per iniziare.'),
      findsOneWidget,
    );
  });

  testWidgets('all\'avvio propone di riprendere la sessione interrotta', (
    tester,
  ) async {
    final logs = FakeWorkoutLogRepository();
    logs.saveLog(
      WorkoutLog.start(
        startedAt: DateTime(2026, 8, 14, 19, 30),
        planNameSnapshot: 'Push Pull Legs',
        dayLabelSnapshot: 'Giorno A',
      ),
    );

    await pumpApp(tester, plans: FakePlanRepository(), logs: logs);

    expect(find.text('Riprendere l\'allenamento?'), findsOneWidget);
    expect(find.textContaining('Push Pull Legs'), findsWidgets);

    // "Più tardi": la sessione resta in corso e la proposta non si ripete —
    // ma resta la card in cima all'archivio, che è il punto di rientro.
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Riprendere l\'allenamento?'), findsNothing);
    expect(find.text('Allenamento in corso'), findsOneWidget);
  });

  testWidgets('la proposta aspetta la shell montata dal gate legale', (
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
    final router = createRouter();

    // Come il gate legale: finché la manleva non è accettata il router — e
    // quindi la shell — non esiste. Il Cubit invece sì (`lazy: false`), e ha
    // già letto il database: la proposta non deve andare persa per strada.
    final accepted = ValueNotifier(false);
    addTearDown(accepted.dispose);

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
            BlocProvider<ActiveSessionCubit>(
              lazy: false,
              create: (context) => ActiveSessionCubit(repository: logs),
            ),
          ],
          child: ValueListenableBuilder<bool>(
            valueListenable: accepted,
            builder: (context, open, child) => open
                ? MaterialApp.router(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    routerConfig: router,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Riprendere l\'allenamento?'), findsNothing);

    accepted.value = true;
    await tester.pumpAndSettle();

    expect(find.text('Riprendere l\'allenamento?'), findsOneWidget);

    // Il dialog va chiuso prima della fine del test: lasciarlo aperto lascia
    // appesa anche l'attesa che lo ha aperto.
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'una sessione aperta ad app avviata compare nell\'archivio senza riavvio',
    (tester) async {
      final plans = FakePlanRepository();
      final logs = FakeWorkoutLogRepository();
      final plan = seedPlan(plans);

      await pumpApp(tester, plans: plans, logs: logs);

      // Nessuna sessione: nessuna card, e nessuna proposta di ripresa.
      expect(find.text('Allenamento in corso'), findsNothing);
      expect(find.text('Riprendere l\'allenamento?'), findsNothing);

      // La sessione nasce mentre l'app è viva: prima di questo, l'archivio se
      // ne accorgeva solo chiudendo e riaprendo l'app.
      logs.startSession(plan: plan, day: plan.days.first);
      await tester.pumpAndSettle();

      expect(find.text('Allenamento in corso'), findsOneWidget);
      // Il nome della scheda è anche nella lista sotto: a distinguere la card
      // è il giorno in corso.
      expect(find.text('Giorno A'), findsOneWidget);
      // La proposta all'avvio riguarda solo la sessione trovata aperta
      // all'apertura dell'app: questa l'ha appena aperta l'utente.
      expect(find.text('Riprendere l\'allenamento?'), findsNothing);
    },
  );

  testWidgets('la card sparisce quando la sessione viene chiusa', (
    tester,
  ) async {
    final plans = FakePlanRepository();
    final logs = FakeWorkoutLogRepository();
    final plan = seedPlan(plans);
    final log = logs.startSession(plan: plan, day: plan.days.first);

    await pumpApp(tester, plans: plans, logs: logs);
    await tester.tap(find.text('Più tardi'));
    await tester.pumpAndSettle();
    expect(find.text('Allenamento in corso'), findsOneWidget);

    log
      ..status = WorkoutStatus.completed
      ..finishedAt = DateTime(2026, 8, 15, 19);
    logs.saveLog(log);
    await tester.pumpAndSettle();

    expect(find.text('Allenamento in corso'), findsNothing);
  });
}
